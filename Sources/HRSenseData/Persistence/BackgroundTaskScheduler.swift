import Foundation
import HRSenseProtocol
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif

/// Cross-platform wrapper around BGTaskScheduler. On iOS it registers a real
/// app-refresh task; on other platforms it keeps launch-triggered cleanup only.
public final class BackgroundTaskScheduler: @unchecked Sendable {
    public static let retentionCleanupIdentifier = "com.hrsense.retention.cleanup"

    private let taskIdentifier: String
    private let earliestBeginDelay: TimeInterval
    private let performCleanup: @Sendable () async -> Void

    public init(
        taskIdentifier: String = BackgroundTaskScheduler.retentionCleanupIdentifier,
        earliestBeginDelay: TimeInterval = 15 * 60,
        performCleanup: @escaping @Sendable () async -> Void
    ) {
        self.taskIdentifier = taskIdentifier
        self.earliestBeginDelay = earliestBeginDelay
        self.performCleanup = performCleanup
    }

    public convenience init(
        cleanupTask: RetentionCleanupTask,
        taskIdentifier: String = BackgroundTaskScheduler.retentionCleanupIdentifier,
        earliestBeginDelay: TimeInterval = 15 * 60
    ) {
        self.init(
            taskIdentifier: taskIdentifier,
            earliestBeginDelay: earliestBeginDelay
        ) {
            do {
                _ = try await cleanupTask.run()
            } catch {
                HRSenseLogging.error(.perf, "Retention cleanup failed: \(error)")
            }
        }
    }

    public func activate() {
        register()
        scheduleNextRun()
        runLaunchSweep()
    }

    public func runLaunchSweep() {
        Task(priority: .utility) {
            await performCleanup()
        }
    }

    public func register() {
#if canImport(BackgroundTasks) && os(iOS)
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: taskIdentifier,
                using: nil
            ) { [weak self] task in
                guard
                    let self,
                    let refreshTask = task as? BGAppRefreshTask
                else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.handle(refreshTask)
            }
        }
#endif
    }

    public func scheduleNextRun() {
#if canImport(BackgroundTasks) && os(iOS)
        if #available(iOS 13.0, *) {
            let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: earliestBeginDelay)

            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                HRSenseLogging.error(.perf, "Failed to submit retention background task: \(error)")
            }
        }
#endif
    }
}

#if canImport(BackgroundTasks) && os(iOS)
@available(iOS 13.0, *)
private extension BackgroundTaskScheduler {
    func handle(_ task: BGAppRefreshTask) {
        scheduleNextRun()

        let completionGate = BGTaskCompletionGate()
        let operation = Task(priority: .utility) {
            await performCleanup()
            completionGate.finish(task: task, success: !Task.isCancelled)
        }

        task.expirationHandler = {
            operation.cancel()
            completionGate.finish(task: task, success: false)
        }
    }
}

@available(iOS 13.0, *)
private final class BGTaskCompletionGate {
    private let lock = NSLock()
    private var isCompleted = false

    func finish(task: BGTask, success: Bool) {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !isCompleted else { return false }
            isCompleted = true
            return true
        }

        guard shouldFinish else { return }
        task.setTaskCompleted(success: success)
    }
}
#endif
