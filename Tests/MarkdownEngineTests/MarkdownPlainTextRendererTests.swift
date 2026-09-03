//
//  MarkdownPlainTextRendererTests.swift
//  MarkdownEngineTests
//
//  The text flavor of a copy is raw markdown, which is what a markdown
//  consumer wants — but a construct that is invisible on screen must not
//  become visible the moment the selection leaves the app. An extension
//  decides that for its own construct; everything else stays byte-exact.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Plain-text renderer")
struct MarkdownPlainTextRendererTests {

    /// A control laid out as an inline box, like Weeve's `[t=…]` citation
    /// marker: nothing to see on screen, nothing to carry out of the app.
    private struct OmittedExtension: MarkdownExtension {
        var id: String { "omitted" }
        var inline: InlineSyntax? {
            InlineSyntax(open: "[t=", close: "]", parsesContent: false, inlineBoxWidth: 20)
        }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML _: String) -> String { "" }
        func plainText(source _: String, childrenText _: String) -> String { "" }
    }

    /// Highlight-style span that says nothing about plain text, so the default
    /// applies and the construct copies exactly as it was written.
    private struct KeptExtension: MarkdownExtension {
        var id: String { "kept" }
        var inline: InlineSyntax? { InlineSyntax(open: "==", close: "==") }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML: String) -> String { "<mark>\(childrenHTML)</mark>" }
    }

    /// Rewrites its construct rather than omitting it, and reads its content
    /// through `childrenText`.
    private struct UnwrappingExtension: MarkdownExtension {
        var id: String { "unwrapping" }
        var inline: InlineSyntax? { InlineSyntax(open: "%%", close: "%%") }

        func contentAttributes(theme _: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML: String) -> String { childrenHTML }
        func plainText(source _: String, childrenText: String) -> String { childrenText }
    }

    private func plain(_ markdown: String, _ extensions: [any MarkdownExtension]) -> String {
        MarkdownPlainTextRenderer.plainText(from: markdown, extensions: extensions)
    }

    // MARK: Omitting

    @Test("an omitted span leaves the bullet and takes its separating space")
    func omitsSpanAndSeparator() {
        #expect(plain("- shipped the deck [t=1284.3-1291.7]", [OmittedExtension()])
            == "- shipped the deck")
    }

    @Test("an omitted span mid-sentence does not leave a double space")
    func omitsSpanMidSentence() {
        #expect(plain("said this [t=1.0-2.0] then that", [OmittedExtension()])
            == "said this then that")
    }

    @Test("indentation in front of an omitted span is kept")
    func keepsLeadingIndent() {
        #expect(plain("  [t=1.0-2.0] indented", [OmittedExtension()]) == "  indented")
    }

    @Test("every line of a multi-line selection is cleared")
    func omitsSpansOnEveryLine() {
        let notes = """
        ## Decisions

        - kept the deadline [t=10.0-12.0]
        - moved the review [t=20.0-22.5]

        Plain paragraph with one [t=30.0-31.0] inside it.
        """
        #expect(plain(notes, [OmittedExtension()]) == """
        ## Decisions

        - kept the deadline
        - moved the review

        Plain paragraph with one inside it.
        """)
    }

    @Test("a span inside a heading, a quote, and a task item is omitted too")
    func omitsSpansInEveryBlockForm() {
        #expect(plain("# Title [t=1.0-2.0]", [OmittedExtension()]) == "# Title")
        #expect(plain("> quoted [t=1.0-2.0]", [OmittedExtension()]) == "> quoted")
        #expect(plain("- [ ] task [t=1.0-2.0]", [OmittedExtension()]) == "- [ ] task")
    }

    @Test("a span inside bold copies out with the bold markers intact")
    func omitsSpanNestedInEmphasis() {
        #expect(plain("- **bold [t=1.0-2.0]** tail", [OmittedExtension()])
            == "- **bold** tail")
    }

    // MARK: Left alone

    @Test("with no extensions registered the markdown is returned unchanged")
    func noExtensionsCopiesVerbatim() {
        let markdown = "- shipped the deck [t=1284.3-1291.7]"
        #expect(plain(markdown, []) == markdown)
    }

    @Test("an extension that says nothing about plain text copies verbatim")
    func defaultKeepsConstructVerbatim() {
        #expect(plain("- an ==accent== span", [KeptExtension()]) == "- an ==accent== span")
    }

    @Test("the same syntax inside a code fence is left literal")
    func codeFenceIsLeftLiteral() {
        let markdown = """
        ```
        - shipped the deck [t=1284.3-1291.7]
        ```
        """
        #expect(plain(markdown, [OmittedExtension()]) == markdown)
    }

    @Test("inline code carrying the syntax is left literal")
    func inlineCodeIsLeftLiteral() {
        #expect(plain("- the marker is `[t=1.0-2.0]`", [OmittedExtension()])
            == "- the marker is `[t=1.0-2.0]`")
    }

    @Test("a construct the registry does not know stays literal")
    func unregisteredSyntaxStaysLiteral() {
        #expect(plain("- shipped the deck [t=1.0-2.0]", [KeptExtension()])
            == "- shipped the deck [t=1.0-2.0]")
    }

    // MARK: Rewriting

    @Test("an extension can rewrite its construct instead of omitting it")
    func rewritesConstructFromChildren() {
        #expect(plain("- a %%comment%% here", [UnwrappingExtension()]) == "- a comment here")
    }

    @Test("a rewritten construct resolves the extensions inside it")
    func rewriteResolvesNestedConstructs() {
        #expect(plain("- a %%comment [t=1.0-2.0]%% here", [UnwrappingExtension(), OmittedExtension()])
            == "- a comment here")
    }
}
