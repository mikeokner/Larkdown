import AppKit
import LarkdownCore

final class LarkdownDocument: NSDocument {
    var text = ""
    private(set) var isClosed = false

    // Captured at load and reused on save so a CRLF file stays CRLF even
    // though the text view inserts LF newlines while editing.
    private(set) var lineEnding: LineEnding = .lf

    private var hasUTF8ByteOrderMark = false

    override var fileURL: URL? {
        didSet {
            if fileURL != oldValue {
                onFileURLChanged?()
            }
        }
    }

    var onFileURLChanged: (() -> Void)?
    var onTextReplaced: (() -> Void)?
    var onWillSave: (() -> Void)?

    override class var autosavesInPlace: Bool {
        true
    }

    override init() {
        super.init()
        hasUndoManager = true
    }

    override func close() {
        isClosed = true
        super.close()
    }

    override func makeWindowControllers() {
        let controller = DocumentWindowController(document: self)
        addWindowController(controller)
    }

    override func data(ofType typeName: String) throws -> Data {
        var state = MarkdownDocumentState(source: text)
        state.lineEnding = lineEnding
        state.hasUTF8ByteOrderMark = hasUTF8ByteOrderMark
        return state.encodedData()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let state = try MarkdownDocumentState(data: data)
        lineEnding = state.lineEnding
        hasUTF8ByteOrderMark = state.hasUTF8ByteOrderMark
        text = state.source
        onTextReplaced?()
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        onWillSave?()
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }
}
