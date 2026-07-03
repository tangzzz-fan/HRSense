import Foundation
import CoreML

public enum InferenceTask: String, Equatable, Sendable {
    case stressClassification = "stress-classification"
}

public struct ModelSelectionRequest: Equatable, Sendable {
    public let task: InferenceTask
    public let featureContractVersion: Int
    public let preferredModelName: String?
    public let preferredModelVersion: String?

    public init(
        task: InferenceTask,
        featureContractVersion: Int,
        preferredModelName: String? = nil,
        preferredModelVersion: String? = nil
    ) {
        self.task = task
        self.featureContractVersion = featureContractVersion
        self.preferredModelName = preferredModelName
        self.preferredModelVersion = preferredModelVersion
    }

    public static let stressClassifierV1 = ModelSelectionRequest(
        task: .stressClassification,
        featureContractVersion: 1,
        preferredModelName: "StressClassifier_v1"
    )
}

public struct ModelDescriptor: Equatable, Sendable {
    public let modelName: String
    public let modelVersion: String
    public let task: String?
    public let featureContractVersion: Int?
    public let url: URL
}

public protocol CoreMLModelCatalog: Sendable {
    func discoverModels() -> [ModelDescriptor]
}

public protocol ModelSelectionStrategy: Sendable {
    func selectModel(
        from descriptors: [ModelDescriptor],
        request: ModelSelectionRequest
    ) -> ModelDescriptor?
}

public struct DefaultModelSelectionStrategy: ModelSelectionStrategy {
    public init() {}

    public func selectModel(
        from descriptors: [ModelDescriptor],
        request: ModelSelectionRequest
    ) -> ModelDescriptor? {
        descriptors
            .compactMap { descriptor -> (ModelDescriptor, Int)? in
                let score = selectionScore(for: descriptor, request: request)
                guard score > Int.min else { return nil }
                return (descriptor, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                if lhs.0.modelVersion != rhs.0.modelVersion {
                    return lhs.0.modelVersion > rhs.0.modelVersion
                }
                return lhs.0.modelName < rhs.0.modelName
            }
            .first?
            .0
    }

    private func selectionScore(
        for descriptor: ModelDescriptor,
        request: ModelSelectionRequest
    ) -> Int {
        var score = 0

        if let task = descriptor.task {
            guard task == request.task.rawValue else {
                return Int.min
            }
            score += 100
        }

        if let contractVersion = descriptor.featureContractVersion {
            guard contractVersion == request.featureContractVersion else {
                return Int.min
            }
            score += 50
        }

        if descriptor.modelName == request.preferredModelName {
            score += 25
        }

        if descriptor.modelVersion == request.preferredModelVersion {
            score += 25
        }

        switch descriptor.url.pathExtension {
        case "mlmodelc":
            score += 5
        case "mlpackage":
            score += 3
        default:
            break
        }

        return score
    }
}

public struct BundleCoreMLModelCatalog: CoreMLModelCatalog, @unchecked Sendable {
    private let bundles: [Bundle]
    private let supportedExtensions: Set<String>

    public init(
        bundles: [Bundle]? = nil,
        supportedExtensions: [String] = ["mlmodelc", "mlpackage", "mlmodel"]
    ) {
        self.bundles = bundles ?? Self.defaultDiscoveryBundles()
        self.supportedExtensions = Set(supportedExtensions)
    }

    public func discoverModels() -> [ModelDescriptor] {
        let uniqueBundles = deduplicateBundles(bundles)

        let candidateURLs = uniqueBundles.flatMap(findModelURLs(in:))
        let uniqueURLs = deduplicateURLs(candidateURLs)

        return uniqueURLs.compactMap(CoreMLModelInspector.inspectModel(at:))
    }

