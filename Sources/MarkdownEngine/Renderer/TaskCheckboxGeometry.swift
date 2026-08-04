//
//  TaskCheckboxGeometry.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 09.07.26.
//
//  Shared geometry for the drawn task-checkbox square. The hidden `[ ] ` chars
//  are collapsed to ~zero advance by the styler, so `drawPosition`/
//  `boundingRect` of the box range sit at the task CONTENT's left edge. The
//  square is right-aligned to that edge with a small gap (Obsidian-style),
//  occupying the `- ` marker slot. Fragment draw and click hit-test both use
//  these functions so their rects can't drift apart.
//

import AppKit

enum TaskCheckboxGeometry {

    /// Gap between the box's right edge and the task content's left edge.
    static let gap: CGFloat = 2.0

    /// Side length of the square for the given (body) font. A fixed marker
    /// column (``ListStyle/markerSlotWidth`` on the indent grid) overrides
    /// the font-derived size: the box fills the column exactly, so checkbox,
    /// bullet, and number markers share one alignment grid.
    static func size(for font: NSFont, slotWidth: CGFloat? = nil) -> CGFloat {
        if let slotWidth { return max(1.0, slotWidth) }
        let ascent = max(0, font.ascender)
        let descent = max(0, -font.descender)
        let fontHeight = max(1, ceil(ascent + descent))
        let markerWidth = ("[ ]" as NSString).size(withAttributes: [.font: font]).width
        return max(1.0, min(floor(fontHeight * 1.2), floor(markerWidth * 1.2)))
    }

    /// Left edge of the square.
    ///
    /// Legacy layout right-aligns the box to the content start x with `gap`
    /// (the hidden `[ ] ` sits at the content edge because `- ` keeps full
    /// advance). In the indent grid (``ListStyle/markerTextGap`` set) the
    /// styler collapses the WHOLE `- [ ] `, so the box range's own position is
    /// the marker-slot origin — the square is LEFT-aligned there, matching
    /// where a bullet or number glyph would start. Gaps narrower than
    /// `size + gap` let the square run into the content; configure
    /// ``ListStyle/markerTextGap`` at least that wide.
    static func boxX(contentX: CGFloat, size: CGFloat, markerTextGap: CGFloat? = nil) -> CGFloat {
        if markerTextGap != nil {
            return contentX
        }
        return contentX - size - gap
    }
}
