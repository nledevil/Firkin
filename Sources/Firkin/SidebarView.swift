import SwiftUI

struct SidebarView: View {
    @Environment(PackageStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.sidebarSelection) {
            Section("Library") {
                ForEach(PackageStore.SidebarSection.librarySections) { section in
                    sectionRow(section)
                }
            }
            Section("Discover") {
                sectionRow(.browse)
            }
            Section("System") {
                sectionRow(.apps)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
            if let version = store.brewVersion {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sectionRow(_ section: PackageStore.SidebarSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .badge(store.count(for: section))
            .tag(section)
    }
}
