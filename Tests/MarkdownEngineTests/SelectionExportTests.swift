//
//  SelectionExportTests.swift
//  MarkdownEngineTests
//
//  A drag writes the selection to its own pasteboard, so it never passes
//  through `copy(_:)` and nothing watching `NSPasteboard.general` can clean up
//  after it. `writeSelection(to:type:)` is the seam it shares with the
//  services menu, and it is where the text flavor of a selection gets the same
//  treatment a copy gets.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Selection export")
struct SelectionExportTests {

    private let document = "- shipped the deck [t=1284.3-1291.7]"

    /// A control laid out as an inline box, like Weeve's `[t=…]` citation
    /// marker: no glyphs on screen, and nothing to carry out of the app.
    private struct OmittedExtension: MarkdownExtension {
        var id: String { "omitted" }
        var inline: InlineSyntax? {
            InlineSyntax(open: "[t=", close: "]", parsesContent: false, inlineBoxWidth: 20)
        }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML _: String) -> String { "" }
        func plainText(source _: String, childrenText _: String) -> String { "" }
    }

    private func editor(_ text: String) -> NativeTextView {
        _ = NSApplication.shared
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configuration.extensions = [OmittedExtension()]
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        return textView
    }

    private func pasteboard(_ name: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        return pasteboard
    }

    @Test("the text a drag writes has the invisible span omitted")
    func dragOmitsInvisibleSpan() {
        let board = pasteboard("dev.markdownengine.tests.drag")
        #expect(editor(document).writeSelection(to: board, type: .string))
        #expect(board.string(forType: .string) == "- shipped the deck")
    }

    @Test("a selection with no extension construct in it is written verbatim")
    func dragWritesPlainSelectionVerbatim() {
        let markdown = "- shipped the **deck**"
        let board = pasteboard("dev.markdownengine.tests.drag.verbatim")
        #expect(editor(markdown).writeSelection(to: board, type: .string))
        #expect(board.string(forType: .string) == markdown)
    }

    @Test("an empty selection is left to AppKit")
    func emptySelectionFallsBackToAppKit() {
        let textView = editor(document)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let board = pasteboard("dev.markdownengine.tests.drag.empty")
        _ = textView.writeSelection(to: board, type: .string)
        #expect(board.string(forType: .string)?.contains("[t=") != true)
    }

    /// The one assumption the fix rests on: AppKit's multi-type entry point,
    /// which is what the drag path calls, writes each type through the
    /// single-type one this module overrides.
    @Test("the multi-type entry point routes through the single-type one")
    func multiTypeEntryPointRoutesThroughSingleType() {
        let board = pasteboard("dev.markdownengine.tests.drag.types")
        #expect(editor(document).writeSelection(to: board, types: [.string]))
        #expect(board.string(forType: .string) == "- shipped the deck")
    }
}
