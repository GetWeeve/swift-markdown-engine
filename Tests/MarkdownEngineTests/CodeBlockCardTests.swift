//
//  CodeBlockCardTests.swift
//  MarkdownEngineTests
//
//  Card rendering for fenced code blocks (`CodeBlockStyle.cornerRadius` +
//  `cardVerticalPadding`) and chip rendering for inline code spans
//  (`InlineCodeStyle.chipCornerRadius`). Both are opt-in; the defaults must
//  keep the historical `.backgroundColor` glyph-run fills exactly.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Code block card and inline code chips")
struct CodeBlockCardTests {

    private let base: CGFloat = 16
    private var fontName: String { NSFont.systemFont(ofSize: 16).fontName }

    private func style(_ text: String, _ config: MarkdownEditorConfiguration = .default,
                       caret: Int = -1) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base,
            caretLocation: caret, configuration: config
        )
    }

    private var cardConfig: MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(
            codeBlock: CodeBlockStyle(cornerRadius: 8, cardVerticalPadding: 16)
        )
    }

    private var chipConfig: MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(
            inlineCode: InlineCodeStyle(chipCornerRadius: 4, chipHorizontalPadding: 3)
        )
    }

    private let fenced = "```swift\nlet x = 1\n```\n"

    // MARK: - Defaults preserved

    @Test("nil cornerRadius keeps the historical background attribute and no card tag")
    func defaultKeepsBackgroundColor() {
        let attrs = style(fenced)
        let codePos = (fenced as NSString).range(of: "let x").location
        let hasBackground = attrs.contains { range, a in
            NSLocationInRange(codePos, range) && a[.backgroundColor] != nil
        }
        let hasCard = attrs.contains { _, a in a[.codeBlockCard] != nil }
        #expect(hasBackground)
        #expect(!hasCard)
    }

    @Test("nil chipCornerRadius keeps the historical inline-code background and no chip tag")
    func defaultKeepsInlineBackground() {
        let text = "some `code` here\n"
        let attrs = style(text)
        let codePos = (text as NSString).range(of: "code").location
        let hasBackground = attrs.contains { range, a in
            NSLocationInRange(codePos, range) && a[.backgroundColor] != nil
        }
        let hasChip = attrs.contains { _, a in a[.inlineCodeChip] != nil }
        #expect(hasBackground)
        #expect(!hasChip)
    }

    // MARK: - Card mode

    @Test("card mode tags the whole block and drops the square background fill")
    func cardModeTagsBlock() {
        let attrs = style(fenced, cardConfig)
        let ns = fenced as NSString
        let codePos = ns.range(of: "let x").location

        var cardRange: NSRange?
        for (range, a) in attrs where a[.codeBlockCard] != nil {
            cardRange = (a[.codeBlockCard] as? NSValue)?.rangeValue
            #expect(NSLocationInRange(codePos, range))
        }
        // The tag carries the block range: opening fence through closing fence.
        #expect(cardRange?.location == 0)
        #expect(cardRange.map { NSMaxRange($0) } == ns.range(of: "```", options: .backwards).length + ns.range(of: "```", options: .backwards).location)

        let hasBackground = attrs.contains { range, a in
            NSLocationInRange(codePos, range) && a[.backgroundColor] != nil
        }
        #expect(!hasBackground)
    }

    @Test("card padding pins the hidden fence lines' height and lifts while the caret reveals them")
    func cardPaddingPinsFenceLines() {
        let ns = fenced as NSString

        // Effective paragraph style on the opening fence (last range wins).
        func fenceStyle(_ attrs: [StyledRange]) -> NSParagraphStyle? {
            var result: NSParagraphStyle?
            for (range, a) in attrs where NSLocationInRange(0, range) {
                if let p = a[.paragraphStyle] as? NSParagraphStyle { result = p }
            }
            return result
        }

        // Hidden fences: pinned to the padding.
        let hidden = fenceStyle(style(fenced, cardConfig))
        #expect(hidden?.minimumLineHeight == 16)
        #expect(hidden?.maximumLineHeight == 16)

        // Caret inside the block: fences reveal at their natural code height.
        let active = fenceStyle(style(fenced, cardConfig, caret: ns.range(of: "let x").location))
        #expect(active != nil)
        #expect(active?.minimumLineHeight != 16)
    }

    // MARK: - Chip mode

    @Test("chip mode tags the span content and drops the square background fill")
    func chipModeTagsSpan() {
        let text = "some `code` here\n"
        let attrs = style(text, chipConfig)
        let ns = text as NSString
        let contentRange = ns.range(of: "code")

        let chip = attrs.first { _, a in (a[.inlineCodeChip] as? Bool) == true }
        #expect(chip?.0 == contentRange)
        let hasBackground = attrs.contains { range, a in
            NSLocationInRange(contentRange.location, range) && a[.backgroundColor] != nil
        }
        #expect(!hasBackground)
    }

    // MARK: - Theme slot

    @Test("inlineCodeBackground defaults to nil and is carried by the theme")
    func inlineCodeBackgroundSlot() {
        #expect(MarkdownEditorTheme.default.inlineCodeBackground == nil)
        let themed = MarkdownEditorTheme(inlineCodeBackground: .systemTeal)
        #expect(themed.inlineCodeBackground == .systemTeal)
    }
}
