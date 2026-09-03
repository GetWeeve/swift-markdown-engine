//
//  MarkdownPlainTextRenderer.swift
//  MarkdownEngine
//
//  The plain-text counterpart of `MarkdownHTMLRenderer`. A copy keeps the raw
//  markdown of the selection as its text flavor, which is what a markdown
//  consumer wants — but a construct that has no glyphs on screen (a control
//  laid out as an inline box, a comment) would carry its own delimiters out of
//  the app inside that flavor. So this walks the same AST the HTML renderer
//  walks and replaces every registered extension's construct with the form the
//  extension asks for in `plainText(source:childrenText:)`.
//
//  Everything else is copied verbatim: markdown outside an extension construct
//  comes back byte-exact, which is what the private raw-markdown flavor needs
//  in order to round-trip a paste between our own editors.
//

import Foundation

public enum MarkdownPlainTextRenderer {

    /// `markdown` with each registered extension's constructs replaced by its
    /// `plainText(source:childrenText:)` form. An unregistered extension's
    /// syntax stays literal, as it does everywhere else in the engine.
    public static func plainText(from markdown: String, extensions: [any MarkdownExtension] = []) -> String {
        guard extensions.isEmpty == false else { return markdown }
        let env = Env(ns: markdown as NSString,
                      byID: {
                          var out: [String: any MarkdownExtension] = [:]
                          for ext in extensions { out[ext.id] = ext }
                          return out
                      }())
        var edits: [Edit] = []
        for block in DocumentAST.parse(markdown, registry: ExtensionRegistry(extensions: extensions)) {
            collect(block, env: env, into: &edits)
        }
        guard edits.isEmpty == false else { return markdown }
        return applying(edits, to: markdown)
    }

    /// The document and the extension lookup, threaded through the walk — the
    /// same shape `MarkdownHTMLRenderer` threads through its own.
    private struct Env {
        let ns: NSString
        let byID: [String: any MarkdownExtension]
    }

    /// One extension construct and what takes its place. Ranges are absolute
    /// in the document being rendered.
    private struct Edit {
        let range: NSRange
        let text: String
    }

    // MARK: - Blocks

    private static func collect(_ node: BlockNode, env: Env, into edits: inout [Edit]) {
        switch node {
        case .paragraph(_, let inlines),
             .heading(_, _, _, let inlines),
             .blockquote(_, let inlines):
            collect(inlines, env: env, into: &edits)

        case .list(_, let items):
            for item in items {
                collect(item.inlines, env: env, into: &edits)
            }

        case .ext(let node):
            guard let edit = edit(forExtension: node.extensionID, range: node.range,
                                  contentRange: node.contentRange, children: node.inlines, env: env)
            else {
                // Kept verbatim, so the constructs inside it still get a say.
                collect(node.inlines, env: env, into: &edits)
                return
            }
            edits.append(edit)

        // Nothing an extension can claim: code, formulas, and tables are
        // opaque to the inline parser, and the rest carries no inlines.
        case .codeBlock, .blockLatex, .table, .thematicBreak, .blank:
            return
        }
    }

    // MARK: - Inlines

    private static func collect(_ nodes: [InlineNode], env: Env, into edits: inout [Edit]) {
        for node in nodes {
            switch node {
            case .emphasis(_, _, _, let children), .link(_, _, _, _, let children):
                collect(children, env: env, into: &edits)

            case .ext(let node):
                guard let edit = edit(forExtension: node.extensionID, range: node.range,
                                      contentRange: node.contentRange, children: node.children, env: env)
                else {
                    collect(node.children, env: env, into: &edits)
                    continue
                }
                edits.append(edit)

            case .text, .code, .image, .wikiLink, .imageEmbed, .inlineLatex, .escape:
                continue
            }
        }
    }

    /// What replaces one extension construct, or nil when the construct stays
    /// as written — because its extension is not registered, or because its
    /// `plainText` handed back the source it was given. A nil is the caller's
    /// cue to walk into the construct instead of replacing it.
    private static func edit(forExtension id: String, range: NSRange, contentRange: NSRange,
                             children: [InlineNode], env: Env) -> Edit? {
        guard let ext = env.byID[id] else { return nil }
        let source = env.ns.substring(with: range)
        let replacement = ext.plainText(
            source: source,
            childrenText: content(children, over: contentRange, env: env)
        )
        guard replacement != source else { return nil }
        return Edit(range: range, text: replacement)
    }

    /// A construct's content with the constructs nested inside it already
    /// resolved, which is what an extension is handed as `childrenText`.
    private static func content(_ children: [InlineNode], over range: NSRange, env: Env) -> String {
        let source = env.ns.substring(with: range)
        guard children.isEmpty == false else { return source }
        var nested: [Edit] = []
        collect(children, env: env, into: &nested)
        // Children sit inside `range`, so shifting their ranges puts them in
        // the coordinate space of the content substring.
        return applying(
            nested.map { Edit(range: NSRange(location: $0.range.location - range.location,
                                             length: $0.range.length), text: $0.text) },
            to: source
        )
    }

    // MARK: - Splicing

    /// `source` with every edit applied, back to front so the ranges of the
    /// edits still to come stay valid.
    private static func applying(_ edits: [Edit], to source: String) -> String {
        let out = NSMutableString(string: source)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            out.replaceCharacters(in: spliceRange(for: edit, in: out), with: edit.text)
        }
        return out as String
    }

    /// An omitted construct takes the horizontal whitespace that separated it
    /// from the text with it, so omitting it leaves neither a double space nor
    /// a space dangling at the end of a line. That separator is the whitespace
    /// in front of the construct, except at the start of a line, where the
    /// whitespace in front is the line's indentation and the separator is the
    /// whitespace after it instead.
    private static func spliceRange(for edit: Edit, in text: NSString) -> NSRange {
        guard edit.text.isEmpty else { return edit.range }
        var start = edit.range.location
        while start > 0, isHorizontalWhitespace(text.character(at: start - 1)) { start -= 1 }
        if start < edit.range.location, start > 0, isLineBreak(text.character(at: start - 1)) == false {
            return NSRange(location: start, length: NSMaxRange(edit.range) - start)
        }
        var end = NSMaxRange(edit.range)
        while end < text.length, isHorizontalWhitespace(text.character(at: end)) { end += 1 }
        return NSRange(location: edit.range.location, length: end - edit.range.location)
    }

    private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2028 || character == 0x2029
    }
}
