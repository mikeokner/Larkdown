import AppKit
import Sparkle

@MainActor
final class UpdaterController: NSObject, NSMenuItemValidation {
    static let shared = UpdaterController()
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        controller?.updater.canCheckForUpdates ?? false
    }
}
