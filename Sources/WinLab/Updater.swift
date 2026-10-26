import Foundation
import Observation
import Sparkle

/// Sparkle updates from the GitHub release appcast (SUFeedURL in Info.plist),
/// signed with the EdDSA key in SUPublicEDKey. A menu bar app has no window
/// to interrupt, so a scheduled update shows as a gentle badge in the menu.
@MainActor
@Observable
final class Updater: NSObject {
    private var controller: SPUStandardUpdaterController?
    /// A scheduled check found an update the user has not looked at yet.
    private(set) var available: String?

    override init() {
        super.init()
        // Only a bundled app has the feed and key; `swift run` does not.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var enabled: Bool { controller != nil }
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Quietly, e.g. when the portal's contract moved past this build.
    func checkInBackground() {
        controller?.updater.checkForUpdatesInBackground()
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate { available = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        available = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        available = nil
    }
}
