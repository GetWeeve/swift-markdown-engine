//
//  ListMarkerStylingTests.swift
//  MarkdownEngineTests
//
//  Per-depth ordered marker styles (`ListStyle.orderedMarkerStyles`) and the
//  `MarkdownEditorTheme.listMarker` ink slot. Lettering only changes the
//  painted overlay — the source digits stay untouched — and the default
//  (single `.numeric`) must keep today's rendering exactly.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("List marker styling")
struct ListMarkerStylingTests {

    private let base: CGFloat = 16
    private var fontName: String { NSFont.systemFont(ofSize: 16).fontName }

    private func style(
        _ text: String,
        styles: [OrderedMarkerStyle] = [.numeric],
        caret: Int = -1
    ) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base, caretLocation: caret,
            configuration: MarkdownEditorConfiguration(lists: ListStyle(orderedMarkerStyles: styles))
        )
    }

    /// The painted overlay marker covering `pos`, if the overlay is active.
    private func overlayMarker(in attrs: [StyledRange], at pos: Int) -> String? {
        var result: String?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let m = a[.orderedMarker] as? String { result = m }
        }
        return result
    }

    // MARK: - Label formatting

    @Test("alpha labels count bijective base-26")
    func alphaLabels() {
        let style = OrderedMarkerStyle.lowerAlpha
        #expect(style.label(for: 1) == "a")
        #expect(style.label(for: 2) == "b")
        #expect(style.label(for: 26) == "z")
        #expect(style.label(for: 27) == "aa")
        #expect(style.label(for: 28) == "ab")
        #expect(style.label(for: 53) == "ba")
        #expect(OrderedMarkerStyle.upperAlpha.label(for: 27) == "AA")
    }

    @Test("roman labels use subtractive notation")
    func romanLabels() {
        let style = OrderedMarkerStyle.lowerRoman
        #expect(style.label(for: 1) == "i")
        #expect(style.label(for: 3) == "iii")
        #expect(style.label(for: 4) == "iv")
        #expect(style.label(for: 9) == "ix")
        #expect(style.label(for: 14) == "xiv")
        #expect(style.label(for: 40) == "xl")
        #expect(OrderedMarkerStyle.upperRoman.label(for: 4) == "IV")
    }

    @Test("numeric labels are the digits; non-positive numbers fall back to digits")
    func numericAndFallbackLabels() {
        #expect(OrderedMarkerStyle.numeric.label(for: 7) == "7")
        #expect(OrderedMarkerStyle.lowerAlpha.label(for: 0) == "0")
    }

    @Test("styles cycle per depth; an empty array reads as numeric")
    func stylesCyclePerDepth() {
        let lists = ListStyle(orderedMarkerStyles: [.numeric, .lowerAlpha, .lowerRoman])
        #expect(lists.orderedMarkerStyle(forDepth: 0) == .numeric)
        #expect(lists.orderedMarkerStyle(forDepth: 1) == .lowerAlpha)
        #expect(lists.orderedMarkerStyle(forDepth: 2) == .lowerRoman)
        #expect(lists.orderedMarkerStyle(forDepth: 3) == .numeric)
        #expect(ListStyle(orderedMarkerStyles: []).orderedMarkerStyle(forDepth: 2) == .numeric)
    }

    // MARK: - Overlay behavior

    @Test("the default stays numeric: a matching source number paints no overlay")
    func defaultNumericPaintsNoOverlayForMatchingSource() {
        // "1." and "2." already display what the source says — the overlay
        // stays off, exactly as before this knob existed.
        let text = "1. one\n2. two\n"
        let attrs = style(text)
        #expect(overlayMarker(in: attrs, at: 0) == nil)
        #expect(overlayMarker(in: attrs, at: 7) == nil)

        // A repeated literal still renumbers by position (existing behavior).
        let repeated = style("1. one\n1. two\n")
        #expect(overlayMarker(in: repeated, at: 7) == "2.")
    }

    @Test("a non-numeric depth letters the marker even when the number matches the source")
    func letteringActivatesOverlayAtNestedDepth() {
        let text = "1. top\n   1. child\n"
        let attrs = style(text, styles: [.numeric, .lowerAlpha])
        let ns = text as NSString
        let childMarker = ns.range(of: "1. child").location
        #expect(overlayMarker(in: attrs, at: 0) == nil, "top level stays numeric with no overlay")
        #expect(overlayMarker(in: attrs, at: childMarker) == "a.")
    }

    @Test("lettering keeps the source punctuation — a paren list stays a paren list")
    func letteringKeepsParenPunctuation() {
        let text = "1) top\n   1) child\n"
        let attrs = style(text, styles: [.numeric, .lowerAlpha])
        let ns = text as NSString
        let childMarker = ns.range(of: "1) child").location
        #expect(overlayMarker(in: attrs, at: childMarker) == "a)")
    }

    @Test("the caret inside the marker reveals the raw digits (overlay off)")
    func caretRevealsRawDigits() {
        let text = "1. top\n   1. child\n"
        let ns = text as NSString
        let childMarker = ns.range(of: "1. child").location
        let attrs = style(text, styles: [.numeric, .lowerAlpha], caret: childMarker + 1)
        #expect(overlayMarker(in: attrs, at: childMarker) == nil)
    }

    // MARK: - Theme slot

    @Test("theme.listMarker defaults to nil and carries a custom ink")
    func listMarkerThemeSlot() {
        #expect(MarkdownEditorTheme.default.listMarker == nil)
        let muted = NSColor(calibratedWhite: 0.5, alpha: 1)
        #expect(MarkdownEditorTheme(listMarker: muted).listMarker == muted)
    }
}
