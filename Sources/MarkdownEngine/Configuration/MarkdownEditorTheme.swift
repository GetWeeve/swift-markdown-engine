//
//  MarkdownEditorTheme.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Color palette for the Markdown editor engine.
//
//  All user-visible colors used by the engine are routed through this
//  struct. Defaults map to system colors so the editor adapts to light/
//  dark mode automatically. Embedders that want a custom palette (for
//  example, a sepia or high-contrast preset) can replace any subset of
//  the colors without touching engine source files.
//

import AppKit
import Foundation

// MARK: - Theme

/// Color palette consumed by the Markdown editor engine.
///
/// Every color the engine puts on screen is read from this struct, so a
/// single override is enough to retheme the entire editor. The defaults
/// reproduce a system-native macOS look using `NSColor` dynamic system
/// colors, so light/dark-mode switching keeps working without extra code.
public struct MarkdownEditorTheme: Sendable {

    // MARK: Text colors

    /// Foreground color for plain body text and the typing caret.
    public var bodyText: NSColor
    /// Foreground color for de-emphasized text and most syntax markers.
    /// Defaults to `secondaryLabelColor` so it tracks the system style.
    public var mutedText: NSColor
    /// Foreground color for content the engine wants to deemphasize further
    /// than `mutedText` — for example, broken wiki-links.
    public var disabledText: NSColor
    /// Foreground color for heading text. `nil` (the default) keeps the
    /// historical behavior: headings render in ``bodyText`` like the rest
    /// of the document.
    ///
    /// Only the heading's own text takes this color. The `#` marker glyphs
    /// stay on ``headingMarker``, and inline constructs inside a heading
    /// (links, inline code, extension spans) keep their own colors, exactly
    /// as they do over ``bodyText``.
    public var headingText: NSColor?
    /// Foreground color for heading marker glyphs (`#`, `##`, …).
    public var headingMarker: NSColor
    /// Foreground color for painted list marker glyphs — the bullet `•` and
    /// the ordered `1.` overlays, including the raw source characters those
    /// painters reveal while the marker sits inside a selection. `nil` (the
    /// default) keeps the historical behavior: markers render in
    /// ``bodyText`` like the item content.
    public var listMarker: NSColor?
    /// Foreground color for a CHECKED task item's label. `nil` (the default)
    /// keeps the historical behavior: the label stays on the document's body
    /// ink. Inline constructs inside the label (links, code, extension
    /// spans) keep their own colors either way, exactly as they do over
    /// ``bodyText``. Pairs with
    /// ``TaskCheckboxStyle/strikethroughCompletedTasks`` for designs that
    /// mark completion by ink instead of a strikethrough.
    public var completedTaskText: NSColor?

    // MARK: Task checkboxes

    /// Tint of the drawn checkbox symbol for a CHECKED task item. `nil`
    /// (the default) keeps the historical ``bodyText`` tint.
    public var taskCheckboxChecked: NSColor?
    /// Tint of the drawn checkbox symbol for an UNCHECKED task item. `nil`
    /// (the default) keeps the historical ``mutedText`` tint.
    public var taskCheckboxUnchecked: NSColor?

    // MARK: Blockquotes

    /// Fill of the painted vertical quote bar(s). `nil` (the default) keeps
    /// the historical half-transparent ``mutedText``. A configured color is
    /// used exactly as given — no alpha is layered on top.
    public var blockquoteBar: NSColor?
    /// Foreground color of blockquote content. `nil` (the default) keeps the
    /// historical behavior of muting quotes in ``mutedText``. The `>` marker
    /// glyphs revealed on the active line stay on ``mutedText`` either way,
    /// and inline constructs keep their own colors as usual.
    public var blockquoteText: NSColor?

    // MARK: Links

    /// Foreground color for hyperlinks that resolve to an URL.
    public var link: NSColor
    /// Foreground color for incomplete `[text]` patterns (no URL yet).
    public var incompleteLink: NSColor

    // MARK: Find / search highlights

