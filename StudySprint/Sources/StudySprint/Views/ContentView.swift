import SwiftUI

enum SidebarItem: Hashable {
    case newGuide
    case guide(UUID)
}

struct ContentView: View {
    @EnvironmentObject private var store: GuideStore
    @State private var selection: SidebarItem? = .newGuide

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("New study sprint", systemImage: "sparkles")
                    .tag(SidebarItem.newGuide)

                if !store.guides.isEmpty {
                    Section("My guides") {
                        ForEach(store.guides) { guide in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(guide.topic).lineLimit(1)
                                ProgressView(value: guide.progress)
                                    .progressViewStyle(.linear)
                                    .controlSize(.mini)
                            }
                            .padding(.vertical, 2)
                            .tag(SidebarItem.guide(guide.id))
                            .contextMenu {
                                Button("Delete", role: .destructive) { delete(guide.id) }
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            switch selection {
            case .guide(let id):
                if let current = store.guides.first(where: { $0.id == id }) {
                    GuideDetailView(guide: Binding(
                        get: { store.guides.first(where: { $0.id == id }) ?? current },
                        set: { store.update($0) }
                    ))
                    .id(id)
                } else {
                    NewGuideView(onCreated: { selection = .guide($0) })
                }
            default:
                NewGuideView(onCreated: { selection = .guide($0) })
            }
        }
    }

    private func delete(_ id: UUID) {
        if selection == .guide(id) { selection = .newGuide }
        store.delete(id: id)
    }
}
