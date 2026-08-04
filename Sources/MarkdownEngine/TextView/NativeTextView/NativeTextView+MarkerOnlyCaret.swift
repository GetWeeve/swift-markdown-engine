//
//  NativeTextView+MarkerOnlyCaret.swift
//  MarkdownEngine
//
//  Caret x on marker-only list lines in the indent grid.
//
//  A fresh list continuation (`- `, `1. `, `- [ ] ` with no content yet)
//  carries its content offset as a kern on the final spacer character
//  (see the grid branch of `styleListItem`). Core Text drops the kern on
//  the last glyph of a line, so while the item is still empty the caret
//  rect collapses back to the raw marker advance — the insertion point
//  blinks at the line's left edge while the drawn marker sits in its slot
//  and the first typed character will land a full slot away. Snap the
//  insertion indicator to the paragraph's `headIndent`, which in grid
//  geometry IS the content origin (depth indent + marker slot).
//
//  Legacy (nil `markerTextGap`) geometry is untouched: content advance
//  there comes from real glyph advances, not an end-of-line kern, and the
//  caret already lands on the content origin.
//

import AppKit

extension NativeTextView {

    /// The corrected caret x (view coordinates) when the caret sits at the
    /// end of a marker-only list line in the indent grid, or nil when no
    /// correction applies.
    func markerOnlyListCaretX() -> CGFloat? {
        guard configuration.lists.helpersEnabled,
              configuration.lists.markerTextGap != nil,
              let ts = textStorage, ts.length > 0 else { return nil }
        let sel = selectedRange()
        guard sel.length == 0, sel.location <= ts.length else { return nil }
        let ns = ts.string as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        var line = paragraph
        while line.length > 0 {
            let last = ns.character(at: NSMaxRange(line) - 1)
            guard last == 0x0A || last == 0x0D else { break }
            line.length -= 1
        }
        // Only an end-of-line caret on a non-empty line can be affected —
        // mid-syntax carets sit before the kerned spacer and are laid out
        // with real advances.
        guard line.length > 0, sel.location == NSMaxRange(line) else { return nil }
        // Marker-only line: the list-marker prefix (the same recognizer the
        // Enter-continuation logic uses) consumes the whole line.
        let text = ns.substring(with: line)
        let textRange = NSRange(location: 0, length: (text as NSString).length)
        guard let match = MarkdownLists.listRegex.firstMatch(in: text, options: [], range: textRange),
              match.range(at: 1).length > 0,
              match.range.location == 0,
              NSMaxRange(match.range(at: 1)) == textRange.length else { return nil }
        // In grid geometry the paragraph's headIndent is the content origin
        // (depth × indentPerLevel + marker slot) — exactly where the first
        // typed character lands once the spacer kern stops being line-final.
        guard let style = ts.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle,
              style.headIndent > 0 else { return nil }
        return textContainerOrigin.x + style.headIndent
    }

    /// Snap the insertion indicator to the marker-only content origin
    /// (companion to the caret workarounds' Y-snap; this one fixes X).
    func fixMarkerOnlyLineCaret() {
        guard let desiredX = markerOnlyListCaretX(),
              let indicator = subviews.first(where: { type(of: $0) == NSTextInsertionIndicator.self }),
              !indicator.isHidden,
              abs(indicator.frame.origin.x - desiredX) >= 0.5 else { return }
        isApplyingCaretShift = true
        indicator.frame.origin.x = desiredX
        isApplyingCaretShift = false
    }
}
