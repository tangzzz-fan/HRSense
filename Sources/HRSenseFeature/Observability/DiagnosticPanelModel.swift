import Foundation
import SwiftUI
import HRSenseCore
import HRSenseProtocol

public struct DiagnosticPanelDependencies: Sendable {
    public let kpiSnapshotProvider: @Sendable () -> KPISnapshot
    public let logEntriesProvider: @Sendable () -> [LogEntry]
    public let stateTransitionsProvider: @Sendable () -> [String]
    public let metricDiagnosticsProvider: @Sendable () -> [String]
    public let metricsSnapshotProvider: @Sendable () -> MetricsSnapshotJSON
    public let systemInfoProvider: @Sendable () -> SystemInfo

    public init(
        kpiSnapshotProvider: @escaping @Sendable () -> KPISnapshot,
        logEntriesProvider: @escaping @Sendable () -> [LogEntry],
        stateTransitionsProvider: @escaping @Sendable () -> [String],
        metricDiagnosticsProvider: @escaping @Sendable () -> [String],
        metricsSnapshotProvider: @escaping @Sendable () -> MetricsSnapshotJSON,
        systemInfoProvider: @escaping @Sendable () -> SystemInfo
    ) {
        self.kpiSnapshotProvider = kpiSnapshotProvider
        self.logEntriesProvider = logEntriesProvider
        self.stateTransitionsProvider = stateTransitionsProvider
        self.metricDiagnosticsProvider = metricDiagnosticsProvider
        self.metricsSnapshotProvider = metricsSnapshotProvider
        self.systemInfoProvider = systemInfoProvider
    }
}

@MainActor
public final class DiagnosticPanelModel: ObservableObject {
    @Published public private(set) var kpi = KPISnapshot(
        connectionSuccessRate: 0,
        reconnectCount: 0,
        commandTimeoutRate: 0,
        sampleLossRate: 0,
        throughputBytesPerSec: 0,
        otaSuccessRate: 0
    )
    @Published public private(set) var crashHistory: [String] = []
    @Published public private(set) var exportURL: URL?
    @Published public private(set) var exportStatusMessage: String?

    private let dependencies: DiagnosticPanelDependencies

    public init(dependencies: DiagnosticPanelDependencies) {
        self.dependencies = dependencies
    }

    public func refresh() {
        kpi = dependencies.kpiSnapshotProvider()
        crashHistory = dependencies.metricDiagnosticsProvider()
    }

    public func exportDiagnosticPackage() {
        do {
            let package = DiagnosticPackage(
                logEntries: dependencies.logEntriesProvider(),
                stateTransitions: dependencies.stateTransitionsProvider(),
                metricsSnapshot: dependencies.metricsSnapshotProvider(),
                systemInfo: dependencies.systemInfoProvider()
            )
            let data = try package.exportJSON()
            let url = makeExportURL()
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportStatusMessage = "已生成 \(url.lastPathComponent)"
        } catch {
            exportStatusMessage = "导出失败: \(error.localizedDescription)"
        }
    }

    public func injectTestCrashRecord() {
        let transitions = dependencies.stateTransitionsProvider()
        MetricKitManager.shared.recordDebugDiagnostic(
            "TEST_CRASH_RECORD @ \(Date())",
            transitions: transitions
        )
        refresh()
    }

    public func injectTestHangRecord() {
        let transitions = dependencies.stateTransitionsProvider()
        MetricKitManager.shared.recordDebugDiagnostic(
            "TEST_HANG_RECORD @ \(Date())",
            transitions: transitions
        )
        refresh()
    }

    private func makeExportURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "hrsense-diagnostic-\(formatter.string(from: Date())).json"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}
