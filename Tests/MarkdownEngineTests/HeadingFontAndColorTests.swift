//
//  HeadingFontAndColorTests.swift
//  MarkdownEngineTests
//
//  The two opt-in heading knobs: `HeadingStyle.fontName` (a dedicated heading
//  typeface) and `MarkdownEditorTheme.headingText` (a dedicated heading text
//  color). Both default to nil, which must keep the stock styling unchanged —
//  headings derive from the base font with the bold trait and inherit the
//  view-level bodyText foreground.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Heading font & color knobs")
struct HeadingFontAndColorTests {

    private let base: CGFloat = 14
    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }

    /// A real, always-installed face that differs from the system font in both
    /// family and weight, so assertions can see it was used verbatim.
    private let headingFace = "Menlo-Regular"

    /// Effective font at `pos`: the last styled range covering it that sets `.font`.
    private func font(in attrs: [StyledRange], at pos: Int) -> NSFont? {
        var result: NSFont?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let f = a[.font] as? NSFont { result = f }
        }
        return result
    }

    /// Effective color at `pos`: the last styled range covering it that sets `.foregroundColor`.
    private func color(in attrs: [StyledRange], at pos: Int) -> NSColor? {
        var result: NSColor?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let c = a[.foregroundColor] as? NSColor { result = c }
        }
        return result
    }

    private func style(
        _ text: String,
        configuration: MarkdownEditorConfiguration = .default
    ) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base, configuration: configuration
        )
    }

    // MARK: - HeadingStyle.fontName

    @Test("headings.fontName renders headings in that face at the multiplied size")
    func headingFontNameUsedVerbatimAtMultipliedSize() {
        let config = MarkdownEditorConfiguration(headings: HeadingStyle(fontName: headingFace))
        // "# One\n\nbody\n\n## Two": O=2, b=7, T=16
        let attrs = style("# One\n\nbody\n\n## Two", configuration: config)

        let h1 = font(in: attrs, at: 2)
        #expect(h1?.fontName == headingFace)
        #expect(h1?.pointSize == base * 2.0)
        // The face is honored exactly: no synthetic bold on the chosen weight.
        #expect(h1?.fontDescriptor.symbolicTraits.contains(.bold) == false)

        // Per-level multipliers still apply to the custom face.
        let h2 = font(in: attrs, at: 16)
        #expect(h2?.fontName == headingFace)
        #expect(h2?.pointSize == base * 1.5)

        // Body text never takes the heading face (no .font range at all).
        #expect(font(in: attrs, at: 7) == nil)
    }

    @Test("emphasis inside a custom-face heading keeps family and size, adds traits")
    func emphasisComposesOnTheCustomHeadingFace() {
        let config = MarkdownEditorConfiguration(headings: HeadingStyle(fontName: headingFace))
        // "# **n*o*des**": n=4, o=6, d=8
        let attrs = style("# **n*o*des**", configuration: config)
        let n = font(in: attrs, at: 4)
        let o = font(in: attrs, at: 6)
        let d = font(in: attrs, at: 8)

        #expect(n?.familyName == "Menlo")
        #expect(o?.familyName == "Menlo")
        #expect(d?.familyName == "Menlo")
        #expect(n?.pointSize == base * 2.0)
        #expect(o?.pointSize == base * 2.0)
        #expect(d?.pointSize == base * 2.0)
        #expect(n?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(o?.fontDescriptor.symbolicTraits.contains([.bold, .italic]) == true)
        #expect(d?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("an unresolvable fontName falls back to the stock heading font")
    func unresolvableFontNameFallsBack() {
        let config = MarkdownEditorConfiguration(
            headings: HeadingStyle(fontName: "Not-A-Real-Font-Face")
        )
        let stock = font(in: style("# Title"), at: 2)
        let fallback = font(in: style("# Title", configuration: config), at: 2)
        #expect(fallback == stock)
        #expect(fallback?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    // MARK: - MarkdownEditorTheme.headingText

    @Test("theme.headingText colors heading text; # markers and body keep their own ink")
    func headingTextColorsContentOnly() {
        var theme = MarkdownEditorTheme.default
        theme.headingText = .systemPink
        let config = MarkdownEditorConfiguration(theme: theme)
        // "# Title\n\nbody": marker=0..1, T=2, b=8
        let attrs = style("# Title\n\nbody", configuration: config)

        #expect(color(in: attrs, at: 2) == .systemPink)
        // The `#` marker glyphs stay on headingMarker (the separate knob).
        #expect(color(in: attrs, at: 0) == theme.headingMarker)
        // Body text still inherits the view-level bodyText (no styled foreground).
        #expect(color(in: attrs, at: 8) == nil)
    }

    @Test("a link inside a colored heading keeps the link ink")
    func linkInsideColoredHeadingKeepsLinkColor() {
        var theme = MarkdownEditorTheme.default
        theme.headingText = .systemPink
        let config = MarkdownEditorConfiguration(theme: theme)
        // "# [x](https://e.com)": x=3
        let attrs = style("# [x](https://e.com)", configuration: config)
        #expect(color(in: attrs, at: 3) == theme.link)
    }

    @Test("emphasis inside a colored heading keeps the heading color")
    func emphasisInsideColoredHeadingKeepsHeadingColor() {
        var theme = MarkdownEditorTheme.default
        theme.headingText = .systemPink
        let config = MarkdownEditorConfiguration(theme: theme)
        // "# **bold**": b=4 — emphasis composes fonts only, so the ink survives.
        let attrs = style("# **bold**", configuration: config)
        #expect(color(in: attrs, at: 4) == .systemPink)
    }

    // MARK: - Defaults stay byte-identical

    @Test("nil knobs: heading content carries the stock font and no foreground")
    func nilKnobsKeepStockHeadingAttributes() {
        // "# Title": T=2
        let attrs = style("# Title")
        let heading = font(in: attrs, at: 2)
        let stock = NSFont(name: fontName, size: base * 2.0) ?? .systemFont(ofSize: base * 2.0)
        let stockBold = NSFont(
            descriptor: stock.fontDescriptor.withSymbolicTraits(
                stock.fontDescriptor.symbolicTraits.union(.bold)),
            size: stock.pointSize
        ) ?? stock
        #expect(heading == stockBold)
        // No styled range sets a heading foreground — bodyText inheritance.
        #expect(color(in: attrs, at: 2) == nil)
    }

    @Test("explicit-nil knobs produce value-identical styling to .default")
    func nilKnobsMatchDefaultsExactly() {
        let doc = "# One **bold** *i*\n\nbody `code`\n\n## Two\n\n- item\n\n> quote\n"
        let expected = style(doc)
        let explicitNil = MarkdownEditorConfiguration(
            theme: MarkdownEditorTheme(headingText: nil),
            headings: HeadingStyle(fontName: nil)
        )
        let actual = style(doc, configuration: explicitNil)

        #expect(actual.count == expected.count)
        for (a, e) in zip(actual, expected) {
            #expect(a.range == e.range)
            #expect((a.attributes as NSDictionary).isEqual(to: e.attributes))
        }
    }
}
