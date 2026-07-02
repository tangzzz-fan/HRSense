import SwiftUI
import HRSenseSimulatorKit

struct ContentView: View {
    @Bindable var viewModel: SimulatorViewModel

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("HRSense Simulator")
                .font(.title)
                .bold()

            // Heart rate display
            VStack {
                Text("\(viewModel.currentHeartRate)")
                    .font(.system(size: 64, weight: .thin, design: .rounded))
                Text("BPM")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(viewModel.connectionStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Generator picker
            Picker("Mode", selection: $viewModel.selectedGeneratorMode) {
                Text("Resting").tag("resting")
                Text("Exercise").tag("exercise")
                Text("Manual").tag("manual")
                Text("Anomaly").tag("anomaly")
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedGeneratorMode) {
                viewModel.toggleGeneratorMode()
            }

            // Manual HR slider
            if viewModel.selectedGeneratorMode == "manual" {
                HStack {
                    Text("HR: \(viewModel.currentHeartRate)")
                    Slider(value: Binding(
                        get: { Double(viewModel.currentHeartRate) },
                        set: { viewModel.setManualHR(Int($0)) }
                    ), in: 30...200, step: 1)
                }
                .padding(.horizontal)
            }

            // Control buttons
            HStack(spacing: 16) {
                if !viewModel.isAdvertising {
                    Button("Start Advertising") {
                        viewModel.startAdvertising()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Stop Advertising") {
                        viewModel.stopAdvertising()
                    }
                    .buttonStyle(.bordered)
                }

                if viewModel.isStreaming {
                    Button("Stop Stream") {
                        viewModel.stopStream()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button("Start Stream") {
                        viewModel.startStream()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }

            // Stats
            GroupBox("Stats") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Samples: \(viewModel.sampleCount)")
                        Text("State: \(String(describing: viewModel.deviceState))")
                    }
                    Spacer()
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}
