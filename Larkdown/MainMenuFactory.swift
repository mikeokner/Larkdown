import AppKit

@MainActor
enum MainMenuFactory {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(windowMenuItem())

        return mainMenu
    }

    private static func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Larkdown", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.addItem(withTitle: "About Larkdown", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let updateItem = menu.addItem(withTitle: "Check for Updates…", action: #selector(UpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = UpdaterController.shared
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Larkdown", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Larkdown", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu
        return item
    }

    private static func fileMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "File")
        let documentController = NSDocumentController.shared
        menu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n").target = documentController
        menu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o").target = documentController

        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let openRecentMenu = NSMenu(title: "Open Recent")
        OpenRecentMenuController.shared.configure(menu: openRecentMenu)
        openRecentItem.submenu = openRecentMenu
        menu.addItem(openRecentItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        menu.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        menu.addItem(withTitle: "Revert to Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        menu.addItem(findMenuItem())
        item.submenu = menu
        return item
    }

    private static func findMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Find")
        addTextFinderItem(to: menu, title: "Find…", keyEquivalent: "f", action: .showFindInterface)
        addTextFinderItem(to: menu, title: "Find and Replace…", keyEquivalent: "f", action: .showReplaceInterface)
            .keyEquivalentModifierMask = [.command, .option]
        addTextFinderItem(to: menu, title: "Find Next", keyEquivalent: "g", action: .nextMatch)
        addTextFinderItem(to: menu, title: "Find Previous", keyEquivalent: "G", action: .previousMatch)
        addTextFinderItem(to: menu, title: "Use Selection for Find", keyEquivalent: "e", action: .setSearchString)
        menu.addItem(withTitle: "Jump to Selection", action: #selector(NSText.centerSelectionInVisibleArea(_:)), keyEquivalent: "j")
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func addTextFinderItem(to menu: NSMenu, title: String, keyEquivalent: String, action: NSTextFinder.Action) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: keyEquivalent)
        item.tag = action.rawValue
        return item
    }

    private static func viewMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "View")
        menu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.control, .command]
        item.submenu = menu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }
}

// AppKit only fills Open Recent automatically for menus loaded from a nib.
@MainActor
private final class OpenRecentMenuController: NSObject, NSMenuDelegate {
    static let shared = OpenRecentMenuController()

    // Resolving recent documents touches the file system, so the menu fills
    // only when it opens, not at launch or on every key equivalent.
    func configure(menu: NSMenu) {
        menu.delegate = self
    }

    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>, action: UnsafeMutablePointer<Selector?>) -> Bool {
        false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        let recentURLs = NSDocumentController.shared.recentDocumentURLs
        for url in recentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            menu.addItem(item)
        }

        if !recentURLs.isEmpty {
            menu.addItem(.separator())
        }
        let clearItem = menu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clearItem.target = NSDocumentController.shared
        clearItem.isEnabled = !recentURLs.isEmpty
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }

        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSAlert(error: error).runModal()
            }
        }
    }
}
