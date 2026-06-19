import AppKit

final class LarkdownApp: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UpdaterController.shared.start()
        NSApp.mainMenu = MainMenuFactory.make()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
