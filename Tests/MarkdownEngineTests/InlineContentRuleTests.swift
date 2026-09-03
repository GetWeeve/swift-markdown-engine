//
//  InlineContentRuleTests.swift
//  MarkdownEngineTests
//
//  `InlineSyntax.contentRule`: the acceptance test an extension applies to a
//  candidate span's content. Delimiters alone can be looser than the construct
//  they stand for — `[t=` … `]` matches `[t=hello]` as readily as
//  `[t=12.0-19.5]` — and a span the extension cannot render must stay literal
//  text rather than be claimed and then drawn as nothing.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

/// `12.0-19.5`: a number, a hyphen, a number, and nothing else. Spelled out
/// rather than left to `Double(_:)`, which happily reads `1284.`, `1e3` and
/// `inf` — exactly the near-misses a rule is here to turn away.
private func isTimeRange(_ content: String) -> Bool {
    func isNumber(_ text: Substring) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ $0.isEmpty == false }) else { return false }
        return text.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
    }
    let bounds = content.split(separator: "-", omittingEmptySubsequences: false)
    return bounds.count == 2 && bounds.allSatisfy(isNumber)
}

@Suite("Inline content rules")
struct InlineContentRuleTests {

    private func r(_ location: Int, _ length: Int) -> NSRange {
        NSRange(location: location, length: length)
    }

    /// A citation-shaped span, narrowed to the time ranges an embedder could
    /// actually resolve: a number, a hyphen, a number.
    private struct TimeSpanExtension: MarkdownExtension {
        var ruleID: String = "time-range"
        var boxWidth: CGFloat?

