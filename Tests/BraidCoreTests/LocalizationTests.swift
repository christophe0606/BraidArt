import XCTest
@testable import BraidCore

final class LocalizationTests: XCTestCase {
    private func bundle(_ language:String) throws -> Bundle {
        let url=try XCTUnwrap(Bundle.module.url(forResource:language,withExtension:"lproj"))
        return try XCTUnwrap(Bundle(url:url))
    }

    private func table(_ language:String) throws -> [String:String] {
        let url=try XCTUnwrap(try bundle(language).url(forResource:"Localizable",withExtension:"strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from:Data(contentsOf:url),format:nil) as? [String:String])
    }

    func testFrenchAndEnglishTablesCoverTheSameMessagesAndFormatArguments() throws {
        let english=try table("en"),french=try table("fr")
        XCTAssertGreaterThan(english.count,300)
        XCTAssertEqual(Set(english.keys),Set(french.keys))
        let formats=try NSRegularExpression(pattern:"%(?:[0-9]+\\$)?(?:[0-9]+)?(?:\\.[0-9]+)?[@df%]")
        func placeholders(_ text:String)->[String] {
            formats.matches(in:text,range:NSRange(text.startIndex...,in:text)).map {
                String(text[Range($0.range,in:text)!])
            }
        }
        for (key,value) in english {
            // The phone tab needs a shorter French translation while retaining
            // the same English text as the full library title.
            let developmentText=key=="Tile Library tab" ? "Tile Library" : key
            XCTAssertEqual(value,developmentText,"English remains the development text")
            let translated=try XCTUnwrap(french[key])
            XCTAssertFalse(translated.isEmpty,key)
            XCTAssertEqual(placeholders(value),placeholders(translated),key)
        }
    }

    func testStandardMacLanguageMatchingAndEnglishFallback() {
        for language in ["fr","fr-FR","fr-CA","fr-CH"] {
            XCTAssertEqual(Bundle.preferredLocalizations(from:["en","fr"],forPreferences:[language]).first,"fr")
        }
        for language in ["en","en-GB","de","ja","es"] {
            XCTAssertEqual(Bundle.preferredLocalizations(from:["en","fr"],forPreferences:[language]).first,"en")
        }
    }

    func testFrenchLookupAndFormattedMessages() throws {
        let french=try bundle("fr")
        XCTAssertEqual(NSLocalizedString("Weave Image",bundle:french,comment:""),"Tresser l’image")
        let crop=NSLocalizedString("Crop: %@%% × %@%% of source",bundle:french,comment:"")
        XCTAssertEqual(String(format:crop,"50","75"),"Recadrage : 50% × 75% de l’image source")
        let part=NSLocalizedString("Solving part %@ of %@ · %@ × %@ tiles",bundle:french,comment:"")
        XCTAssertEqual(String(format:part,"2","6","10","8"),"Résolution de la partie 2 sur 6 · 10 × 8 tuiles")
    }

    func testLookupUsesTheBundleSelectedByMacOS() throws {
        let language=try XCTUnwrap(Bundle.module.preferredLocalizations.first)
        let selected=try bundle(language)
        XCTAssertEqual(L("Weave Image"),NSLocalizedString("Weave Image",bundle:selected,comment:""))
        let format=NSLocalizedString("Saved %@",bundle:selected,comment:"")
        XCTAssertEqual(L("Saved %@","portrait.png"),String(format:format,"portrait.png"))
        XCTAssertEqual(L("Exact (0%)"),NSLocalizedString("Exact (0%)",bundle:selected,comment:""))
    }
}
