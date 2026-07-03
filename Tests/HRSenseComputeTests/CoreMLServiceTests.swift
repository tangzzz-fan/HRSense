import Foundation
import XCTest
@testable import HRSenseCompute

final class CoreMLServiceTests: XCTestCase {
    func test_defaultSelectionStrategyPrefersMatchingTaskContractAndName() {
        let strategy = DefaultModelSelectionStrategy()
        let request = ModelSelectionRequest.stressClassifierV1
        let descriptors = [
            ModelDescriptor(
                modelName: "StressClassifier_v2",
                modelVersion: "2.0.0",
                task: InferenceTask.stressClassification.rawValue,
                featureContractVersion: 2,
                url: URL(fileURLWithPath: "/tmp/v2.mlpackage")
            ),
            ModelDescriptor(
                modelName: "StressClassifier_v1",
                modelVersion: "1.0.0-placeholder",
                task: InferenceTask.stressClassification.rawValue,
                featureContractVersion: 1,
                url: URL(fileURLWithPath: "/tmp/v1.mlpackage")
            ),
            ModelDescriptor(
                modelName: "SleepClassifier_v1",
                modelVersion: "1.0.0",
                task: "sleep-stage",
                featureContractVersion: 1,
                url: URL(fileURLWithPath: "/tmp/sleep.mlpackage")
            )
        ]

        let selected = strategy.selectModel(from: descriptors, request: request)

        XCTAssertEqual(selected?.modelName, "StressClassifier_v1")
        XCTAssertEqual(selected?.featureContractVersion, 1)
    }

    func test_predictFallsBackWhenExplicitModelURLIsMissing() {
        let missingURL = URL(fileURLWithPath: "/tmp/HRSense/MissingModel.mlpackage")
        let service = CoreMLService(modelURL: missingURL)

        let prediction = service.predict(
            features: [12, 18, 4, 760, 98, 220, 180, 2.6, 400, 15, 28, 1.1, 1.3, 620]
        )

        XCTAssertEqual(service.activeModelVersion, "fallback-rule-engine")
        XCTAssertEqual(prediction?.label, "Stress")
        XCTAssertEqual(prediction?.probabilities["Stress"] ?? 0, 0.7, accuracy: 0.0001)
    }

    func test_predictLoadsPlaceholderModelFromExplicitURL() {
        let service = CoreMLService(modelURL: placeholderModelURL())

        let prediction = service.predict(
            features: [48, 42, 18, 840, 72, 650, 580, 1.2, 1400, 28, 54, 1.4, 0.88, 220]
        )

        guard let prediction else {
            XCTFail("Expected placeholder model prediction to be non-nil")
            return
        }
        XCTAssertNotEqual(service.activeModelVersion, "fallback-rule-engine")
        XCTAssertEqual(service.activeModelDescriptor?.modelName, "StressClassifier_v1")
        XCTAssertEqual(Set(prediction.probabilities.keys), Set<String>(["Baseline", "Stress"]))
    }

    func test_fallbackPredictionGoldenSamplesRemainStable() {
        let missingURL = URL(fileURLWithPath: "/tmp/HRSense/MissingModel.mlpackage")
        let service = CoreMLService(modelURL: missingURL)

        let stress = service.predict(
            features: [12, 18, 4, 760, 98, 220, 180, 2.6, 400, 15, 28, 1.1, 1.3, 620]
        )
        let baseline = service.predict(
            features: [48, 42, 18, 840, 72, 650, 580, 1.2, 1400, 28, 54, 1.4, 0.88, 220]
        )

        XCTAssertEqual(stress?.label, "Stress")
        XCTAssertEqual(stress?.probabilities["Stress"] ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertEqual(stress?.probabilities["Baseline"] ?? 0, 0.3, accuracy: 0.0001)

        XCTAssertEqual(baseline?.label, "Baseline")
        XCTAssertEqual(baseline?.probabilities["Baseline"] ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertEqual(baseline?.probabilities["Stress"] ?? 0, 0.3, accuracy: 0.0001)
    }

    func test_predictRejectsUnexpectedFeatureCount() {
        let service = CoreMLService(modelURL: placeholderModelURL())

        let prediction = service.predict(features: [1, 2, 3])

        XCTAssertNil(prediction)
    }

    func test_bundleCatalogHandlesDuplicateBundleURLs() {
        let testBundle = Bundle(for: Self.self)
        let catalog = BundleCoreMLModelCatalog(
            bundles: [testBundle, testBundle, testBundle],
            supportedExtensions: []
        )

        let models = catalog.discoverModels()

        XCTAssertTrue(models.isEmpty)
    }

    func test_defaultDiscoveryBundlesStayInsideMainBundleScope() {
        let bundles = BundleCoreMLModelCatalog.defaultDiscoveryBundles()
        let mainBundlePath = Bundle.main.bundleURL.standardizedFileURL.path

        XCTAssertFalse(bundles.isEmpty)
        XCTAssertTrue(
            bundles.allSatisfy { bundle in
                let bundlePath = bundle.bundleURL.standardizedFileURL.path
                return bundlePath == mainBundlePath || bundlePath.hasPrefix(mainBundlePath + "/")
            }
        )
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
