//
//  PlainTextCopyTests.swift
//  MarkdownEngineTests
//
//  The `.string` flavor of a copy is RAW markdown, so a construct that renders
//  as something other than its own characters — a box-laid-out control — used
//  to carry its source syntax out of the app. `MarkdownExtension.plainText`
//  gives the extension the same say over plain text that `html` gives it over
//  HTML, and every path that serializes a selection (copy override, context
//  menu, Edit menu, drag, services) goes through one funnel so a flavor cannot
//  be clean on one path and raw on another.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Plain-text copy")
@MainActor
struct PlainTextCopyTests {

    /// A control laid out as a box: no glyphs of its own, so no plain text.
    private struct BoxExtension: MarkdownExtension {
        var id: String { "box" }
        var inline: InlineSyntax? {
            InlineSyntax(open: "[t=", close: "]", parsesContent: false, inlineBoxWidth: 20)
        }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML _: String) -> String { "" }
        func plainText(content _: String) -> String? { "" }
    }

    /// Same syntax, no opinion about plain text: the default keeps the source.
    private struct SilentExtension: MarkdownExtension {
        var id: String { "silent" }
        var inline: InlineSyntax? {
            InlineSyntax(open: "[t=", close: "]", parsesContent: false)
        }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML _: String) -> String { "" }
    }

    /// Keeps its content, drops its markers — the other useful answer.
    private struct UnwrappingExtension: MarkdownExtension {
        var id: String { "highlight" }
        var inline: InlineSyntax? { InlineSyntax(open: "==", close: "==") }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML: String) -> String { "<mark>\(childrenHTML)</mark>" }
        func plainText(content: String) -> String? { content }
    }

    private func pasteboard(_ name: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.markdownengine.tests.\(name)"))
        pasteboard.clearContents()
        return pasteboard
    }

    // MARK: - The renderer

    @Test("an extension with no plain-text form drops its whole construct")
    func dropsConstruct() {
        let text = "- Discussed the budget[t=1284.3-1291.7]\n- Next step[t=1300.0-1305.0]"
        #expect(MarkdownPlainTextRenderer.plainText(from: text, extensions: [BoxExtension()])
            == "- Discussed the budget\n- Next step")
    }

    @Test("the default keeps the construct exactly as written")
    func defaultKeepsSource() {
        let text = "- Discussed the budget[t=1284.3-1291.7]"
        #expect(MarkdownPlainTextRenderer.plainText(from: text, extensions: [SilentExtension()]) == text)
        #expect(MarkdownPlainTextRenderer.plainText(from: text) == text)
    }

    @Test("an extension can keep its content and drop its markers")
    func unwrapsContent() {
        #expect(MarkdownPlainTextRenderer.plainText(from: "a ==b== c", extensions: [UnwrappingExtension()])
            == "a b c")
    }

    @Test("markers are dropped in every block a span can appear in")
    func dropsAcrossBlocks() {
        let text = """
        # Heading[t=1.0-2.0]

        A paragraph[t=3.0-4.0] with more after it.

        > Quoted[t=5.0-6.0]

        | a[t=7.0-8.0] | b |
        | --- | --- |
        | c | d |
        """
        let stripped = MarkdownPlainTextRenderer.plainText(from: text, extensions: [BoxExtension()])
        #expect(stripped.contains("[t=") == false)
        #expect(stripped.contains("# Heading"))
        #expect(stripped.contains("A paragraph with more after it."))
        #expect(stripped.contains("> Quoted"))
    }

    @Test("a fenced code block keeps its literal source")
    func codeBlockIsLiteral() {
        let text = "```\nlet marker = \"[t=1.0-2.0]\"\n```"
        #expect(MarkdownPlainTextRenderer.plainText(from: text, extensions: [BoxExtension()]) == text)
    }

    @Test("text without a construct comes back identical")
    func untouchedText() {
        let text = "- Just a bullet\n- And another"
        #expect(MarkdownPlainTextRenderer.plainText(from: text, extensions: [BoxExtension()]) == text)
        #expect(MarkdownPlainTextRenderer.plainText(from: "", extensions: [BoxExtension()]) == "")
    }

    // MARK: - The pasteboard flavors

    @Test("copy strips the marker from both text flavors")
    func copyStripsTextFlavors() {
        let board = pasteboard("copy")
        MarkdownPasteboardWriter.write(
            markdown: "- Discussed the budget[t=1284.3-1291.7]",
            to: board,
            extensions: [BoxExtension()]
        )
        #expect(board.string(forType: .string) == "- Discussed the budget")
        #expect(board.string(forType: MarkdownPasteboardWriter.markdownType) == "- Discussed the budget")
    }

    @Test("html, rtf and web archive stay clean")
    func richFlavorsStayClean() throws {
        let board = pasteboard("rich")
        MarkdownPasteboardWriter.write(
            markdown: "- Discussed the budget[t=1284.3-1291.7]",
            to: board,
            extensions: [BoxExtension()]
        )
        let html = try #require(board.string(forType: .html))
        #expect(html.contains("[t=") == false)
        #expect(html.contains("Discussed the budget"))

        let rtf = try #require(board.data(forType: .rtf))
        let attributed = try #require(NSAttributedString(rtf: rtf, documentAttributes: nil))
        #expect(attributed.string.contains("[t=") == false)

        let archive = try #require(board.data(forType: MarkdownPasteboardWriter.webArchiveType))
        #expect(String(decoding: archive, as: UTF8.self).contains("[t=") == false)
    }

    @Test("a flavor the writer does not produce yields no data")
    func unknownFlavor() {
        let selection = MarkdownPasteboardWriter.Selection(
            markdown: "- Discussed the budget[t=1284.3-1291.7]",
            extensions: [BoxExtension()]
        )
        #expect(selection.data(forType: .tabularText) == nil)
    }

    // MARK: - The drag path

    @Test("a drag writes the stripped selection to the drag's own pasteboard")
    func dragStripsMarker() {
        _ = NSApplication.shared
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configuration.extensions = [BoxExtension()]
        textView.string = "- Discussed the budget[t=1284.3-1291.7]"
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))

        let board = pasteboard("drag")
        board.declareTypes([.string, .rtf], owner: nil)
        // The plural form is what AppKit's selection drag calls.
        #expect(textView.writeSelection(to: board, types: [.string, .rtf]))
        #expect(board.string(forType: .string) == "- Discussed the budget")
    }

    @Test("a drag of an empty selection is left to AppKit")
    func dragWithoutSelection() {
        _ = NSApplication.shared
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configuration.extensions = [BoxExtension()]
        textView.string = "- Discussed the budget[t=1284.3-1291.7]"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let board = pasteboard("drag-empty")
        board.declareTypes([.string], owner: nil)
        _ = textView.writeSelection(to: board, types: [.string])
        #expect(board.string(forType: .string)?.contains("Discussed") != true)
    }
}
