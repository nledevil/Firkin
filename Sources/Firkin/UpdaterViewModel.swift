import SwiftUI
import Combine
import Sparkle

/// Owns Sparkle's updater. Update checks are permission-based: Sparkle asks
/// the user before enabling scheduled checks, and the only network contact is
/// the appcast feed and release downloads on GitHub.
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?

    init() {
        // A bare `swift run` binary has no bundle identity or Info.plist feed;
        // Sparkle only makes sense from the packaged Firkin.app.
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
