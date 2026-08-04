//
//  BlockquoteStylingTests.swift
//  MarkdownEngineTests
//
//  Blockquote styling knobs: the bar/indent metrics
//  (`BlockquoteStyle.barWidth` / `textIndent`) and the theme slots
//  (`blockquoteBar`, `blockquoteText`). Defaults must reproduce the previous
//  hard-coded constants (3pt bar, 18pt indent, muted content) exactly.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Blockquote styling knobs")
struct BlockquoteStylingTests {

    private let base: CGFloat = 16
    private var fontName: String { NSFont.systemFont(ofSize: 16).fontName }

    private func style(
        _ text: String,
        theme: MarkdownEditorTheme = .default,
        blockquote: BlockquoteStyle = .default,
        caret: Int = -1
    ) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base, caretLocation: caret,
            configuration: MarkdownEditorConfiguration(theme: theme, blockquote: blockquote)
        )
    }

    private func paragraphStyle(in attrs: [StyledRange], at pos: Int) -> NSParagraphStyle? {
        var result: NSParagraphStyle?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let p = a[.paragraphStyle] as? NSParagraphStyle { result = p }
        }
        return result
    }

    private func color(in attrs: [StyledRange], at pos: Int) -> NSColor? {
        var result: NSColor?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let c = a[.foregroundColor] as? NSColor { result = c }
        }
        return result
    }

    // MARK: - Metrics

    @Test("defaults reproduce the previous hard-coded constants")
    func defaultsMatchHistoricalConstants() {
        #expect(BlockquoteStyle.default.barWidth == 3)
        #expect(BlockquoteStyle.default.textIndent == 18)

        // Level 1 text hangs at 1 × 18 + 9 = 27pt, exactly as before.
        let attrs = style("> quoted line\n")
        let ps = paragraphStyle(in: attrs, at: 2)
        #expect(abs((ps?.firstLineHeadIndent ?? 0) - 27) < 0.01)
        #expect(abs((ps?.headIndent ?? 0) - 27) < 0.01)
    }

    @Test("textIndent drives the hanging indent per nesting level")
    func textIndentDrivesHangingIndent() {
        let narrow = BlockquoteStyle(textIndent: 12)
        let single = style("> quoted line\n", blockquote: narrow)
        let ps1 = paragraphStyle(in: single, at: 2)
        #expect(abs((ps1?.firstLineHeadIndent ?? 0) - (12 + 6)) < 0.01)

        let nested = style(">> deep quote\n", blockquote: narrow)
        let ps2 = paragraphStyle(in: nested, at: 3)
        #expect(abs((ps2?.firstLineHeadIndent ?? 0) - (24 + 6)) < 0.01)
    }

    // MARK: - Theme slots

    @Test("blockquoteText lifts the historical muting; nil keeps it")
    func blockquoteTextSlot() {
        let text = "> quoted line\n"
        let contentPos = (text as NSString).range(of: "quoted").location

        let muted = style(text)
        #expect(color(in: muted, at: contentPos) == MarkdownEditorTheme.default.mutedText)

        let bodyInk = NSColor(calibratedWhite: 0.9, alpha: 1)
        let restyled = style(text, theme: MarkdownEditorTheme(blockquoteText: bodyInk))
        #expect(color(in: restyled, at: contentPos) == bodyInk)
    }

    @Test("the revealed > marker stays muted even with a custom content ink")
    func revealedMarkerStaysMuted() {
        let text = "> quoted line\n"
        let bodyInk = NSColor(calibratedWhite: 0.9, alpha: 1)
        // Caret on the line reveals the marker.
        let attrs = style(text, theme: MarkdownEditorTheme(blockquoteText: bodyInk), caret: 3)
        #expect(color(in: attrs, at: 0) == MarkdownEditorTheme.default.mutedText)
    }

    @Test("bar theme slot defaults to nil and carries a custom ink")
    func blockquoteBarSlot() {
        #expect(MarkdownEditorTheme.default.blockquoteBar == nil)
        let brand = NSColor(calibratedRed: 1, green: 0.8, blue: 0.81, alpha: 1)
        #expect(MarkdownEditorTheme(blockquoteBar: brand).blockquoteBar == brand)
    }
}