    /// Background color used to highlight all matches when the user is
    /// running an in-document search.
    ///
    /// The default is `.systemYellow` so embedders that don't customize
    /// this still get a sensible result. Apps with their own brand color
    /// (for example, the Nodes app uses its custom yellow) should override
    /// this to match their palette.
    public var findMatchHighlight: NSColor
    /// Background color used to highlight the currently-focused match
    /// during in-document search. Typically a stronger version of
    /// ``findMatchHighlight``.
    public var findCurrentMatchHighlight: NSColor

    // MARK: LaTeX rendering

    /// Foreground color used when rendering LaTeX formulas in light mode.
    public var latexLightModeText: NSColor
    /// Foreground color used when rendering LaTeX formulas in dark mode.
    public var latexDarkModeText: NSColor

    // MARK: Strikethrough / decoration

    /// Stroke color used for strikethrough decorations
    /// (e.g. completed task list items, horizontal rules).
    public var strikethroughColor: NSColor

    // MARK: Highlight

    /// Background color used for `==highlight==` inline markup.
    public var highlightColor: NSColor

    // MARK: Code

    /// Background color behind fenced code blocks and inline `` `code` ``
    /// spans. `nil` (the default) keeps the historical behavior: the
    /// syntax-highlighter service's background color.
    public var codeBackground: NSColor?

    // MARK: Init

    public init(
        bodyText: NSColor = .labelColor,
        mutedText: NSColor = .secondaryLabelColor,
        disabledText: NSColor = .tertiaryLabelColor,
        headingText: NSColor? = nil,
        headingMarker: NSColor = .gray,
        listMarker: NSColor? = nil,
        completedTaskText: NSColor? = nil,
        taskCheckboxChecked: NSColor? = nil,
        taskCheckboxUnchecked: NSColor? = nil,
        blockquoteBar: NSColor? = nil,
        blockquoteText: NSColor? = nil,
        link: NSColor = .linkColor,
        incompleteLink: NSColor = .systemBlue,
        findMatchHighlight: NSColor = .systemYellow,
        findCurrentMatchHighlight: NSColor = .systemYellow,
        latexLightModeText: NSColor = .black,
        latexDarkModeText: NSColor = .white,
        strikethroughColor: NSColor = .labelColor,
        highlightColor: NSColor = .systemOrange.withAlphaComponent(0.4),
        codeBackground: NSColor? = nil
    ) {
        self.bodyText = bodyText
        self.mutedText = mutedText
        self.disabledText = disabledText
        self.headingText = headingText
        self.headingMarker = headingMarker
        self.listMarker = listMarker
        self.completedTaskText = completedTaskText
        self.taskCheckboxChecked = taskCheckboxChecked
        self.taskCheckboxUnchecked = taskCheckboxUnchecked
        self.blockquoteBar = blockquoteBar
        self.blockquoteText = blockquoteText
        self.link = link
        self.incompleteLink = incompleteLink
        self.findMatchHighlight = findMatchHighlight
        self.findCurrentMatchHighlight = findCurrentMatchHighlight
        self.latexLightModeText = latexLightModeText
        self.latexDarkModeText = latexDarkModeText
        self.strikethroughColor = strikethroughColor
        self.highlightColor = highlightColor
        self.codeBackground = codeBackground
    }

    /// System-native palette built from `NSColor` dynamic system colors.
    ///
    /// Use this if you want the engine to look like a stock macOS
    /// `NSTextView`. It's also the default when no theme is supplied.
    public static let `default` = MarkdownEditorTheme()
}

// MARK: - Display attributes

extension MarkdownEditorTheme {
    /// Attributes for `NSTextView.linkTextAttributes`, which AppKit layers
    /// over every `.link` range at DISPLAY time — on top of whatever
    /// foreground the styler already set. Left at AppKit's default, links
    /// always render `.linkColor` blue, so a custom ``link`` ink never
    /// reaches the screen. Re-declaring the theme's link ink (plus the
    /// standard underline and pointing-hand cursor the default also carries)
    /// makes the displayed color follow the theme.
    var linkTextAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
    }
}
