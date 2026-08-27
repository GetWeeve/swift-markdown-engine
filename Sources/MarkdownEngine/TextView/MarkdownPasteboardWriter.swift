//
//  MarkdownPasteboardWriter.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 09.07.26.
//
//  Writes a clean, multi-flavor representation of a raw markdown selection to
//  an NSPasteboard. The editor's storage holds RAW markdown styled in place,
//  so a default copy leaks syntax markers and drops thematic breaks. Here we
//  render the raw markdown to clean HTML, write it as web archive + HTML,
//  derive RTF with visible stand-ins for constructs RTF cannot carry, and
//  keep the raw markdown itself as the plain-text flavor — minus whatever an
//  extension gives no plain-text form (`MarkdownPlainTextRenderer`).
//
//  `Selection` derives every flavor in one place, and every path that
//  serializes a selection funnels through it: `copy(_:)`, the context menu,
//  the Edit menu, a drag, a service. A flavor therefore cannot be clean on the
//  Cmd+C path and raw on a pointer-driven one.
//

import AppKit

enum MarkdownPasteboardWriter {
    /// Private flavor carrying the raw markdown of the selection. When one
    /// of our own editors pastes, it prefers this over the derived HTML so wiki
    /// links (`[[Name|UUID]]`), code, and every other construct round-trip
    /// byte-exact instead of being re-derived from the lossy HTML flavor.
    static let markdownType = NSPasteboard.PasteboardType("dev.markdownengine.raw-markdown")

    /// Safari-style web archive, for WebKit-reading consumers.
    static let webArchiveType = NSPasteboard.PasteboardType("com.apple.webarchive")

    /// Every flavor this writer produces, in the order it writes them.
    static let writableTypes: [NSPasteboard.PasteboardType] = [
        .string, markdownType, webArchiveType, .html, .rtf,
    ]

    /// One selection's pasteboard flavors, derived once.
    struct Selection {
        /// Raw markdown minus the constructs an extension gives no plain-text
        /// form. Both text flavors carry this: a construct hidden on screen
        /// must not reappear in a paste, including a paste into our own editor.
        let plainText: String
        /// The `.html` flavor's body: keeps the GFM checkbox markup so markdown
        /// apps (Obsidian etc.) restore `- [ ]` on paste.
        private let htmlBody: String
        /// Rich targets (web archive + RTF) show task items as plain bullets.
        private let richBody: String

        init(markdown: String, extensions: [any MarkdownExtension] = []) {
            plainText = MarkdownPlainTextRenderer.plainText(from: markdown, extensions: extensions)
            htmlBody = MarkdownHTMLRenderer.html(from: markdown, extensions: extensions)
            richBody = stripTaskCheckboxes(htmlBody)
        }

        /// The selection serialized as `type`, or nil for a flavor this writer
        /// does not produce — the caller then leaves that flavor to AppKit.
        @MainActor
        func data(forType type: NSPasteboard.PasteboardType) -> Data? {
            switch type {
            case .string, MarkdownPasteboardWriter.markdownType:
                return Data(plainText.utf8)
            case .html:
                return Data(document(body: htmlBody).utf8)
            case MarkdownPasteboardWriter.webArchiveType:
                // Built straight from OUR html — deriving it from
                // NSAttributedString(html:) silently dropped <hr>.
                return webArchiveData(html: document(body: richBody))
            case .rtf:
                return rtfData()
            default:
                return nil
            }
        }

        /// RTF for consumers without web-archive support. RTF has no horizontal
        /// rule and the HTML importer drops it, so convert a body with a
        /// visible ─ stand-in on the main thread.
        @MainActor
        private func rtfData() -> Data? {
            guard let html = document(body: rtfFallbackBody(richBody)).data(using: .utf8),
                  let attributed = try? NSAttributedString(
                      data: html,
                      options: [
                          .documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue,
                      ],
                      documentAttributes: nil
                  )
            else { return nil }
            return try? attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }

        private func document(body: String) -> String {
            "<html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
        }
    }

    /// Replaces `pasteboard`'s contents with every flavor of `markdown`. For a
    /// copy or a cut, which own the pasteboard outright.
    @MainActor
    static func write(markdown: String, to pasteboard: NSPasteboard,
                      extensions: [any MarkdownExtension] = []) {
        pasteboard.clearContents()
        place(Selection(markdown: markdown, extensions: extensions),
              on: pasteboard, types: writableTypes)
    }

    /// Writes each flavor in `types` this writer produces, and reports whether
    /// it wrote any.
    ///
    /// Does not clear the pasteboard: a drag is handed one whose types AppKit
    /// has already declared, and clearing there would drop the declaration.
    @discardableResult
    @MainActor
    static func place(_ selection: Selection, on pasteboard: NSPasteboard,
                      types: [NSPasteboard.PasteboardType]) -> Bool {
        var wrote = false
        for type in types {
            guard let data = selection.data(forType: type) else { continue }
            pasteboard.setData(data, forType: type)
            wrote = true
        }
        return wrote
    }

    /// Stand-in for what RTF can't carry: the Cocoa HTML importer drops `<hr>`,
    /// so substitute a line of U+2500 (glyphs connect edge-to-edge); 40 chars
    /// reads full-width yet never wraps in ~72-char columns.
    static func rtfFallbackBody(_ body: String) -> String {
        body.replacingOccurrences(of: "<hr>", with: "<p>\(rtfRuleStandIn)</p>")
    }

    /// The visible horizontal-rule stand-in for the RTF flavor.
    static let rtfRuleStandIn = String(repeating: "─", count: 40)

    /// Rich targets show task items as plain bullets: drop the GFM checkbox
    /// inputs the renderer emits (the .html flavor keeps them).
    static func stripTaskCheckboxes(_ body: String) -> String {
        body
            .replacingOccurrences(of: "<input type=\"checkbox\" checked disabled> ", with: "")
            .replacingOccurrences(of: "<input type=\"checkbox\" disabled> ", with: "")
    }

    /// A minimal Safari-style web archive with `html` as its main resource.
    static func webArchiveData(html: String) -> Data? {
        let resource: [String: Any] = [
            "WebResourceData": Data(html.utf8),
            "WebResourceMIMEType": "text/html",
            "WebResourceTextEncodingName": "UTF-8",
            "WebResourceURL": "about:blank",
        ]
        return try? PropertyListSerialization.data(
            fromPropertyList: ["WebMainResource": resource],
            format: .binary,
            options: 0
        )
    }
}
