import Foundation

/// Shared utility for generating realistic RR intervals with physiological variability.
///
/// Real heart-rate monitors report 1–3 RR intervals per 1-second sample.
/// This helper synthesises plausible intervals using:
///   - Respiratory Sinus Arrhythmia (RSA) — sinusoidal modulation at ~0.25 Hz
///   - Gaussian noise — natural beat-to-beat jitter
///
/// These two components produce non-trivial RMSSD / SDNN values that exercise
/// the full HRV computation pipeline (C++ 14-dim features, CoreML fallback).
public enum RRSynthesizer {

    /// Generate realistic RR intervals for one sample period.
    ///
    /// - Parameters:
    ///   - heartRate: current heart rate in bpm.
    ///   - elapsedSeconds: seconds since streaming started (for RSA phase).
    ///   - rsaAmplitude: RSA modulation amplitude in ms (default 20).
    ///   - noiseStd: Gaussian noise standard deviation in ms (default 10).
    ///   - rsaPeriodSeconds: respiratory cycle period in seconds (default 4).
    ///   - intervalCount: number of RR intervals to generate (default 2).
    /// - Returns: array of RR intervals in milliseconds.
    public static func generate(
        heartRate: Double,
        elapsedSeconds: Double,
        rsaAmplitude: Double = 20,
        noiseStd: Double = 10,
        rsaPeriodSeconds: Double = 4.0,
        intervalCount: Int = 2
    ) -> [UInt16] {
        let meanRR = 60_000.0 / max(heartRate, 30)

        var intervals: [UInt16] = []
        intervals.reserveCapacity(intervalCount)

        for i in 0..<intervalCount {
            // Spread RSA phase across sub-intervals within the sample period
            let subPhase = Double(i) / Double(intervalCount)
            let rsaComponent = rsaAmplitude * sin(
                2 * .pi * (elapsedSeconds + subPhase) / rsaPeriodSeconds
            )
            let noiseComponent = gaussianRandom(mean: 0, std: noiseStd)
            let rr = meanRR + rsaComponent + noiseComponent
            intervals.append(UInt16(max(rr, 300)))  // floor at 300ms (200 bpm)
        }

        return intervals
    }

    /// Box-Muller transform for Gaussian random numbers.
    private static func gaussianRandom(mean: Double, std: Double) -> Double {
        let u1 = Double.random(in: 1e-10...1)
        let u2 = Double.random(in: 0...(2 * .pi))
        let z = sqrt(-2 * log(u1)) * cos(u2)
        return mean + std * z
    }
}
