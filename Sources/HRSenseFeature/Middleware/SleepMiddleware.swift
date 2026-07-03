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
    computeRepository: any ComputeRepository,
    sleepInferenceRepository: any SleepInferenceRepository,
    persistenceStore: (any PersistenceStore)? = nil,
    windowDuration: TimeInterval = 300,
    circadianHistoryDuration: TimeInterval = 4 * 60 * 60,
    calendar: Calendar = Calendar(identifier: .gregorian),
    nowProvider: @escaping @Sendable () -> Date = Date.init
) -> Middleware<AppState, Action> {
    var metricsHistory: [SleepMetricSnapshot] = []

    return { store, action, next in
        next(action)

        switch action {
        case .connectionStateChanged(.connected), .connectionStateChanged(.restoredConnected):
            store.dispatch(.sleep(.monitoringStarted(nowProvider())))

        case .connectionStateChanged(.disconnected):
            store.dispatch(.sleep(.monitoringStopped(nowProvider())))

        case .sleep(.historyLoadRequested(let limit)):
            guard let persistenceStore else { break }
            Task {
                do {
                    let sessions = try await persistenceStore.querySleepSessions(
                        SleepSessionQuery(limit: limit)
                    )
                    await MainActor.run {
                        store.dispatch(.sleep(.historyLoaded(sessions)))
                    }
                } catch {
                    await MainActor.run {
                        store.dispatch(.errorOccurred(.persistenceFailed(reason: error.localizedDescription)))
                    }
                }
            }

        case .clearSamples:
            metricsHistory.removeAll()
            store.dispatch(.sleep(.reset))

        case .hrvComputed(let metrics):
            guard store.state.sleep.isMonitoring else { break }
            guard let latestSample = store.state.live.recentSamples.last else { break }

            metricsHistory.append(
                SleepMetricSnapshot(
                    timestamp: latestSample.timestamp,
                    rmssd: metrics.rmssd
                )
            )
            let historyCutoff = latestSample.timestamp.addingTimeInterval(-circadianHistoryDuration)
            metricsHistory.removeAll { $0.timestamp < historyCutoff }

            guard let input = makeSleepWindowInput(
                state: store.state,
                metrics: metrics,
                computeRepository: computeRepository,
                metricsHistory: metricsHistory,
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
            if case .sleep(.sessionPersisted) = action {
                store.dispatch(.sleep(.historyLoadRequested(limit: 7)))
            }
            break
        }
    }
}

private func makeSleepWindowInput(
    state: AppState,
    metrics: HRVMetrics,
    computeRepository: any ComputeRepository,
    metricsHistory: [SleepMetricSnapshot],
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

    let heartRates = windowSamples.map(\.heartRate)
    let hrvWindowValues = metricsHistory.map(\.rmssd)

    let cxxFeatures = (try? computeRepository.computeSleepFeatures(
        heartRates: heartRates,
        hrvWindowValues: hrvWindowValues
    )) ?? SleepCXXFeatures()

    return SleepWindowInput(
        metrics: metrics,
        timeContext: timeContext,
        cxxFeatures: cxxFeatures
    )
}

private struct SleepMetricSnapshot {
    let timestamp: Date
    let rmssd: Double
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
