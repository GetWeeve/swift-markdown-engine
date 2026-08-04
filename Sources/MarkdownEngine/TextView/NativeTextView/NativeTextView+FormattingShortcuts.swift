//
//  NativeTextView+FormattingShortcuts.swift
//  MarkdownEngine
//
//  Inline-formatting key equivalents, wired to the coordinator's existing
//  toggleable formatting actions (the same wrap/unwrap logic the context
//  menu drives):
//
//    ⌘B  bold          (`**` wrap/unwrap; ***both*** → *italic*)
//    ⌘I  italic        (`*` wrap/unwrap)
//    ⌘E  inline code   (`` ` `` wrap/unwrap)
//    ⌘⇧K link scaffold (`[text](url)`; plain ⌘K is left untouched — it is
//                       a common embedder binding, e.g. command palettes)
//
//  Gated by `MarkdownEditorConfiguration.formattingShortcutsEnabled`
//  (default on, like the list helpers). Only exact modifier matches are
//  consumed, so every other ⌘-combination keeps flowing to menus and the
//  responder chain.
//

import AppKit

extension NativeTextView {

    /// Handles an inline-formatting key equivalent. Returns true when the
    /// event was consumed.
    func handleFormattingShortcut(_ event: NSEvent) -> Bool {
        guard configuration.formattingShortcutsEnabled,
              isEditable,
              let coordinator = delegate as? NativeTextViewCoordinator,
              let characters = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (modifiers, characters) {
        case (.command, "b"):
            coordinator.didMarkdownBold(nil)
            return true
        case (.command, "i"):
            coordinator.didMarkdownItalic(nil)
            return true
        case (.command, "e"):
            coordinator.didMarkdownInlineCode(nil)
            return true
        case ([.command, .shift], "k"):
            coordinator.didMarkdownLink(nil)
            return true
        default:
            return false
        }
    }
}
