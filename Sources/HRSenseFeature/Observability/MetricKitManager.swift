import Foundation
import MetricKit
import HRSenseProtocol

/// MetricKit manager — subscribes to crash/hang/CPU diagnostic reports.
///
/// Associates crash reports with the most recent state transitions from
/// StateTransitionRecorder (defined in LoggingMiddleware).
public final class MetricKitManager: NSObject, @unchecked Sendable {
    public static let shared = MetricKitManager()

    /// Callback: invoked when a new diagnostic payload is received.
    public var onDiagnosticReceived: ((String, [String]) -> Void)?
    private let lock = NSLock()
    private var diagnosticsHistory: [String] = []

    private override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    public var recentDiagnostics: [String] {
        lock.withLock { diagnosticsHistory }
    }

    public func recordDebugDiagnostic(_ info: String, transitions: [String]) {
        let entry = ([info] + transitions.prefix(5)).joined(separator: "\n")
        lock.withLock { diagnosticsHistory.append(entry) }
        onDiagnosticReceived?(info, transitions)
    }

    private func appendDiagnostic(_ info: String, transitions: [String]) {
        let entry = ([info] + transitions.prefix(5)).joined(separator: "\n")
        lock.withLock { diagnosticsHistory.append(entry) }
        onDiagnosticReceived?(info, transitions)
    }
}

// MARK: - MXMetricManagerSubscriber

extension MetricKitManager: MXMetricManagerSubscriber {

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let transitions = StateTransitionRecorder.shared.recentTransitions

            if let crashDiag = payload.crashDiagnostics {
                for crash in crashDiag {
                    let reason = crash.terminationReason ?? "unknown"
                    let info = "CRASH: reason=\(reason)"
                    HRSenseLogging.fault(.state, info)
                    appendDiagnostic(info, transitions: transitions)
                }
            }

            if let hangDiag = payload.hangDiagnostics {
                for hang in hangDiag {
                    let duration = hang.hangDuration.value / 1_000_000_000.0
                    let info = "HANG: duration=\(String(format: "%.1f", duration))s"
                    HRSenseLogging.error(.state, info)
                    appendDiagnostic(info, transitions: transitions)
                }
            }

            if let cpuDiag = payload.cpuExceptionDiagnostics {
                let info = "CPU_EXCEPTION: count=\(cpuDiag.count)"
                HRSenseLogging.error(.state, info)
                appendDiagnostic(info, transitions: transitions)
            }
        }
    }
}
