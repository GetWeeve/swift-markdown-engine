//
//  ListMarkerSlotTests.swift
//  MarkdownEngineTests
//
//  The fixed marker column on the indent grid (`ListStyle.markerSlotWidth`):
//  every marker kind occupies an invisible fixed-width slot at the depth
//  indent — bullets and painted ordered markers center in it, the task
//  checkbox fills it exactly — and content hangs `slot + gap` after the
//  marker origin so all three list kinds share one alignment grid.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("List marker slot (ListStyle.markerSlotWidth)")
struct ListMarkerSlotTests {

    private let base: CGFloat = 16
    private var fontName: String { NSFont.systemFont(ofSize: 16).fontName }
    private var baseFont: NSFont { NSFont.systemFont(ofSize: 16) }

    private func slotConfig(slot: CGFloat = 20, gap: CGFloat = 16, indent: CGFloat = 24) -> MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(
            lists: ListStyle(indentPerLevel: indent, markerTextGap: gap, markerSlotWidth: slot)
        )
    }

    private func style(_ text: String, _ config: MarkdownEditorConfiguration) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(text: text, fontName: fontName, fontSize: base, configuration: config)
    }

    private func paragraphStyle(in attrs: [StyledRange], at pos: Int) -> NSParagraphStyle? {
        var result: NSParagraphStyle?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let p = a[.paragraphStyle] as? NSParagraphStyle { result = p }
        }
        return result
    }

    private func kern(in attrs: [StyledRange], at pos: Int) -> CGFloat? {
        var result: CGFloat?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let k = a[.kern] as? CGFloat { result = k }
        }
        return result
    }

    // MARK: - Gating

    @Test("markerSlotWidth without markerTextGap is inert")
    func slotRequiresGrid() {
        let lists = ListStyle(markerSlotWidth: 20)
        #expect(lists.effectiveMarkerSlotWidth == nil)
        // Layout stays the historical geometry bit-for-bit.
        let config = MarkdownEditorConfiguration(lists: lists)
        let attrs = style("- alpha\n", config)
        let ps = paragraphStyle(in: attrs, at: 0)
        #expect(ps?.firstLineHeadIndent == lists.indentPerLevel)
    }

    @Test("markerSlotWidth on the grid is in effect")
    func slotActiveOnGrid() {
        #expect(ListStyle(markerTextGap: 16, markerSlotWidth: 20).effectiveMarkerSlotWidth == 20)
    }

    // MARK: - Content offset = slot + gap

    @Test("bullet, ordered, and task content all hang slot + gap after the marker origin")
    func allMarkerKindsShareTheContentEdge() {
        let config = slotConfig()   // 20 + 16 = 36
        for text in ["- bullet item\n", "1. ordered item\n", "- [ ] task item\n"] {
            let attrs = style(text, config)
            let ps = paragraphStyle(in: attrs, at: 0)
            #expect(ps?.firstLineHeadIndent == 0, "first line origin for \(text)")
            #expect(abs((ps?.headIndent ?? 0) - 36) < 0.01, "content edge for \(text)")
        }
    }

    @Test("nested items step by indentPerLevel and keep the slot + gap hang")
    func nestedSlotGeometry() {
        let text = "- top\n  - nested\n"
        let attrs = style(text, slotConfig())
        let ns = text as NSString
        let nested = paragraphStyle(in: attrs, at: ns.range(of: "- nested").location)
        #expect(nested?.firstLineHeadIndent == 24)
        #expect(abs((nested?.headIndent ?? 0) - (24 + 36)) < 0.01)
    }

    @Test("the spacer kern lands content exactly on the slot edge")
    func spacerKernTargetsSlotEdge() {
        let attrs = style("- alpha\n", slotConfig())
        let markerWidth = HeadingHelpers.textWidth("- ", font: baseFont)
        let k = kern(in: attrs, at: 1)
        #expect(k != nil)
        #expect(abs((k ?? 0) - (36 - markerWidth)) < 0.01)
    }

    // MARK: - Ordered overlay forced

    @Test("slot mode paints ordered markers even when the display number matches the source digits")
    func slotModeForcesOrderedOverlay() {
        // Numeric style + matching digits normally skips the overlay (the raw
        // digits already read right); the slot's centering requires painting.
        let attrs = style("1. first\n", slotConfig())
        let hasOverlay = attrs.contains { _, a in a[.orderedMarker] != nil }
        #expect(hasOverlay)

        // Without a slot the historical skip stays.
        let gridOnly = MarkdownEditorConfiguration(lists: ListStyle(indentPerLevel: 24, markerTextGap: 36))
        let plain = style("1. first\n", gridOnly)
        let hasPlainOverlay = plain.contains { _, a in a[.orderedMarker] != nil }
        #expect(!hasPlainOverlay)
    }

    // MARK: - Checkbox geometry

    @Test("the checkbox square fills the slot exactly; nil slot keeps the font-derived size")
    func checkboxFillsSlot() {
        #expect(TaskCheckboxGeometry.size(for: baseFont, slotWidth: 20) == 20)
        let legacy = TaskCheckboxGeometry.size(for: baseFont)
        #expect(legacy == TaskCheckboxGeometry.size(for: baseFont, slotWidth: nil))
        #expect(legacy > 0)
    }
}
