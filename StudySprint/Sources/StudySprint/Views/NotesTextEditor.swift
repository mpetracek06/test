import AppKit
import SwiftUI
import StudySprintCore

/// The notes box. Like a plain text editor, except that pasting or dropping content that
/// contains pictures keeps the pictures (they go to the picture strip) as well as the text.
struct NotesTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onPictures: ([NoteAttachment]) -> Void
    var onFiles: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PastingTextView(frame: .zero)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.delegate = context.coordinator
        textView.onPictures = { pictures in context.coordinator.parent.onPictures(pictures) }
        textView.onFiles = { urls in context.coordinator.parent.onFiles(urls) }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextEditor
        init(_ parent: NotesTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

final class PastingTextView: NSTextView {
    var onPictures: (([NoteAttachment]) -> Void)?
    var onFiles: (([URL]) -> Void)?

    override func paste(_ sender: Any?) {
        if takeContent(from: .general) { return }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if takeContent(from: sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }

    /// Returns true when it handled the content itself.
    private func takeContent(from pb: NSPasteboard) -> Bool {
        // Files (copied in Finder or dragged in): import them like "Import files…".
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            onFiles?(urls)
            return true
        }
        let pictures = NotesImporter.pictures(from: pb)
        guard !pictures.isEmpty else { return false }
        onPictures?(pictures)
        if let text = pb.string(forType: .string), !text.isEmpty {
            insertText(text, replacementRange: selectedRange())
        }
        return true
    }
}
