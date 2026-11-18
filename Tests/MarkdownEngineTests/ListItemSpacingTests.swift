import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
struct ListItemSpacingTests {
    @Test(arguments: [nil, 0, 6] as [CGFloat?])
    func spacingAppliesOnlyBetweenConsecutiveItems(_ spacing: CGFloat?) throws {
        let text = "- apple\n  1. pear\n- [x] peach\n\n- plum"
        let font = NSFont.systemFont(ofSize: 16)
        let config = MarkdownEditorConfiguration(lists: ListStyle(itemSpacing: spacing))
        let attrs = MarkdownASTStyler.styleAttributes(text: text, fontName: font.fontName, fontSize: font.pointSize,
                                                      configuration: config)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let baseSpacing = ceil(lineHeight * config.paragraph.spacingFactor)
        for (word, expected) in [("apple", spacing ?? baseSpacing), ("pear", spacing ?? baseSpacing),
                                 ("peach", baseSpacing), ("plum", baseSpacing)] {
            let location = (text as NSString).range(of: word).location
            let style = try #require(attrs.compactMap { range, attributes in
                NSLocationInRange(location, range) ? attributes[.paragraphStyle] as? NSParagraphStyle : nil
            }.last)
            #expect(style.paragraphSpacing == expected)
            #expect(style.minimumLineHeight == lineHeight + config.lists.extraLineHeight)
            #expect(style.lineSpacing == 0)
        }
    }
    @Test func multiLinePasteUpdatesThePreviousListItem() throws {
        let original = "- first\nTail"
        let coordinator = NativeTextViewCoordinator(text: .constant(original), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil)
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let config = MarkdownEditorConfiguration(lists: ListStyle(itemSpacing: 6, adjacentParagraphSpacing: 20))
        coordinator.configuration = config
        view.configuration = config
        view.delegate = coordinator
        coordinator.textView = view
        coordinator.rebuildTextStorageAndStyle(view, from: original)
        coordinator.lastSyncedText = original
        coordinator.lastComputedStorage = original
        coordinator.previousDisplayLength = original.utf16.count
        #expect(try style("first", in: view).paragraphSpacing == 20)

        let insertion = (original as NSString).range(of: "Tail").location
        let list = "- second\n- third\n- fourth\n"
        view.insertText(list, replacementRange: NSRange(location: insertion, length: 0))
        let pasted = view.string
        #expect(pasted == "- first\n" + list + "Tail")
        let words = ["first", "second", "third", "fourth"]
        let incremental = try words.map { try style($0, in: view).paragraphSpacing }
        #expect(incremental == [6, 6, 6, 20])
        coordinator.rebuildTextStorageAndStyle(view, from: pasted)
        #expect(try words.map { try style($0, in: view).paragraphSpacing } == incremental)
        view.insertText("", replacementRange: (pasted as NSString).range(of: list))
        #expect(view.string == original)
        #expect(try style("first", in: view).paragraphSpacing == 20)
    }

    @Test func mountedEditorAdoptsSpacingAndRestoresInheritedMetrics() throws {
        _ = NSApplication.shared
        let text = "Intro\n- first\n- last\nTail\n\n- solo"
        func wrapper(item: CGFloat?, adjacent: CGFloat?) -> NativeTextViewWrapper {
            NativeTextViewWrapper(text: .constant(text),
                configuration: MarkdownEditorConfiguration(lists: ListStyle(itemSpacing: item, adjacentParagraphSpacing: adjacent)),
                documentId: "spacing-fixture", isEditable: false)
        }
        let host = NSHostingView(rootView: wrapper(item: nil, adjacent: nil))
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 400, 200), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        func nativeView(_ node: NSView) -> NativeTextView? {
            if let v = node as? NativeTextView { return v }
            return node.subviews.lazy.compactMap { nativeView($0) }.first
        }
        let view = try #require(nativeView(host))
        let initial = try style("first", in: view).paragraphSpacing
        for (item, adjacent) in [(CGFloat(6), CGFloat(20)), (nil, nil)] as [(CGFloat?, CGFloat?)] {
            host.rootView = wrapper(item: item, adjacent: adjacent)
            host.layoutSubtreeIfNeeded()
            #expect(try style("first", in: view).paragraphSpacingBefore == (adjacent ?? 0))
            #expect(try style("first", in: view).paragraphSpacing == (item ?? initial))
            #expect(try style("last", in: view).paragraphSpacing == (adjacent ?? initial))
            #expect(try style("solo", in: view).paragraphSpacingBefore == 0)
            #expect(try style("solo", in: view).paragraphSpacing == initial)
            #expect(nativeView(host) === view)
        }
    }

    private func style(_ word: String, in view: NativeTextView) throws -> NSParagraphStyle {
        let position = (view.string as NSString).range(of: word)
        try #require(position.location != NSNotFound)
        return try #require(view.textStorage?.attribute(.paragraphStyle, at: position.location, effectiveRange: nil) as? NSParagraphStyle)
    }
}
