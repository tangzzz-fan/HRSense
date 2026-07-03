import Foundation
import SwiftUI
import HRSenseCore
import HRSenseProtocol

public struct DiagnosticPanelDependencies {
    public let kpiSnapshotProvider: () -> KPISnapshot
    public let logEntriesProvider: () -> [LogEntry]
    public let stateTransitionsProvider: () -> [String]
    public let metricDiagnosticsProvider: () -> [String]
    public let metricsSnapshotProvider: () -> MetricsSnapshotJSON
    public let latestFeatureVectorProvider: () -> FeatureVectorSnapshotJSON?
    public let latestInferenceProvider: () -> InferenceSnapshotJSON?
    public let systemInfoProvider: () -> SystemInfo

    public init(
        kpiSnapshotProvider: @escaping () -> KPISnapshot,
        logEntriesProvider: @escaping () -> [LogEntry],
        stateTransitionsProvider: @escaping () -> [String],
        metricDiagnosticsProvider: @escaping () -> [String],
        metricsSnapshotProvider: @escaping () -> MetricsSnapshotJSON,
        latestFeatureVectorProvider: @escaping () -> FeatureVectorSnapshotJSON?,
        latestInferenceProvider: @escaping () -> InferenceSnapshotJSON?,
        systemInfoProvider: @escaping () -> SystemInfo
    ) {
        self.kpiSnapshotProvider = kpiSnapshotProvider
        self.logEntriesProvider = logEntriesProvider
        self.stateTransitionsProvider = stateTransitionsProvider
        self.metricDiagnosticsProvider = metricDiagnosticsProvider
        self.metricsSnapshotProvider = metricsSnapshotProvider
        self.latestFeatureVectorProvider = latestFeatureVectorProvider
        self.latestInferenceProvider = latestInferenceProvider
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
    @Published public private(set) var latestFeatureVector: FeatureVectorSnapshotJSON?
    @Published public private(set) var latestInference: InferenceSnapshotJSON?
    @Published public private(set) var exportURL: URL?
    @Published public private(set) var exportStatusMessage: String?

    private let dependencies: DiagnosticPanelDependencies

    public init(dependencies: DiagnosticPanelDependencies) {
        self.dependencies = dependencies
    }

    public func refresh() {
        kpi = dependencies.kpiSnapshotProvider()
        crashHistory = dependencies.metricDiagnosticsProvider()
        latestFeatureVector = dependencies.latestFeatureVectorProvider()
        latestInference = dependencies.latestInferenceProvider()
    }

    public func exportDiagnosticPackage() {
        do {
            let package = DiagnosticPackage(
                logEntries: dependencies.logEntriesProvider(),
                stateTransitions: dependencies.stateTransitionsProvider(),
                metricsSnapshot: dependencies.metricsSnapshotProvider(),
                latestFeatureVector: dependencies.latestFeatureVectorProvider(),
                latestInference: dependencies.latestInferenceProvider(),
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
