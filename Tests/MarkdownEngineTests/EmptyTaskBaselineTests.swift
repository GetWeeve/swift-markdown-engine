//
//  EmptyTaskBaselineTests.swift
//  MarkdownEngineTests
//
//  Empty grid-hidden task lines (`- [ ] ` with no content) must keep a
//  body-font strut on the trailing spacer so TextKit's baseline matches a
//  content line. Without it every glyph is the 0.1pt inline-marker font,
//  the baseline parks at the fragment bottom, and the drawn checkbox sits
//  too low relative to the caret.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Empty task baseline strut")
struct EmptyTaskBaselineTests {

    private let fontSize: CGFloat = 16
    private var fontName: String { NSFont.systemFont(ofSize: fontSize).fontName }
    private var baseFont: NSFont { NSFont.systemFont(ofSize: fontSize) }

    private var grid: MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(
            lists: ListStyle(indentPerLevel: 24, markerTextGap: 16, markerSlotWidth: 20)
        )
    }

    private func style(_ text: String, caret: Int = -1) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            caretLocation: caret,
            configuration: grid
        )
    }

    private func font(in attrs: [StyledRange], at pos: Int) -> NSFont? {
        var result: NSFont?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let f = a[.font] as? NSFont { result = f }
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

    @Test("empty task trailing spacer keeps body font")
    func emptyTaskSpacerKeepsBodyFont() {
        let text = "- [ ] "
        let attrs = style(text)
        // Trailing spacer is the last character (index 5).
        let spacerFont = font(in: attrs, at: 5)
        #expect(spacerFont?.pointSize == baseFont.pointSize)
        // Box chars stay collapsed.
        #expect(font(in: attrs, at: 2)?.pointSize == grid.markers.hiddenMarkerFontSize)
    }

    @Test("empty task spacer kern subtracts the body-font advance")
    func emptyTaskSpacerKernCompensatesBodyWidth() {
        let text = "- [ ] "
        let attrs = style(text)
        let spacerWidth = HeadingHelpers.textWidth(" ", font: baseFont)
        // Collapsed marker group (`- `) measures at the inline-marker font.
        let markerWidth = HeadingHelpers.textWidth(
            "- ",
            font: NSFont(name: fontName, size: grid.markers.hiddenMarkerFontSize)
                ?? .systemFont(ofSize: grid.markers.hiddenMarkerFontSize)
        )
        let slot: CGFloat = 36 // 20 + 16
        let expected = slot - markerWidth - spacerWidth
        let k = kern(in: attrs, at: 5)
        #expect(k != nil)
        #expect(abs((k ?? 0) - expected) < 0.01)
    }

    @Test("content task spacer stays collapsed")
    func contentTaskSpacerStaysCollapsed() {
        let text = "- [ ] Write something"
        let attrs = style(text)
        // Trailing spacer after `]` is index 5; content lines keep the tiny font.
        #expect(font(in: attrs, at: 5)?.pointSize == grid.markers.hiddenMarkerFontSize)
        let markerWidth = HeadingHelpers.textWidth(
            "- ",
            font: NSFont(name: fontName, size: grid.markers.hiddenMarkerFontSize)
                ?? .systemFont(ofSize: grid.markers.hiddenMarkerFontSize)
        )
        let expected = 36 - markerWidth
        let k = kern(in: attrs, at: 5)
        #expect(abs((k ?? 0) - expected) < 0.01)
    }

    @Test("empty task baseline matches content task baseline")
    func emptyAndContentShareBaseline() {
        // Layout-level check: with the body-font strut, the line's baseline
        // for the checkbox char matches a content line (not the fragment
        // bottom that 0.1pt-only lines produce).
        _ = NSApplication.shared
        func baselineY(for text: String) -> CGFloat? {
            let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            view.configuration = grid
            view.baseFont = baseFont
            view.string = text
            if let storage = view.textStorage {
                storage.addAttribute(.font, value: baseFont, range: NSRange(location: 0, length: storage.length))
                for (range, a) in style(text) {
                    storage.addAttributes(a, range: range)
                }
            }
            guard let tlm = view.textLayoutManager,
                  let tcs = tlm.textContentManager as? NSTextContentStorage,
                  let loc = tcs.location(tcs.documentRange.location, offsetBy: 0)
            else { return nil }
            tlm.ensureLayout(for: tlm.documentRange)
            var baseline: CGFloat?
            tlm.enumerateTextLayoutFragments(from: loc, options: [.ensuresLayout]) { fragment in
                guard let line = fragment.textLineFragments.first else { return false }
                let local = min(2, max(0, line.characterRange.length - 1))
                let charPos = line.locationForCharacter(at: local)
                baseline = fragment.layoutFragmentFrame.origin.y
                    + line.typographicBounds.origin.y
                    + charPos.y
                return false
            }
            return baseline
        }

        let empty = baselineY(for: "- [ ] ")
        let content = baselineY(for: "- [ ] Write something")
        #expect(empty != nil && content != nil)
        if let empty, let content {
            // Body strut should pull the empty-line baseline onto the content
            // line's (~18 for SF@16 in a ~21pt fragment), not the ~21 bottom.
            #expect(abs(empty - content) < 1.0, "empty=\(empty) content=\(content)")
            #expect(empty < 20.5, "empty baseline still parked at fragment bottom: \(empty)")
        }
    }
}
