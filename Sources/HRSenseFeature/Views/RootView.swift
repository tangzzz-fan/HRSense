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
                waveformView
                errorBannerView
                Spacer()
            }
            .padding()
        }
        .onAppear {
            store.dispatch(.startScanning)
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
            if store.state.connection == .connected {
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
        if store.state.connection != .connected && !store.state.discoveredDevices.isEmpty {
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

    // MARK: - Waveform

    @ViewBuilder
    private var waveformView: some View {
        if store.state.waveform.isStreaming {
            WaveformDisplayView(
                samples: store.state.waveform.ecgSamples,
                metrics: store.state.waveform.metrics,
                selectedType: Binding(
                    get: { store.state.waveform.selectedType },
                    set: { store.dispatch(.waveformTypeSelected($0)) }
                )
            )
        }
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
        case .connecting, .handshaking: return .yellow
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
        case .disconnecting: return "Disconnecting..."
        case .disconnected: return "Disconnected"
        }
    }

    private var canConnectToDevice: Bool {
        switch store.state.connection {
        case .idle, .scanning, .disconnected:
            return true
        case .connecting, .handshaking, .connected, .disconnecting:
            return false
        }
    }

    private func deviceDisplayName(_ device: DeviceInfo) -> String {
        if !device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return device.name
        }
        return "HRSense Peripheral"
    }
}
