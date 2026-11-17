import Foundation
import CBCLibrary

/// Owns the native cancellation flag until both the worker and cancellation
/// handler finish. Only the C ABI's atomic operations run on cancelling threads.
final class CBCRequest: @unchecked Sendable {
    let handle: OpaquePointer
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("BraidArt-\(UUID().uuidString)",isDirectory:true)
    init() throws {
        guard let handle=braid_cbc_create() else { throw BraidError.invalid(L("Could not allocate the CBC solver.")) }
        self.handle=handle
    }
    deinit { braid_cbc_destroy(handle) }
    func cancel() { braid_cbc_cancel(handle) }
    var eventCount: UInt64 { braid_cbc_event_count(handle) }
    var searchEventCount: UInt64 { braid_cbc_search_event_count(handle) }
}

public enum CBCRunner {
    public static func solve(problem: BlockProblem, settings: Settings) async throws -> String {
        try await solve(problem:problem,settings:settings,request:CBCRequest())
    }

    static func solve(problem:BlockProblem,settings:Settings,request:CBCRequest) async throws -> String {
        try settings.validate();try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            do {
                let result=try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<String,Error>) in
                    // A blocking native solve must never occupy the main actor or a
                    // Swift cooperative executor thread. Native code serializes CBC.
                    DispatchQueue.global(qos:.userInitiated).async {
                        do { continuation.resume(returning:try solveFiles(problem:problem,settings:settings,request:request)) }
                        catch { continuation.resume(throwing:error) }
                    }
                }
                // Discard an otherwise valid solution if cancellation raced completion.
                try Task.checkCancellation()
                return result
            } catch {
                // Cancellation also wins a race against a recoverable native error.
                try Task.checkCancellation()
                throw error
            }
        } onCancel: { request.cancel() }
    }

    private static func solveFiles(problem:BlockProblem,settings:Settings,request:CBCRequest) throws -> String {
        let temp=request.directory
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temp) }
        let input=temp.appendingPathComponent("partition.lp"),seed=temp.appendingPathComponent("seed.sol")
        let output=temp.appendingPathComponent("result.sol"),log=temp.appendingPathComponent("solver.log")
        try problem.lp.write(to:input,atomically:true,encoding:.utf8)
        try problem.warmStart.write(to:seed,atomically:true,encoding:.utf8)
        var error=[CChar](repeating:0,count:2048)
        let status=braid_cbc_solve(request.handle,input.path,seed.path,output.path,log.path,
                                  settings.secondsPerPartition,settings.relativeGap,Int32(settings.threads),&error,error.count)
        switch Int(status) {
        case BRAID_CBC_OK: return try String(contentsOf:output,encoding:.utf8)
        case BRAID_CBC_CANCELLED: throw CancellationError()
        case BRAID_CBC_TIMEOUT: throw BraidError.invalid(L("CBC exceeded its time limit. Reduce the partition size."))
        default:
            let detail=String(cString:error)
            let diagnostic=(try? String(contentsOf:log,encoding:.utf8)) ?? ""
            throw BraidError.invalid(L("CBC could not solve this partition.\n%@",String((detail+"\n"+diagnostic).suffix(2500))))
        }
    }
}
