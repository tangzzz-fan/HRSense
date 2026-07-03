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
                systemInfoProvider: { SystemInfo.current }
            )
        )

        model.refresh()

        XCTAssertEqual(model.kpi.reconnectCount, 2)
        XCTAssertEqual(model.kpi.connectionSuccessRate, 0.75)
        XCTAssertEqual(model.crashHistory, ["CRASH: reason=test"])
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

        try? FileManager.default.removeItem(at: exportURL)
    }
}
