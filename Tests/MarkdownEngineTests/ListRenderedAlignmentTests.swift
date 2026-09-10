import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
struct ListRenderedAlignmentTests {
    @Test(arguments: ["- ", "*   ", "1. ", "1.  ", "- [ ] ", "- [x] ", "-   [ ]  "])
    func firstLineMatchesWrappedLine(prefix: String) async throws {
        let text = prefix + "Prepare the pilot and review the next steps together before the meeting starts."
        let configuration = MarkdownEditorConfiguration(lists: ListStyle(indentPerLevel: 24, markerTextGap: 16, markerSlotWidth: 20))
        let font = NSFont.systemFont(ofSize: 16)
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        view.isRichText = true
        view.configuration = configuration
        view.baseFont = font
        view.string = text
        let storage = try #require(view.textStorage)
        storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))
        for (range, attributes) in MarkdownASTStyler.styleAttributes(text: text, fontName: font.fontName, fontSize: 16, configuration: configuration) {
            storage.addAttributes(attributes, range: range)
        }
        let manager = try #require(view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        var points: [CGFloat] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            for line in fragment.textLineFragments {
                let offset = points.isEmpty ? (prefix as NSString).length : line.characterRange.location
                // The caret at a kerned space's boundary bisects its advance.
                // Measure inside the first word and subtract its glyph width
                // to compare the actual text origin, not that caret position.
                let char = (text as NSString).substring(with: NSRange(location: offset, length: 1))
                let width = (char as NSString).size(withAttributes: [.font: font]).width
                points.append(line.locationForCharacter(at: offset + 1).x - width + line.typographicBounds.minX + fragment.layoutFragmentFrame.minX)
            }
            return true
        }
        #expect(points.count >= 2)
        if points.count >= 2 {
            #expect(abs(points[0] - points[1]) < 1, "\(prefix.debugDescription): \(points)")
        }
    }
}

struct ListPaddingParsingTests {
    @Test(arguments: ["- ", "*   ", "+    ", "1.  ", "2)   ", "-\t", "-   [ ]  ", "-   [x]   "])
    func separatesPaddingFromContent(prefix: String) throws {
        let text = prefix + "**Review** the proposal.\n"
        let block = try #require(DocumentAST.parse(text).first)
        guard case let .list(_, items) = block else {
            Issue.record("Expected a list item")
            return
        }
        let item = try #require(items.first)
        #expect((text as NSString).substring(with: item.contentRange) == "**Review** the proposal.")
        #expect(item.range == NSRange(location: 0, length: (text as NSString).length))
        #expect(item.indent == 0)
        #expect((item.checkbox != nil) == prefix.contains("["))
    }

    @Test func preservesNestedIndentAndWhitespaceInCode() throws {
        let text = "*   Parent\n    *   Child\n\n```text\n*   Keep source spaces\n```\n"
        let blocks = DocumentAST.parse(text)
        let list = try #require(blocks.first)
        guard case let .list(_, items) = list else { Issue.record("Expected list"); return }
        #expect(items.map(\.indent) == [0, 4])
        #expect(items.map { (text as NSString).substring(with: $0.contentRange) } == ["Parent", "Child"])
        #expect(blocks.contains { if case .codeBlock = $0 { return true }; return false })
    }
}
