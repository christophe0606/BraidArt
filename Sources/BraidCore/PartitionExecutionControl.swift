import Foundation

/// A cooperative boundary between partitions, not a suspended solver thread.
/// The current CBC request is interrupted only if the OS withdraws background time.
public final class PartitionExecutionControl:@unchecked Sendable {
    public struct Snapshot:Sendable,Equatable {
        public let isBackground:Bool
        public let isPartitionRunning:Bool
        public let currentPartition:Int
        public let totalPartitions:Int
        public let completedPartitions:Int
        /// Genuine native solver events plus committed partitions; total work is unknown.
        public let completedWorkUnits:Int64
        public var isPaused:Bool { isBackground && !isPartitionRunning }
    }
    private struct Partition {
        let id:UUID
        var interrupted=false
        var cancel:(@Sendable()->Void)?
        var sampledEvents:UInt64=0
    }
    private final class Waiter:@unchecked Sendable {
        let id=UUID()
        var cancelled=false
        var continuation:CheckedContinuation<Void,Error>?
    }
    private let lock=NSLock()
    private let onChange:@Sendable()->Void
    private var background=false
    private var partition:Partition?
    private var waiters:[UUID:Waiter]=[:]
    private var current=0,total=0,completed=0
    private var work:Int64=0
    private var pauseStarted:Date?
    private var accumulatedPause=0.0

    public init(onChange:@escaping @Sendable()->Void = {}) { self.onChange=onChange }
    private func locked<T>(_ body:()->T)->T { lock.lock();defer { lock.unlock() };return body() }
    public var snapshot:Snapshot {
        locked { Snapshot(isBackground:background,isPartitionRunning:partition != nil,currentPartition:current,
                          totalPartitions:total,completedPartitions:completed,completedWorkUnits:work) }
    }
    public var pausedSeconds:Double {
        locked { accumulatedPause+(pauseStarted.map { Date().timeIntervalSince($0) } ?? 0) }
    }
    public func requestPauseAfterCurrentPartition() {
        locked {
            background=true
            if partition == nil,pauseStarted == nil { pauseStarted=Date() }
        }
        onChange()
    }
    public func resume() {
        let continuations:[CheckedContinuation<Void,Error>]=locked {
            background=false
            if let pauseStarted { accumulatedPause+=Date().timeIntervalSince(pauseStarted);self.pauseStarted=nil }
            let pending=waiters.values.compactMap { waiter -> CheckedContinuation<Void,Error>? in
                defer { waiter.continuation=nil };return waiter.continuation
            }
            waiters.removeAll();return pending
        }
        for continuation in continuations { continuation.resume() }
        onChange()
    }
    /// Called only for expiration/cancellation of the OS background allowance.
    /// User cancellation instead cancels the owning Swift task, including any wait.
    public func backgroundTimeExpired() {
        let cancel:(@Sendable()->Void)?=locked {
            guard background,partition != nil else { return nil }
            partition!.interrupted=true
            if pauseStarted == nil { pauseStarted=Date() }
            return partition!.cancel
        }
        cancel?()
        onChange()
    }
    public func waitUntilForeground() async throws {
        try Task.checkCancellation()
        let waiter=Waiter()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                let immediate:Result<Void,Error>?=locked {
                    if waiter.cancelled { return .failure(CancellationError()) }
                    if !background { return .success(()) }
                    waiter.continuation=continuation;waiters[waiter.id]=waiter
                    return nil
                }
                if let immediate { continuation.resume(with:immediate) }
            }
            try Task.checkCancellation()
        } onCancel: {
            let continuation=self.locked { ()->CheckedContinuation<Void,Error>? in
                waiter.cancelled=true
                self.waiters.removeValue(forKey:waiter.id)
                defer { waiter.continuation=nil }
                return waiter.continuation
            }
            continuation?.resume(throwing:CancellationError())
        }
    }
    func beginPartition(index:Int,total:Int) async throws -> UUID {
        while true {
            try await waitUntilForeground()
            let id:UUID?=locked {
                // Close the race between foreground admission and backgrounding.
                guard !background else { return nil }
                precondition(partition == nil,"A weaving run solves one partition at a time")
                let id=UUID();partition=Partition(id:id)
                self.current=index+1;self.total=total;completed=index
                return id
            }
            if let id { onChange();return id }
        }
    }
    func attachCancellation(_ id:UUID,cancel:@escaping @Sendable()->Void) {
        let interrupt=locked {
            guard partition?.id==id else { return false }
            partition!.cancel=cancel
            return partition!.interrupted
        }
        if interrupt { cancel() }
    }
    func sampleNativeEvents(_ id:UUID,count:UInt64) {
        let changed=locked {
            guard partition?.id==id,count>partition!.sampledEvents else { return false }
            work+=Int64(clamping:count-partition!.sampledEvents)
            partition!.sampledEvents=count;return true
        }
        if changed { onChange() }
    }
    @discardableResult
    func endPartition(_ id:UUID,completed:Bool)->Bool {
        let interrupted=locked {
            guard partition?.id==id else { return false }
            let interrupted=partition!.interrupted
            partition=nil
            if completed { self.completed=current;work+=1 }
            if background,pauseStarted == nil { pauseStarted=Date() }
            return interrupted
        }
        onChange();return interrupted
    }
}
