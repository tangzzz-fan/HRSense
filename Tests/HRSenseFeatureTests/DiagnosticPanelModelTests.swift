import XCTest
@testable import HRSenseFeature
import HRSenseCore
import HRSenseProtocol

@MainActor
final class DiagnosticPanelModelTests: XCTestCase {
    func test_refreshLoadsLiveKPIAndDiagnostics() {
        let model = DiagnosticPanelModel(
            dependencies: DiagnosticPanelDependencies(
                kpiSnapshotProvider: {
                    KPISnapshot(
                        connectionSuccessRate: 0.75,
                        reconnectCount: 2,
                        commandTimeoutRate: 0.1,
                        sampleLossRate: 0.05,
                        throughputBytesPerSec: 512,
                        otaSuccessRate: 1.0
                    )
                },
                logEntriesProvider: { [] },
                stateTransitionsProvider: { ["connect -> connected"] },
                metricDiagnosticsProvider: { ["CRASH: reason=test"] },
                metricsSnapshotProvider: {
                    MetricsSnapshotJSON(
                        totalSamplesReceived: 10,
                        samplesLost: 1,
                        reconnectCount: 2,
                        bytesReceived: 2048
                    )
                },
                latestFeatureVectorProvider: {
                    FeatureVectorSnapshotJSON(contractVersion: 1, values: Array(repeating: 1.5, count: 14))
                },
                latestInferenceProvider: {
                    InferenceSnapshotJSON(
                        label: "Stress",
                        probabilities: ["Stress": 0.8, "Baseline": 0.2],
                        inferenceTimeMs: 3.2,
                        modelVersion: "1.0.0-placeholder"
                    )
                },
                systemInfoProvider: { SystemInfo.current }
            )
        )

        model.refresh()

        XCTAssertEqual(model.kpi.reconnectCount, 2)
        XCTAssertEqual(model.kpi.connectionSuccessRate, 0.75)
        XCTAssertEqual(model.crashHistory, ["CRASH: reason=test"])
        XCTAssertEqual(model.latestFeatureVector?.contractVersion, 1)
        XCTAssertEqual(model.latestInference?.modelVersion, "1.0.0-placeholder")
    }

    func test_exportDiagnosticPackageWritesReadableJSON() throws {
        let model = DiagnosticPanelModel(
            dependencies: DiagnosticPanelDependencies(
                kpiSnapshotProvider: {
                    KPISnapshot(
                        connectionSuccessRate: 1,
                        reconnectCount: 0,
                        commandTimeoutRate: 0,
                        sampleLossRate: 0,
                        throughputBytesPerSec: 128,
                        otaSuccessRate: 1
                    )
                },
                logEntriesProvider: {
                    [LogEntry(category: "ota", level: "INFO", message: "OTA complete")]
                },
                stateTransitionsProvider: { ["otaStateChanged(completed)"] },
                metricDiagnosticsProvider: { [] },
                metricsSnapshotProvider: {
                    MetricsSnapshotJSON(
                        totalSamplesReceived: 20,
                        samplesLost: 0,
                        reconnectCount: 1,
                        bytesReceived: 4096
                    )
                },
                latestFeatureVectorProvider: {
                    FeatureVectorSnapshotJSON(contractVersion: 1, values: Array(repeating: 2.0, count: 14))
                },
                latestInferenceProvider: {
                    InferenceSnapshotJSON(
                        label: "Baseline",
                        probabilities: ["Baseline": 0.9, "Stress": 0.1],
                        inferenceTimeMs: 2.1,
                        modelVersion: "2.0.0"
                    )
                },
                systemInfoProvider: { SystemInfo.current }
            )
        )

        model.exportDiagnosticPackage()

        guard let exportURL = model.exportURL else {
            return XCTFail("Expected export URL")
        }
        let data = try Data(contentsOf: exportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticPackage.self, from: data)

        XCTAssertEqual(decoded.logEntries.count, 1)
        XCTAssertEqual(decoded.stateTransitions, ["otaStateChanged(completed)"])
        XCTAssertEqual(decoded.metricsSnapshot.bytesReceived, 4096)
        XCTAssertEqual(decoded.latestFeatureVector?.values.count, 14)
        XCTAssertEqual(decoded.latestInference?.modelVersion, "2.0.0")

        try? FileManager.default.removeItem(at: exportURL)
    }
}
