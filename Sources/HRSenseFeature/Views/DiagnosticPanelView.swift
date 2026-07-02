import SwiftUI
import HRSenseCore
import HRSenseProtocol
import HRSenseData

#if DEBUG

/// Debug diagnostics panel — toggled via developer gesture (e.g., triple-tap logo).
///
/// Sections:
///   1. Real-time KPI metrics (6 KPIs, 1s refresh)
///   2. Log category toggles + level selector
///   3. MetricKit diagnostics (crash/hang/CPU exceptions)
///   4. Diagnostic export (JSON → Share sheet)
public struct DiagnosticPanelView: View {
    @State private var kpi: KPISnapshot = KPISnapshot(
        connectionSuccessRate: 0, reconnectCount: 0, commandTimeoutRate: 0,
        sampleLossRate: 0, throughputBytesPerSec: 0, otaSuccessRate: 0
    )
    @State private var logCategories: [HRSenseLogCategory: Bool] = [:]
    @State private var minimumLevel: HRSenseLogLevel = .debug
    @State private var crashHistory: [String] = []
    @State private var isExporting = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                // Section 1: KPIs
                Section("Real-time Metrics") {
                    kpiRow("Connection Rate", String(format: "%.0f%%", kpi.connectionSuccessRate * 100))
                    kpiRow("Reconnects", "\(kpi.reconnectCount)")
                    kpiRow("Cmd Timeout Rate", String(format: "%.1f%%", kpi.commandTimeoutRate * 100))
                    kpiRow("Sample Loss Rate", String(format: "%.1f%%", kpi.sampleLossRate * 100))
                    kpiRow("Throughput", throughputLabel)
                    kpiRow("OTA Success Rate", String(format: "%.0f%%", kpi.otaSuccessRate * 100))
                }

                // Section 2: Log toggles
                Section("Log Categories") {
                    ForEach(Array(logCategories.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.rawValue) { cat in
                        Toggle(cat.rawValue, isOn: Binding(
                            get: { logCategories[cat] ?? true },
                            set: { LoggingRegistry.shared.filter.setEnabled(cat, enabled: $0) }
                        ))
                    }
                    Picker("Min Level", selection: $minimumLevel) {
                        Text("Debug").tag(HRSenseLogLevel.debug)
                        Text("Info").tag(HRSenseLogLevel.info)
                        Text("Notice").tag(HRSenseLogLevel.notice)
                        Text("Error").tag(HRSenseLogLevel.error)
                    }
                    HStack {
                        Button("All On") { LoggingRegistry.shared.filter.enableAll() }
                        Spacer()
                        Button("All Off") { LoggingRegistry.shared.filter.disableAll() }
                    }
                }

                // Section 3: MetricKit diagnostics
                Section("MetricKit Diagnostics") {
                    if crashHistory.isEmpty {
                        Text("No diagnostics recorded").foregroundColor(.secondary)
                    } else {
                        ForEach(crashHistory, id: \.self) { entry in
                            Text(entry).font(.caption2)
                        }
                    }
                    Button("Inject Test Crash") {
                        // Record state before crash
                        let transitions = StateTransitionRecorder.shared.recentTransitions
                        crashHistory.append("Test crash @ \(Date())\nRecent: \(transitions.joined(separator: "\n"))")
                    }
                    Button("Inject Test Hang") {
                        let info = "HANG: test hang recorded @ \(Date())"
                        crashHistory.append(info)
                    }
                }

                // Section 4: Export
                Section("Diagnostic Export") {
                    Button("Export Diagnostic Package") {
                        isExporting = true
                    }
                    .sheet(isPresented: $isExporting) {
                        Text("⚠️ Export requires share sheet")
                            .padding()
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
                logCategories[cat] = true
            }
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
        if kpi.throughputBytesPerSec > 1024 {
            String(format: "%.1f KB/s", kpi.throughputBytesPerSec / 1024)
        } else {
            String(format: "%.0f B/s", kpi.throughputBytesPerSec)
        }
    }

    private func refreshMetrics() {
        // In a real setup, this would pull from the live MetricsCollector.
        // M7: panell reads from a shared MetricsCollector injected via environment.
    }
}

#endif
