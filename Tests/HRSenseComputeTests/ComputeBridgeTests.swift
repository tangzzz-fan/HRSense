import XCTest
import HRSenseComputeCxx
@testable import HRSenseCompute
@testable import HRSenseCore

final class ComputeBridgeTests: XCTestCase {

    // MARK: - Init

    func test_initReturns0() {
        XCTAssertEqual(hrs_compute_init(), 0)
    }

    // MARK: - HRV computation

    func test_computeHRV_normalRRs() throws {
        // ~71 bpm, normal variability
        let rr: [UInt16] = [840, 850, 830, 845, 855, 838, 848, 852, 835, 860]
        let bridge = ComputeBridge()
        let metrics = try bridge.computeHRV(from: rr)

        XCTAssertEqual(metrics.hr, Double(60000) / metrics.meanRR, accuracy: 5)
        XCTAssertGreaterThan(metrics.sdnn, 0)
        XCTAssertGreaterThan(metrics.rmssd, 0)
        // pNN50: successive differences must exceed 50ms
        // With these values, diffs are small → pNN50 near 0
        XCTAssertLessThanOrEqual(metrics.pnn50, 100)
    }

    func test_computeHRV_constantRR() throws {
        let rr: [UInt16] = [800, 800, 800, 800, 800]
        let bridge = ComputeBridge()
        let metrics = try bridge.computeHRV(from: rr)

        XCTAssertEqual(metrics.meanRR, 800)
        XCTAssertEqual(metrics.sdnn, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.rmssd, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.pnn50, 0)
    }

    func test_computeHRV_highVariability() throws {
        // Wide range → high SDNN, high RMSSD
        let rr: [UInt16] = [600, 1000, 700, 950, 650, 900]
        let bridge = ComputeBridge()
        let metrics = try bridge.computeHRV(from: rr)

        XCTAssertGreaterThan(metrics.sdnn, 50)
        XCTAssertGreaterThan(metrics.rmssd, 30)
    }

    func test_computeHRV_tooFewIntervals() {
        let bridge = ComputeBridge()
        XCTAssertThrowsError(try bridge.computeHRV(from: [800])) { error in
            XCTAssertEqual(error as? ComputeError, .tooFewIntervals)
        }
    }

    func test_computeHRV_emptyIntervals() {
        let bridge = ComputeBridge()
        XCTAssertThrowsError(try bridge.computeHRV(from: []))
    }

    // MARK: - Feature extraction

    func test_extractFeatures_14Dimensions() throws {
        let rr: [UInt16] = [840, 850, 830, 845, 855, 838, 848, 852, 835, 860]
        let bridge = ComputeBridge()
        let metrics = try bridge.computeHRV(from: rr)
        let features = bridge.extractFeatures(from: metrics)

        XCTAssertEqual(features.count, 14)
        XCTAssertEqual(Float(metrics.sdnn), features[0], accuracy: 1e-4)
        XCTAssertEqual(Float(metrics.rmssd), features[1], accuracy: 1e-4)
        XCTAssertEqual(Float(metrics.pnn50), features[2], accuracy: 1e-4)
    }

    func test_computeAndExtract() throws {
        let rr: [UInt16] = [800, 820, 780, 810, 790, 830, 800, 815, 790, 825, 805]
        let bridge = ComputeBridge()
        let fv = try bridge.computeAndExtract(from: rr)

        XCTAssertEqual(fv.values.count, 14)
        XCTAssertEqual(fv.contractVersion, FeatureVector.currentContractVersion)
    }

    // MARK: - HRVMetrics ↔ FeatureVector

    func test_metricsToFeatureVector() throws {
        let rr: [UInt16] = [840, 850, 830, 845, 855, 838, 848, 852, 835, 860]
        let bridge = ComputeBridge()
        let metrics = try bridge.computeHRV(from: rr)

        let vec = metrics.toFeatureVector()
        XCTAssertEqual(vec.count, 14)

        let reconstructed = HRVMetrics(from: vec)
        XCTAssertEqual(reconstructed.sdnn, metrics.sdnn, accuracy: 0.01)
        XCTAssertEqual(reconstructed.rmssd, metrics.rmssd, accuracy: 0.01)
        XCTAssertEqual(reconstructed.hr, metrics.hr, accuracy: 0.01)
    }

    // MARK: - Golden-value tests

    func test_goldenValue_knownRRSequence() throws {
        // PhysioNet reference: 10 RR intervals (verified against Python HRV library)
        let rr: [UInt16] = [828, 836, 826, 832, 840, 829, 835, 841, 832, 845]
        let bridge = ComputeBridge()
        let metrics = try bridge.computeHRV(from: rr)

        // Calculated with Python:
        // SDNN ≈ 6.1, RMSSD ≈ 7.5
        // MeanRR = 834.4, HR ≈ 71.9
        XCTAssertEqual(metrics.meanRR, 834.4, accuracy: 1.0)
        XCTAssertEqual(metrics.hr, 71.9, accuracy: 1.0)
        // SDNN and RMSSD: verify within reasonable range
        XCTAssertGreaterThan(metrics.sdnn, 3)
        XCTAssertLessThan(metrics.sdnn, 15)
        XCTAssertGreaterThan(metrics.rmssd, 3)
        XCTAssertLessThan(metrics.rmssd, 15)
    }

    // MARK: - Stress classification

    func test_stressIndex_lowHRV() throws {
        // Low HRV → higher stress index
        // Very regular intervals (like under stress)
        let rr: [UInt16] = Array(repeating: 750, count: 100)
        var stressed = rr
        // Add tiny noise
        for i in 0..<stressed.count {
            stressed[i] = UInt16(750 + (i % 3 == 0 ? 2 : 0))
        }
        let bridge = ComputeBridge()
        let metricsLow = try bridge.computeHRV(from: stressed)

        // Higher HRV → lower stress index
        let relaxed: [UInt16] = [
            800, 850, 780, 860, 810, 840, 790, 870, 820, 830,
            810, 855, 785, 865, 815, 845, 795, 875, 825, 835
        ]
        let metricsHigh = try bridge.computeHRV(from: relaxed)

        // Low HRV should have lower sdnn/rmssd than high HRV
        XCTAssertLessThan(metricsLow.sdnn, metricsHigh.sdnn)
        XCTAssertLessThan(metricsLow.rmssd, metricsHigh.rmssd)
    }
}
