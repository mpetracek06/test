import SwiftUI
import StudySprintCore

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject private var speaker = Speaker.shared

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            detail
        }
        .onChange(of: app.selection) { _ in speaker.stop() }
    }

    @ViewBuilder
    private var detail: some View {
        switch app.selection {
        case .review:
            ReviewView()
        case .guide(let id):
            if let binding = app.binding(for: id) {
                GuideDetailView(guide: binding)
                    .id(id)
            } else {
                NewGuideView()
            }
        default:
            NewGuideView()
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        SidebarList(generation: app.generation)
    }
}

private struct SidebarList: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var generation: GenerationController

    var body: some View {
        List(selection: $app.selection) {
            Section {
                Label {
                    HStack {
                        Text("New sprint")
                        if generation.isRunning {
                            Spacer()
                            PulseDot()
                        }
                    }
                } icon: {
                    Image(systemName: "sparkles")
                }
                .tag(SidebarItem.newGuide)

                Label("Review", systemImage: "brain.head.profile")
                    .badge(app.dueCount)
                    .tag(SidebarItem.review)
            }

            if !app.guides.isEmpty {
                Section("My sprints") {
                    ForEach(app.guides) { guide in
                        GuideRow(guide: guide)
                            .tag(SidebarItem.guide(guide.id))
                            .contextMenu {
                                Button("Delete", role: .destructive) { app.delete(guide.id) }
                            }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            StreakFooter()
        }
    }
}

private struct GuideRow: View {
    let guide: StudyGuide

    var body: some View {
        HStack(spacing: 10) {
            Text(guide.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(guide.topic).lineLimit(1)
                Text(guide.progress >= 1 ? "Complete" : "\(guide.remainingMinutes) min left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            ProgressRing(progress: guide.progress, lineWidth: 3, size: 22, showLabel: false)
        }
        .padding(.vertical, 3)
    }
}

private struct StreakFooter: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let streak = app.log.streak()
        let today = app.log.reviews()
        HStack(spacing: 12) {
            Label("\(streak)", systemImage: "flame.fill")
                .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
                .help("Day streak")
            Label("\(today)", systemImage: "checkmark.seal")
                .foregroundStyle(.secondary)
                .help("Cards reviewed today")
            Spacer()
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
