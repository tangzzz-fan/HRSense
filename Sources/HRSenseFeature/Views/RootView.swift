import SwiftUI
import HRSenseCore
import TGReduxKit

/// Root view that composes all sub-views and connects to the Redux store.
public struct RootView: View {
    @Environment(Store<AppState, Action>.self) private var store

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectionStatusView
                discoveredDevicesView
                deviceInfoView
                heartRateView
                inferenceResultView
                waveformSectionView
                sleepMonitoringView
                sleepHistoryView
                errorBannerView
                Spacer(minLength: 24)
            }
            .padding()
        }
        .onAppear {
            store.dispatch(.appLaunched)
            store.dispatch(.sleep(.historyLoadRequested(limit: 7)))
        }
    }

    // MARK: - Connection status

    @ViewBuilder
    private var connectionStatusView: some View {
        HStack {
            Circle()
                .fill(connectionColor)
                .frame(width: 10, height: 10)
            Text(connectionLabel)
                .font(.caption)
            Spacer()
            if store.state.connection == .connected || store.state.connection == .restoredConnected {
                Button("Disconnect") {
                    store.dispatch(.disconnect)
                }
                .buttonStyle(.bordered)
            } else if store.state.connection == .idle || store.state.connection == .disconnected {
                Button("Scan") {
                    store.dispatch(.startScanning)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Device info

    @ViewBuilder
    private var discoveredDevicesView: some View {
        if store.state.connection != .connected && store.state.connection != .restoredConnected && !store.state.discoveredDevices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Available Devices")
                    .font(.headline)

                ForEach(store.state.discoveredDevices, id: \.peripheralIdentifier) { device in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(deviceDisplayName(device))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(device.peripheralIdentifier.uuidString)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("Connect") {
                            store.dispatch(.connect(deviceID: device.peripheralIdentifier))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canConnectToDevice)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
    }

    // MARK: - Device info

    @ViewBuilder
    private var deviceInfoView: some View {
        if let device = store.state.device {
            Text("\(device.model) v\(device.firmwareVersion)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Heart rate

    @ViewBuilder
    private var heartRateView: some View {
        VStack {
            if let hr = store.state.live.currentHeartRate {
                Text("\(hr)")
                    .font(.system(size: 72, weight: .thin, design: .rounded))
                Text("BPM")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else {
                Text("--")
                    .font(.system(size: 72, weight: .thin, design: .rounded))
                    .foregroundColor(.secondary)
                Text("BPM")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 32)
    }

    // MARK: - Inference result

    @ViewBuilder
    private var inferenceResultView: some View {
        if let result = store.state.inference.latestResult {
            HStack(spacing: 8) {
                Image(systemName: result.label == "Stress" ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundColor(result.label == "Stress" ? .orange : .green)
                Text(result.label)
                    .font(.headline)
                    .fontWeight(.semibold)
                if let prob = result.probabilities[result.label] {
                    Text(String(format: "(%.0f%%)", prob * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(result.modelVersion)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if result.inferenceTimeMs > 0 {
                    Text(String(format: "%.1f ms", result.inferenceTimeMs))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill((result.label == "Stress" ? Color.orange : Color.green).opacity(0.12))
            )
            .padding(.horizontal)
        }
    }

    // MARK: - Sleep

    @ViewBuilder
    private var sleepMonitoringView: some View {
        if let session = store.state.sleep.currentSession {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sleep Monitoring")
                        .font(.headline)
                    Spacer()
                    Text(store.state.sleep.statusLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let inference = store.state.sleep.lastInference {
                    HStack(spacing: 8) {
                        Text(inference.stage.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(String(format: "%.0f%%", inference.confidence * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(inference.modelVersion)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                SleepHypnogramView(session: session)

                if let latestInput = store.state.sleep.latestWindowInput {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sleep Model Contract v\(latestInput.contractVersion)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(SleepModelFeatureSpec.orderedFeatureNames.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sleepHistoryView: some View {
        let historicalSessions = store.state.sleep.recentSessions.filter {
            $0.id != store.state.sleep.currentSession?.id
        }

        if !historicalSessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Sleep Sessions")
                    .font(.headline)

                ForEach(Array(historicalSessions.prefix(3))) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Self.dateFormatter.string(from: session.date))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(session.stages.count) segments")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        SleepHypnogramView(session: session)
                    }
                }
            }
        }
    }

    // MARK: - Waveform

    @ViewBuilder
    private var waveformSectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack {
                Text("Waveform")
                    .font(.headline)
                Spacer()
                if store.state.waveform.isStreaming {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Idle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if store.state.waveform.isStreaming {
                WaveformDisplayView(
                    samples: displayedWaveformSamples,
                    metrics: store.state.waveform.metrics,
                    selectedType: Binding(
                        get: { store.state.waveform.selectedType },
                        set: { store.dispatch(.waveformTypeSelected($0)) }
                    )
                )
            } else {
                // Placeholder when no waveform stream is active
                VStack(spacing: 12) {
                    WaveformCanvasView(samples: [], waveformType: .ecg, windowSeconds: 5)
                        .frame(height: 120)
                        .background(Color.black.opacity(0.04))
                        .cornerRadius(8)
                        .overlay {
                            Text("Waiting for waveform data…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                    Picker("Type", selection: Binding(
                        get: { store.state.waveform.selectedType },
                        set: { store.dispatch(.waveformTypeSelected($0)) }
                    )) {
                        Text("ECG").tag(WaveformType.ecg)
                        Text("PPG").tag(WaveformType.ppg)
                    }
                    .pickerStyle(.segmented)
                    .disabled(true)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBannerView: some View {
        if let error = store.state.error {
            HStack {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    store.dispatch(.dismissError)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.red.opacity(0.8))
            .cornerRadius(8)
        }
    }

    // MARK: - Helpers

    private var connectionColor: Color {
        switch store.state.connection {
        case .connected: return .green
        case .connecting, .handshaking, .restoredValidating: return .yellow
        case .restored, .restoredConnected: return .mint
        case .disconnecting: return .orange
        case .disconnected, .idle: return .gray
        case .scanning: return .blue
        }
    }

    private var connectionLabel: String {
        switch store.state.connection {
        case .idle: return "Idle"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .handshaking: return "Handshaking..."
        case .connected: return "Connected"
        case .restored: return "Restoring Previous Device..."
        case .restoredValidating: return "Validating Previous Device..."
        case .restoredConnected: return "Connected"
        case .disconnecting: return "Disconnecting..."
        case .disconnected: return "Disconnected"
        }
    }

    private var canConnectToDevice: Bool {
        switch store.state.connection {
        case .idle, .scanning, .disconnected:
            return true
        case .connecting, .handshaking, .connected, .restored, .restoredValidating, .restoredConnected, .disconnecting:
            return false
        }
    }

    private func deviceDisplayName(_ device: DeviceInfo) -> String {
        if !device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return device.name
        }
        return "HRSense Peripheral"
    }

    private var displayedWaveformSamples: [WaveformSample] {
        switch store.state.waveform.selectedType {
        case .ecg:
            return store.state.waveform.ecgSamples
        case .ppg:
            return store.state.waveform.ppgSamples
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private extension SleepState {
    var statusLabel: String {
        switch status {
        case .idle: return "Idle"
        case .monitoring: return "Monitoring"
        case .inferring: return "Inferring"
        case .ready: return "Ready"
        }
    }
}

private extension SleepStage {
    var displayName: String {
        switch self {
        case .wake: return "Wake"
        case .light: return "Light"
        case .deep: return "Deep"
        case .rem: return "REM"
        }
    }
}
