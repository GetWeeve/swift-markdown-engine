//
//  CaretFollowScrollTests.swift
//  MarkdownEngineTests
//
//  Caret-follow in `.scrolls` mode: `scrollRangeToVisible` must reveal an
//  off-screen caret through the engine's manual TextKit-2 fragment reveal —
//  AppKit's native implementation routes through the absent TextKit 1 layout
//  manager and silently no-ops for off-screen content, so typing at the
//  bottom of a small viewport never scrolled. Also pins the
//  `caretFollowAnimationDuration` knob's default (0 = instant, the
//  historical behavior).
//
//  Headless: no window, so the animated branch (which requires a window) is
//  never taken and reveals apply instantly — deterministic assertions.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Caret follow in .scrolls mode")
struct CaretFollowScrollTests {

    private func makeStack(
        lines: Int = 30,
        viewport: NSSize = NSSize(width: 360, height: 300)
    ) -> HeightBehaviorStack {
        _ = NSApplication.shared
        let stack = HeightBehaviorStack(viewport: viewport, heightBehavior: .scrolls)
        let tv = stack.textView
        tv.string = (1...lines).map { "line number \($0)" }.joined(separator: "\n")
        if let tlm = tv.textLayoutManager {
            tv.layoutBridge = LayoutBridge(tlm)
        }
        tv.recalcOverscroll(for: stack.scrollView)
        stack.scrollView.layoutSubtreeIfNeeded()
        return stack
    }

    @Test("the animation knob defaults to instant")
    func animationDefaultsToZero() {
        #expect(MarkdownEditorConfiguration.default.caretFollowAnimationDuration == 0)
        // Negative durations clamp to instant rather than trapping later.
        let config = MarkdownEditorConfiguration(caretFollowAnimationDuration: -1)
        #expect(config.caretFollowAnimationDuration == 0)
    }

    @Test("revealing an off-screen caret scrolls it into the viewport")
    func revealAtBottomScrolls() {
        let stack = makeStack()
        let tv = stack.textView
        let cv = stack.scrollView.contentView
        #expect(cv.bounds.origin.y == 0)

        let end = (tv.string as NSString).length
        tv.setSelectedRange(NSRange(location: end, length: 0))
        tv.scrollRangeToVisible(NSRange(location: end, length: 0))

        // The clip view moved down, and the last line's rect now sits inside
        // the visible band.
        let y = cv.bounds.origin.y
        #expect(y > 0)
        guard let tlm = tv.textLayoutManager,
              let loc = tlm.textContentManager?.location(tlm.documentRange.location, offsetBy: end - 1)
        else {
            Issue.record("no layout manager")
            return
        }
        var lineRect = CGRect.zero
        tlm.enumerateTextSegments(in: NSTextRange(location: loc), type: .standard, options: []) { _, rect, _, _ in
            lineRect = rect
            return false
        }
        let lineInDoc = lineRect.offsetBy(dx: 0, dy: tv.frame.origin.y)
        #expect(lineInDoc.maxY <= cv.bounds.origin.y + cv.bounds.height + 0.5)
        #expect(lineInDoc.minY >= cv.bounds.origin.y - 0.5)
    }

    @Test("an already-visible caret does not move the viewport")
    func visibleCaretDoesNotScroll() {
        let stack = makeStack()
        let tv = stack.textView
        let cv = stack.scrollView.contentView

        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
        #expect(cv.bounds.origin.y == 0)
    }

    @Test("revealing an off-screen caret above the viewport scrolls back up")
    func revealAboveScrollsUp() {
        let stack = makeStack()
        let tv = stack.textView
        let cv = stack.scrollView.contentView

        // Park the viewport at the bottom first.
        let end = (tv.string as NSString).length
        tv.scrollRangeToVisible(NSRange(location: end, length: 0))
        let bottomY = cv.bounds.origin.y
        #expect(bottomY > 0)

        tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
        #expect(cv.bounds.origin.y < bottomY)
        // The first line is at the document top: the reveal target clamps to
        // the inset origin instead of overshooting negative.
        #expect(cv.bounds.origin.y <= 0)
    }

    @Test("the reveal target clamps to the scrollable content")
    func revealClampsToContent() {
        let stack = makeStack()
        let tv = stack.textView
        let cv = stack.scrollView.contentView
        let container = stack.scrollView.documentView as? NativeTextViewContainer

        let end = (tv.string as NSString).length
        tv.scrollRangeToVisible(NSRange(location: end, length: 0))

        let realHeight = container?.scrollableContentHeight ?? 0
        let maxY = max(-stack.scrollView.contentInsets.top, realHeight - cv.bounds.height)
        #expect(cv.bounds.origin.y <= maxY + 0.5)
    }

    // MARK: - Empty list continuation

