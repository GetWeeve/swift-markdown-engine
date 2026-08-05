//
//  ListMarkerDeleteBackwardTests.swift
//  MarkdownEngineTests
//
//  Backspace at a list item's content origin removes the whole marker in one
//  step (tasks, bullets, ordered) so hidden `- [ ] ` never peels into raw
//  syntax or demotes to a bullet with a leftover `[`.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("List marker deleteBackward")
struct ListMarkerDeleteBackwardTests {

    private func makeEditor(
        text: String,
        helpersEnabled: Bool = true
    ) -> NativeTextView {
        _ = NSApplication.shared
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.isEditable = true
        textView.configuration = MarkdownEditorConfiguration(
            lists: ListStyle(helpersEnabled: helpersEnabled)
        )
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text),
            fontName: "SF Pro Text",
            fontSize: 14,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.string = text
        coordinator.lastSyncedText = text
        coordinator.lastComputedStorage = text
        coordinator.previousDisplayLength = (text as NSString).length
        return textView
    }

    private func backspace(_ tv: NativeTextView, at location: Int) -> Bool {
        tv.setSelectedRange(NSRange(location: location, length: 0))
        return MarkdownLists.handleDeleteBackward(textView: tv)
    }

    // MARK: - Empty task

    @Test("empty task backspace merges onto the previous line")
    func emptyTaskMergesToPreviousLine() {
        let tv = makeEditor(text: "None noted.\n- [ ] ")
        let caret = (tv.string as NSString).length
        #expect(backspace(tv, at: caret))
        #expect(tv.string == "None noted.")
        #expect(tv.selectedRange() == NSRange(location: ("None noted." as NSString).length, length: 0))
    }

    @Test("empty checked task backspace also removes the full marker")
    func emptyCheckedTaskMerges() {
        let tv = makeEditor(text: "prev\n- [x] ")
        #expect(backspace(tv, at: (tv.string as NSString).length))
        #expect(tv.string == "prev")
    }

    @Test("empty task at document start unwraps to an empty line")
    func emptyTaskAtDocumentStart() {
        let tv = makeEditor(text: "- [ ] ")
        #expect(backspace(tv, at: 6))
        #expect(tv.string == "")
        #expect(tv.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test("empty task between paragraphs keeps the following line")
    func emptyTaskBetweenParagraphs() {
        let tv = makeEditor(text: "A\n- [ ] \nB")
        // Caret at content origin of the empty task (after `- [ ] `).
        #expect(backspace(tv, at: 8))
        #expect(tv.string == "A\nB")
        #expect(tv.selectedRange() == NSRange(location: 1, length: 0))
    }

    // MARK: - Non-empty unwrap

    @Test("backspace at start of task content unwraps the marker")
    func nonEmptyTaskUnwraps() {
        let tv = makeEditor(text: "- [ ] Write something")
        #expect(backspace(tv, at: 6))
        #expect(tv.string == "Write something")
        #expect(tv.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test("backspace at start of bullet content unwraps the marker")
    func nonEmptyBulletUnwraps() {
        let tv = makeEditor(text: "- hello")
        #expect(backspace(tv, at: 2))
        #expect(tv.string == "hello")
    }

    @Test("backspace at start of ordered content unwraps the marker")
    func nonEmptyOrderedUnwraps() {
        let tv = makeEditor(text: "1. hello")
        #expect(backspace(tv, at: 3))
        #expect(tv.string == "hello")
    }

    // MARK: - Empty bullet / ordered (parity)

    @Test("empty bullet merges onto the previous line")
    func emptyBulletMerges() {
        let tv = makeEditor(text: "prev\n- ")
        #expect(backspace(tv, at: (tv.string as NSString).length))
        #expect(tv.string == "prev")
    }

    @Test("empty ordered merges onto the previous line")
    func emptyOrderedMerges() {
        let tv = makeEditor(text: "prev\n1. ")
        #expect(backspace(tv, at: (tv.string as NSString).length))
        #expect(tv.string == "prev")
    }

    // MARK: - Inert cases

    @Test("helpers off leaves deleteBackward to AppKit")
    func helpersOffIsInert() {
        let tv = makeEditor(text: "prev\n- [ ] ", helpersEnabled: false)
        #expect(!backspace(tv, at: (tv.string as NSString).length))
        #expect(tv.string == "prev\n- [ ] ")
    }

    @Test("mid-marker caret does not consume the keystroke")
    func midMarkerIsInert() {
        let tv = makeEditor(text: "- [ ] ")
        #expect(!backspace(tv, at: 3))
        #expect(tv.string == "- [ ] ")
    }

    @Test("caret after content deletes normally")
    func afterContentIsInert() {
        let tv = makeEditor(text: "- [ ] hi")
        #expect(!backspace(tv, at: 8))
        #expect(tv.string == "- [ ] hi")
    }

    @Test("selection is inert")
    func selectionIsInert() {
        let tv = makeEditor(text: "- [ ] ")
        tv.setSelectedRange(NSRange(location: 2, length: 2))
        #expect(!MarkdownLists.handleDeleteBackward(textView: tv))
    }

    @Test("inside a code fence is inert")
    func codeFenceIsInert() {
        let tv = makeEditor(text: "```\n- [ ] \n```")
        #expect(!backspace(tv, at: 10))
        #expect(tv.string == "```\n- [ ] \n```")
    }

    @Test("character-by-character peel never appears after one backspace")
    func noPartialMarkerLeftBehind() {
        let tv = makeEditor(text: "None noted.\n- [ ] ")
        #expect(backspace(tv, at: (tv.string as NSString).length))
        #expect(!tv.string.contains("["))
        #expect(!tv.string.contains("]"))
        #expect(!tv.string.contains("- "))
    }
}
