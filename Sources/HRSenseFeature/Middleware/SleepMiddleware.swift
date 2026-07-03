import Foundation
import HRSenseCore
import TGReduxKit

/// Orchestrates the M9 phase 5 sleep pipeline.
///
/// Current bootstrap path:
/// - reuse `hrvComputed` as upstream trigger
/// - build `SleepWindowInput` from live samples + HRV metrics
/// - run sleep-stage inference
/// - merge stage segments into `SleepSession`
/// - persist the evolving sleep session
public func makeSleepMiddleware(
    sleepInferenceRepository: any SleepInferenceRepository,
    persistenceStore: (any PersistenceStore)? = nil,
    windowDuration: TimeInterval = 300,
    calendar: Calendar = Calendar(identifier: .gregorian),
    nowProvider: @escaping @Sendable () -> Date = Date.init
) -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)

        switch action {
        case .connectionStateChanged(.connected):
            store.dispatch(.sleep(.monitoringStarted(nowProvider())))

        case .connectionStateChanged(.disconnected):
            store.dispatch(.sleep(.monitoringStopped(nowProvider())))

        case .clearSamples:
            store.dispatch(.sleep(.reset))

        case .hrvComputed(let metrics):
            guard store.state.sleep.isMonitoring else { break }
            guard let input = makeSleepWindowInput(
                state: store.state,
                metrics: metrics,
                windowDuration: windowDuration,
                calendar: calendar
            ) else {
                break
            }

            store.dispatch(.sleep(.windowPrepared(input)))
            store.dispatch(.sleep(.inferenceStarted))

            Task {
                do {
                    let prediction = try await sleepInferenceRepository.inferSleepStage(input: input)
                    await MainActor.run {
                        store.dispatch(.sleep(.inferenceCompleted(prediction)))
                    }

                    let updatedSession = mergeSleepPrediction(
                        prediction,
                        into: store.state.sleep.currentSession,
                        sourceSessionID: store.state.device?.peripheralIdentifier,
                        calendar: calendar
                    )

                    await MainActor.run {
                        store.dispatch(.sleep(.sessionUpdated(updatedSession)))
                    }

                    if let persistenceStore {
                        do {
                            try await persistenceStore.saveSleepSession(updatedSession)
                            await MainActor.run {
                                store.dispatch(.sleep(.sessionPersisted(updatedSession.id)))
                            }
                        } catch {
                            await MainActor.run {
                                store.dispatch(.errorOccurred(.persistenceFailed(reason: error.localizedDescription)))
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        store.dispatch(.errorOccurred(mapSleepInferenceError(error)))
                    }
                }
            }

        default:
            break
        }
    }
}

private func makeSleepWindowInput(
    state: AppState,
    metrics: HRVMetrics,
    windowDuration: TimeInterval,
    calendar: Calendar
) -> SleepWindowInput? {
    guard let latestSample = state.live.recentSamples.last else { return nil }

    let cutoff = latestSample.timestamp.addingTimeInterval(-windowDuration)
    let windowSamples = state.live.recentSamples.filter { $0.timestamp >= cutoff }
    guard let firstSample = windowSamples.first else { return nil }

    let sessionStart = state.sleep.monitoringStartedAt ?? firstSample.timestamp
    let timeContext = SleepTimeContext(
        windowStart: firstSample.timestamp,
        windowEnd: latestSample.timestamp,
        sessionStart: sessionStart,
        calendar: calendar
    )

    return SleepWindowInput(
        metrics: metrics,
        timeContext: timeContext,
        cxxFeatures: makeSleepCXXFeaturePlaceholders(from: windowSamples)
    )
}

private func makeSleepCXXFeaturePlaceholders(
    from samples: [HeartRateSample]
) -> SleepCXXFeatures {
    guard
        let first = samples.first?.heartRate,
        let last = samples.last?.heartRate,
        !samples.isEmpty
    else {
        return SleepCXXFeatures()
    }

    let hrTrend = Double(last - first) / Double(max(samples.count - 1, 1))
    let minHR = samples.map(\.heartRate).min() ?? first
    let maxHR = samples.map(\.heartRate).max() ?? first
    let circadianVariation = Double(maxHR - minHR) / 100.0

    return SleepCXXFeatures(
        hrTrend: hrTrend,
        circadianVariation: circadianVariation
    )
}

private func mergeSleepPrediction(
    _ prediction: SleepStagePrediction,
    into currentSession: SleepSession?,
    sourceSessionID: UUID?,
    calendar: Calendar
) -> SleepSession {
    if let currentSession {
        var stages = currentSession.stages
        if let last = stages.last, last.stage == prediction.stage {
            stages[stages.count - 1] = SleepStageSegment(
                id: last.id,
                stage: last.stage,
                startAt: last.startAt,
                endAt: prediction.timestamp
            )
        } else {
            let startAt = stages.last?.endAt ?? prediction.timestamp
            stages.append(
                SleepStageSegment(
                    stage: prediction.stage,
                    startAt: startAt,
                    endAt: prediction.timestamp
                )
            )
        }

        return SleepSession(
            id: currentSession.id,
            date: currentSession.date,
            sourceSessionID: currentSession.sourceSessionID,
            stages: stages,
            modelVersion: prediction.modelVersion
        )
    }

    let sessionDate = calendar.startOfDay(for: prediction.timestamp)
    return SleepSession(
        date: sessionDate,
        sourceSessionID: sourceSessionID,
        stages: [
            SleepStageSegment(
                stage: prediction.stage,
                startAt: prediction.timestamp,
                endAt: prediction.timestamp
            )
        ],
        modelVersion: prediction.modelVersion
    )
}

private func mapSleepInferenceError(_ error: Error) -> AppError {
    if let appError = error as? AppError {
        return appError
    }
    return .sleepInferenceFailed
}
