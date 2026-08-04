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
}
