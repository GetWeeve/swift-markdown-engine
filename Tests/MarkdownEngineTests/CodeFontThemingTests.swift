//
//  CodeFontThemingTests.swift
//  MarkdownEngineTests
//
//  Code typography and background knobs: `CodeBlockStyle.fontName`,
//  `InlineCodeStyle.fontName`, and the `MarkdownEditorTheme.codeBackground`
//  slot. Defaults must keep the syntax-highlighter service's font and
//  background exactly as before.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Code font and background knobs")
struct CodeFontThemingTests {

    private let base: CGFloat = 16
    private var fontName: String { NSFont.systemFont(ofSize: 16).fontName }
    /// A face that ships with macOS and is not the mono default.
    private let customFace = "Menlo-Regular"

    private func style(
        _ text: String, configuration: MarkdownEditorConfiguration = .default
    ) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base, configuration: configuration
        )
    }

    private func font(in attrs: [StyledRange], at pos: Int) -> NSFont? {
        var result: NSFont?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let f = a[.font] as? NSFont { result = f }
        }
        return result
    }

    private func background(in attrs: [StyledRange], at pos: Int) -> NSColor? {
        var result: NSColor?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let c = a[.backgroundColor] as? NSColor { result = c }
        }
        return result
    }

    // MARK: - Fonts

    @Test("nil fontName keeps the service's code font in blocks and inline")
    func defaultsKeepServiceFont() {
        let expected = MarkdownEditorServices.default.syntaxHighlighter
            .codeFont(size: round(base * 0.85))

        let block = style("```\nlet x = 1\n```\n")
        #expect(font(in: block, at: 6)?.fontName == expected.fontName)

        let text = "some `code` here\n"
        let inline = style(text)
        let pos = (text as NSString).range(of: "code").location
        #expect(font(in: inline, at: pos)?.fontName == expected.fontName)
    }

    @Test("codeBlock.fontName swaps the block face; inline follows by default")
    func codeBlockFontNameAppliesToBoth() {
        let config = MarkdownEditorConfiguration(codeBlock: CodeBlockStyle(fontName: customFace))

        let block = style("```\nlet x = 1\n```\n", configuration: config)
        #expect(font(in: block, at: 6)?.fontName == customFace)

        let text = "some `code` here\n"
        let inline = style(text, configuration: config)
        let pos = (text as NSString).range(of: "code").location
        #expect(font(in: inline, at: pos)?.fontName == customFace)
    }

    @Test("inlineCode.fontName overrides inline spans independently")
    func inlineCodeFontNameOverridesInline() {
        let config = MarkdownEditorConfiguration(
            inlineCode: InlineCodeStyle(fontName: customFace)
        )
        let serviceFont = MarkdownEditorServices.default.syntaxHighlighter
            .codeFont(size: round(base * 0.85))

        let text = "some `code` here\n"
        let inline = style(text, configuration: config)
        let pos = (text as NSString).range(of: "code").location
        #expect(font(in: inline, at: pos)?.fontName == customFace)

        // Blocks stay on the service font.
        let block = style("```\nlet x = 1\n```\n", configuration: config)
        #expect(font(in: block, at: 6)?.fontName == serviceFont.fontName)
    }

    @Test("an unresolvable name degrades to the service font")
    func unresolvableNameFallsBack() {
        let config = MarkdownEditorConfiguration(
            codeBlock: CodeBlockStyle(fontName: "NoSuchFace-Regular")
        )
        let expected = MarkdownEditorServices.default.syntaxHighlighter
            .codeFont(size: round(base * 0.85))
        let block = style("```\nlet x = 1\n```\n", configuration: config)
        #expect(font(in: block, at: 6)?.fontName == expected.fontName)
    }

    // MARK: - Background

    @Test("codeBackground slot replaces the service background; nil keeps it")
    func codeBackgroundSlot() {
        #expect(MarkdownEditorTheme.default.codeBackground == nil)

        let serviceBackground = MarkdownEditorServices.default.syntaxHighlighter.backgroundColor()
        let stock = style("```\nlet x = 1\n```\n")
        #expect(background(in: stock, at: 6) == serviceBackground)

        let card = NSColor(calibratedWhite: 0.15, alpha: 1)
        let themed = style(
            "```\nlet x = 1\n```\n",
            configuration: MarkdownEditorConfiguration(theme: MarkdownEditorTheme(codeBackground: card))
        )
        #expect(background(in: themed, at: 6) == card)

        let text = "some `code` here\n"
        let inline = style(
            text,
            configuration: MarkdownEditorConfiguration(theme: MarkdownEditorTheme(codeBackground: card))
        )
        let pos = (text as NSString).range(of: "code").location
        #expect(background(in: inline, at: pos) == card)
    }
}
