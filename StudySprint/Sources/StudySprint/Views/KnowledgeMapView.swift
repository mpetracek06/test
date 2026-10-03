import SwiftUI
import StudySprintCore

/// A map of how the steps build on each other, colored by your progress.
struct KnowledgeMapView: View {
    @Binding var guide: StudyGuide
    var onStartSprint: () -> Void
    @State private var selected: Int?

    private let nodeSize = CGSize(width: 200, height: 70)
    private let columnGap: CGFloat = 90
    private let rowGap: CGFloat = 26
    private let margin: CGFloat = 30

    private var depths: [Int] { KnowledgeMapLayout.depths(for: guide.steps) }

    /// Center point of every node.
    private var positions: [CGPoint] {
        let d = depths
        var rowInColumn: [Int: Int] = [:]
        return d.map { depth in
            let row = rowInColumn[depth, default: 0]
            rowInColumn[depth] = row + 1
            return CGPoint(
                x: margin + CGFloat(depth) * (nodeSize.width + columnGap) + nodeSize.width / 2,
                y: margin + CGFloat(row) * (nodeSize.height + rowGap) + nodeSize.height / 2
            )
        }
    }

    private var canvasSize: CGSize {
        let p = positions
        let maxX = (p.map(\.x).max() ?? 0) + nodeSize.width / 2 + margin
        let maxY = (p.map(\.y).max() ?? 0) + nodeSize.height / 2 + margin
        return CGSize(width: maxX, height: maxY)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                let pts = positions
                ZStack(alignment: .topLeading) {
                    edges(pts)
                    ForEach(guide.steps.indices, id: \.self) { i in
                        node(i)
                            .position(pts[i])
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .padding(10)
            }
            .background(
                Canvas { ctx, size in
                    let spacing: CGFloat = 22
                    var x: CGFloat = 0
                    while x < size.width {
                        var y: CGFloat = 0
                        while y < size.height {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)),
                                     with: .color(.primary.opacity(0.12)))
                            y += spacing
                        }
                        x += spacing
                    }
                }
            )

            legend

            if let selected, guide.steps.indices.contains(selected) {
                Divider()
                detail(selected)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    private func edges(_ pts: [CGPoint]) -> some View {
        Canvas { ctx, _ in
            for (i, step) in guide.steps.enumerated() {
                for p in step.prerequisites where p - 1 >= 0 && p - 1 < i {
                    let from = CGPoint(x: pts[p - 1].x + nodeSize.width / 2, y: pts[p - 1].y)
                    let to = CGPoint(x: pts[i].x - nodeSize.width / 2, y: pts[i].y)
                    var path = Path()
                    path.move(to: from)
                    let dx = (to.x - from.x) * 0.5
                    path.addCurve(to: to, control1: CGPoint(x: from.x + dx, y: from.y), control2: CGPoint(x: to.x - dx, y: to.y))
                    let lit = guide.steps[p - 1].status.isComplete
                    ctx.stroke(path, with: .color(lit ? .green.opacity(0.6) : .secondary.opacity(0.35)),
                               style: StrokeStyle(lineWidth: lit ? 2.5 : 1.5, lineCap: .round))
                    // Arrowhead
                    var head = Path()
                    head.move(to: to)
                    head.addLine(to: CGPoint(x: to.x - 8, y: to.y - 4.5))
                    head.addLine(to: CGPoint(x: to.x - 8, y: to.y + 4.5))
                    head.closeSubpath()
                    ctx.fill(head, with: .color(lit ? .green.opacity(0.7) : .secondary.opacity(0.5)))
                }
            }
            // Simple chain when Claude gave no dependencies
            if guide.steps.allSatisfy({ $0.prerequisites.isEmpty }) && pts.count > 1 {
                for i in 1..<pts.count {
                    var path = Path()
                    path.move(to: CGPoint(x: pts[i - 1].x + nodeSize.width / 2, y: pts[i - 1].y))
                    path.addLine(to: CGPoint(x: pts[i].x - nodeSize.width / 2, y: pts[i].y))
                    ctx.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1.5)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
    }

    private func node(_ i: Int) -> some View {
        let step = guide.steps[i]
        let isNext = guide.nextStepIndex == i
        let isSelected = selected == i
        return Button {
            selected = selected == i ? nil : i
        } label: {
            HStack(spacing: 8) {
                Text("\(i + 1)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(step.status.isComplete ? step.status.color : Color.indigo.opacity(isNext ? 1 : 0.25)))
                    .foregroundStyle(step.status.isComplete || isNext ? Color.white : Color.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title).font(.callout.weight(.semibold)).lineLimit(2)
                    Text("\(step.minutes) min\(step.videos.isEmpty ? "" : " · ▶︎")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: nodeSize.width, height: nodeSize.height)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(step.status.isComplete ? step.status.color.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: isNext ? Color.indigo.opacity(0.35) : .black.opacity(0.06), radius: isNext ? 10 : 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected || isNext ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.1)),
                                  lineWidth: isSelected ? 3 : isNext ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            LegendDot(color: .indigo, label: "Up next")
            LegendDot(color: Theme.done, label: "Done")
            LegendDot(color: Theme.testedOut, label: "Tested out")
            LegendDot(color: .secondary.opacity(0.4), label: "Not started")
            Spacer()
            Text("Arrows point from an idea to the ideas that build on it. Click a step for details.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func detail(_ i: Int) -> some View {
        let step = guide.steps[i]
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(i + 1). \(step.title)").font(.headline)
                Text(step.why).foregroundStyle(.secondary)
                BulletList(items: Array(step.keyPoints.prefix(4)))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Picker("Status", selection: $guide.steps[i].status) {
                    Text("Not started").tag(StepStatus.notStarted)
                    Text("Done").tag(StepStatus.done)
                    Text("Tested out").tag(StepStatus.testedOut)
                }
                .frame(width: 220)
                Button {
                    onStartSprint()
                } label: {
                    Label("Sprint from here", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent).tint(.indigo)
            }
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.caption)
        }
    }
}
