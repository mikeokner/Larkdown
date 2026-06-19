import AppKit

final class DocumentWindowController: NSWindowController {
    init(document: LarkdownDocument) {
        let splitViewController = EditorSplitViewController(document: document)
        let window = NSWindow(contentViewController: splitViewController)
        window.title = document.displayName
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.minSize = NSSize(width: 720, height: 420)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = false
        super.init(window: window)
        shouldCloseDocument = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
