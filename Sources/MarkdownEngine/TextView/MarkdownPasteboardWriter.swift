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
//  keep the raw markdown itself as the plain-text flavor.
//
//  Every flavor is derived from the same pass, and the text ones run through
//  `MarkdownPlainTextRenderer`, so a construct an extension omits from plain
//  text reaches the pasteboard on no flavor at all.
//
//  Two callers, two shapes: `copy(_:)` hands over a pasteboard of its own and
//  takes the whole set, while a drag and the services menu ask for the
//  selection one type at a time — `write(markdown:forType:to:extensions:)`.
//

import AppKit

enum MarkdownPasteboardWriter {
    /// Private flavor carrying the raw markdown of the selection. When one of
    /// our own editors pastes, it prefers this over the derived HTML so wiki
    /// links (`[[Name|UUID]]`), code, and every other construct round-trip
    /// byte-exact instead of being re-derived from the lossy HTML flavor.
    static let markdownType = NSPasteboard.PasteboardType("dev.markdownengine.raw-markdown")

    /// Safari's flavor, which has no AppKit constant.
    static let webArchiveType = NSPasteboard.PasteboardType("com.apple.webarchive")

    /// What a text view still calls plain text and RTF in
    /// `writablePasteboardTypes` — the list a drag and the services menu ask
    /// from, one type at a time. These are NOT equal to `.string` and `.rtf`,
    /// so a writer that matched only the UTIs would hand every real drag
    /// straight back to AppKit.
    static let legacyStringType = NSPasteboard.PasteboardType("NSStringPboardType")
    static let legacyRTFType = NSPasteboard.PasteboardType("NeXT Rich Text Format v1.0 pasteboard type")

    /// Every flavor this writer derives from one selection, rendered together:
    /// a caller that wants several does not pay for the HTML render and the
    /// RTF conversion once per flavor.
    struct Flavors {
        /// The plain-text flavor, and the private raw-markdown one.
        let text: String
        let html: Data
        let webArchive: Data?
        let rtf: Data?
    }

    @MainActor
    static func write(markdown: String, to pasteboard: NSPasteboard,
                      extensions: [any MarkdownExtension] = []) {
        let flavors = flavors(markdown: markdown, extensions: extensions)
        pasteboard.clearContents()

        // The raw markdown as plain text, and under our private flavor so our
        // own paste path can round-trip it.
        pasteboard.setString(flavors.text, forType: .string)
        pasteboard.setString(flavors.text, forType: Self.markdownType)

        // Web archive built straight from OUR html — deriving it from
        // NSAttributedString(html:) silently dropped <hr>, so WebKit-reading
        // consumers get the real document instead.
        if let webArchive = flavors.webArchive {
            pasteboard.setData(webArchive, forType: Self.webArchiveType)
        }
        pasteboard.setData(flavors.html, forType: .html)
        if let rtf = flavors.rtf {
            pasteboard.setData(rtf, forType: .rtf)
        }
    }

    /// Writes one flavor onto a pasteboard the caller owns and has already
    /// declared types on, for the paths that ask for the selection a type at a
    /// time: a drag, and the services menu.
    ///
    /// False means this writer has no flavor of its own for `type` — the
    /// caller's cue to let AppKit serialize that one. RTFD is the type that
    /// matters there: a text view offers it only when the selection carries an
    /// attachment, and AppKit's own serialization is what keeps a dragged
    /// image an image.
    @MainActor
    static func write(markdown: String, forType type: NSPasteboard.PasteboardType,
                      to pasteboard: NSPasteboard, extensions: [any MarkdownExtension] = []) -> Bool {
        guard let flavor = flavor(for: type) else { return false }
        // Written back under the type the caller asked for, whichever spelling
        // that was: the pasteboard was declared with that one.
        let flavors = flavors(markdown: markdown, extensions: extensions)
        switch flavor {
        case .text:
            return pasteboard.setString(flavors.text, forType: type)
        case .html:
            return pasteboard.setData(flavors.html, forType: type)
        case .webArchive:
            return flavors.webArchive.map { pasteboard.setData($0, forType: type) } ?? false
        case .rtf:
            return flavors.rtf.map { pasteboard.setData($0, forType: type) } ?? false
        }
    }

    /// One of the flavors this writer renders.
    enum Flavor: Equatable {
        case text
        case html
        case webArchive
        case rtf
    }

    /// Which flavor a pasteboard type asks for, or nil when this writer
    /// derives none — RTFD, which a text view offers only for a selection
    /// carrying an attachment and which AppKit serializes better than we
    /// could. Both the UTI and the legacy name map here.
    static func flavor(for type: NSPasteboard.PasteboardType) -> Flavor? {
        switch type {
        case .string, Self.markdownType, Self.legacyStringType: .text
        case .html: .html
        case Self.webArchiveType: .webArchive
        case .rtf, Self.legacyRTFType: .rtf
        default: nil
        }
    }

    /// Renders the selection once into every flavor.
    @MainActor
    static func flavors(markdown: String, extensions: [any MarkdownExtension] = []) -> Flavors {
        // Plain text keeps the raw markdown, minus the constructs their
        // extensions omit from it. Markdown outside such a construct is
        // untouched, so the private flavor still round-trips byte-exact.
        let text = MarkdownPlainTextRenderer.plainText(from: markdown, extensions: extensions)

        // Render the selection to clean HTML.
        let htmlBody = MarkdownHTMLRenderer.html(from: markdown, extensions: extensions)
        // Rich targets (web archive + RTF) show task items as plain bullets
        // (user's call); the .html flavour keeps the GFM checkbox markup so
        // markdown apps (Obsidian etc.) restore `- [ ]` on paste.
        let richBody = stripTaskCheckboxes(htmlBody)
        let fullHTML = "<html><head><meta charset=\"utf-8\"></head><body>\(htmlBody)</body></html>"
        let richHTML = "<html><head><meta charset=\"utf-8\"></head><body>\(richBody)</body></html>"

        return Flavors(
            text: text,
            html: Data(fullHTML.utf8),
            webArchive: webArchiveData(html: richHTML),
            rtf: rtfData(body: rtfFallbackBody(richBody))
        )
    }

    /// RTF for consumers without web-archive support — which is what a drag
    /// into a rich-text app takes. RTF has no horizontal rule and the HTML
    /// importer drops it, so the body arrives with a visible ─ stand-in, and
    /// the conversion runs on the main thread.
    @MainActor
    private static func rtfData(body: String) -> Data? {
        let html = "<html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
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
