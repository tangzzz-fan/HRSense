import SwiftUI
import HRSenseCore

/// Root view that composes all sub-views and connects to the Redux store.
public struct RootView: View {
    @EnvironmentObject private var store: StoreWrapper<AppState, Action>

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            connectionStatusView
            heartRateView
            errorBannerView
            Spacer()
        }
        .padding()
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
}

// MARK: - Store wrapper (erase Store generic types for EnvironmentObject)

/// Type-erased store wrapper for SwiftUI EnvironmentObject injection.
/// TGReduxKit's Store<State, Action> is used directly via its
/// `storeProvider` modifier; this wrapper exists for preview/test contexts.
public final class StoreWrapper<State: Equatable & Sendable, A: Equatable & Sendable>: ObservableObject {
    @Published var state: State
    private let _dispatch: (A) -> Void

    public init(state: State, dispatch: @escaping (A) -> Void) {
        self.state = state
        self._dispatch = dispatch
    }

    public func dispatch(_ action: A) {
        _dispatch(action)
    }
}
