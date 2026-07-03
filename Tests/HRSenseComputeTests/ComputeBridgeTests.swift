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

    func test_goldenValue_knownRRSequenceProducesStableMetricsAndFeatures() throws {
        let rr: [UInt16] = [828, 836, 826, 832, 840, 829, 835, 841, 832, 845]
        let bridge = ComputeBridge()
        let metrics = try bridge.computeHRV(from: rr)
        let features = bridge.extractFeatures(from: metrics)

        let expected = HRVMetrics(
            sdnn: 6.168017869984201,
            rmssd: 8.863157200205555,
            pnn50: 0,
            meanRR: 834.4,
            hr: 71.90795781399808,
            lfPower: 0.001967590735822901,
            hfPower: 0.04178620837899738,
            lfHfRatio: 0.04708708476196306,
            totalPower: 0.1959984990539984,
            sd1: 6.1232203259799345,
            sd2: 6.212492392622711,
            sampleEntropy: .infinity,
            dfaAlpha1: 0,
            stressIndex: 426649.04720439174
        )

        let expectedFeatures: [Float] = [
            Float(expected.sdnn),
            Float(expected.rmssd),
            Float(expected.pnn50),
            Float(expected.meanRR),
            Float(expected.hr),
            Float(expected.lfPower),
            Float(expected.hfPower),
            Float(expected.lfHfRatio),
            Float(expected.totalPower),
            Float(expected.sd1),
            Float(expected.sd2),
            .infinity,
            Float(expected.dfaAlpha1),
            Float(expected.stressIndex)
        ]

        assertMetrics(metrics, expected: expected)
        assertFeatureVector(features, expected: expectedFeatures)
    }

    func test_goldenValue_referenceRRWindowKeepsFeatureContractStable() throws {
        let rr: [UInt16] = [
            812, 824, 801, 838, 795, 846, 808, 832,
            790, 850, 805, 827, 798, 843, 811, 835,
            792, 848, 806, 830, 799, 844, 814, 836
        ]
        let bridge = ComputeBridge()
        let metrics = try bridge.computeHRV(from: rr)
        let features = bridge.extractFeatures(from: metrics)

        let expected = HRVMetrics(
            sdnn: 19.692564623463227,
            rmssd: 37.617063658144154,
            pnn50: 13.043478260869565,
            meanRR: 820.1666666666666,
            hr: 73.15586262954685,
            lfPower: 0.0036803633365140964,
            hfPower: 0.033583937633278306,
            lfHfRatio: 0.10958701081159782,
            totalPower: 0.043910722467122625,
            sd1: 26.58904503155352,
            sd2: 8.283531083334557,
            sampleEntropy: 0.2231435513142097,
            dfaAlpha1: 0,
            stressIndex: 42317.156209325636
        )

        let expectedFeatures: [Float] = [
            Float(expected.sdnn),
            Float(expected.rmssd),
            Float(expected.pnn50),
            Float(expected.meanRR),
            Float(expected.hr),
            Float(expected.lfPower),
            Float(expected.hfPower),
            Float(expected.lfHfRatio),
            Float(expected.totalPower),
            Float(expected.sd1),
            Float(expected.sd2),
            Float(expected.sampleEntropy),
            Float(expected.dfaAlpha1),
            Float(expected.stressIndex)
        ]

        assertMetrics(metrics, expected: expected)
        assertFeatureVector(features, expected: expectedFeatures)
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

    private func assertMetrics(
        _ metrics: HRVMetrics,
        expected: HRVMetrics,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(metrics.sdnn, expected.sdnn, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.rmssd, expected.rmssd, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.pnn50, expected.pnn50, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.meanRR, expected.meanRR, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.hr, expected.hr, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.lfPower, expected.lfPower, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.hfPower, expected.hfPower, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.lfHfRatio, expected.lfHfRatio, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.totalPower, expected.totalPower, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.sd1, expected.sd1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.sd2, expected.sd2, accuracy: 0.0001, file: file, line: line)
        if expected.sampleEntropy.isInfinite {
            XCTAssertTrue(metrics.sampleEntropy.isInfinite, file: file, line: line)
        } else {
            XCTAssertEqual(metrics.sampleEntropy, expected.sampleEntropy, accuracy: 0.0001, file: file, line: line)
        }
        XCTAssertEqual(metrics.dfaAlpha1, expected.dfaAlpha1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(metrics.stressIndex, expected.stressIndex, accuracy: 0.001, file: file, line: line)
    }

    private func assertFeatureVector(
        _ features: [Float],
        expected: [Float],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(features.count, expected.count, file: file, line: line)

        for (index, pair) in zip(features, expected).enumerated() {
            let (actual, target) = pair
            if target.isInfinite {
                XCTAssertTrue(actual.isInfinite, "Feature index \(index) should be infinite", file: file, line: line)
            } else {
                XCTAssertEqual(actual, target, accuracy: 0.0001, "Feature index \(index) drifted", file: file, line: line)
            }
        }
    }
}
