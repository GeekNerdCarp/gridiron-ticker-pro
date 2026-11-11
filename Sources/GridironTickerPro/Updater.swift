import AppKit
import Sparkle

/// Updates come from Sparkle: it checks the appcast on the project's GitHub releases, shows the release
/// notes, then downloads, verifies (EdDSA signature), installs and relaunches. Nothing about you is sent.
@MainActor
final class UpdateService {
    static let shared = UpdateService()

    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    /// The "Check for updates automatically" setting. Sparkle stores it in the app's preferences.
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
