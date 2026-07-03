import XCTest
@testable import HRSenseData
import HRSenseCompute

final class InferenceRepositoryImplTests: XCTestCase {
    func test_runInferencePropagatesFallbackModelVersionForStressSample() async throws {
        let service = CoreMLService(modelURL: URL(fileURLWithPath: "/tmp/HRSense/MissingModel.mlpackage"))
        let repository = InferenceRepositoryImpl(mlService: service)

        let result = try await repository.runInference(
            features: [12, 18, 4, 760, 98, 220, 180, 2.6, 400, 15, 28, 1.1, 1.3, 620]
        )

        XCTAssertEqual(result.label, "Stress")
        XCTAssertEqual(result.modelVersion, "fallback-rule-engine")
        XCTAssertEqual(result.probabilities["Stress"] ?? 0, Float(0.7), accuracy: 0.0001)
    }

    func test_runInferencePropagatesLoadedModelVersionForPlaceholderModel() async throws {
        let repository = InferenceRepositoryImpl(
            mlService: CoreMLService(modelURL: placeholderModelURL())
        )

        let result = try await repository.runInference(
            features: [48, 42, 18, 840, 72, 650, 580, 1.2, 1400, 28, 54, 1.4, 0.88, 220]
        )

        XCTAssertNotEqual(result.modelVersion, "fallback-rule-engine")
        XCTAssertFalse(result.modelVersion.isEmpty)
        XCTAssertEqual(Set(result.probabilities.keys), Set(["Baseline", "Stress"]))
    }

    private func placeholderModelURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Models")
            .appendingPathComponent("StressClassifier_v1.mlpackage")
    }
}
