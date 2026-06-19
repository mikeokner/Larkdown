import AppKit
import LarkdownCore

final class EditorSplitViewController: NSSplitViewController {
    private let markdownDocument: LarkdownDocument
    private let editorController: MarkdownEditorViewController
    private let previewController = MarkdownPreviewViewController()
    private let renderer = MarkdownRenderer()
    private var renderWorkItem: DispatchWorkItem?
    private var renderGeneration = 0
    private var lastEditorScrollPosition: MarkdownEditorScrollPosition?
    private let renderQueue = DispatchQueue(label: "Larkdown.render", qos: .userInitiated)

    init(document: LarkdownDocument) {
        self.markdownDocument = document
        self.editorController = MarkdownEditorViewController(text: document.text)
        super.init(nibName: nil, bundle: nil)
        editorController.onTextChange = { [weak self] text in
            self?.documentTextDidChange(text)
        }
        editorController.onScrollPositionChange = { [weak self] position in
            self?.lastEditorScrollPosition = position
            if let position {
                self?.previewController.scroll(to: position)
            }
        }
        editorController.undoManagerProvider = { [weak document] in
            document?.undoManager
        }
        document.onTextReplaced = { [weak self] in
            guard let self else {
                return
            }
            self.editorController.replaceText(with: self.markdownDocument.text)
            self.scheduleRender(immediate: true)
        }
        document.onFileURLChanged = { [weak self] in
            self?.scheduleRender(immediate: true)
        }
        document.onWillSave = { [weak self] in
            self?.editorController.breakUndoCoalescing()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let editorItem = NSSplitViewItem(viewController: editorController)
        editorItem.minimumThickness = 300
        editorItem.preferredThicknessFraction = 0.5

        let previewItem = NSSplitViewItem(viewController: previewController)
        previewItem.minimumThickness = 300

        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)
        scheduleRender(immediate: true)
    }

    private func documentTextDidChange(_ text: String) {
        guard markdownDocument.text != text else {
            return
        }

        markdownDocument.text = text
        scheduleRender(immediate: false)
    }

    private func scheduleRender(immediate: Bool) {
        renderWorkItem?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        let source = markdownDocument.text
        let baseURL = markdownDocument.fileURL.map(PreviewResource.baseURL(forDocumentAt:))

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            let rendered = renderer.render(source: source)

            DispatchQueue.main.async { [weak self] in
                guard let self, !self.markdownDocument.isClosed, generation == self.renderGeneration else {
                    return
                }

                if immediate {
                    self.previewController.load(
                        rendered: rendered,
                        baseURL: baseURL,
                        restoring: self.lastEditorScrollPosition
                    )
                } else {
                    self.previewController.update(
                        rendered: rendered,
                        baseURL: baseURL,
                        restoring: self.lastEditorScrollPosition
                    )
                }
            }
        }

        renderWorkItem = workItem
        let deadline: DispatchTime = immediate ? .now() : .now() + .milliseconds(150)
        renderQueue.asyncAfter(deadline: deadline, execute: workItem)
    }

    deinit { renderWorkItem?.cancel() }
}
