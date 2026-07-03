import SwiftUI
import HRSenseSimulatorKit

struct SimulatorDashboardView: View {
    @Bindable var viewModel: SimulatorViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("HRSense Simulator")
                .font(.title)
                .bold()

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

            Picker("Mode", selection: Binding(
                get: { viewModel.selectedGeneratorMode },
                set: { viewModel.selectGeneratorMode($0) }
            )) {
                Text("Resting").tag(SimulatorLaunchOptions.GeneratorMode.resting)
                Text("Exercise").tag(SimulatorLaunchOptions.GeneratorMode.exercise)
                Text("Manual").tag(SimulatorLaunchOptions.GeneratorMode.manual)
                Text("Anomaly").tag(SimulatorLaunchOptions.GeneratorMode.anomaly)
            }
            .pickerStyle(.segmented)

            if viewModel.selectedGeneratorMode == .manual {
                HStack {
                    Text("HR: \(viewModel.currentHeartRate)")
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.currentHeartRate) },
                            set: { viewModel.setManualHR(Int($0)) }
                        ),
                        in: 30...200,
                        step: 1
                    )
                }
                .padding(.horizontal)
            }

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
