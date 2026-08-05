//
//  TaskShorthandTests.swift
//  MarkdownEngine
//
//  ListStyle.taskShorthandEnabled: typing a space when the line so far reads
//  `[]`, `[ ]`, or `- []` rewrites that prefix into an unchecked `- [ ] `
//  task item. These pin the trigger set, indent/suffix preservation, and —
//  just as important — everything that must stay inert: the default-off
//  configuration, code blocks, mid-line brackets, checked markers, and
//  selection-replacing spaces.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Task checkbox shorthand")
struct TaskShorthandTests {

    private func makeEditor(text: String, shorthandEnabled: Bool = true, helpersEnabled: Bool = true) -> NativeTextView {
        _ = NSApplication.shared
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.isEditable = true
        textView.configuration = MarkdownEditorConfiguration(
            lists: ListStyle(
                helpersEnabled: helpersEnabled,
                taskShorthandEnabled: shorthandEnabled
            )
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

    private func typeSpace(_ tv: NativeTextView, at location: Int) {
        tv.setSelectedRange(NSRange(location: location, length: 0))
        tv.insertText(" ", replacementRange: NSRange(location: location, length: 0))
    }

    // MARK: - Conversions

    @Test func spaceConvertsBareBrackets() {
        let tv = makeEditor(text: "[]")
        typeSpace(tv, at: 2)
        #expect(tv.string == "- [ ] ")
        #expect(tv.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test func spaceConvertsSpacedBrackets() {
        let tv = makeEditor(text: "[ ]")
        typeSpace(tv, at: 3)
        #expect(tv.string == "- [ ] ")
        #expect(tv.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test func spaceConvertsDashBrackets() {
        let tv = makeEditor(text: "- []")
        typeSpace(tv, at: 4)
        #expect(tv.string == "- [ ] ")
        #expect(tv.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test func indentIsPreserved() {
        let tv = makeEditor(text: "\t[]")
        typeSpace(tv, at: 3)
        #expect(tv.string == "\t- [ ] ")
    }

    @Test func conversionOnLaterLineKeepsDocument() {
        let tv = makeEditor(text: "first note\n[]")
        typeSpace(tv, at: 13)
        #expect(tv.string == "first note\n- [ ] ")
    }

    @Test func textAfterCaretIsKept() {
        // Only the prefix BEFORE the caret converts; the rest of the line
        // becomes the task's text (matches the retired editors).
        let tv = makeEditor(text: "[]read more")
        typeSpace(tv, at: 2)
        #expect(tv.string == "- [ ] read more")
        #expect(tv.selectedRange() == NSRange(location: 6, length: 0))
    }

    // MARK: - Inert cases

    @Test func offByDefaultKeepsLiteralSpace() {
        let tv = makeEditor(text: "[]", shorthandEnabled: false)
        typeSpace(tv, at: 2)
        #expect(tv.string == "[] ")
    }

    @Test func disabledHelpersKeepLiteralSpace() {
        let tv = makeEditor(text: "[]", helpersEnabled: false)
        typeSpace(tv, at: 2)
        #expect(tv.string == "[] ")
    }

    @Test func midLineBracketsStayText() {
        let tv = makeEditor(text: "see []")
        typeSpace(tv, at: 6)
        #expect(tv.string == "see [] ")
    }

    @Test func checkedMarkerStaysText() {
        let tv = makeEditor(text: "[x]")
        typeSpace(tv, at: 3)
        #expect(tv.string == "[x] ")
    }

    @Test func existingTaskMarkerIsNotRewritten() {
        let tv = makeEditor(text: "- [ ]")
        typeSpace(tv, at: 5)
        #expect(tv.string == "- [ ] ")
    }

    @Test func insideCodeFenceStaysLiteral() {
        let tv = makeEditor(text: "```\n[]\n```")
        typeSpace(tv, at: 6)
        #expect(tv.string == "```\n[] \n```")
    }

    @Test func selectionReplacingSpaceStaysLiteral() {
        let tv = makeEditor(text: "[]x")
        tv.setSelectedRange(NSRange(location: 2, length: 1))
        tv.insertText(" ", replacementRange: NSRange(location: 2, length: 1))
        #expect(tv.string == "[] ")
    }
}
