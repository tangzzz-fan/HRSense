import Foundation
import HRSenseCore
import TGReduxKit

/// Middleware that accumulates RR intervals in a 5-minute sliding window
/// and triggers C++ HRV computation → feature extraction → CoreML inference.
///
/// Window: 5 min (300s)
/// Step: 30s (computation triggered every 30s of new data)
///
/// Pipeline: RR intervals → hrs_compute_hrv() → 14 features → CoreML → InferenceResult
public func makeComputeMiddleware(
    computeRepo: any ComputeRepository,
    inferenceRepo: any InferenceRepository,
    windowDuration: TimeInterval = 300,
    stepInterval: TimeInterval = 30
) -> Middleware<AppState, Action> {
    // Accumulated RR intervals with timestamps
    var rrBuffer: [(date: Date, rr: Int)] = []
    var lastComputeTime: Date = Date.distantPast

    return { store, action, next in
        next(action)

        switch action {
        case .heartRateReceived(let samples):
            for sample in samples {
                for rr in sample.rrIntervals {
                    rrBuffer.append((sample.timestamp, rr))
                }
            }
            // Prune old entries
            let windowStart = Date().addingTimeInterval(-windowDuration)
            rrBuffer = rrBuffer.filter { $0.date >= windowStart }

            // Trigger compute every stepInterval
            let now = Date()
            if now.timeIntervalSince(lastComputeTime) >= stepInterval, rrBuffer.count >= 2 {
                lastComputeTime = now

                let rrValues = rrBuffer.map { UInt16($0.rr) }
                Task {
                    do {
                        let metrics = try computeRepo.computeHRV(from: rrValues.map(Int.init))
                        await MainActor.run {
                            store.dispatch(.hrvComputed(metrics))
                        }

                        let features = metrics.toFeatureVector()
                        let result = try await inferenceRepo.runInference(features: features)
                        await MainActor.run {
                            store.dispatch(.inferenceCompleted(result))
                        }
                    } catch {
                        await MainActor.run {
                            store.dispatch(.errorOccurred(.computeFailed))
                        }
                    }
                }
            }

        case .clearSamples:
            rrBuffer.removeAll()

        default:
            break
        }
    }
}
