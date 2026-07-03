import SwiftUI
import HRSenseCore

public struct SleepHypnogramView: View {
    private let session: SleepSession

    public init(session: SleepSession) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sleep Hypnogram")
                    .font(.headline)
                Spacer()
                Text(session.modelVersion)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if session.stages.isEmpty {
                Text("No staged sleep segments yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                GeometryReader { proxy in
                    Canvas { context, size in
                        drawHypnogram(in: &context, size: size)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(height: 160)

                HStack(spacing: 12) {
                    ForEach(SleepStage.allCases, id: \.rawValue) { stage in
                        Label(stage.displayName, systemImage: "square.fill")
                            .font(.caption2)
                            .foregroundStyle(stage.color)
                    }
                }

                HStack {
                    Text(sessionStartLabel)
                    Spacer()
                    Text(totalDurationLabel)
                    Spacer()
                    Text(sessionEndLabel)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospacedDigit()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func drawHypnogram(in context: inout GraphicsContext, size: CGSize) {
        guard let firstStart = session.stages.first?.startAt,
              let lastEnd = session.stages.last?.endAt
        else { return }

        let totalDuration = max(lastEnd.timeIntervalSince(firstStart), 1)
        let bandHeight = size.height / CGFloat(SleepStage.allCases.count)

        for (index, stage) in SleepStage.displayOrder.enumerated() {
            let y = CGFloat(index) * bandHeight
            let bandRect = CGRect(x: 0, y: y, width: size.width, height: bandHeight)
            context.fill(
                Path(bandRect),
                with: .color(stage.color.opacity(0.08))
            )
        }

        for segment in session.stages {
            let startOffset = segment.startAt.timeIntervalSince(firstStart) / totalDuration
            let endOffset = max(segment.endAt.timeIntervalSince(firstStart) / totalDuration, startOffset + 0.005)
            let bandIndex = SleepStage.displayOrder.firstIndex(of: segment.stage) ?? 0
            let rect = CGRect(
                x: size.width * startOffset,
                y: CGFloat(bandIndex) * bandHeight + 4,
                width: max(size.width * (endOffset - startOffset), 2),
                height: bandHeight - 8
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: 4),
                with: .color(segment.stage.color)
            )
        }
    }

    private var sessionStartLabel: String {
        session.stages.first.map { Self.timeFormatter.string(from: $0.startAt) } ?? "--:--"
    }

    private var sessionEndLabel: String {
        session.stages.last.map { Self.timeFormatter.string(from: $0.endAt) } ?? "--:--"
    }

    private var totalDurationLabel: String {
        guard let first = session.stages.first?.startAt,
              let last = session.stages.last?.endAt
        else { return "0m" }
        let minutes = max(Int(last.timeIntervalSince(first) / 60), 0)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return hours > 0 ? "\(hours)h \(remainingMinutes)m" : "\(remainingMinutes)m"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private extension SleepStage {
    static let displayOrder: [SleepStage] = [.wake, .rem, .light, .deep]

    var displayName: String {
        switch self {
        case .wake: return "Wake"
        case .light: return "Light"
        case .deep: return "Deep"
        case .rem: return "REM"
        }
    }

    var color: Color {
        switch self {
        case .wake: return Color.gray
        case .light: return Color.blue
        case .deep: return Color.indigo
        case .rem: return Color.purple
        }
    }
}
