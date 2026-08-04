//
//  FormattingShortcutTests.swift
//  MarkdownEngineTests
//
//  Inline-formatting key equivalents (⌘B/⌘I/⌘E/⌘⇧K) dispatching to the
//  coordinator's toggleable formatting actions, and the
//  `formattingShortcutsEnabled` gate. The wrap/unwrap semantics themselves
//  are covered by FormattingActionTests.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Formatting shortcuts")
struct FormattingShortcutTests {

    private func makeEditor(
        _ text: String,
        selection: NSRange,
        configure: (inout MarkdownEditorConfiguration) -> Void = { _ in }
    ) -> (NativeTextView, NativeTextViewCoordinator) {
        // The coordinator's selection-change delegate reads NSApp.currentEvent;
        // headless test bundles must materialize the shared app first.
        _ = NSApplication.shared
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.isEditable = true
        var config = MarkdownEditorConfiguration.default
        configure(&config)
        textView.configuration = config
        let coordinator = NativeTextViewCoordinator(
            text: .constant(""),
            fontName: "SF Pro Text",
            fontSize: 14,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.textView = textView
        coordinator.configuration = config
        textView.delegate = coordinator
        textView.string = text
        textView.setSelectedRange(selection)
        return (textView, coordinator)
    }

    private func keyEvent(_ character: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: character, charactersIgnoringModifiers: character,
            isARepeat: false, keyCode: 0
        )!
    }

    // MARK: - Dispatch

    @Test("⌘B wraps the selection in bold markers")
    func commandBWraps() {
        let (tv, _) = makeEditor("hello world", selection: NSRange(location: 0, length: 5))
        #expect(tv.handleFormattingShortcut(keyEvent("b", modifiers: .command)))
        #expect(tv.string == "**hello** world")
        #expect(tv.selectedRange() == NSRange(location: 2, length: 5))
    }

    @Test("⌘B unwraps an already-bold target (toggle)")
    func commandBToggles() {
        let (tv, _) = makeEditor("aa **bb** cc", selection: NSRange(location: 5, length: 2))
        #expect(tv.handleFormattingShortcut(keyEvent("b", modifiers: .command)))
        #expect(tv.string == "aa bb cc")
    }

    @Test("⌘I wraps and unwraps italics")
    func commandIToggles() {
        let (tv, _) = makeEditor("hello world", selection: NSRange(location: 0, length: 5))
        #expect(tv.handleFormattingShortcut(keyEvent("i", modifiers: .command)))
        #expect(tv.string == "*hello* world")
        tv.setSelectedRange(NSRange(location: 1, length: 5))
        #expect(tv.handleFormattingShortcut(keyEvent("i", modifiers: .command)))
        #expect(tv.string == "hello world")
    }

    @Test("⌘E wraps the selection in inline code")
    func commandEWrapsCode() {
        let (tv, _) = makeEditor("run this now", selection: NSRange(location: 4, length: 4))
        #expect(tv.handleFormattingShortcut(keyEvent("e", modifiers: .command)))
        #expect(tv.string == "run `this` now")
    }

    @Test("⌘⇧K inserts the link scaffold around the selection")
    func commandShiftKLinks() {
        let (tv, _) = makeEditor("visit here today", selection: NSRange(location: 6, length: 4))
        #expect(tv.handleFormattingShortcut(keyEvent("k", modifiers: [.command, .shift])))
        #expect(tv.string.contains("[here]("))
    }

    // MARK: - Events that must keep flowing

    @Test("plain ⌘K is never consumed (embedder binding)")
    func plainCommandKPassesThrough() {
        let (tv, _) = makeEditor("visit here today", selection: NSRange(location: 6, length: 4))
        #expect(!tv.handleFormattingShortcut(keyEvent("k", modifiers: .command)))
        #expect(tv.string == "visit here today")
    }

    @Test("extra modifiers pass through")
    func extraModifiersPassThrough() {
        let (tv, _) = makeEditor("hello", selection: NSRange(location: 0, length: 5))
        #expect(!tv.handleFormattingShortcut(keyEvent("b", modifiers: [.command, .option])))
        #expect(!tv.handleFormattingShortcut(keyEvent("b", modifiers: [.command, .shift])))
        #expect(tv.string == "hello")
    }

    @Test("the gate turns every shortcut off")
    func gateDisablesShortcuts() {
        let (tv, _) = makeEditor("hello", selection: NSRange(location: 0, length: 5)) {
            $0.formattingShortcutsEnabled = false
        }
        #expect(!tv.handleFormattingShortcut(keyEvent("b", modifiers: .command)))
        #expect(!tv.handleFormattingShortcut(keyEvent("i", modifiers: .command)))
        #expect(!tv.handleFormattingShortcut(keyEvent("e", modifiers: .command)))
        #expect(!tv.handleFormattingShortcut(keyEvent("k", modifiers: [.command, .shift])))
        #expect(tv.string == "hello")
    }

    @Test("read-only editors don't consume the keys")
    func readOnlyPassesThrough() {
        let (tv, _) = makeEditor("hello", selection: NSRange(location: 0, length: 5))
        tv.isEditable = false
        #expect(!tv.handleFormattingShortcut(keyEvent("b", modifiers: .command)))
        #expect(tv.string == "hello")
    }

    @Test("shortcuts default on")
    func defaultsOn() {
        #expect(MarkdownEditorConfiguration.default.formattingShortcutsEnabled)
    }
}
