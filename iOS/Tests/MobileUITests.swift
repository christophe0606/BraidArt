import XCTest

final class MobileUITests:XCTestCase {
    @MainActor
    func testIPhoneFrenchTabLabelsFitBothOrientations() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-hasShownFirstLaunchHelp","YES","-AppleLanguages","(fr)","-AppleLocale","fr_FR"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["weave"].waitForExistence(timeout:20))
        let tabs=app.tabBars.firstMatch
        for orientation in [UIDeviceOrientation.portrait,.landscapeLeft] {
            XCUIDevice.shared.orientation=orientation
            for name in ["Préparer","Tuiles","Résultat","3D","Réglages"] {
                XCTAssertTrue(tabs.buttons[name].isHittable,"Missing French phone tab: \(name)")
            }
            XCTAssertFalse(tabs.buttons["Bibliothèque de tuiles"].exists)
            tabs.buttons["Tuiles"].tap()
            screenshot(orientation == .portrait ? "iPhone French portrait short tile tab" : "iPhone French landscape short tile tab")
            tabs.buttons["Résultat"].tap()
            XCTAssertTrue(app.buttons["weave"].isHittable)
            XCTAssertTrue(app.buttons["export"].isHittable)
            XCTAssertGreaterThan(app.buttons["export"].frame.minX-app.buttons["weave"].frame.maxX,0)
        }
    }
    @MainActor
    func testIPhoneTabsRotationAndTouchControls() throws {
        continueAfterFailure=false
        let app=launchPhoneFixture()
        let tabs=app.tabBars.firstMatch
        for name in ["Prepare","Tile Library","Result","3D","Settings"] {
            XCTAssertTrue(tabs.buttons[name].isHittable,"Missing phone tab: \(name)")
        }
        XCTAssertFalse(app.buttons["sidebarToggle"].exists)
        XCTAssertFalse(app.buttons["export"].exists)
        screenshot("iPhone portrait prepare")
        tabs.buttons["Settings"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["sidebarImageWidth"].firstMatch.waitForExistence(timeout:5))
        screenshot("iPhone portrait settings tab")
        rotatePhone(app,to:.landscapeLeft,landscape:true)
        screenshot("iPhone landscape settings tab")
        tabs.buttons["Tile Library"].tap()
        XCTAssertFalse(app.buttons["export"].exists)
        screenshot("iPhone landscape tile library")
        tabs.buttons["Prepare"].tap()
        XCTAssertTrue(app.buttons["weave"].isHittable)
        screenshot("iPhone landscape prepare")
        rotatePhone(app,to:.portrait,landscape:false)
        weavePhoneFixture(app)
        let result=app.scrollViews["resultCanvas"]
        let original=result.screenshot().pngRepresentation
        result.pinch(withScale:2,velocity:1)
        XCTAssertNotEqual(original,result.screenshot().pngRepresentation,"Result pinch should zoom the picture")
        screenshot("iPhone portrait result pinch zoom")
        result.swipeLeft()
        rotatePhone(app,to:.landscapeRight,landscape:true)
        XCTAssertTrue(result.isHittable)
        screenshot("iPhone landscape result after rotation")
        app.buttons["Fit"].tap()
        tabs.buttons["3D"].tap()
        let scene=app.descendants(matching:.any)["sculptureCanvas"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout:10))
        XCTAssertGreaterThan(min(scene.frame.width,scene.frame.height),110,"Landscape controls must leave room to manipulate the sculpture")
        let front=scene.screenshot().pngRepresentation
        scene.coordinate(withNormalizedOffset:CGVector(dx:0.45,dy:0.5)).press(forDuration:0.05,thenDragTo:scene.coordinate(withNormalizedOffset:CGVector(dx:0.65,dy:0.65)))
        XCTAssertNotEqual(front,scene.screenshot().pngRepresentation,"One-finger drag should rotate the sculpture")
        let rotated=scene.screenshot().pngRepresentation
        scene.pinch(withScale:1.5,velocity:1)
        XCTAssertNotEqual(rotated,scene.screenshot().pngRepresentation,"3D pinch should zoom the sculpture")
        screenshot("iPhone landscape 3D rotated and zoomed")
        rotatePhone(app,to:.portrait,landscape:false)
        let portrait=scene.screenshot().pngRepresentation
        scene.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.05,thenDragTo:scene.coordinate(withNormalizedOffset:CGVector(dx:0.6,dy:0.55)))
        XCTAssertNotEqual(portrait,scene.screenshot().pngRepresentation,"The 3D canvas must accept touch after rotation")
        XCTAssertTrue(app.buttons["weave"].isHittable)
        XCTAssertTrue(app.buttons["export"].isHittable)
        XCTAssertGreaterThan(app.buttons["export"].frame.minX-app.buttons["weave"].frame.maxX,0)
        screenshot("iPhone portrait 3D after rotation")
    }
    @MainActor
    func testIPhone3DPictureExport() throws {
        continueAfterFailure=false
        let app=launchPhoneFixture()
        weavePhoneFixture(app)
        app.tabBars.buttons["3D"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["sculptureCanvas"].firstMatch.waitForExistence(timeout:10))
        app.buttons["export"].tap()
        app.buttons["3D View as PNG…"].tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Files"].exists)
        app.buttons["Files"].tap()
        savePhoneFile(app,name:"BraidArt-iPhone-3D-Test-\(UUID().uuidString.prefix(8)).png")
        expectStatus(app,"Saved to Files.")
        screenshot("iPhone 3D picture exported to Files")
    }
    @MainActor
    func testIPhonePicturePhotosAndFilesExport() throws {
        continueAfterFailure=false
        let app=launchPhoneFixture()
        weavePhoneFixture(app)
        app.buttons["export"].tap()
        app.buttons["Result as PNG…"].tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Files"].exists)
        screenshot("iPhone picture destination choices")
        app.buttons["Photos"].tap()
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let permission=springboard.alerts.firstMatch
        if permission.waitForExistence(timeout:5) {
            let allow=permission.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Allow' OR label == 'Add Photos Only' OR label BEGINSWITH 'Autoriser' OR label BEGINSWITH 'Ajouter'")).firstMatch
            XCTAssertTrue(allow.exists,permission.debugDescription)
            allow.tap()
        }
        expectStatus(app,"Saved to Photos.")
        screenshot("iPhone picture saved to Photos")
        app.buttons["export"].tap()
        app.buttons["Result as PNG…"].tap()
        app.buttons["Files"].tap()
        savePhoneFile(app,name:"BraidArt-iPhone-Test-\(UUID().uuidString.prefix(8)).png")
        expectStatus(app,"Saved to Files.")
        screenshot("iPhone picture saved to Files")
    }
    @MainActor
    func testIPhonePDFAnd3DObjectsUseFiles() throws {
        continueAfterFailure=false
        let app=launchPhoneFixture()
        weavePhoneFixture(app)
        for (title,suffix) in [("Vector PDF…","pdf"),("3D Object (GLB)…","glb"),("3D Object (USDZ)…","usdz")] {
            app.buttons["export"].tap()
            app.buttons[title].tap()
            XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout:30) || app.buttons["Move"].waitForExistence(timeout:10))
            XCTAssertFalse(app.buttons["Photos"].exists,"\(title) must use Files directly")
            savePhoneFile(app,name:"BraidArt-iPhone-Test-\(UUID().uuidString.prefix(8)).\(suffix)")
            expectStatus(app,"Saved to Files.")
        }
        screenshot("iPhone PDF GLB USDZ Files exports completed")
    }
    @MainActor private func launchPhoneFixture()->XCUIApplication {
        let app=XCUIApplication()
        app.launchArguments=["-hasShownFirstLaunchHelp","YES","--ui-fixture","-AppleLanguages","(en)","-AppleLocale","en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let weave=app.buttons["weave"]
        XCTAssertTrue(weave.waitForExistence(timeout:20))
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:weave)
        waitForExpectations(timeout:30)
        return app
    }
    @MainActor private func weavePhoneFixture(_ app:XCUIApplication) {
        app.buttons["weave"].tap()
        XCTAssertTrue(app.scrollViews["resultCanvas"].waitForExistence(timeout:90))
        // Continued-processing completion briefly covers the navigation bar on
        // phones without a Dynamic Island. Wait for the system banner to leave.
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let banner=springboard.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","Weaving image")).firstMatch
        if banner.waitForExistence(timeout:2) {
            expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:banner)
            waitForExpectations(timeout:20)
        }
    }
    @MainActor private func rotatePhone(_ app:XCUIApplication,to orientation:UIDeviceOrientation,landscape:Bool) {
        XCUIDevice.shared.orientation=orientation
        let predicate=NSPredicate { _,_ in landscape ? app.frame.width>app.frame.height : app.frame.height>app.frame.width }
        expectation(for:predicate,evaluatedWith:app)
        waitForExpectations(timeout:10)
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Settings"].isHittable)
    }
    @MainActor private func expectStatus(_ app:XCUIApplication,_ message:String) {
        expectation(for:NSPredicate(format:"label == %@",message),evaluatedWith:app.staticTexts["status"])
        waitForExpectations(timeout:30)
    }
    @MainActor private func savePhoneFile(_ app:XCUIApplication,name:String) {
        let save=app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout:30) || app.buttons["Move"].waitForExistence(timeout:5))
        screenshot("iPhone standard Files save dialog")
        let filename=app.textFields.firstMatch
        if filename.exists {
            filename.tap()
            filename.press(forDuration:1)
            if app.menuItems["Select All"].waitForExistence(timeout:2) { app.menuItems["Select All"].tap() }
            filename.typeText(name)
            if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        }
        XCTAssertTrue(save.isEnabled,app.debugDescription)
        save.tap()
    }
    @MainActor
    func testIPadWeaveZoomRotateAndSaveChoices() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-hasShownFirstLaunchHelp","YES","--ui-fixture","-AppleLanguages","(en)","-AppleLocale","en_US"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let weave=app.buttons["weave"]
        XCTAssertTrue(weave.waitForExistence(timeout:20))
        let ready=NSPredicate(format:"enabled == true")
        expectation(for:ready,evaluatedWith:weave)
        waitForExpectations(timeout:30)
        screenshot("iPad prepare")
        weave.tap()
        let result=app.scrollViews["resultCanvas"]
        XCTAssertTrue(result.waitForExistence(timeout:90))
        let before=result.screenshot().pngRepresentation
        result.pinch(withScale:2,velocity:1)
        XCTAssertNotEqual(before,result.screenshot().pngRepresentation)
        screenshot("iPad result zoom")
        app.segmentedControls.buttons["3D"].tap()
        let scene=app.descendants(matching:.any)["sculptureCanvas"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout:20))
        let front=scene.screenshot().pngRepresentation
        scene.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.05,thenDragTo:scene.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:0.6)))
        XCTAssertNotEqual(front,scene.screenshot().pngRepresentation)
        scene.pinch(withScale:1.5,velocity:1)
        screenshot("iPad 3D rotated and zoomed")
        app.buttons["export"].tap()
        app.buttons["3D View as PNG…"].tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Files"].exists)
        app.buttons["Files"].tap()
        XCTAssertTrue(app.navigationBars["Move"].waitForExistence(timeout:20) || app.buttons["Save"].waitForExistence(timeout:10))
        screenshot("iPad Files export")
    }
    @MainActor
    func testIPadReviewFixes() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-hasShownFirstLaunchHelp","YES","-AppleLanguages","(fr)","-AppleLocale","fr_FR"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let toggle=app.buttons["sidebarToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout:20))
        let sidebar=app.scrollViews["settingsSidebar"]
        if !sidebar.exists { toggle.tap() }
        XCTAssertTrue(sidebar.waitForExistence(timeout:5))
        let open=app.buttons["openMedia"]
        XCTAssertTrue(open.exists)
        XCTAssertEqual(open.frame.midX,app.segmentedControls.firstMatch.frame.midX,accuracy:2)
        XCTAssertEqual(app.buttons["weave"].label,"Tresser l’image")
        let dimensions=app.descendants(matching:.any)["sidebarOutputDimensions"].firstMatch
        let width=app.descendants(matching:.any)["sidebarImageWidth"].firstMatch
        XCTAssertTrue(dimensions.exists);XCTAssertTrue(width.exists)
        XCTAssertGreaterThan(width.frame.minY-dimensions.frame.maxY,10)
        screenshot("iPad centered opening and sidebar spacing")
        let originalWidth=sidebar.frame.width
        let delta:CGFloat=originalWidth>440 ? -80 : 80
        let handle=app.descendants(matching:.any)["sidebarResize"].firstMatch
        let start=handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:delta,dy:0)))
        XCTAssertEqual(sidebar.frame.width,originalWidth+delta,accuracy:10)
        screenshot("iPad resized sidebar and text weave button")
        let paneWidth=app.segmentedControls.firstMatch.frame.width
        toggle.tap()
        XCTAssertFalse(sidebar.exists)
        XCTAssertGreaterThan(app.segmentedControls.firstMatch.frame.width,paneWidth+250)
        screenshot("iPad hidden sidebar")
        toggle.tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout:5))
        let restored=handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        restored.press(forDuration:0.05,thenDragTo:restored.withOffset(CGVector(dx:-delta,dy:0)))
        app.buttons["help"].tap()
        let book=app.descendants(matching:.any)["helpBookLink"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:5))
        XCTAssertTrue(book.isHittable,"The book link must be visible when help first opens")
        screenshot("iPad help opening with Opt Art reference")
        app.scrollViews["helpDocument"].swipeUp()
        screenshot("iPad illustrated shared help")
        app.buttons["closeHelp"].tap()
    }
    @MainActor
    func testThirdPartyCreditsRetainLicenseTextAndSourceLinks() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-hasShownFirstLaunchHelp","YES","-AppleLanguages","(fr)","-AppleLocale","fr_FR"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["help"].waitForExistence(timeout:15))
        app.buttons["help"].tap()
        app.descendants(matching:.any)["thirdPartyCreditsLink"].firstMatch.tap()
        let credits=app.scrollViews["thirdPartyCredits"]
        XCTAssertTrue(credits.waitForExistence(timeout:5))
        screenshot("iPad third-party photo rights and sources")
        let source=app.descendants(matching:.any)["thirdPartySource-Cbc"].firstMatch
        for _ in 0..<5 { if source.isHittable { break };credits.swipeUp() }
        XCTAssertTrue(source.isHittable)
        let licenses=app.buttons["thirdPartyLicenses-Cbc"]
        XCTAssertTrue(licenses.isHittable)
        screenshot("iPad third-party libraries with license and source links")
        licenses.tap()
        app.buttons["EPL 2.0 — licence de distribution"].tap()
        let original=app.descendants(matching:.any)["thirdPartyOriginalSource"].firstMatch
        XCTAssertTrue(original.waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","Eclipse Public License")).firstMatch.exists)
        screenshot("iPad preserved upstream EPL license and original source")
    }
    @MainActor
    func testHelpOpensOnFirstLaunchOnlyAndRemainsAvailable() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        let language=["-AppleLanguages","(fr)","-AppleLocale","fr_FR"]
        // The argument overrides only this launch; the helper still saves its marker.
        app.launchArguments=["-hasShownFirstLaunchHelp","NO"]+language
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let close=app.buttons["closeHelp"]
        XCTAssertTrue(close.waitForExistence(timeout:15))
        XCTAssertTrue(app.descendants(matching:.any)["helpBookLink"].firstMatch.isHittable)
        screenshot("iPad first-launch help")
        close.tap()
        app.terminate()
        app.launchArguments=language
        app.launch()
        XCTAssertTrue(app.buttons["help"].waitForExistence(timeout:15))
        XCTAssertFalse(close.exists,"Help must not reopen on subsequent launches")
        app.buttons["help"].tap()
        XCTAssertTrue(close.waitForExistence(timeout:5))
        close.tap()
    }
    @MainActor
    func testExportIsSeparateAndOnlyVisibleInResultAnd3D() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-hasShownFirstLaunchHelp","YES","-AppleLanguages","(fr)","-AppleLocale","fr_FR"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let weave=app.buttons["weave"]
        XCTAssertTrue(weave.waitForExistence(timeout:15))
        XCTAssertFalse(app.buttons["export"].exists)
        let tabs=app.segmentedControls.firstMatch
        tabs.buttons["Bibliothèque de tuiles"].tap()
        XCTAssertFalse(app.buttons["export"].exists)
        tabs.buttons["Résultat"].tap()
        let export=app.buttons["export"]
        XCTAssertTrue(export.waitForExistence(timeout:5))
        XCTAssertGreaterThan(export.frame.minX-weave.frame.maxX,8)
        screenshot("iPad separate weave and export on Result")
        tabs.buttons["3D"].tap()
        XCTAssertTrue(export.exists)
        screenshot("iPad export on 3D")
        tabs.buttons["Préparer"].tap()
        XCTAssertFalse(export.exists)
    }
    @MainActor
    func testBackgroundWeaveFinishesCurrentPartThenResumesNextPart() async throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-hasShownFirstLaunchHelp","YES","--background-weave-fixture","--trace-background-weaving","-AppleLanguages","(en)","-AppleLocale","en_US"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let weave=app.buttons["weave"]
        XCTAssertTrue(weave.waitForExistence(timeout:20))
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:weave)
        waitForExpectations(timeout:20)
        weave.tap()
        let status=app.staticTexts["status"]
        expectation(for:NSPredicate(format:"label CONTAINS %@","Solving part 1 of 2"),evaluatedWith:status)
        waitForExpectations(timeout:10)
        XCUIDevice.shared.press(.home)
        // The 40-second partition deliberately exceeds the usual short grace.
        // Waiting longer also proves the second part does not start in background.
        try await Task.sleep(for:.seconds(55))
        app.activate()
        XCTAssertTrue(status.waitForExistence(timeout:15))
        expectation(for:NSPredicate(format:"value CONTAINS %@","resumedPart=2"),evaluatedWith:status)
        waitForExpectations(timeout:15)
        let trace=status.value as? String ?? ""
        XCTAssertTrue(trace.contains("pausedPart=1 completed=1"),trace)
        XCTAssertTrue(trace.contains("continued=true"),"Extended runtime was not granted: \(trace)")
        screenshot("Resumed at next partition after extended background runtime")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(weave.waitForExistence(timeout:10))
    }
    @MainActor private func screenshot(_ name:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
}
