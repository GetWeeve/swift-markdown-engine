//
//  HeadingMetricsTests.swift
//  MarkdownEngineTests
//
//  Heading metric knobs: `HeadingStyle.lineHeights` (fixed per-level line
//  heights, empty = derived from font metrics as before) and
//  `HeadingStyle.paragraphSpacing` (below-heading spacing, nil = the base
//  paragraph spacing as before).
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Heading metric knobs")
struct HeadingMetricsTests {

    private let base: CGFloat = 16
    private var fontName: String { NSFont.systemFont(ofSize: 16).fontName }

    private func headingParagraphStyle(
        _ text: String, headings: HeadingStyle = .default
    ) -> NSParagraphStyle? {
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base,
            configuration: MarkdownEditorConfiguration(headings: headings)
        )
        var result: NSParagraphStyle?
        for (range, a) in attrs where NSLocationInRange(0, range) {
            if let p = a[.paragraphStyle] as? NSParagraphStyle { result = p }
        }
        return result
    }

    @Test("empty lineHeights keeps the metric-derived height")
    func defaultsDeriveFromFontMetrics() {
        #expect(HeadingStyle.default.lineHeights.isEmpty)
        #expect(HeadingStyle.default.paragraphSpacing == nil)

        // Reproduce the styler's stock heading font: base face + bold trait.
        let plain = NSFont(name: fontName, size: base * 2) ?? .systemFont(ofSize: base * 2)
        let merged = plain.fontDescriptor.symbolicTraits.union(.bold)
        let font = NSFont(descriptor: plain.fontDescriptor.withSymbolicTraits(merged), size: base * 2) ?? plain
        let derived = ceil(font.ascender - font.descender + font.leading) + 1
        let ps = headingParagraphStyle("# Title\n")
        #expect(abs((ps?.minimumLineHeight ?? 0) - derived) < 0.01)
        #expect(ps?.minimumLineHeight == ps?.maximumLineHeight)
    }

    @Test("lineHeights pins a fixed grid per level, reusing the last entry")
    func lineHeightsPinAFixedGrid() {
        let grid = HeadingStyle(lineHeights: [48, 44, 40])
        let h1 = headingParagraphStyle("# Title\n", headings: grid)
        #expect(h1?.minimumLineHeight == 48)
        #expect(h1?.maximumLineHeight == 48)

        let h2 = headingParagraphStyle("## Title\n", headings: grid)
        #expect(h2?.minimumLineHeight == 44)

        // Levels past the array reuse the last entry (fontMultipliers pattern).
        let h5 = headingParagraphStyle("##### Title\n", headings: grid)
        #expect(h5?.minimumLineHeight == 40)
    }

    @Test("paragraphSpacing overrides the below-heading gap; nil keeps base")
    func paragraphSpacingOverridesBelowHeadingGap() {
        // Default: base paragraph spacing = ceil(baseLineHeight × 0.3).
        let baseFont = NSFont(name: fontName, size: base) ?? .systemFont(ofSize: base)
        let baseLineHeight = ceil(baseFont.ascender - baseFont.descender + baseFont.leading)
        let expectedBase = ceil(baseLineHeight * ParagraphStyle.default.spacingFactor)
        let stock = headingParagraphStyle("# Title\n")
        #expect(abs((stock?.paragraphSpacing ?? 0) - expectedBase) < 0.01)

        let tight = headingParagraphStyle("# Title\n", headings: HeadingStyle(paragraphSpacing: 4))
        #expect(tight?.paragraphSpacing == 4)
    }
}