    /// Restrict default discovery to bundles inside the app's own bundle root.
    /// This avoids scanning system/private frameworks that may contain unrelated
    /// CoreML assets and generate noisy runtime errors when inspected.
    static func defaultDiscoveryBundles() -> [Bundle] {
        let mainBundleURL = Bundle.main.bundleURL.standardizedFileURL
        let appScopedBundles = ([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks).filter { bundle in
            let bundleURL = bundle.bundleURL.standardizedFileURL
            return bundleURL.path == mainBundleURL.path || bundleURL.path.hasPrefix(mainBundleURL.path + "/")
        }

        return appScopedBundles.isEmpty ? [Bundle.main] : appScopedBundles
    }

    // Xcode/iOS runtime can surface the same bundle multiple times across
    // Bundle.main, allBundles, and allFrameworks. Use stable manual dedup
    // instead of Dictionary(uniqueKeysWithValues:), which would trap.
    private func deduplicateBundles(_ bundles: [Bundle]) -> [Bundle] {
        var seen: Set<URL> = []
        var uniqueBundles: [Bundle] = []

        for bundle in bundles {
            let key = bundle.bundleURL.standardizedFileURL
            if seen.insert(key).inserted {
                uniqueBundles.append(bundle)
            }
        }

        return uniqueBundles
    }

    private func deduplicateURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        var uniqueURLs: [URL] = []

        for url in urls {
            let key = url.standardizedFileURL
            if seen.insert(key).inserted {
                uniqueURLs.append(url)
            }
        }

        return uniqueURLs
    }

    private func findModelURLs(in bundle: Bundle) -> [URL] {
        guard let resourceURL = bundle.resourceURL else {
            return []
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            if supportedExtensions.contains(fileURL.pathExtension) {
                urls.append(fileURL)
            }
        }
        return urls
    }
}

enum CoreMLModelInspector {
    static func inspectModel(at url: URL) -> ModelDescriptor? {
        let metadata = loadMetadata(from: url)
        let modelName = url.deletingPathExtension().lastPathComponent
        let modelVersion = modelVersion(from: metadata) ?? modelVersionFallback(from: url)
        let featureContractVersion = featureContractVersion(from: metadata)
        let task = task(from: metadata)

        return ModelDescriptor(
            modelName: modelName,
            modelVersion: modelVersion,
            task: task,
            featureContractVersion: featureContractVersion,
            url: url
        )
    }

    static func loadMetadata(from url: URL) -> [MLModelMetadataKey: Any]? {
        guard let model = loadModel(at: url) else {
            return nil
        }
        return model.modelDescription.metadata
    }

    static func loadModel(at url: URL) -> MLModel? {
        do {
            if url.pathExtension == "mlmodelc" {
                return try MLModel(contentsOf: url)
            }

            let compiledURL = try MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiledURL)
        } catch {
            return nil
        }
    }

    static func modelVersion(from metadata: [MLModelMetadataKey: Any]?) -> String? {
        guard let metadata else { return nil }

        if let creatorDefined = metadata[.creatorDefinedKey] as? [String: String],
           let modelVersion = creatorDefined["modelVersion"],
           !modelVersion.isEmpty
        {
            return modelVersion
        }

        if let creatorDefined = metadata[.creatorDefinedKey] as? [String: Any],
           let modelVersion = creatorDefined["modelVersion"] as? String,
           !modelVersion.isEmpty
        {
            return modelVersion
        }

        if let versionString = metadata[.versionString] as? String, !versionString.isEmpty {
            return versionString
        }

        return nil
    }

    static func featureContractVersion(from metadata: [MLModelMetadataKey: Any]?) -> Int? {
        guard let metadata else { return nil }

        if let creatorDefined = metadata[.creatorDefinedKey] as? [String: String],
           let rawValue = creatorDefined["featureContractVersion"]
        {
            return Int(rawValue)
        }

        if let creatorDefined = metadata[.creatorDefinedKey] as? [String: Any] {
            if let rawValue = creatorDefined["featureContractVersion"] as? Int {
                return rawValue
            }
            if let rawValue = creatorDefined["featureContractVersion"] as? String {
                return Int(rawValue)
            }
        }

        return nil
    }

    static func task(from metadata: [MLModelMetadataKey: Any]?) -> String? {
        guard let metadata else { return nil }

        if let creatorDefined = metadata[.creatorDefinedKey] as? [String: String] {
            return creatorDefined["task"]
        }

        if let creatorDefined = metadata[.creatorDefinedKey] as? [String: Any] {
            return creatorDefined["task"] as? String
        }

        return nil
    }

    static func modelVersionFallback(from url: URL) -> String {
        if url.pathExtension == "mlmodelc" {
            return url.deletingPathExtension().lastPathComponent
        }
        return url.lastPathComponent
    }
}
