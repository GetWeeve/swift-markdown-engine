//
//  ListIndentGridTests.swift
//  MarkdownEngineTests
//
//  The opt-in list indent grid (`ListStyle.markerTextGap`): markers on a
//  deterministic depth × indentPerLevel grid with level 1 on the body origin,
//  the raw source whitespace neutralized, and content hanging a fixed slot
//  after the marker. `nil` (the default) must keep the historical geometry
//  bit-for-bit.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("List indent grid (ListStyle.markerTextGap)")
struct ListIndentGridTests {

    private let base: CGFloat = 16
    private var fontName: String { NSFont.systemFont(ofSize: 16).fontName }
    private var baseFont: NSFont { NSFont.systemFont(ofSize: 16) }

    private func gridConfig(gap: CGFloat = 36, indent: CGFloat = 24) -> MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(lists: ListStyle(indentPerLevel: indent, markerTextGap: gap))
    }

    private func style(_ text: String, _ config: MarkdownEditorConfiguration = .default) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(text: text, fontName: fontName, fontSize: base, configuration: config)
    }

    /// Effective paragraph style at `pos` (last styled range wins).
    private func paragraphStyle(in attrs: [StyledRange], at pos: Int) -> NSParagraphStyle? {
        var result: NSParagraphStyle?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let p = a[.paragraphStyle] as? NSParagraphStyle { result = p }
        }
        return result
    }

    /// Effective kern at `pos`, if any styled range sets one.
    private func kern(in attrs: [StyledRange], at pos: Int) -> CGFloat? {
        var result: CGFloat?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let k = a[.kern] as? CGFloat { result = k }
        }
        return result
    }

    /// Effective font at `pos` (last styled range wins).
    private func font(in attrs: [StyledRange], at pos: Int) -> NSFont? {
        var result: NSFont?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let f = a[.font] as? NSFont { result = f }
        }
        return result
    }

    // MARK: - Default preserved

    @Test("nil markerTextGap keeps the historical flat first-line indent and raw-whitespace nesting")
    func nilGapKeepsLegacyGeometry() {
        let text = "- top\n  - nested\n"
        let attrs = style(text)
        let perLevel = MarkdownEditorConfiguration.default.lists.indentPerLevel

        let top = paragraphStyle(in: attrs, at: 0)
        #expect(top?.firstLineHeadIndent == perLevel)
        #expect(top?.defaultTabInterval == perLevel)
        let markerWidth = HeadingHelpers.textWidth("- ", font: baseFont)
        #expect(abs((top?.headIndent ?? 0) - (perLevel + markerWidth)) < 0.01)

        // Nested: first line stays FLAT (raw whitespace is the visual indent),
        // only the wrapped-line hang includes the depth.
        let nested = paragraphStyle(in: attrs, at: 8)
        #expect(nested?.firstLineHeadIndent == perLevel)
        #expect(abs((nested?.headIndent ?? 0) - (perLevel + perLevel + markerWidth)) < 0.01)

        // No kern correction and no whitespace collapse in legacy mode.
        #expect(kern(in: attrs, at: 1) == nil)
        #expect(font(in: attrs, at: 6)?.pointSize == nil || font(in: attrs, at: 6)?.pointSize == base)
    }

    // MARK: - Grid geometry

    @Test("level 1 marker sits on the body origin; content hangs at the gap")
    func levelOneOnBodyOrigin() {
        let text = "- alpha beta\n"
        let attrs = style(text, gridConfig())
        let ps = paragraphStyle(in: attrs, at: 0)
        #expect(ps?.firstLineHeadIndent == 0)
        #expect(ps?.headIndent == 36)

        // The final spacer char (before "alpha") is kerned so the marker→content
        // advance lands exactly on the slot.
        let markerWidth = HeadingHelpers.textWidth("- ", font: baseFont)
        let k = kern(in: attrs, at: 1)
        #expect(k != nil)
        #expect(abs((k ?? 0) - (36 - markerWidth)) < 0.01)
    }

    @Test("nesting steps by indentPerLevel and collapses the source whitespace")
    func nestedStepsByIndentPerLevel() {
        let text = "- top\n  - two\n    - three\n"
        let attrs = style(text, gridConfig())
        let ns = text as NSString

        let two = paragraphStyle(in: attrs, at: ns.range(of: "- two").location)
        #expect(two?.firstLineHeadIndent == 24)
        #expect(abs((two?.headIndent ?? 0) - (24 + 36)) < 0.01)

        let three = paragraphStyle(in: attrs, at: ns.range(of: "- three").location)
        #expect(three?.firstLineHeadIndent == 48)
        #expect(abs((three?.headIndent ?? 0) - (48 + 36)) < 0.01)

        // The two leading spaces collapse to the hidden-marker font so the
        // source indent stops shifting the line.
        let hidden = MarkdownEditorConfiguration.default.markers.hiddenMarkerFontSize
        #expect(font(in: attrs, at: 6)?.pointSize == hidden)
    }

    @Test("tab-indented items land on the same grid; tabs advance by a sub-point interval")
    func tabIndentedItemsUseGrid() {
        let text = "- top\n\t- nested\n"
        let attrs = style(text, gridConfig())
        let ns = text as NSString
        let nested = paragraphStyle(in: attrs, at: ns.range(of: "- nested").location)
        #expect(nested?.firstLineHeadIndent == 24)
        #expect(nested?.defaultTabInterval == 0.25)
    }

    @Test("ordered markers share the same slot so bullet and numbered content align")
    func orderedMarkersShareTheSlot() {
        let text = "1. first\n2. second\n"
        let attrs = style(text, gridConfig())
        let ps = paragraphStyle(in: attrs, at: 0)
        #expect(ps?.firstLineHeadIndent == 0)
        #expect(ps?.headIndent == 36)

        let markerWidth = HeadingHelpers.textWidth("1. ", font: baseFont)
        let k = kern(in: attrs, at: 2)   // the space between "1." and "first"
        #expect(k != nil)
        #expect(abs((k ?? 0) - (36 - markerWidth)) < 0.01)
    }

    @Test("task items keep the grid geometry")
    func taskItemsKeepGridGeometry() {
        let text = "- [ ] task content\n"
        let attrs = style(text, gridConfig())
        let ps = paragraphStyle(in: attrs, at: 0)
        #expect(ps?.firstLineHeadIndent == 0)
        #expect(ps?.headIndent == 36)
    }

    @Test("a slot narrower than the marker widens just enough to keep the spacer advance positive")
    func narrowSlotClamps() {
        let text = "10. wide marker\n"
        let attrs = style(text, gridConfig(gap: 4))
        let markerWidth = HeadingHelpers.textWidth("10. ", font: baseFont)
        let spacerWidth = HeadingHelpers.textWidth(" ", font: baseFont)
        let expectedSlot = markerWidth - spacerWidth + 0.5
        let ps = paragraphStyle(in: attrs, at: 0)
        #expect(abs((ps?.headIndent ?? 0) - expectedSlot) < 0.01)
        let k = kern(in: attrs, at: 3)
        #expect(abs((k ?? 0) - (expectedSlot - markerWidth)) < 0.01)
    }

    // MARK: - Checkbox slot

    @Test("the drawn checkbox left-aligns to the marker slot in grid mode and right-aligns otherwise")
    func checkboxAlignmentPerMode() {
        // Legacy: right-aligned to the content edge with the fixed gap.
        #expect(TaskCheckboxGeometry.boxX(contentX: 100, size: 17) == 100 - 17 - TaskCheckboxGeometry.gap)
        // Grid: left-aligned to the slot origin.
        #expect(TaskCheckboxGeometry.boxX(contentX: 100, size: 17, markerTextGap: 36) == 64)
        // A slot narrower than the box falls back to the right-aligned position.
        #expect(
            TaskCheckboxGeometry.boxX(contentX: 100, size: 17, markerTextGap: 10)
                == 100 - 17 - TaskCheckboxGeometry.gap
        )
    }
}