    /// List Enter is intercepted and applied via `performEdit` (storage replace
    /// + `didChangeText`), which skips `NSTextView.insertText` and therefore
    /// skips AppKit's post-insert `scrollRangeToVisible`. A new marker-only
    /// item (`- `, `1. `, `- [ ] `) at the bottom of a small viewport must
    /// still reveal its full line — not wait until the first content character.
    @Test("Enter on a list item at the bottom reveals the new empty item")
    func emptyListContinuationScrollsFullyIntoView() {
        let stack = makeListStack(items: 30, lastContent: "last item")
        let tv = stack.textView
        let cv = stack.scrollView.contentView

        let beforeEnter = (tv.string as NSString).length
        tv.setSelectedRange(NSRange(location: beforeEnter, length: 0))
        tv.scrollRangeToVisible(NSRange(location: beforeEnter, length: 0))
        let yBefore = cv.bounds.origin.y
        #expect(yBefore > 0)

        tv.insertText("\n", replacementRange: NSRange(location: beforeEnter, length: 0))
        #expect(tv.string.hasSuffix("\n- "))

        let caret = tv.selectedRange()
        #expect(caret.length == 0)
        #expect(caret.location == (tv.string as NSString).length)

        let line = lineRect(in: tv, at: max(caret.location - 1, 0))
        #expect(line.height > 0, "empty list item has no line fragment")
        #expect(line.maxY <= cv.bounds.origin.y + cv.bounds.height + 0.5)
        #expect(line.minY >= cv.bounds.origin.y - 0.5)
        #expect(cv.bounds.origin.y >= yBefore, "viewport should not jump upward")
    }

    @Test("revealing a marker-only last line uses the full line height")
    func emptyListItemRevealMatchesLineHeight() {
        let stack = makeListStack(items: 30, lastContent: "")
        let tv = stack.textView
        let cv = stack.scrollView.contentView
        #expect(tv.string.hasSuffix("\n- "))

        let end = (tv.string as NSString).length
        tv.setSelectedRange(NSRange(location: end, length: 0))
        tv.scrollRangeToVisible(NSRange(location: end, length: 0))

        let line = lineRect(in: tv, at: max(end - 1, 0))
        #expect(line.height > 0)
        #expect(line.maxY <= cv.bounds.origin.y + cv.bounds.height + 0.5)
        #expect(line.minY >= cv.bounds.origin.y - 0.5)
    }

    // MARK: - List helpers

    private struct ListScrollStack {
        let scrollView: ClampedScrollView
        let textView: NativeTextView
        let coordinator: NativeTextViewCoordinator
        let layoutBridge: LayoutBridge?
    }

    private func makeListStack(items: Int, lastContent: String) -> ListScrollStack {
        _ = NSApplication.shared
        let viewport = NSSize(width: 360, height: 120)
        let stack = HeightBehaviorStack(viewport: viewport, heightBehavior: .scrolls)
        let tv = stack.textView
        var config = tv.configuration
        config.lists = ListStyle(
            indentPerLevel: 24,
            extraLineHeight: 2,
            markerTextGap: 16,
            markerSlotWidth: 20
        )
        tv.configuration = config

        let body = (1..<items).map { "- line number \($0)" }
        let last = lastContent.isEmpty ? "- " : "- \(lastContent)"
        let text = (body + [last]).joined(separator: "\n")

        let coordinator = NativeTextViewCoordinator(
            text: .constant(text),
            fontName: NSFont.systemFont(ofSize: 16).fontName,
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.configuration = config
        coordinator.textView = tv
        tv.delegate = coordinator
        var bridge: LayoutBridge?
        if let tlm = tv.textLayoutManager {
            bridge = LayoutBridge(tlm)
            tv.layoutBridge = bridge
            coordinator.layoutBridge = bridge
        }
        coordinator.rebuildTextStorageAndStyle(tv, from: text)
        tv.recalcOverscroll(for: stack.scrollView)
        stack.scrollView.layoutSubtreeIfNeeded()
        return ListScrollStack(
            scrollView: stack.scrollView,
            textView: tv,
            coordinator: coordinator,
            layoutBridge: bridge
        )
    }

    /// Typographic bounds of the text line containing `offset`, in document-view
    /// coordinates (text-view frame origin applied), matching the reveal math.
    private func lineRect(in tv: NativeTextView, at offset: Int) -> CGRect {
        guard let tlm = tv.textLayoutManager,
              let loc = tlm.textContentManager?.location(
                  tlm.documentRange.location, offsetBy: offset
              )
        else { return .zero }
        var rect = CGRect.zero
        tlm.enumerateTextLayoutFragments(from: loc, options: [.ensuresLayout]) { fragment in
            guard let line = fragment.textLineFragments.last(where: { $0.characterRange.length > 0 })
                ?? fragment.textLineFragments.last
            else { return false }
            rect = CGRect(
                x: fragment.layoutFragmentFrame.minX + line.typographicBounds.minX,
                y: fragment.layoutFragmentFrame.minY + line.typographicBounds.minY,
                width: max(line.typographicBounds.width, 1),
                height: line.typographicBounds.height
            )
            return false
        }
        return rect.offsetBy(dx: 0, dy: tv.frame.origin.y)
    }
}
