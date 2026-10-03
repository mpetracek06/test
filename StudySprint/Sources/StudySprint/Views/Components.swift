import SwiftUI
import StudySprintCore

enum Theme {
    static let gradient = LinearGradient(colors: [Color.indigo, Color.purple, Color.pink.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardRadius: CGFloat = 14
    static let done = Color.green
    static let testedOut = Color.teal
}

/// Rounded panel used throughout the app.
struct Card<Content: View>: View {
    var title: String? = nil
    var systemImage: String? = nil
    var tint: Color = .accentColor
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack {
                    if let systemImage {
                        Image(systemName: systemImage).foregroundStyle(tint)
                    }
                    Text(title).font(.headline)
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct BulletList: View {
    let items: [String]
    var bullet: String = "•"
    var color: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bullet).foregroundStyle(color)
                    MarkdownText(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Renders inline Markdown (bold, italics, code, links) and keeps line breaks.
struct MarkdownText: View {
    let source: String
    init(_ source: String) { self.source = source }

    var body: some View {
        Text(Self.attributed(source))
            .textSelection(.enabled)
    }

    static func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(Capsule().fill(tint.opacity(0.13)))
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 6
    var size: CGFloat = 44
    var showLabel = true

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(Theme.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
            if showLabel {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
    }
}

/// Speaker button that reads text aloud.
struct SpeakButton: View {
    let id: String
    let text: String
    @ObservedObject private var speaker = Speaker.shared

    var body: some View {
        Button {
            speaker.toggle(id: id, text: text)
        } label: {
            Image(systemName: speaker.speakingID == id ? "speaker.wave.2.fill" : "speaker.wave.2")
        }
        .buttonStyle(.borderless)
        .help(speaker.speakingID == id ? "Stop reading" : "Read aloud")
    }
}

struct GradientTitle: View {
    let text: String
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.gradient)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(Theme.gradient)
            Text(title).font(.title3.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }
}

/// Pulsing dot to show something is live.
struct PulseDot: View {
    var color: Color = .accentColor
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .scaleEffect(on ? 1.25 : 0.8)
            .opacity(on ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension StepStatus {
    var color: Color {
        switch self {
        case .notStarted: return .secondary
        case .done: return Theme.done
        case .testedOut: return Theme.testedOut
        }
    }
    var icon: String {
        switch self {
        case .notStarted: return "circle"
        case .done: return "checkmark.circle.fill"
        case .testedOut: return "forward.circle.fill"
        }
    }
    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .done: return "Done"
        case .testedOut: return "Tested out"
        }
    }
}

func elapsedString(since date: Date, now: Date = Date()) -> String {
    let s = max(0, Int(now.timeIntervalSince(date)))
    return String(format: "%d:%02d", s / 60, s % 60)
}
