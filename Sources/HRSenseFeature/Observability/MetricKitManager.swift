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

    private override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
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
                    onDiagnosticReceived?(info, transitions)
                }
            }

            if let hangDiag = payload.hangDiagnostics {
                for hang in hangDiag {
                    let duration = hang.hangDuration.value / 1_000_000_000.0
                    let info = "HANG: duration=\(String(format: "%.1f", duration))s"
                    HRSenseLogging.error(.state, info)
                    onDiagnosticReceived?(info, transitions)
                }
            }

            if let cpuDiag = payload.cpuExceptionDiagnostics {
                let info = "CPU_EXCEPTION: count=\(cpuDiag.count)"
                HRSenseLogging.error(.state, info)
                onDiagnosticReceived?(info, transitions)
            }
        }
    }
}
