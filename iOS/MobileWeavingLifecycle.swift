import UIKit
import BackgroundTasks
import BraidCore

/// Owns OS runtime only until the next safe partition boundary. The Swift task
/// then waits on a continuation, without a timer, until the app is foregrounded.
@MainActor
final class MobileWeavingLifecycle {
    private let onChange:(PartitionExecutionControl.Snapshot?)->Void
    private var observers:[NSObjectProtocol]=[]
    private var runID:UUID?
    private(set) var execution:PartitionExecutionControl?
    private var title=""
    private var cancelForeground:(()->Void)?
    private var submittedIdentifier:String?
    private var continued:AnyObject?
    private var grace=UIBackgroundTaskIdentifier.invalid
    private var lastTrace=""
    #if DEBUG
    private(set) var testPausedPart=0,testCompletedPart=0,testResumedPart=0
    private(set) var testUsedContinued=false
    #endif

    init(onChange:@escaping(PartitionExecutionControl.Snapshot?)->Void) {
        self.onChange=onChange
        observers.append(NotificationCenter.default.addObserver(forName:UIApplication.didEnterBackgroundNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.enteredBackground() }
        })
        observers.append(NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    func start(title:String,cancelForeground:@escaping()->Void)->PartitionExecutionControl {
        stopPermits(success:false)
        let id=UUID()
        let execution=PartitionExecutionControl { [weak self] in
            Task { @MainActor in self?.changed(id) }
        }
        self.execution=execution;runID=id;self.title=title;self.cancelForeground=cancelForeground
        #if DEBUG
        testPausedPart=0;testCompletedPart=0;testResumedPart=0;testUsedContinued=false
        #endif
        if UIApplication.shared.applicationState == .background { enteredBackground() }
        else { requestContinuedProcessing() }
        changed(id)
        return execution
    }
    func finish(_ execution:PartitionExecutionControl,success:Bool) {
        guard self.execution === execution else { return }
        stopPermits(success:success)
        self.execution=nil;runID=nil;cancelForeground=nil
        onChange(nil)
    }
    private func enteredBackground() {
        guard let execution else { return }
        if !hasContinuedTask,grace == .invalid {
            grace=UIApplication.shared.beginBackgroundTask(withName:"Finish current braid partition") { [weak self,weak execution] in
                MainActor.assumeIsolated {
                    guard let self,self.execution === execution else { return }
                    execution?.backgroundTimeExpired()
                    self.endGrace()
                }
            }
        }
        execution.requestPauseAfterCurrentPartition()
        if !hasContinuedTask,grace == .invalid { execution.backgroundTimeExpired() }
        if let runID { changed(runID) }
    }
    private func becameActive() {
        guard let execution else { return }
        endGrace()
        execution.resume()
        requestContinuedProcessing()
        if let runID { changed(runID) }
    }
    private var hasContinuedTask:Bool {
        if #available(iOS 26.0,*),let handle=continued as? ContinuedTaskHandle { return !handle.isFinished }
        return false
    }
    private func requestContinuedProcessing() {
        guard #available(iOS 26.0,*),UIApplication.shared.applicationState != .background,
              let execution,let runID,submittedIdentifier == nil,!hasContinuedTask else { return }
        let identifier=(Bundle.main.bundleIdentifier ?? "com.christophefav.BraidArt")+".weave."+UUID().uuidString
        // Continued tasks explicitly permit registration at the time of a user
        // request. Register the exact identifier rather than relying on matching.
        let registered=BGTaskScheduler.shared.register(forTaskWithIdentifier:identifier,using:.main) { [weak self] task in
            guard let task=task as? BGContinuedProcessingTask else { task.setTaskCompleted(success:false);return }
            MainActor.assumeIsolated {
                guard let self else { task.setTaskCompleted(success:false);return }
                self.attach(task,identifier:identifier,runID:runID,execution:execution)
            }
        }
        guard registered else { return }
        submittedIdentifier=identifier
        let request=BGContinuedProcessingTaskRequest(identifier:identifier,title:title,subtitle:L("Preparing to weave…"))
        request.strategy = .fail
        // CPU only: no subsequent image preparation, Metal render or video
        // frame is admitted once backgrounded. Only the current CBC part runs.
        do { try BGTaskScheduler.shared.submit(request) }
        catch { submittedIdentifier=nil }
    }
    @available(iOS 26.0,*)
    private func attach(_ task:BGContinuedProcessingTask,identifier:String,runID:UUID,execution:PartitionExecutionControl) {
        guard self.runID==runID,self.execution === execution,submittedIdentifier==identifier,!execution.snapshot.isPaused else {
            task.setTaskCompleted(success:false);return
        }
        let handle=ContinuedTaskHandle(task)
        continued=handle
        task.progress.totalUnitCount = -1 // A CBC search has no known total number of steps.
        task.expirationHandler = { [weak self,weak execution,weak handle] in
            let wasBackground=execution?.snapshot.isBackground ?? true
            if wasBackground { execution?.backgroundTimeExpired() }
            handle?.finish(success:false)
            Task { @MainActor in
                guard let self,self.runID==runID,self.submittedIdentifier==identifier else { return }
                self.continued=nil;self.submittedIdentifier=nil
                // In the foreground, honor cancellation from the system's Live
                // Activity as cancellation of the user job. In the background,
                // keep completed parts and wait for the next activation.
                if !wasBackground { self.cancelForeground?() }
                self.changed(runID)
            }
        }
        endGrace()
        changed(runID)
    }
    private func changed(_ id:UUID) {
        guard id==runID,let execution else { return }
        let state=execution.snapshot
        #if DEBUG
        if state.isBackground,hasContinuedTask { testUsedContinued=true }
        if state.isPaused { testPausedPart=state.currentPartition;testCompletedPart=state.completedPartitions }
        if !state.isBackground,testPausedPart>0,state.currentPartition>testPausedPart { testResumedPart=state.currentPartition }
        #endif
        onChange(state)
        if state.isPaused {
            if #available(iOS 26.0,*),let handle=continued as? ContinuedTaskHandle {
                handle.update(title:L("Weaving paused"),subtitle:L("Return to BraidArt to continue."))
            }
            stopPermits(success:true)
        }
        else if #available(iOS 26.0,*),let handle=continued as? ContinuedTaskHandle,!handle.isFinished {
            handle.task.progress.completedUnitCount=state.completedWorkUnits
            let subtitle=state.currentPartition>0 ? L("Part %@ of %@",String(state.currentPartition),String(state.totalPartitions)) : L("Preparing to weave…")
            handle.update(title:state.isBackground ? L("Finishing current partition") : title,subtitle:subtitle)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--trace-background-weaving") {
            let mode=hasContinuedTask ? "continued" : grace != .invalid ? "grace" : "none"
            let trace="background=\(state.isBackground) paused=\(state.isPaused) part=\(state.currentPartition) completed=\(state.completedPartitions) runtime=\(mode)"
            if trace != lastTrace { print("BRAID_WEAVE \(trace)");fflush(stdout);lastTrace=trace }
        }
        #endif
    }
    private func endGrace() {
        guard grace != .invalid else { return }
        let task=grace;grace = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
    private func stopPermits(success:Bool) {
        let identifier=submittedIdentifier
        submittedIdentifier=nil
        if #available(iOS 26.0,*),let handle=continued as? ContinuedTaskHandle {
            // Complete a delivered task directly; cancel only an undelivered request.
            handle.finish(success:success)
        } else if let identifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:identifier) }
        continued=nil
        endGrace()
    }
}

@available(iOS 26.0,*)
private final class ContinuedTaskHandle:@unchecked Sendable {
    let task:BGContinuedProcessingTask
    private let lock=NSLock()
    private var finished=false
    private var lastTitle="",lastSubtitle=""
    var isFinished:Bool { lock.lock();defer { lock.unlock() };return finished }
    init(_ task:BGContinuedProcessingTask) { self.task=task }
    func update(title:String,subtitle:String) {
        guard !isFinished,title != lastTitle || subtitle != lastSubtitle else { return }
        lastTitle=title;lastSubtitle=subtitle;task.updateTitle(title,subtitle:subtitle)
    }
    func finish(success:Bool) {
        lock.lock()
        guard !finished else { lock.unlock();return }
        finished=true;lock.unlock()
        task.expirationHandler=nil
        if success {
            task.progress.totalUnitCount=max(1,task.progress.completedUnitCount)
            task.progress.completedUnitCount=task.progress.totalUnitCount
        }
        task.setTaskCompleted(success:success)
    }
}
