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
//  Cut needs nothing of its own: AppKit's `cut(_:)` copies through this
//  override and then deletes.
//
//  A drag is the copy path that does not pass through here: it writes the
//  selection to its own pasteboard, never to `NSPasteboard.general`, and it
//  asks for one type at a time. The `writeSelection` override below is the
//  seam it shares with the services menu, and it hands every flavor we derive
//  to the same writer a copy uses.
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

    /// A selection dragged out, or taken by a service, is serialized here. A
    /// text view offers plain text and RTF (and RTFD when the selection
    /// carries an attachment), and AppKit would derive all of them from the
    /// storage — which is styled RAW markdown, so both the syntax markers and
    /// the constructs an extension omits would ride out with it. Every flavor
    /// the writer derives is therefore ours; RTFD stays AppKit's, which is
    /// what keeps a dragged image an image.
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        let selection = selectedRange()
        guard selection.length > 0 else {
            return super.writeSelection(to: pboard, type: type)
        }
        let raw = (string as NSString).substring(with: selection)
        if MarkdownPasteboardWriter.write(markdown: raw, forType: type, to: pboard,
                                          extensions: configuration.extensions) {
            return true
        }
        return super.writeSelection(to: pboard, type: type)
    }
}
