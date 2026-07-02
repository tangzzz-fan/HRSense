import SwiftUI
import HRSenseCore

/// High-performance waveform canvas using TimelineView + min/max downsampling.
///
/// Renders waveform samples as a filled polygon. Uses pixel-column min/max
/// downsampling to avoid overdraw and maintain ≥55 fps.
public struct WaveformCanvasView: View {
    /// Samples to render (oldest → newest).
    public let samples: [WaveformSample]
    /// Waveform type for colour-mapping.
    public let waveformType: WaveformType
    /// Visible time window in seconds (default 5s).
    public let windowSeconds: Double

    public init(samples: [WaveformSample], waveformType: WaveformType = .ecg, windowSeconds: Double = 5) {
        self.samples = samples
        self.waveformType = waveformType
        self.windowSeconds = windowSeconds
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard !samples.isEmpty, size.width > 0, size.height > 0 else { return }

                // Downsample: one column per pixel
                let pixelWidth = Int(size.width)
                let midY = size.height / 2
                let scaleY = size.height / 2  // ±1 scaled range → half canvas

                // Compute min/max per pixel column
                let samplesPerPixel = max(1, samples.count / pixelWidth)

                var path = Path()
                var started = false

                for px in 0..<pixelWidth {
                    let startIdx = px * samplesPerPixel
                    let endIdx = min(startIdx + samplesPerPixel, samples.count)
                    guard startIdx < endIdx else { break }

                    var colMin: Float = .greatestFiniteMagnitude
                    var colMax: Float = -.greatestFiniteMagnitude
                    for i in startIdx..<endIdx {
                        let v = samples[i].value
                        if v < colMin { colMin = v }
                        if v > colMax { colMax = v }
                    }
                    let x = CGFloat(px)
                    let yMin = midY - CGFloat(colMax) * scaleY / 1000.0

                    if !started {
                        path.move(to: CGPoint(x: x, y: yMin))
                        started = true
                    } else {
                        path.addLine(to: CGPoint(x: x, y: yMin))
                    }
                }

                // Reverse pass (bottom edge)
                for px in (0..<pixelWidth).reversed() {
                    let startIdx = px * samplesPerPixel
                    let endIdx = min(startIdx + samplesPerPixel, samples.count)
                    guard startIdx < endIdx else { continue }
                    var colMin: Float = .greatestFiniteMagnitude
                    var colMax: Float = -.greatestFiniteMagnitude
                    for i in startIdx..<endIdx {
                        let v = samples[i].value
                        if v < colMin { colMin = v }
                        if v > colMax { colMax = v }
                    }
                    let x = CGFloat(px)
                    let yMax = midY - CGFloat(colMin) * scaleY / 1000.0
                    path.addLine(to: CGPoint(x: x, y: yMax))
                }
                path.closeSubpath()

                // Fill with gradient
                let color: Color = waveformType == .ecg ? .green : .orange
                context.fill(path, with: .color(color.opacity(0.3)))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
    }
}
