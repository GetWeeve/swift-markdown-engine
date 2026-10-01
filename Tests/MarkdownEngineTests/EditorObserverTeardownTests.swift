//
//  EditorObserverTeardownTests.swift
//  MarkdownEngineTests
//
//  The clip view observers `makeNSView` registers are owned by the
//  coordinator and released when SwiftUI dismantles the editor. Registered
//  inline with strong captures and no tokens, every editor ever created stayed
//  registered and in memory for the life of the app.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Editor observer teardown")
struct EditorObserverTeardownTests {

    private func makeCoordinator() -> NativeTextViewCoordinator {
        _ = NSApplication.shared
        return NativeTextViewCoordinator(
            text: .constant(""),
            fontName: "SF Pro Text",
            fontSize: 14,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
    }

    @Test("Installing registers both viewport observers, once")
    func installRegistersBothObserversOnce() {
        let coordinator = makeCoordinator()
        let scrollView = ClampedScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let textView = NativeTextView(frame: .zero)

        coordinator.installViewportObservers(scrollView: scrollView, textView: textView)
        coordinator.installViewportObservers(scrollView: scrollView, textView: textView)

        #expect(coordinator.viewportObservers.count == 2)
    }

    @Test("Dismantling removes every viewport observer")
    func dismantleRemovesTheObservers() {
        let coordinator = makeCoordinator()
        let scrollView = ClampedScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let textView = NativeTextView(frame: .zero)
        coordinator.installViewportObservers(scrollView: scrollView, textView: textView)

        NativeTextViewWrapper.dismantleNSView(scrollView, coordinator: coordinator)

        #expect(coordinator.viewportObservers.isEmpty)
    }

    /// `NSTextView` outlives a test scope on its own (it is not released even
    /// with no observers at all), so this checks what the observers decide:
    /// they must not keep the scroll view or the coordinator alive.
    @Test("The observers keep neither the scroll view nor the coordinator alive")
    func observersHoldWeakReferences() {
        weak var weakScrollView: ClampedScrollView?
        weak var weakCoordinator: NativeTextViewCoordinator?
        let textView = NativeTextView(frame: .zero)
        autoreleasepool {
            let coordinator = makeCoordinator()
            let scrollView = ClampedScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            weakScrollView = scrollView
            weakCoordinator = coordinator
            coordinator.installViewportObservers(scrollView: scrollView, textView: textView)
        }

        #expect(weakScrollView == nil)
        #expect(weakCoordinator == nil)
    }

    @Test("A scroll after teardown reaches no observer")
    func aScrollAfterTeardownIsIgnored() {
        let coordinator = makeCoordinator()
        let scrollView = ClampedScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let textView = NativeTextView(frame: .zero)
        coordinator.installViewportObservers(scrollView: scrollView, textView: textView)
        coordinator.removeAllObservers()

        // Posting must not crash or reach a released closure.
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        #expect(coordinator.viewportObservers.isEmpty)
    }
}
