//
//  NativeTextView+Copy.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 09.07.26.
//
//  Copy override. The storage holds RAW markdown styled in place, so the
//  default copy serializes junk (leaked syntax markers, raw caret line,
//  missing thematic breaks). Instead we hand the selected raw markdown to
//  `MarkdownPasteboardWriter`, which renders a clean HTML/RTF/web-archive set
//  and keeps the raw markdown as the plain-text flavor.
//
//  A drag is the copy path that does not pass through here: it writes the
//  selection to its own pasteboard, never to `NSPasteboard.general`. The
//  `writeSelection` override below is the seam it shares with the services
//  menu, and it gives the text flavor the same treatment a copy gets.
//

import AppKit

extension NativeTextView {
    override func copy(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length > 0 else {
            super.copy(sender)
            return
        }
        let raw = (string as NSString).substring(with: sel)
        MarkdownPasteboardWriter.write(markdown: raw, to: .general, extensions: configuration.extensions)
    }

    /// Only the text flavor is ours to correct here; the rest of what a drag
    /// carries stays AppKit's own serialization of the selection, RTFD
    /// attachments included.
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string, let text = exportedSelectionText() else {
            return super.writeSelection(to: pboard, type: type)
        }
        return pboard.setString(text, forType: .string)
    }

    /// The selected raw markdown as it may leave the app, or nil when there is
    /// no selection to write.
    ///
    /// The text flavor is written from the storage either way rather than only
    /// when a construct needs omitting: storage is the raw markdown, so this is
    /// what AppKit would serialize anyway, and one path is easier to trust than
    /// two.
    private func exportedSelectionText() -> String? {
        let selection = selectedRange()
        guard selection.length > 0 else { return nil }
        let raw = (string as NSString).substring(with: selection)
        return MarkdownPlainTextRenderer.plainText(from: raw, extensions: configuration.extensions)
    }
}
