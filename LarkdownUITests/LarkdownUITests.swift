//
//  LarkdownUITests.swift
//  LarkdownUITests
//
//  Created by Mike Okner on 6/18/26.
//

import XCTest

final class LarkdownUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Debug builds share saved window state with an installed Larkdown, so
    // don't reopen its documents.
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }

    @MainActor
    func testNewDocumentSupportsNativeEditingUndoAndRedo() throws {
        let app = launchApp()
        app.typeKey("n", modifierFlags: .command)
        let window = app.windows.firstMatch
        let editor = window.textViews["markdownSourceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("Draft text")
        XCTAssertEqual(editor.value as? String, "Draft text")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "")
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(editor.value as? String, "Draft text")
    }

    @MainActor
    func testMainMenuContainsDocumentCommands() throws {
        let app = launchApp()

        XCTAssertTrue(app.menuBars.menuBarItems["File"].waitForExistence(timeout: 3))
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["New"].exists)
        XCTAssertTrue(app.menuItems["Open…"].exists)
        XCTAssertTrue(app.menuItems["Open Recent"].exists)
        app.typeKey(.escape, modifierFlags: [])

        app.menuBars.menuBarItems["Edit"].click()
        app.menuItems["Find"].hover()
        XCTAssertTrue(app.menuItems["Find and Replace…"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])

        // AppKit can insert its own full-screen item; the menu must have one.
        app.menuBars.menuBarItems["View"].click()
        let fullScreenItems = app.menuItems.matching(NSPredicate(format: "title == %@", "Enter Full Screen"))
        XCTAssertEqual(fullScreenItems.count, 1)
    }
}
