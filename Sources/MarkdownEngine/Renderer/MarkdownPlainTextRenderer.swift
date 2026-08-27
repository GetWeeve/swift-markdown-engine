//
//  MarkdownPlainTextRenderer.swift
//  MarkdownEngine
//
//  The plain-text flavor of a copy is the RAW markdown of the selection, so a
//  paste back into an editor round-trips byte-exact. That is right for every
//  construct whose rendered form IS its characters, and wrong for one whose is
//  not: a span laid out as a box (`InlineSyntax.inlineBoxWidth`) shows no
//  glyphs at all, yet its source would leave the app on every copy, cut and
//  drag. `MarkdownExtension.plainText(content:)` is the extension's say over
//  plain text, mirroring what `html(childrenHTML:)` already gives it over HTML;
//  this walks the same block-scoped tokens the editor styles from and applies
//  it.
//

import Foundation

public enum MarkdownPlainTextRenderer {

    /// `markdown` with each registered extension's constructs replaced by the
    /// plain-text form its extension gives them. An extension that returns
    /// `nil` (the default), and every construct the core owns, is left exactly
    /// as written.
    public static func plainText(from markdown: String, extensions: [any MarkdownExtension] = []) -> String {
        guard !markdown.isEmpty, !extensions.isEmpty else { return markdown }
        let registry = ExtensionRegistry(extensions: extensions)
        guard !registry.isEmpty else { return markdown }
        var byID: [String: any MarkdownExtension] = [:]
        for ext in extensions { byID[ext.id] = ext }

        let ns = markdown as NSString
        let blocks = BlockParser.parse(markdown, registry: registry)
        let tokens = MarkdownTokenizer.fullTokens(blocks: blocks, ns: ns, registry: registry)

        // Tokens arrive outermost-first, so a construct nested inside one that
        // is already being replaced is skipped: it is gone with its parent, and
        // editing it too would edit text that no longer exists. Fenced code
        // emits only its code-block token, so a marker quoted in code stays
        // literal.
        var replacements: [(range: NSRange, text: String)] = []
        for token in tokens {
            guard let id = token.kind.extensionID, let ext = byID[id],
                  let text = ext.plainText(content: ns.substring(with: token.contentRange))
            else { continue }
            guard !replacements.contains(where: { NSIntersectionRange($0.range, token.range).length > 0 })
            else { continue }
            replacements.append((token.range, text))
        }
        guard !replacements.isEmpty else { return markdown }

        let out = NSMutableString(string: markdown)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            out.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        return out as String
    }
}

extension MarkdownTokenKind {
    /// The id of the extension that contributed this construct, or nil for a
    /// construct the core owns.
    var extensionID: String? {
        switch self {
        case .extensionSpan(let id), .extensionBlock(let id): return id
        default: return nil
        }
    }
}
