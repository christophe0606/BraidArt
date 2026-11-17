import XCTest
import AVFoundation
#if SWIFT_PACKAGE
import VideoTestSupport
#endif
@testable import BraidCore

private actor PauseProbe {
    var requested=false
    var fractions:[Double]=[]
    let expire:Bool
    init(expire:Bool) { self.expire=expire }
    func progress(_ fraction:Double,execution:PartitionExecutionControl) {
        fractions.append(fraction)
        if fraction>0,!requested {
            requested=true
            execution.requestPauseAfterCurrentPartition()
            if expire { execution.backgroundTimeExpired() }
        }
    }
}

final class PartitionPauseTests:XCTestCase {
    private func settings()->Settings {
        var settings=Settings();settings.partitionSize=2;settings.threads=1;settings.secondsPerPartition=5;settings.relativeGap=0
        return settings
    }
    private func image()->PixelImage {
        let pixels:[RGB]=(0..<24).map { index in
            let r=Double((index*37)%101)/100
            let g=Double((index*71)%101)/100
            let b=Double((index*19)%101)/100
            return RGB(r,g,b)
        }
        return PixelImage(width:6,height:4,pixels:pixels)
    }
    private func waitForPause(_ control:PartitionExecutionControl) async throws {
        let deadline=ContinuousClock.now.advanced(by:.seconds(5))
        while !control.snapshot.isPaused || control.snapshot.currentPartition==0 {
            guard ContinuousClock.now<deadline else { XCTFail("Partition did not reach its pause boundary");throw CancellationError() }
            try await Task.sleep(for:.milliseconds(10))
        }
    }
    func testBackgroundFinishesExactlyCurrentPartitionAndResumesWithoutRepeatingCommittedParts() async throws {
        let execution=PartitionExecutionControl(),probe=PauseProbe(expire:false)
        let input=image(),settings=settings(),started=Date()
        let task=Task {
            try await PartitionSolver.solve(image:input,settings:settings,execution:execution) { value,_ in
                await probe.progress(value,execution:execution)
            }
        }
        defer { task.cancel();execution.resume() }
        try await waitForPause(execution)
        XCTAssertEqual(execution.snapshot.completedPartitions,2)
        XCTAssertEqual(execution.snapshot.currentPartition,2)
        let before=await probe.fractions
        try await Task.sleep(for:.milliseconds(200))
        let after=await probe.fractions
        XCTAssertEqual(before,after,"No next partition or rendering may start while backgrounded")
        execution.resume()
        let (data,result)=try await task.value
        try result.validate(tileData:data)
        XCTAssertEqual(result.reports.count,6)
        XCTAssertEqual(result.reports.map { "\($0.row),\($0.column)" },["0,0","0,1","0,2","1,0","1,1","1,2"])
        let fractions=await probe.fractions
        XCTAssertEqual(fractions.filter { abs($0-1.0/6)<0.00001 }.count,1,"The completed second part must not be repeated")
        XCTAssertGreaterThanOrEqual(execution.pausedSeconds,0.19)
        XCTAssertGreaterThan(Date().timeIntervalSince(started)-result.elapsedSeconds,0.19)
    }
    func testExpirationRetriesOnlyUnfinishedPartitionAndDoesNotCancelWholeWeave() async throws {
        let execution=PartitionExecutionControl(),probe=PauseProbe(expire:true)
        let input=image(),settings=settings()
        let task=Task {
            try await PartitionSolver.solve(image:input,settings:settings,execution:execution) { value,_ in
                await probe.progress(value,execution:execution)
            }
        }
        defer { task.cancel();execution.resume() }
        try await waitForPause(execution)
        XCTAssertEqual(execution.snapshot.completedPartitions,1)
        XCTAssertEqual(execution.snapshot.currentPartition,2)
        XCTAssertFalse(task.isCancelled)
        execution.resume()
        let (data,result)=try await task.value
        try result.validate(tileData:data)
        XCTAssertEqual(result.reports.count,6)
        let fractions=await probe.fractions
        XCTAssertEqual(fractions.filter { abs($0-1.0/6)<0.00001 }.count,2)
        XCTAssertEqual(fractions.filter { $0==0 }.count,2,"Neither cost computation nor the first part should restart")
    }
    func testCancellationWhilePausedReturnsWithoutForegrounding() async throws {
        let execution=PartitionExecutionControl()
        execution.requestPauseAfterCurrentPartition()
        let stopped=expectation(description:"Paused weave cancels")
        let input=image(),settings=settings()
        let task=Task {
            do { _=try await PartitionSolver.solve(image:input,settings:settings,execution:execution);XCTFail("Expected cancellation") }
            catch is CancellationError {}
            catch { XCTFail("Unexpected error: \(error)") }
            stopped.fulfill()
        }
        try await Task.sleep(for:.milliseconds(50))
        task.cancel()
        await fulfillment(of:[stopped],timeout:2)
        execution.resume() // Also ensure cleanup if this regression ever fails.
        await task.value
        XCTAssertEqual(execution.snapshot.completedPartitions,0)
    }
    func testCancellationAndForegroundRacesDoNotLoseOrDoubleResumeWaiters() async throws {
        for _ in 0..<30 {
            let execution=PartitionExecutionControl()
            execution.requestPauseAfterCurrentPartition()
            let jobs=(0..<8).map { _ in Task { try await execution.waitUntilForeground() } }
            for (index,job) in jobs.enumerated() where index%2==0 { job.cancel() }
            execution.resume()
            for (index,job) in jobs.enumerated() {
                do { try await job.value;XCTAssertEqual(index%2,1) }
                catch { XCTAssertTrue(error is CancellationError);XCTAssertEqual(index%2,0) }
            }
        }
    }
    func testVideoWithAudioPausesAtSamePartitionBoundaryAndCompletesAfterResuming() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let input=folder.appendingPathComponent("input.mov"),output=folder.appendingPathComponent("output.mp4")
        try await VideoFixture.make(at:input,audio:true)
        let source=try await VideoSource.open(url:input)
        var settings=settings();settings.columns=8
        settings.outputSize = .custom(try CustomPictureSize(name:"Pause test",width:128,height:96))
        let execution=PartitionExecutionControl(),probe=PauseProbe(expire:false),snapshot=settings
        let task=Task {
            try await VideoWeaver.write(source:source,settings:snapshot,format:.mostCompatible,to:output,execution:execution) { value,_ in
                await probe.progress(value,execution:execution)
            }
        }
        defer { task.cancel();execution.resume() }
        try await waitForPause(execution)
        XCTAssertEqual(execution.snapshot.completedPartitions,2)
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertEqual(execution.snapshot.completedPartitions,2)
        execution.resume()
        let report=try await task.value
        XCTAssertEqual(report.frames,4)
        let asset=AVURLAsset(url:output)
        let videos=try await asset.loadTracks(withMediaType:.video),audio=try await asset.loadTracks(withMediaType:.audio)
        XCTAssertEqual(videos.count,1);XCTAssertEqual(audio.count,1)
    }
    func testCancellingPausedVideoDoesNotWaitForForegroundOrReplaceDestination() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let input=folder.appendingPathComponent("input.mov"),output=folder.appendingPathComponent("output.mp4")
        try await VideoFixture.make(at:input,audio:true)
        try Data("previous output".utf8).write(to:output)
        let source=try await VideoSource.open(url:input)
        var settings=settings();settings.columns=8
        settings.outputSize = .custom(try CustomPictureSize(name:"Pause test",width:128,height:96))
        let execution=PartitionExecutionControl(),probe=PauseProbe(expire:false),snapshot=settings
        let stopped=expectation(description:"Paused video cancels")
        let task=Task {
            defer { stopped.fulfill() }
            return try await VideoWeaver.write(source:source,settings:snapshot,format:.mostCompatible,to:output,execution:execution) { value,_ in
                await probe.progress(value,execution:execution)
            }
        }
        defer { task.cancel();execution.resume() }
        try await waitForPause(execution)
        task.cancel()
        await fulfillment(of:[stopped],timeout:3)
        do { _=try await task.value;XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf:output),Data("previous output".utf8))
    }

}
