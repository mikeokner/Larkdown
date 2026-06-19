import AppKit
import Foundation
import LarkdownCore
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import Larkdown

struct LarkdownTests {
    @Test func bundleRegistersMarkdownDocumentTypes() throws {
        let documentTypes = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let markdownType = try #require(documentTypes.first)

        let contentTypes = Set(try #require(markdownType["LSItemContentTypes"] as? [String]))
        let filenameExtensions = Set(try #require(markdownType["CFBundleTypeExtensions"] as? [String]))

        #expect(contentTypes.contains("public.markdown"))
        #expect(contentTypes.contains("net.daringfireball.markdown"))
        #expect(filenameExtensions.isSuperset(of: ["md", "markdown", "mdown"]))

        if let systemMarkdownType = UTType(filenameExtension: "md")?.identifier {
            #expect(contentTypes.contains(systemMarkdownType))
        }
    }

    @Test func bundleContainsAboutVersionMetadata() throws {
        let version = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

        #expect(!version.isEmpty)
        #expect(!version.contains("$("))
        #expect(!build.isEmpty)
        #expect(!build.contains("$("))
    }

    @MainActor
    @Test func mainMenuListsRecentDocumentsInOpenRecentSubmenu() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        try Data("# Recent".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        let menu = MainMenuFactory.make()
        let fileMenu = try #require(menu.item(withTitle: "File")?.submenu)
        let openRecentMenu = try #require(fileMenu.item(withTitle: "Open Recent")?.submenu)
        openRecentMenu.delegate?.menuNeedsUpdate?(openRecentMenu)

        #expect(openRecentMenu.item(withTitle: "Clear Menu") != nil)
        #expect(openRecentMenu.item(withTitle: url.lastPathComponent) != nil)
    }

    @MainActor
    @Test func documentRoundTripsMarkdownDataSafely() throws {
        let source = """
        ---
        title: App Document
        ---

        # Heading

        A paragraph with **strong** text.
        """.replacingOccurrences(of: "\n", with: "\r\n")
        let document = LarkdownDocument()

        try document.read(from: Data(source.utf8), ofType: "net.daringfireball.markdown")

        #expect(document.text == source)
        #expect(document.lineEnding == .crlf)
        #expect(String(data: try document.data(ofType: "net.daringfireball.markdown"), encoding: .utf8) == source)

        document.text += "\r\nA saved edit.\r\n"
        let saved = try #require(String(data: try document.data(ofType: "net.daringfireball.markdown"), encoding: .utf8))

        #expect(saved.hasSuffix("\r\nA saved edit.\r\n"))
        #expect(!saved.contains("\nA saved edit.\n"))
    }

    @MainActor
    @Test func preservesCRLFWhenEditsIntroduceLFNewlines() throws {
        let document = LarkdownDocument()
        try document.read(from: Data("one\r\ntwo\r\n".utf8), ofType: "net.daringfireball.markdown")

        // The text view inserts plain LF newlines while typing.
        document.text += "\nthree\n"
        let saved = try #require(String(data: document.data(ofType: "net.daringfireball.markdown"), encoding: .utf8))

        #expect(document.lineEnding == .crlf)
        #expect(saved.contains("three\r\n"))
        #expect(!saved.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    @MainActor
    @Test func readReplacingTextNotifiesForRevertAndReload() throws {
        let document = LarkdownDocument()
        var replacements = 0
        document.onTextReplaced = { replacements += 1 }

        try document.read(from: Data("# One".utf8), ofType: "net.daringfireball.markdown")
        try document.read(from: Data("# Two".utf8), ofType: "net.daringfireball.markdown")

        #expect(replacements == 2)
        #expect(document.text == "# Two")
    }
}

@Suite(.serialized)
struct DocumentEditingTests {
    private let typeName = "net.daringfireball.markdown"

    @MainActor
    @Test func editorSaveReopenUndoAndRevertPreserveSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document.md")
        let original = "# Original\r\nUnicode: 🐦 café\r\n"
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data(original.utf8)
        try bytes.write(to: url)
        let document = try LarkdownDocument(contentsOf: url, ofType: typeName)
        document.makeWindowControllers()
        defer { document.close() }
        let window = try #require(document.windowControllers.first?.window)
        let editor = try #require(findTextView(in: window.contentView))
        #expect(editor.string == original)
        editor.insertText("Before save\n", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
        editor.breakUndoCoalescing()
        let savedText = document.text
        try await save(document, to: url)
        let savedBytes = try Data(contentsOf: url)
        #expect(savedBytes.starts(with: [0xEF, 0xBB, 0xBF]))
        let reopened = try LarkdownDocument(contentsOf: url, ofType: typeName)
        defer { reopened.close() }
        #expect(reopened.text == savedText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n"))
        editor.insertText("After save", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
        editor.breakUndoCoalescing()
        document.undoManager?.undo()
        #expect(document.text == savedText)
        document.undoManager?.redo()
        #expect(document.text.hasSuffix("After save"))
        try document.revert(toContentsOf: url, ofType: typeName)
        #expect(editor.string == reopened.text)
        #expect(!document.undoManager!.canUndo)
        #expect(!document.isDocumentEdited)
        editor.insertText("Fresh edit", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
        editor.breakUndoCoalescing()
        document.undoManager?.undo()
        #expect(editor.string == reopened.text)
        #expect(document.text == reopened.text)
    }

    @MainActor
    @Test func firstSaveAndSaveAsRefreshRelativePreviewLinks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let secondDirectory = directory.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = LarkdownDocument()
        document.text = "[Next](next.md)"
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try #require(document.windowControllers.first?.window?.contentViewController as? EditorSplitViewController)
        let previewController = try #require(controller.splitViewItems.last?.viewController as? MarkdownPreviewViewController)
        _ = previewController.view
        let preview = try #require(previewController.webView)
        let firstURL = directory.appendingPathComponent("first.md")
        try await save(document, to: firstURL)
        try await expectPreviewLink(preview, equals: PreviewResource.baseURL(forDocumentAt: firstURL).appendingPathComponent("next.md").absoluteString)
        let secondURL = secondDirectory.appendingPathComponent("second.md")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.save(to: secondURL, ofType: typeName, for: .saveAsOperation) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        #expect(document.fileURL == secondURL)
        try await expectPreviewLink(preview, equals: PreviewResource.baseURL(forDocumentAt: secondURL).appendingPathComponent("next.md").absoluteString)
    }

    @MainActor
    @Test func replacementPreservesScrollOriginAndSelection() throws {
        let lines = (1...400).map { "Line \($0)" }
        let controller = MarkdownEditorViewController(text: lines.joined(separator: "\n"))
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        window.setContentSize(NSSize(width: 400, height: 300))
        window.contentView?.layoutSubtreeIfNeeded()
        let editor = try #require(findTextView(in: window.contentView))
        let scrollView = try #require(editor.enclosingScrollView)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 2000))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        editor.setSelectedRange(NSRange(location: 10, length: 4))

        controller.replaceText(with: (lines + ["Appended"]).joined(separator: "\n").replacingOccurrences(of: "Line 1\n", with: "Line One\n"))

        #expect(scrollView.contentView.bounds.origin.y == 2000)
        #expect(editor.selectedRange() == NSRange(location: 10, length: 4))
    }

    @MainActor
    private func expectPreviewLink(_ preview: WKWebView, equals expected: String) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let actual = try? await evaluatePreviewScript(preview, "document.querySelector('a')?.href"),
               actual as? String == expected { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Preview did not resolve its relative link to \(expected)")
    }

    @MainActor
    @Test func failedReadAndSaveLeaveDocumentContentIntact() async throws {
        let document = LarkdownDocument()
        try document.read(from: Data("# Keep this\r\n".utf8), ofType: typeName)
        #expect(throws: MarkdownDocumentStateError.unsupportedEncoding) {
            try document.read(from: Data([0xFF, 0xFE]), ofType: typeName)
        }
        #expect(document.text == "# Keep this\r\n")
        #expect(document.lineEnding == .crlf)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("absent/document.md")
        do {
            try await save(document, to: url)
            Issue.record("Saving into an absent parent directory should fail")
        } catch {
            #expect(document.text == "# Keep this\r\n")
            #expect(document.fileURL == nil)
        }
        document.close()
    }

    @MainActor
    private func save(_ document: LarkdownDocument, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.save(to: url, ofType: typeName, for: .saveOperation) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    @MainActor
    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { findTextView(in: $0) }.first
    }
}
