import AppKit
import LarkdownCore

struct MarkdownEditorScrollPosition {
    var topVisibleLine: Int
    var scrollFraction: Double
    var isAtBottom: Bool
}

final class MarkdownEditorViewController: NSViewController, NSTextViewDelegate {
    var onTextChange: ((String) -> Void)?
    var onScrollPositionChange: ((MarkdownEditorScrollPosition?) -> Void)?
    var undoManagerProvider: () -> UndoManager? = { nil }

    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let initialText: String
    private let editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let highlightQueue = DispatchQueue(label: "Larkdown.highlight", qos: .utility)
    private let headingFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
    private var isApplyingSyntaxHighlighting = false
    private var syntaxHighlightWorkItem: DispatchWorkItem?
    private var syntaxHighlightGeneration = 0

    init(text: String) {
        self.initialText = text
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        syntaxHighlightWorkItem?.cancel()
    }

    override func loadView() {
        view = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityIdentifier("markdownSourceEditor")
        textView.setAccessibilityLabel("Markdown source")
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = editorFont
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.string = initialText
        textView.delegate = self
        textView.typingAttributes = baseAttributes
        scheduleSyntaxHighlighting(after: .milliseconds(0))

        scrollView.documentView = textView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplyingSyntaxHighlighting else {
            return
        }

        let text = textView.string
        onTextChange?(text)
        scheduleSyntaxHighlighting(after: .milliseconds(120))
        // Report after AppKit lays out the edit, retaining a valid scroll anchor.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onScrollPositionChange?(self.scrollPosition())
        }
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        undoManagerProvider() ?? view.window?.undoManager
    }

    // Replaces the buffer without dirtying the document, for reverts and
    // external reloads. The scroll origin and selection stay where they were.
    func replaceText(with text: String) {
        guard textView.string != text else {
            return
        }

        let scrollOrigin = scrollView.contentView.bounds.origin
        let selectedRange = textView.selectedRange()

        textView.string = text
        textView.typingAttributes = baseAttributes
        scheduleSyntaxHighlighting(after: .milliseconds(0))

        let length = (text as NSString).length
        let location = min(selectedRange.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(selectedRange.length, length - location)))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let maxScrollY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: scrollOrigin.x, y: min(scrollOrigin.y, maxScrollY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        // Report after AppKit lays out the replacement.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onScrollPositionChange?(self.scrollPosition())
        }
    }

    func breakUndoCoalescing() {
        textView.breakUndoCoalescing()
    }

    private func scheduleSyntaxHighlighting(after delay: DispatchTimeInterval) {
        syntaxHighlightWorkItem?.cancel()
        syntaxHighlightGeneration += 1

        let generation = syntaxHighlightGeneration
        let source = textView.string
        let workItem = DispatchWorkItem { [weak self] in
            let tokens = MarkdownSourceHighlighter().tokens(in: source)

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      generation == self.syntaxHighlightGeneration,
                      source == self.textView.string else {
                    return
                }
                self.applySyntaxHighlighting(tokens: tokens)
            }
        }

        syntaxHighlightWorkItem = workItem
        highlightQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func applySyntaxHighlighting(tokens: [MarkdownSourceToken]) {
        guard let textStorage = textView.textStorage else {
            return
        }

        isApplyingSyntaxHighlighting = true
        defer { isApplyingSyntaxHighlighting = false }

        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        guard fullRange.length > 0 else {
            textView.typingAttributes = baseAttributes
            return
        }

        let selectedRanges = textView.selectedRanges
        let undoWasEnabled = textView.undoManager?.isUndoRegistrationEnabled ?? false
        if undoWasEnabled {
            textView.undoManager?.disableUndoRegistration()
        }
        defer {
            if undoWasEnabled {
                textView.undoManager?.enableUndoRegistration()
            }
        }

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: fullRange)

        for token in tokens {
            let range = NSRange(location: token.location, length: token.length)
            guard NSMaxRange(range) <= fullRange.length else {
                continue
            }
            textStorage.addAttributes(attributes(for: token.kind), range: range)
        }

        textStorage.endEditing()
        restoreSelection(selectedRanges)
        textView.typingAttributes = baseAttributes
    }

    private func restoreSelection(_ selectedRanges: [NSValue]) {
        let fullLength = (textView.string as NSString).length
        let validRanges = selectedRanges.filter { NSMaxRange($0.rangeValue) <= fullLength }
        guard !validRanges.isEmpty else {
            return
        }
        textView.selectedRanges = validRanges
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: editorFont,
            .foregroundColor: NSColor.labelColor
        ]
    }

    private func attributes(for kind: MarkdownSourceTokenKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .headingMarker:
            return [.foregroundColor: NSColor.systemTeal, .font: headingFont]
        case .headingText:
            return [.foregroundColor: NSColor.labelColor, .font: headingFont]
        case .listMarker, .blockQuoteMarker, .emphasisDelimiter, .frontMatterDelimiter, .thematicBreak:
            return [.foregroundColor: NSColor.secondaryLabelColor]
        case .codeFence:
            return [.foregroundColor: NSColor.systemPurple]
        case .codeBlockContent, .inlineCode:
            return [
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.textColor.withAlphaComponent(0.06)
            ]
        case .linkText:
            return [.foregroundColor: NSColor.systemBlue]
        case .linkDestination:
            return [.foregroundColor: NSColor.systemIndigo]
        case .frontMatterContent:
            return [.foregroundColor: NSColor.systemOrange]
        }
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        onScrollPositionChange?(scrollPosition())
    }

    private func scrollPosition() -> MarkdownEditorScrollPosition? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }

        let clipBounds = scrollView.contentView.bounds
        let documentHeight = max(textView.bounds.height, scrollView.documentView?.bounds.height ?? 0)
        let maxScrollY = max(0, documentHeight - clipBounds.height)

        // A pane whose content fits entirely has no scroll state worth
        // mirroring; reporting one would pin the preview.
        guard maxScrollY > 2 else {
            return nil
        }

        let clampedOriginY = min(max(clipBounds.origin.y, 0), maxScrollY)
        let visibleRect = NSRect(
            x: clipBounds.origin.x,
            y: clampedOriginY,
            width: clipBounds.width,
            height: clipBounds.height
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.location != NSNotFound else {
            return nil
        }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        let topLine = lineNumber(forCharacterIndex: characterIndex)

        let scrollFraction = clampedOriginY / maxScrollY
        let isAtBottom = clampedOriginY >= maxScrollY - 2
        return MarkdownEditorScrollPosition(
            topVisibleLine: topLine,
            scrollFraction: scrollFraction,
            isAtBottom: isAtBottom
        )
    }

    // The conversion works in UTF-16 units; mixing in Character counts
    // miscounts lines in documents containing emoji or other multi-unit
    // characters.
    private func lineNumber(forCharacterIndex characterIndex: Int) -> Int {
        let nsString = textView.string as NSString
        let prefixLength = min(characterIndex, nsString.length)
        var line = 1
        var searchIndex = 0
        while searchIndex < prefixLength {
            let searchRange = NSRange(location: searchIndex, length: prefixLength - searchIndex)
            let newline = nsString.range(of: "\n", options: [], range: searchRange)
            guard newline.location != NSNotFound else {
                break
            }
            line += 1
            searchIndex = newline.location + 1
        }
        return line
    }
}
