import Foundation

/// Diagnostic KPI snapshot shared between data collection and presentation.
public struct KPISnapshot: Equatable, Sendable {
    public let connectionSuccessRate: Double
    public let reconnectCount: Int
    public let commandTimeoutRate: Double
    public let sampleLossRate: Double
    public let throughputBytesPerSec: Double
    public let otaSuccessRate: Double

    public init(
        connectionSuccessRate: Double,
        reconnectCount: Int,
        commandTimeoutRate: Double,
        sampleLossRate: Double,
        throughputBytesPerSec: Double,
        otaSuccessRate: Double
    ) {
        self.connectionSuccessRate = connectionSuccessRate
        self.reconnectCount = reconnectCount
        self.commandTimeoutRate = commandTimeoutRate
        self.sampleLossRate = sampleLossRate
        self.throughputBytesPerSec = throughputBytesPerSec
        self.otaSuccessRate = otaSuccessRate
    }
}
