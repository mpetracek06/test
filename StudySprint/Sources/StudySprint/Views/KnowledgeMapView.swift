import SwiftUI
import StudySprintCore

/// A map of how the steps build on each other, colored by your progress.
struct KnowledgeMapView: View {
    @Binding var guide: StudyGuide
    var onStartSprint: () -> Void
    @State private var selected: Int?

    private let nodeSize = CGSize(width: 200, height: 70)
    private let columnGap: CGFloat = 56
    private let rowGap: CGFloat = 22
    private let bandGap: CGFloat = 48
    private let margin: CGFloat = 30

    private var depths: [Int] { KnowledgeMapLayout.depths(for: guide.steps) }

    struct Layout {
        var points: [CGPoint]
        var bands: [Int]
        var size: CGSize
    }

    /// Columns by dependency depth; when the chain is wider than the window it wraps
    /// onto further rows ("bands") instead of shrinking, so text stays readable.
    private func layout(width: CGFloat) -> Layout {
        let d = depths
        guard !d.isEmpty else { return Layout(points: [], bands: [], size: .zero) }
        let maxDepth = d.max() ?? 0
        let perRow = max(1, Int((width - 2 * margin + columnGap) / (nodeSize.width + columnGap)))
        let bandCount = maxDepth / perRow + 1

        var perDepth: [Int: Int] = [:]
        for depth in d { perDepth[depth, default: 0] += 1 }
        var rowsInBand = [Int](repeating: 1, count: bandCount)
        for (depth, count) in perDepth { rowsInBand[depth / perRow] = max(rowsInBand[depth / perRow], count) }

        var bandTop = [CGFloat](repeating: margin, count: bandCount)
        for b in 1..<max(bandCount, 1) where b < bandCount {
            bandTop[b] = bandTop[b - 1] + CGFloat(rowsInBand[b - 1]) * (nodeSize.height + rowGap) - rowGap + bandGap
        }

        var rowInDepth: [Int: Int] = [:]
        let points = d.map { depth -> CGPoint in
            let row = rowInDepth[depth, default: 0]
            rowInDepth[depth] = row + 1
            let band = depth / perRow, col = depth % perRow
            return CGPoint(x: margin + CGFloat(col) * (nodeSize.width + columnGap) + nodeSize.width / 2,
                           y: bandTop[band] + CGFloat(row) * (nodeSize.height + rowGap) + nodeSize.height / 2)
        }
        let cols = min(perRow, maxDepth + 1)
        let size = CGSize(
            width: 2 * margin + CGFloat(cols) * nodeSize.width + CGFloat(cols - 1) * columnGap,
            height: bandTop[bandCount - 1] + CGFloat(rowsInBand[bandCount - 1]) * (nodeSize.height + rowGap) - rowGap + margin
        )
        return Layout(points: points, bands: d.map { $0 / perRow }, size: size)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let l = layout(width: geo.size.width)
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        edges(l)
                        ForEach(guide.steps.indices, id: \.self) { i in
                            node(i)
                                .position(l.points[i])
                        }
                    }
                    .frame(width: l.size.width, height: l.size.height)
                    .frame(width: geo.size.width, height: max(geo.size.height, l.size.height))
                }
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

    private func edges(_ l: Layout) -> some View {
        let pts = l.points
        let chainOnly = guide.steps.allSatisfy { $0.prerequisites.isEmpty }
        var links: [(Int, Int)] = []
        for (i, step) in guide.steps.enumerated() {
            for p in step.prerequisites where p - 1 >= 0 && p - 1 < i { links.append((p - 1, i)) }
        }
        if chainOnly && pts.count > 1 { links = (1..<pts.count).map { ($0 - 1, $0) } }

        return Canvas { ctx, _ in
            for (a, b) in links {
                let lit = guide.steps[a].status.isComplete
                let color: Color = lit ? .green.opacity(0.65) : .secondary.opacity(0.4)
                var path = Path()
                var head = Path()
                if l.bands[a] == l.bands[b] && pts[b].x > pts[a].x {
                    // Same row: right edge → left edge.
                    let from = CGPoint(x: pts[a].x + nodeSize.width / 2, y: pts[a].y)
                    let to = CGPoint(x: pts[b].x - nodeSize.width / 2, y: pts[b].y)
                    let dx = (to.x - from.x) * 0.5
                    path.move(to: from)
                    path.addCurve(to: to, control1: CGPoint(x: from.x + dx, y: from.y), control2: CGPoint(x: to.x - dx, y: to.y))
                    head.move(to: to)
                    head.addLine(to: CGPoint(x: to.x - 8, y: to.y - 4.5))
                    head.addLine(to: CGPoint(x: to.x - 8, y: to.y + 4.5))
                } else {
                    // Wraps to a later row: bottom edge → top edge.
                    let from = CGPoint(x: pts[a].x, y: pts[a].y + nodeSize.height / 2)
                    let to = CGPoint(x: pts[b].x, y: pts[b].y - nodeSize.height / 2)
                    let dy = max(30, (to.y - from.y) * 0.5)
                    path.move(to: from)
                    path.addCurve(to: to, control1: CGPoint(x: from.x, y: from.y + dy), control2: CGPoint(x: to.x, y: to.y - dy))
                    head.move(to: to)
                    head.addLine(to: CGPoint(x: to.x - 4.5, y: to.y - 8))
                    head.addLine(to: CGPoint(x: to.x + 4.5, y: to.y - 8))
                }
                head.closeSubpath()
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lit ? 2.5 : 1.5, lineCap: .round))
                ctx.fill(head, with: .color(color))
            }
        }
        .frame(width: l.size.width, height: l.size.height)
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