        var id: String { "time-span" }
        var inline: InlineSyntax? {
            InlineSyntax(
                open: "[t=",
                close: "]",
                parsesContent: false,
                inlineBoxWidth: boxWidth,
                contentRule: InlineContentRule(id: ruleID, accepts: isTimeRange)
            )
        }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML _: String) -> String { "" }
    }

    /// The same syntax with no rule, so the difference under test is the knob.
    private struct UnnarrowedExtension: MarkdownExtension {
        var boxWidth: CGFloat?

        var id: String { "time-span" }
        var inline: InlineSyntax? {
            InlineSyntax(open: "[t=", close: "]", parsesContent: false, inlineBoxWidth: boxWidth)
        }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML _: String) -> String { "" }
    }

    private func parse(_ text: String, _ extensions: [any MarkdownExtension]) -> [InlineNode] {
        InlineParser.parse(text, registry: ExtensionRegistry(extensions: extensions))
    }

    /// A span node for an opaque extension: `parsesContent: false`, so the
    /// content is not re-parsed and the node has no children.
    private func span(_ id: String, at location: Int, open: Int, content: Int) -> InlineNode {
        .ext(ExtensionInlineNode(
            extensionID: id,
            range: r(location, open + content + 1),
            contentRange: r(location + open, content),
            markers: [r(location, open), r(location + open + content, 1)],
            children: []
        ))
    }

    /// Extension ids of every span in `text`, in document order.
    private func claimedIDs(_ text: String, _ extensions: [any MarkdownExtension]) -> [String] {
        parse(text, extensions).compactMap { node in
            guard case .ext(let span) = node else { return nil }
            return span.extensionID
        }
    }

    // MARK: - Acceptance

    @Test("a candidate the rule accepts parses as an extension span")
    func acceptedCandidateIsClaimed() {
        #expect(parse("[t=12.0-19.5]", [TimeSpanExtension()]) == [
            span("time-span", at: 0, open: 3, content: 9),
        ])
    }

    @Test("a candidate the rule rejects stays literal text")
    func rejectedCandidateStaysLiteral() {
        #expect(parse("[t=hello]", [TimeSpanExtension()]) == [.text(r(0, 9))])
    }

    @Test("a malformed time range is rejected, not claimed and blanked")
    func malformedRangeStaysLiteral() {
        // The shape a mangled marker takes: still nothing but digits, dots and
        // a hyphen, so only the construct's own grammar can tell it apart.
        #expect(parse("[t=1284.-1291.7]", [TimeSpanExtension()]) == [.text(r(0, 16))])
    }

    @Test("without a rule the delimiters claim every span they match")
    func noRuleClaimsEverything() {
        // Pins the pre-`contentRule` behavior: the knob is opt-in, and an
        // extension that does not set it parses exactly as before.
        #expect(claimedIDs("[t=hello]", [UnnarrowedExtension()]) == ["time-span"])
    }

    // MARK: - What the rule is given

    @Test("the rule is given the content, without the delimiters")
    func ruleSeesContentOnly() {
        struct ExactExtension: MarkdownExtension {
            var id: String { "exact" }
            var inline: InlineSyntax? {
                InlineSyntax(
                    open: "[t=",
                    close: "]",
                    parsesContent: false,
                    contentRule: InlineContentRule(id: "exactly-ok") { $0 == "ok" }
                )
            }

            func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
            func html(childrenHTML _: String) -> String { "" }
        }
        // A rule testing for equality with "ok" is the proof: it sees neither
        // the opener, nor the closer, nor a character beyond them.
        #expect(claimedIDs("[t=ok]", [ExactExtension()]) == ["exact"])
        #expect(claimedIDs("[t=ok ]", [ExactExtension()]) == [])
        #expect(claimedIDs("[t= ok]", [ExactExtension()]) == [])
    }

    @Test("an empty span is rejected before the rule is consulted")
    func emptyContentNeverReachesTheRule() {
        struct AcceptsEverything: MarkdownExtension {
            var id: String { "everything" }
            var inline: InlineSyntax? {
                InlineSyntax(
                    open: "[t=",
                    close: "]",
                    parsesContent: false,
                    contentRule: InlineContentRule(id: "yes") { _ in true }
                )
            }

            func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
            func html(childrenHTML _: String) -> String { "" }
        }
        // `requiresNonEmptyContent` still decides `[t=]`, so a rule never has
        // to defend against an empty string.
        #expect(claimedIDs("[t=]", [AcceptsEverything()]) == [])
    }

    // MARK: - Rejection is a fall-through, not an end of scanning

    @Test("a rejected candidate falls through to the next registered extension")
    func rejectionFallsThroughToTheNextExtension() {
        struct Sibling: MarkdownExtension {
            var id: String { "sibling" }
            var inline: InlineSyntax? { InlineSyntax(open: "[t=", close: "]", parsesContent: false) }
            func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
            func html(childrenHTML _: String) -> String { "" }
        }
        // Registration order is precedence: the narrowed extension declines and
        // the one behind it gets its chance, the same way a built-in that
        // matches and fails falls through to the extensions.
        #expect(claimedIDs("[t=hello]", [TimeSpanExtension(), Sibling()]) == ["sibling"])
        #expect(claimedIDs("[t=12.0-19.5]", [TimeSpanExtension(), Sibling()]) == ["time-span"])
    }

    @Test("a real span later in the line is still found after a rejected one")
    func scanningContinuesPastARejectedCandidate() {
        #expect(parse("[t=hello] and [t=12.0-19.5]", [TimeSpanExtension()]) == [
            .text(r(0, 14)),
            span("time-span", at: 14, open: 3, content: 9),
        ])
    }

    @Test("a rejected candidate does not swallow the real span nested in it")
    func rejectionExposesANestedCandidate() {
        // The closer is the FIRST `]`, so the outer candidate's content is
        // `[t=12.0-19.5`. Rejecting it lets the scan reach the inner opener.
        #expect(parse("[t=[t=12.0-19.5]", [TimeSpanExtension()]) == [
            .text(r(0, 3)),
            span("time-span", at: 3, open: 3, content: 9),
        ])
    }

    // MARK: - The symptom the rule exists to prevent

    @Test("a rejected span keeps its own glyphs, with no box space reserved")
    func rejectedSpanReservesNoSpace() {
        // The bug: a 20pt box over `[t=hello]` collapsed nine characters the
        // reader had typed into blank line space, still saved but invisible.
        let document = "- Ask about [t=hello] before Friday"
        let start = (document as NSString).range(of: "[t=").location
        let narrowed = attributes(document, extensions: [TimeSpanExtension(boxWidth: 20)])

        // No space reserved on the opener, and no glyph collapsed to nothing.
        #expect(effective(.kern, in: narrowed, at: start) == nil)
        #expect(effective(.font, in: narrowed, at: start) == nil)
        #expect((effective(.foregroundColor, in: narrowed, at: start + 4) as? NSColor) != .clear)

        // Stronger: the styling over the whole candidate is what the document
        // gets with no extension registered at all. `[t=hello]` is ordinary
        // bracketed prose, and the engine's own incomplete-link ink is right
        // for it — the extension declined, so it left nothing behind.
        #expect(
            snapshot(narrowed, over: NSRange(location: start, length: 9))
                == snapshot(attributes(document, extensions: []), over: NSRange(location: start, length: 9))
        )

        // Same document, same box, no rule: the span is claimed and blanked.
        let unnarrowed = attributes(document, extensions: [UnnarrowedExtension(boxWidth: 20)])
        #expect(effective(.kern, in: unnarrowed, at: start) != nil)
        #expect((effective(.foregroundColor, in: unnarrowed, at: start + 4) as? NSColor) == .clear)
    }

    // MARK: - Cache keying

    @Test("registries differing only in the rule parse under distinct keys")
    func fingerprintCoversTheRule() {
        let narrowed = ExtensionRegistry(extensions: [TimeSpanExtension()])
        let unnarrowed = ExtensionRegistry(extensions: [UnnarrowedExtension()])
        let otherRule = ExtensionRegistry(extensions: [TimeSpanExtension(ruleID: "time-range-v2")])

        #expect(narrowed.fingerprint != unnarrowed.fingerprint)
        #expect(narrowed.fingerprint != otherRule.fingerprint)
        #expect(narrowed.fingerprint == ExtensionRegistry(extensions: [TimeSpanExtension()]).fingerprint)
    }

    @Test("two rules are the same rule when they carry the same id")
    func ruleIdentityIsTheId() {
        let one = InlineContentRule(id: "time-range") { _ in true }
        let sameID = InlineContentRule(id: "time-range") { _ in false }
        let otherID = InlineContentRule(id: "other") { _ in true }

        #expect(one == sameID)
        #expect(one != otherID)
    }

    // MARK: - Styling helpers

    private let base: CGFloat = 14
    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }

    private func attributes(_ text: String, extensions: [any MarkdownExtension]) -> [StyledRange] {
        var configuration = MarkdownEditorConfiguration.default
        configuration.extensions = extensions
        return MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: fontName,
            fontSize: base,
            caretLocation: 0,
            configuration: configuration
        )
    }

    /// Order-independent digest of the styled ranges touching `span`, so two
    /// style runs can be compared for equality over one construct.
    private func snapshot(_ ranges: [StyledRange], over span: NSRange) -> String {
        ranges
            .filter { NSIntersectionRange($0.range, span).length > 0 }
            .map { range, values in
                let keys = values.keys
                    .map { "\($0.rawValue)=\(String(describing: values[$0]!))" }
                    .sorted()
                return "\(range.location)+\(range.length):\(keys.joined(separator: ","))"
            }
            .sorted()
            .joined(separator: "\n")
    }

    /// Effective value of `key` at `position`: the last styled range wins, the
    /// same way the text storage applies them.
    private func effective(
        _ key: NSAttributedString.Key,
        in attrs: [StyledRange],
        at position: Int
    ) -> Any? {
        var result: Any?
        for (range, values) in attrs where NSLocationInRange(position, range) {
            if let value = values[key] { result = value }
        }
        return result
    }
}
