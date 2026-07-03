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

    func test_defaultSelectionStrategySelectsSleepStageRequest() {
        let strategy = DefaultModelSelectionStrategy()
        let request = ModelSelectionRequest.sleepStageClassifierV1
        let descriptors = [
            ModelDescriptor(
                modelName: "StressClassifier_v1",
                modelVersion: "1.0.0",
                task: InferenceTask.stressClassification.rawValue,
                featureContractVersion: 1,
                url: URL(fileURLWithPath: "/tmp/stress.mlpackage")
            ),
            ModelDescriptor(
                modelName: "SleepStageClassifier_v1",
                modelVersion: "1.0.0-placeholder",
                task: InferenceTask.sleepStage.rawValue,
                featureContractVersion: 1,
                url: URL(fileURLWithPath: "/tmp/sleep.mlpackage")
            )
        ]

        let selected = strategy.selectModel(from: descriptors, request: request)

        XCTAssertEqual(selected?.modelName, "SleepStageClassifier_v1")
        XCTAssertEqual(selected?.task, InferenceTask.sleepStage.rawValue)
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
        XCTAssertEqual(service.activeModelVersion, "1.0.0-placeholder")
        XCTAssertEqual(service.activeModelDescriptor?.modelName, "StressClassifier_v1")
        XCTAssertEqual(Set(prediction.probabilities.keys), Set<String>(["Baseline", "Stress"]))
        XCTAssertEqual(
            prediction.probabilities.values.reduce(0, +),
            1,
            accuracy: 0.0001
        )
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

    func test_fallbackPredictionThresholdContractRemainsStable() {
        let missingURL = URL(fileURLWithPath: "/tmp/HRSense/MissingModel.mlpackage")
        let service = CoreMLService(modelURL: missingURL)

        let baselineAtThreshold = service.predict(
            features: [0, 30, 0, 800, 90, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        )
        let stressByRMSSD = service.predict(
            features: [0, 29.9, 0, 800, 90, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        )
        let stressByHR = service.predict(
            features: [0, 30, 0, 800, 90.1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        )

        XCTAssertEqual(service.activeModelVersion, "fallback-rule-engine")

        XCTAssertEqual(baselineAtThreshold?.label, "Baseline")
        XCTAssertEqual(baselineAtThreshold?.probabilities["Baseline"] ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertEqual(baselineAtThreshold?.probabilities["Stress"] ?? 0, 0.3, accuracy: 0.0001)

        XCTAssertEqual(stressByRMSSD?.label, "Stress")
        XCTAssertEqual(stressByRMSSD?.probabilities["Stress"] ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertEqual(stressByRMSSD?.probabilities["Baseline"] ?? 0, 0.3, accuracy: 0.0001)

        XCTAssertEqual(stressByHR?.label, "Stress")
        XCTAssertEqual(stressByHR?.probabilities["Stress"] ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertEqual(stressByHR?.probabilities["Baseline"] ?? 0, 0.3, accuracy: 0.0001)
    }

    func test_predictRejectsUnexpectedFeatureCount() {
        let service = CoreMLService(modelURL: placeholderModelURL())

        let prediction = service.predict(features: [1, 2, 3])

        XCTAssertNil(prediction)
    }

    func test_sleepConfigurationUsesSleepFallbackVersionAndNoFallbackPrediction() {
        let missingURL = URL(fileURLWithPath: "/tmp/HRSense/MissingSleepModel.mlpackage")
        let service = CoreMLService(
            modelURL: missingURL,
            selectionRequest: .sleepStageClassifierV1,
            configuration: .sleepStageClassifier
        )

        let prediction = service.predict(features: Array(repeating: 0, count: 18))

        XCTAssertEqual(service.activeModelVersion, "sleep-stage-fallback-v1")
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
