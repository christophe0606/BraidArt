import XCTest
import CBCLibrary
import Darwin
@testable import BraidCore

final class CBCLibraryTests: XCTestCase {
    private func problem(size:Int=2,colors:Int=2) throws -> (BlockProblem,Settings,TileData) {
        var settings=Settings();settings.partitionSize=min(size,20);settings.secondsPerPartition=60
        settings.relativeGap=0;settings.threads=1
        settings.palette=[RGB.black,RGB.white,RGB(0.8,0.1,0.2),RGB(0.1,0.4,0.9)].prefix(colors).map{$0}
        let image=PixelImage(width:size,height:size,pixels:(0..<(size*size)).map { i in
            RGB(Double((i*37)%101)/100,Double((i*71)%101)/100,Double((i*19)%101)/100)
        })
        let data=TileData(settings:settings),costs=try CostEngine.compute(image:image,tiles:data,useGPU:false)
        return (try PartitionSolver.makeProblem(block:Block(x:0,y:0,width:size,height:size),image:image,data:data,costs:costs),settings,data)
    }

    private func waitForEvents(_ request:CBCRequest) async throws {
        let limit=Date().addingTimeInterval(10)
        while request.eventCount < 10,Date()<limit { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertGreaterThanOrEqual(request.eventCount,10,"Cancellation must reach a real native solve")
    }

    func testTaskCancellationDuringNativeSolveCleansFilesAndNextSolveWorks() async throws {
        for threads in [1,4] {
            var (problem,settings,_)=try problem(size:20,colors:4)
            settings.threads=threads
            let request=try CBCRequest()
            let task=Task { try await CBCRunner.solve(problem:problem,settings:settings,request:request) }
            do { try await waitForEvents(request) }
            catch { task.cancel();_ = try? await task.value;throw error }
            XCTAssertTrue(FileManager.default.fileExists(atPath:request.directory.path))
            let cancelledAt=Date();task.cancel()
            do { _=try await task.value;XCTFail("Expected cancellation") }
            catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertLessThan(Date().timeIntervalSince(cancelledAt),5)
            XCTAssertFalse(FileManager.default.fileExists(atPath:request.directory.path))
        }
        let (small,settings,data)=try problem()
        let text=try await CBCRunner.solve(problem:small,settings:settings)
        XCTAssertTrue(try PartitionSolver.parseSolution(text,problem:small,data:data).optimal)
    }

    func testCancellationBeforeStartDoesNotCreateFiles() async throws {
        let (problem,settings,_)=try problem(),request=try CBCRequest()
        let task=Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CBCRunner.solve(problem:problem,settings:settings,request:request)
        }
        do { _=try await task.value;XCTFail("Expected cancellation") }
        catch is CancellationError {}
        XCTAssertEqual(request.eventCount,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:request.directory.path))
    }

    func testQueuedCancellationDoesNotCancelActiveSolve() async throws {
        let (large,settings,_)=try problem(size:20,colors:4)
        let active=try CBCRequest(),queued=try CBCRequest()
        let first=Task { try await CBCRunner.solve(problem:large,settings:settings,request:active) }
        try await waitForEvents(active)
        let second=Task { try await CBCRunner.solve(problem:large,settings:settings,request:queued) }
        try await Task.sleep(nanoseconds:30_000_000)
        XCTAssertEqual(queued.eventCount,0)
        second.cancel()
        do { _=try await second.value;XCTFail("Expected queued cancellation") }
        catch is CancellationError {}
        let eventsBefore=active.eventCount
        try await Task.sleep(nanoseconds:20_000_000)
        XCTAssertGreaterThan(active.eventCount,eventsBefore)
        first.cancel()
        do { _=try await first.value;XCTFail("Expected active cancellation") }
        catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath:active.directory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:queued.directory.path))
    }

    func testMalformedLPReturnsErrorCleansFilesAndRecovers() async throws {
        var (problem,settings,data)=try problem()
        let valid=problem
        for invalid in ["This is not an LP model\n",String(valid.lp.dropLast(5)),
                        valid.lp.replacingOccurrences(of:"Subject To",with:"Unexpected"),
                        valid.lp.replacingOccurrences(of:"choose0:",with:":"),
                        valid.lp.replacingOccurrences(of:" obj:",with:" obj: NaN"),
                        valid.lp.replacingOccurrences(of:"Binary\n",with:"Binary\nunknown_variable\n")] {
            let request=try CBCRequest();problem.lp=invalid
            do { _=try await CBCRunner.solve(problem:problem,settings:settings,request:request);XCTFail("Expected invalid model") }
            catch is CancellationError { XCTFail("A malformed model is not cancellation") }
            catch { XCTAssertTrue(error.localizedDescription.contains("CBC")) }
            XCTAssertFalse(FileManager.default.fileExists(atPath:request.directory.path))
        }
        let text=try await CBCRunner.solve(problem:valid,settings:settings)
        XCTAssertTrue(try PartitionSolver.parseSolution(text,problem:valid,data:data).optimal)
    }

    func testInfeasibleSolveIsRejectedAndNextSolveWorks() async throws {
        var (problem,settings,data)=try problem()
        let valid=problem,request=try CBCRequest()
        problem.lp=problem.lp.replacingOccurrences(of:"Binary\n",
            with:" mustselect: + x0_1 = 1\n mustreject: + x0_1 = 0\nBinary\n")
        let text=try await CBCRunner.solve(problem:problem,settings:settings,request:request)
        XCTAssertThrowsError(try PartitionSolver.parseSolution(text,problem:problem,data:data))
        XCTAssertFalse(FileManager.default.fileExists(atPath:request.directory.path))
        let recovered=try await CBCRunner.solve(problem:valid,settings:settings)
        XCTAssertTrue(try PartitionSolver.parseSolution(recovered,problem:valid,data:data).optimal)
    }

    func testRepeatedAndConcurrentSolvesKeepNamesSeamsAndSignalHandler() async throws {
        var before=sigaction(),after=sigaction()
        XCTAssertEqual(sigaction(SIGINT,nil,&before),0)
        let (problem,settings,data)=try problem()
        try await withThrowingTaskGroup(of:String.self) { group in
            for _ in 0..<8 { group.addTask { try await CBCRunner.solve(problem:problem,settings:settings) } }
            for try await text in group {
                let parsed=try PartitionSolver.parseSolution(text,problem:problem,data:data)
                XCTAssertEqual(parsed.ids.count,4);XCTAssertTrue(parsed.optimal)
            }
        }
        XCTAssertEqual(sigaction(SIGINT,nil,&after),0)
        XCTAssertEqual(unsafeBitCast(before.__sigaction_u.__sa_handler,to:UInt.self),
                       unsafeBitCast(after.__sigaction_u.__sa_handler,to:UInt.self))
        XCTAssertEqual(before.sa_flags,after.sa_flags)
    }

    func testTimeLimitedSolveRetainsFeasibleIncumbent() async throws {
        var (problem,settings,data)=try problem(size:20,colors:4)
        settings.secondsPerPartition=1;settings.threads=4
        let started=Date(),text=try await CBCRunner.solve(problem:problem,settings:settings)
        XCTAssertLessThan(Date().timeIntervalSince(started),10)
        let parsed=try PartitionSolver.parseSolution(text,problem:problem,data:data)
        XCTAssertEqual(parsed.ids.count,400)
        XCTAssertFalse(parsed.optimal,"Exercise an actual time-limited incumbent")
    }

    func testCancellationDuringBranchAndBoundWithSolverThreads() async throws {
        var (problem,settings,_)=try problem(size:20,colors:4)
        settings.threads=4
        let request=try CBCRequest()
        let task=Task { try await CBCRunner.solve(problem:problem,settings:settings,request:request) }
        let limit=Date().addingTimeInterval(15)
        while request.searchEventCount == 0,Date()<limit { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertGreaterThan(request.searchEventCount,0,"Must reach branch-and-bound, beyond initial LP solving")
        let started=Date();task.cancel()
        do { _=try await task.value;XCTFail("Expected cancellation") }
        catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(started),5)
        XCTAssertFalse(FileManager.default.fileExists(atPath:request.directory.path))
    }

    func testNativeMissingInputAndUnwritableOutputReturnErrors() throws {
        let (problem,settings,_)=try problem(),request=try CBCRequest()
        let folder=request.directory
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let lp=folder.appendingPathComponent("input.lp"),seed=folder.appendingPathComponent("seed.sol")
        let output=folder.appendingPathComponent("missing/result.sol"),log=folder.appendingPathComponent("log")
        func run(_ request:CBCRequest)->(Int,String) {
            var error=[CChar](repeating:0,count:1024)
            let status=braid_cbc_solve(request.handle,lp.path,seed.path,output.path,log.path,
                settings.secondsPerPartition,settings.relativeGap,1,&error,error.count)
            return (Int(status),String(cString:error))
        }
        let missing=run(request)
        XCTAssertEqual(missing.0,BRAID_CBC_ERROR);XCTAssertFalse(missing.1.isEmpty)
        try problem.lp.write(to:lp,atomically:true,encoding:.utf8)
        try problem.warmStart.write(to:seed,atomically:true,encoding:.utf8)
        let unwritable=run(try CBCRequest())
        XCTAssertEqual(unwritable.0,BRAID_CBC_ERROR);XCTAssertFalse(unwritable.1.isEmpty)
    }
}
