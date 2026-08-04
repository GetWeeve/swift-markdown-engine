//
//  MarkerOnlyCaretTests.swift
//  MarkdownEngineTests
//
//  Caret x on marker-only list lines (fresh Enter continuations) in the
//  indent grid: the insertion point must sit at the paragraph's content
//  origin (headIndent), where the first typed character lands — not at the
//  raw collapsed-marker advance that Core Text reports once the spacer
//  kern falls at the end of the line.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Marker-only line caret")
struct MarkerOnlyCaretTests {

    private func makeView(_ text: String, caret: Int, _ config: MarkdownEditorConfiguration) -> NativeTextView {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.configuration = config
        view.string = text
        let font = NSFont.systemFont(ofSize: 16)
        if let storage = view.textStorage {
            storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))
            let attrs = MarkdownASTStyler.styleAttributes(
                text: text, fontName: font.fontName, fontSize: 16, configuration: config
            )
            for (range, a) in attrs {
                storage.addAttributes(a, range: range)
            }
        }
        view.setSelectedRange(NSRange(location: caret, length: 0))
        return view
    }

    private var grid: MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(
            lists: ListStyle(indentPerLevel: 24, markerTextGap: 16, markerSlotWidth: 20)
        )
    }

    // MARK: - Grid geometry: every marker kind snaps to the content origin

    @Test("empty task, bullet, and ordered continuations snap to headIndent")
    func markerOnlyLinesSnap() {
        for text in ["- [ ] ", "- ", "1. ", "- [x] "] {
            let caret = (text as NSString).length
            let view = makeView(text, caret: caret, grid)
            let x = view.markerOnlyListCaretX()
            let style = view.textStorage?.attribute(
                .paragraphStyle, at: 0, effectiveRange: nil
            ) as? NSParagraphStyle
            #expect(style != nil, "grid paragraph style missing for \(text)")
            #expect(x != nil, "no caret correction for marker-only \(text)")
            if let x, let style {
                // Content origin: depth 0 × 24 + slot(20) + gap(16) = 36.
                #expect(style.headIndent == 36)
                #expect(x == view.textContainerOrigin.x + style.headIndent)
            }
        }
    }

    @Test("nested continuations step by indentPerLevel")
    func nestedMarkerOnlyLine() {
        let text = "- parent\n  - "
        let caret = (text as NSString).length
        let view = makeView(text, caret: caret, grid)
        let x = view.markerOnlyListCaretX()
        #expect(x != nil)
        if let x {
            // Depth 1: 24 + slot(20) + gap(16) = 60.
            #expect(x == view.textContainerOrigin.x + 60)
        }
    }

    // MARK: - No correction where the caret is already right

    @Test("a line with content is untouched")
    func contentLineUntouched() {
        let text = "- [ ] task content"
        let view = makeView(text, caret: (text as NSString).length, grid)
        #expect(view.markerOnlyListCaretX() == nil)
    }

    @Test("a mid-syntax caret is untouched")
    func midSyntaxCaretUntouched() {
        let view = makeView("- [ ] ", caret: 3, grid)
        #expect(view.markerOnlyListCaretX() == nil)
    }

    @Test("plain text is untouched")
    func plainTextUntouched() {
        let text = "hello"
        let view = makeView(text, caret: 5, grid)
        #expect(view.markerOnlyListCaretX() == nil)
    }

    @Test("legacy geometry is untouched")
    func legacyUntouched() {
        // Legacy content advance comes from real glyph advances, not an
        // end-of-line kern — the caret is already at the content origin.
        let view = makeView("- [ ] ", caret: 6, .default)
        #expect(view.markerOnlyListCaretX() == nil)
    }

    @Test("a selection is untouched")
    func selectionUntouched() {
        let view = makeView("- [ ] ", caret: 6, grid)
        view.setSelectedRange(NSRange(location: 2, length: 4))
        #expect(view.markerOnlyListCaretX() == nil)
    }

    @Test("helpers off means no correction")
    func helpersOffUntouched() {
        var config = grid
        config.lists.helpersEnabled = false
        let view = makeView("- [ ] ", caret: 6, config)
        #expect(view.markerOnlyListCaretX() == nil)
    }
}
