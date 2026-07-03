import SwiftUI
import HRSenseCore
import HRSenseProtocol

#if DEBUG

/// Debug diagnostics panel — toggled via developer gesture (e.g., triple-tap logo).
///
/// Sections:
///   1. Real-time KPI metrics (6 KPIs, 1s refresh)
///   2. Log category toggles + level selector
///   3. MetricKit diagnostics (crash/hang/CPU exceptions)
///   4. Diagnostic export (JSON → Share sheet)
public struct DiagnosticPanelView: View {
    @EnvironmentObject private var model: DiagnosticPanelModel
    @State private var logCategories: [HRSenseLogCategory: Bool] = [:]
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                // Section 1: KPIs
                Section("Real-time Metrics") {
                    kpiRow("Connection Rate", String(format: "%.0f%%", model.kpi.connectionSuccessRate * 100))
                    kpiRow("Reconnects", "\(model.kpi.reconnectCount)")
                    kpiRow("Cmd Timeout Rate", String(format: "%.1f%%", model.kpi.commandTimeoutRate * 100))
                    kpiRow("Sample Loss Rate", String(format: "%.1f%%", model.kpi.sampleLossRate * 100))
                    kpiRow("Throughput", throughputLabel)
                    kpiRow("OTA Success Rate", String(format: "%.0f%%", model.kpi.otaSuccessRate * 100))
                }

                // Section 2: Log toggles
                Section("Log Categories") {
                    ForEach(Array(logCategories.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.rawValue) { cat in
                        Toggle(cat.rawValue, isOn: Binding(
                            get: { logCategories[cat] ?? LoggingRegistry.shared.filter.isCategoryEnabled(cat) },
                            set: {
                                logCategories[cat] = $0
                                LoggingRegistry.shared.filter.setEnabled(cat, enabled: $0)
                            }
                        ))
                    }
                    Picker(
                        "Min Level",
                        selection: Binding(
                            get: { LoggingRegistry.shared.filter.minimumLevel },
                            set: { LoggingRegistry.shared.filter.setMinimumLevel($0) }
                        )
                    ) {
                        Text("Debug").tag(HRSenseLogLevel.debug)
                        Text("Info").tag(HRSenseLogLevel.info)
                        Text("Notice").tag(HRSenseLogLevel.notice)
                        Text("Error").tag(HRSenseLogLevel.error)
                    }
                    HStack {
                        Button("All On") {
                            LoggingRegistry.shared.filter.enableAll()
                            for cat in HRSenseLogCategory.allCases {
                                logCategories[cat] = true
                            }
                        }
                        Spacer()
                        Button("All Off") {
                            LoggingRegistry.shared.filter.disableAll()
                            for cat in HRSenseLogCategory.allCases {
                                logCategories[cat] = false
                            }
                        }
                    }
                }

                // Section 3: MetricKit diagnostics
                Section("MetricKit Diagnostics") {
                    if model.crashHistory.isEmpty {
                        Text("No diagnostics recorded").foregroundColor(.secondary)
                    } else {
                        ForEach(model.crashHistory, id: \.self) { entry in
                            Text(entry).font(.caption2)
                        }
                    }
                    Button("Inject Test Crash") {
                        model.injectTestCrashRecord()
                    }
                    Button("Inject Test Hang") {
                        model.injectTestHangRecord()
                    }
                }

                // Section 4: Export
                Section("Diagnostic Export") {
                    Button("Export Diagnostic Package") {
                        model.exportDiagnosticPackage()
                    }
                    if let exportStatusMessage = model.exportStatusMessage {
                        Text(exportStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let exportURL = model.exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share Latest Package", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
        }
        .onReceive(timer) { _ in
            refreshMetrics()
        }
        .onAppear {
            for cat in HRSenseLogCategory.allCases {
                logCategories[cat] = LoggingRegistry.shared.filter.isCategoryEnabled(cat)
            }
            refreshMetrics()
        }
    }

    private func kpiRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
    }

    private var throughputLabel: String {
        if model.kpi.throughputBytesPerSec > 1024 {
            String(format: "%.1f KB/s", model.kpi.throughputBytesPerSec / 1024)
        } else {
            String(format: "%.0f B/s", model.kpi.throughputBytesPerSec)
        }
    }

    private func refreshMetrics() {
        model.refresh()
    }
}

#endif
