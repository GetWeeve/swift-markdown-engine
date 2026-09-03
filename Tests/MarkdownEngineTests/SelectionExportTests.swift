//
//  SelectionExportTests.swift
//  MarkdownEngineTests
//
//  A drag writes the selection to its own pasteboard, so it never passes
//  through `copy(_:)` and nothing watching `NSPasteboard.general` can clean up
//  after it. It asks for one type at a time through
//  `writeSelection(to:type:)` — the seam it shares with the services menu —
//  and a text view offers plain text and RTF, so BOTH have to come from the
//  writer rather than from the styled raw-markdown storage.
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
        pasteboard.declareTypes([.string, .rtf], owner: nil)
        return pasteboard
    }

    /// The types a drag actually asks for, which is what the override has to
    /// cover. A text view answers with its LEGACY names, so this is also the
    /// guard against matching only the UTIs and handing every real drag back
    /// to AppKit. (RTFD, the one flavor left to AppKit, appears only once the
    /// selection carries an attachment.)
    @Test("every flavor a dragged selection offers is one the writer derives")
    func everyOfferedFlavorIsDerived() {
        let offered = editor(document).writablePasteboardTypes
        #expect(offered.isEmpty == false)
        for type in offered {
            #expect(
                MarkdownPasteboardWriter.flavor(for: type) != nil,
                "\(type.rawValue) would fall back to AppKit's own serialization"
            )
        }
    }

    @Test("the legacy names are the same two flavors as the UTIs")
    func legacyNamesMapToTheSameFlavors() {
        #expect(MarkdownPasteboardWriter.flavor(for: MarkdownPasteboardWriter.legacyStringType) == .text)
        #expect(MarkdownPasteboardWriter.flavor(for: .string) == .text)
        #expect(MarkdownPasteboardWriter.flavor(for: MarkdownPasteboardWriter.legacyRTFType) == .rtf)
        #expect(MarkdownPasteboardWriter.flavor(for: .rtf) == .rtf)
    }

    @Test("the text a drag writes has the invisible span omitted")
    func dragOmitsInvisibleSpanFromText() {
        let board = pasteboard("dev.markdownengine.tests.drag")
        #expect(editor(document).writeSelection(to: board, type: .string))
        #expect(board.string(forType: .string) == "- shipped the deck")
    }

    /// The flavor a rich-text app takes on a drop, asked for by the name a
    /// text view actually offers. It used to come straight from the styled
    /// storage, where the marker's characters still live.
    @Test("the RTF a drag writes has the invisible span omitted")
    func dragOmitsInvisibleSpanFromRTF() throws {
        let board = pasteboard("dev.markdownengine.tests.drag.rtf")
        #expect(editor(document).writeSelection(to: board, type: MarkdownPasteboardWriter.legacyRTFType))
        let rtf = try #require(board.data(forType: .rtf))
        let text = try #require(NSAttributedString(rtf: rtf, documentAttributes: nil)?.string)
        #expect(text.contains("shipped the deck"))
        #expect(text.contains("t=1284.3") == false)
        #expect(text.contains("[t=") == false)
    }

    @Test("a selection with no extension construct in it is written verbatim")
    func dragWritesPlainSelectionVerbatim() {
        let markdown = "- shipped the deck"
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

    /// A type we derive nothing for — RTFD, so a dragged attachment stays an
    /// attachment — is AppKit's to serialize.
    @Test("RTFD is left to AppKit")
    func rtfdIsLeftToAppKit() {
        #expect(MarkdownPasteboardWriter.flavor(for: .rtfd) == nil)
        #expect(MarkdownPasteboardWriter.flavor(for: NSPasteboard.PasteboardType("NeXT RTFD pasteboard type")) == nil)
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

    /// Records the copy without writing anything, so the assertion costs the
    /// general pasteboard nothing. A plain `NSTextView`, because
    /// `NativeTextView` is final: what is under test is AppKit's routing, and
    /// `NativeTextView` has no `cut(_:)` of its own to change it.
    private final class CopyRecorder: NSTextView {
        var copies = 0
        override func copy(_: Any?) { copies += 1 }
    }

    @Test("cut is served by the copy override, so it needs none of its own")
    func cutRoutesThroughCopy() {
        _ = NSApplication.shared
        let textView = CopyRecorder(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.string = document
        textView.setSelectedRange(NSRange(location: 0, length: (document as NSString).length))
        textView.cut(nil)
        #expect(textView.copies == 1)
    }
}
