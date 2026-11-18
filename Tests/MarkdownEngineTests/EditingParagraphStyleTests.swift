import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
struct EditingParagraphStyleTests {
    @Test("Focused prose follows a collapsed caret and keeps the source and other block styles")
    func focusedParagraphInk() throws {
        _ = NSApplication.shared
        let source = "First paragraph\nSecond with **bold**\n- List item\n# Heading"
        let coordinator = NativeTextViewCoordinator(
            text: .constant(source), fontName: "Helvetica", fontSize: 13,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        var config = MarkdownEditorConfiguration.default
        config.theme.bodyText = .black
        config.theme.editingParagraphText = .gray
        config.paragraph.centersExtraLineHeight = true
        config.paragraph.lineHeightExtraSpacing = 4
        config.lists.extraLineHeight = 6
        let view = NativeTextView(frame: CGRect(x: 0, y: 0, width: 360, height: 180))
        let panel = NSPanel(contentRect: view.frame, styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        defer { panel.close() }
        view.configuration = config
        coordinator.configuration = config
        view.isEditable = true
        view.delegate = coordinator
        coordinator.textView = view
        coordinator.rebuildTextStorageAndStyle(view, from: source)
        let storage = try #require(view.textStorage)
        let first = (source as NSString).range(of: "First")
        let second = (source as NSString).range(of: "Second")
        let item = (source as NSString).range(of: "List")
        func color(_ range: NSRange) -> NSColor? {
            storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
        }
        try #require(panel.makeFirstResponder(view))
        view.setSelectedRange(NSRange(location: second.location + 1, length: 0))
        #expect(color(first) == .black)
        #expect(color(second) == .gray)
        view.setSelectedRange(first)
        #expect(color(second) == .black)
        #expect(color(first) == .black)
        view.setSelectedRange(NSRange(location: first.location, length: 0))
        #expect(color(first) == .gray)
        try #require(panel.makeFirstResponder(nil))
        #expect(color(first) == .black)
        let bodyStyle = try #require(storage.attribute(.paragraphStyle, at: second.location, effectiveRange: nil) as? NSParagraphStyle)
        let itemStyle = try #require(storage.attribute(.paragraphStyle, at: item.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(bodyStyle.lineSpacing == 2)
        #expect(itemStyle.lineSpacing == 3)
        try #require(panel.makeFirstResponder(view))
        let insertion = NSRange(location: second.location + 1, length: 0)
        view.setSelectedRange(insertion)
        coordinator.rebuildTextStorageAndStyle(view, from: source, preservingSelection: true)
        #expect(view.selectedRange() == insertion && color(second) == .gray && color(first) == .black)
        coordinator.rebuildTextStorageAndStyle(view, from: source)
        let actualParagraph = try #require(view.editingParagraph)
        #expect(color(second) == (NSIntersectionRange(actualParagraph, second).length == 0 ? .black : .gray))
        #expect(view.string == source)
        view.setSelectedRange(insertion)
        #expect(color(second) == .gray)
        view.updateEditability(false)
        #expect(color(second) == .black)
        #expect(view.editingParagraph == nil)
    }
}
