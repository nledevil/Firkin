import SwiftUI
import FirkinKit

@main
struct FirkinApp: App {
    @State private var store = PackageStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 780, minHeight: 480)
                .task { await store.refresh() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Packages") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
