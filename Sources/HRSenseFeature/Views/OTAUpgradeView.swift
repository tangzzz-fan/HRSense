import SwiftUI
import HRSenseCore

/// OTA upgrade progress view.
public struct OTAUpgradeView: View {
    public let progress: OTAProgress
    public let onCancel: () -> Void

    public init(progress: OTAProgress, onCancel: @escaping () -> Void) {
        self.progress = progress
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 24) {
            Text("Firmware Upgrade")
                .font(.title2).bold()

            // Phase indicator
            OTAProgressBar(phase: progress.phase)

            // Cancel button
            if progress.phase != .completed(newVersion: "") && progress.phase != .failed(error: "") {
                Button("Cancel", role: .destructive) { onCancel() }
            }
        }
        .padding()
    }
}

/// Monotonic progress bar for OTA.
public struct OTAProgressBar: View {
    public let phase: OTAPhase

    public init(phase: OTAPhase) {
        self.phase = phase
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Progress
            let prog: Double = {
                switch phase {
                case .transferring(let p): return p
                case .validating: return 0.95
                case .applying: return 0.98
                case .completed: return 1.0
                default: return 0
                }
            }()

            ProgressView(value: prog)
                .progressViewStyle(.linear)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(String(format: "%.0f%%", prog * 100))
                .font(.headline)
        }
    }

    private var label: String {
        switch phase {
        case .idle: return "Ready"
        case .preparing: return "Preparing..."
        case .transferring: return "Transferring firmware..."
        case .validating: return "Validating..."
        case .applying: return "Applying update..."
        case .completed(let v): return "Upgraded to \(v)"
        case .failed(let e): return "Failed: \(e)"
        }
    }
}
