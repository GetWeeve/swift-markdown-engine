//
//  MarkdownPasteboardWriterTests.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 11.07.26.
//
//  The web archive must carry OUR html verbatim (deriving it from
//  NSAttributedString(html:) dropped <hr> and checkboxes), and the RTF path
//  substitutes visible stand-ins for what RTF cannot represent. Every text
//  flavor goes through the plain-text renderer, so a construct an extension
//  omits leaves the app on none of them.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Pasteboard writer flavors")
struct MarkdownPasteboardWriterTests {

    @Test("web archive wraps our html verbatim as its main resource")
    func webArchiveCarriesRealHTML() throws {
        let html = "<html><body><p>a</p><hr><li><input type=\"checkbox\" disabled> t</li></body></html>"
        let data = try #require(MarkdownPasteboardWriter.webArchiveData(html: html))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let main = try #require(plist["WebMainResource"] as? [String: Any])
        #expect(main["WebResourceMIMEType"] as? String == "text/html")
        let payload = try #require(main["WebResourceData"] as? Data)
        let roundTripped = try #require(String(data: payload, encoding: .utf8))
        #expect(roundTripped == html)   // <hr> and the checkbox survive untouched
    }

    @Test("rich flavors strip checkbox inputs to plain bullets")
    func stripCheckboxes() {
        let body = "<ul>\n<li><input type=\"checkbox\" disabled> open</li>\n<li><input type=\"checkbox\" checked disabled> done</li>\n</ul>"
        #expect(MarkdownPasteboardWriter.stripTaskCheckboxes(body) == "<ul>\n<li>open</li>\n<li>done</li>\n</ul>")
    }

    @Test("rtf stand-in: hr becomes a 40-char rule")
    func rtfFallbackRule() {
        let rule = String(repeating: "─", count: 40)
        #expect(MarkdownPasteboardWriter.rtfFallbackBody("<p>a</p>\n<hr>\n<p>b</p>")
            == "<p>a</p>\n<p>\(rule)</p>\n<p>b</p>")
    }

    /// A control laid out as an inline box, like Weeve's `[t=…]` citation
    /// marker: no glyphs on screen, and nothing to carry out of the app.
    private struct OmittedExtension: MarkdownExtension {
        var id: String { "omitted" }
        var inline: InlineSyntax? {
            InlineSyntax(open: "[t=", close: "]", parsesContent: false, inlineBoxWidth: 20)
        }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML _: String) -> String { "" }
        func plainText(source _: String, childrenText _: String) -> String { "" }
    }

    @MainActor
    @Test("every flavor of a copy omits an invisible span")
    func flavorsOmitInvisibleSpans() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.markdownengine.tests.copy"))
        MarkdownPasteboardWriter.write(
            markdown: "- shipped the deck [t=1284.3-1291.7]",
            to: pasteboard,
            extensions: [OmittedExtension()]
        )

        #expect(pasteboard.string(forType: .string) == "- shipped the deck")
        #expect(pasteboard.string(forType: MarkdownPasteboardWriter.markdownType) == "- shipped the deck")
        let html = try #require(pasteboard.data(forType: .html).flatMap { String(data: $0, encoding: .utf8) })
        #expect(html.contains("t=1284.3") == false)
    }

    @MainActor
    @Test("markdown with no extension construct in it copies byte-exact")
    func textFlavorsStayVerbatim() {
        let markdown = "- shipped the **deck** [not a marker]"
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.markdownengine.tests.copy.verbatim"))
        MarkdownPasteboardWriter.write(markdown: markdown, to: pasteboard, extensions: [OmittedExtension()])

        #expect(pasteboard.string(forType: .string) == markdown)
        #expect(pasteboard.string(forType: MarkdownPasteboardWriter.markdownType) == markdown)
    }
}
