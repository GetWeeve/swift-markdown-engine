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
//  `copy(_:)` covers every path that copies to the general pasteboard —
//  Cmd+C, the context menu, the Edit menu — because they all send the same
//  action. A drag does not: AppKit serializes the selection onto the drag's own
//  pasteboard through `writeSelection`, which is also how a service reads the
//  selection, so that seam gets the same flavors.
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

    /// AppKit asks per declared type here, so the writer answers the ones it
    /// produces and leaves the rest — `.rtfd`, a file promise — to AppKit.
    override func writeSelection(to pboard: NSPasteboard,
                                 type: NSPasteboard.PasteboardType) -> Bool {
        let sel = selectedRange()
        guard sel.length > 0 else { return super.writeSelection(to: pboard, type: type) }
        let raw = (string as NSString).substring(with: sel)
        let selection = MarkdownPasteboardWriter.Selection(
            markdown: raw, extensions: configuration.extensions
        )
        guard MarkdownPasteboardWriter.place(selection, on: pboard, types: [type]) else {
            return super.writeSelection(to: pboard, type: type)
        }
        return true
    }
}
