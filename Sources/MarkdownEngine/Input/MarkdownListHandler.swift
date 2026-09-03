//
//  MarkdownListHandler.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// Makes list editing feel natural by continuing items, handling indentation,
// and applying spacing/alignment that keeps lists easy to read.
import AppKit

struct MarkdownLists {
    static func performEdit(_ textView: NSTextView, replace range: NSRange, with string: String) {
        let ns = textView.string as NSString
        let loc = min(range.location, ns.length)
        let maxLen = ns.length - loc
        let len = min(range.length, max(0, maxLen))
        let safeRange = NSRange(location: loc, length: len)

        if let coord = textView.delegate as? NativeTextViewWrapper.Coordinator {
            coord.isProgrammaticEdit = true
            // This edit REPLACES a suppressed keystroke that never applied.
            // Dropping its pending count lets the shouldChangeText below
            // re-register as the cycle's single tracked edit, so textDidChange
            // keeps the trusted fast paths (the descriptor is refreshed for
            // every proposed edit and describes THIS transition exactly).
            coord.pendingEditCount = 0
        }
        defer {
            if let coord = textView.delegate as? NativeTextViewWrapper.Coordinator { coord.isProgrammaticEdit = false }
        }

        guard textView.shouldChangeText(in: safeRange, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: safeRange, with: string)
        textView.didChangeText()
        // `insertText` reveals the caret as part of AppKit's post-edit
        // processing. This path replaces storage directly, so a newly
        // continued list/quote line at the bottom of a small viewport would
        // otherwise stay clipped until the next real keystroke (the first
        // content character on that empty item).
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    // Markers: `-`/`*`/`+` (raw Markdown) + legacy `•` (rendered, never typed).
    static let listRegex = try! NSRegularExpression(
        pattern: #"^\s*((?:(\d+)\.|[-•*+])(?:\s+\[[ xX]\])?\s+)"#
    )
    /// Blockquote line: ≤3 indent + `>` marker run; group 1 = whitespace, group 2 = markers.
    // Trailing `[ \t]*` so the prefix length covers the space(s) the continuation
    // inserts (`markers + " "`) — otherwise exiting an empty quote leaves a stray
    // space (greedy like listRegex's `\s+`).
    static let blockquoteRegex = try! NSRegularExpression(
        pattern: #"^( {0,3})(>+(?:[ \t]+>+)*)[ \t]*"#
    )
    static let dashNoSpaceRegex = try! NSRegularExpression(pattern: #"^\s*-(?!\s)"#)
    static let leadingWhitespaceRegex = try! NSRegularExpression(pattern: #"^\s*"#)

    static func indentLevel(from leadingWhitespace: String) -> Int {
        let tabCount = leadingWhitespace.filter { $0 == "\t" }.count
        let spaceCount = leadingWhitespace.filter { $0 == " " }.count
        return tabCount + (spaceCount / 2)
    }

    /// Remove the current line's leading marker and put the caret at line start (exit empty block on Enter).
    private static func removeLinePrefixAndExit(
        textView: NSTextView,
        currentLineRange: NSRange,
        prefixLength: Int
    ) -> Bool {
        let lineEnd = currentLineRange.location + currentLineRange.length
        let hasNewline = currentLineRange.length > 0
            && (textView.string as NSString)
                .substring(with: NSRange(location: lineEnd - 1, length: 1)) == "\n"
        let maxBodyLen = hasNewline ? currentLineRange.length - 1 : currentLineRange.length
        let removalLength = min(prefixLength, maxBodyLen)
        let removalRange = NSRange(location: currentLineRange.location, length: removalLength)
        performEdit(textView, replace: removalRange, with: "")
        textView.setSelectedRange(NSRange(location: currentLineRange.location, length: 0))
        return false
    }

    /// Backspace at a list item's content origin removes the whole marker in
    /// one step — the same class of helper as Enter-on-empty — so the user
    /// never walks character-by-character through a hidden `- [ ] ` (or `- `,
    /// `1. `) and briefly sees raw task syntax demote into a bullet with a
    /// leftover `[`.
    ///
    /// - Empty item with a previous line: delete the preceding newline and
    ///   the marker, landing the caret at the end of the previous line.
    /// - Empty item at document start: delete the marker only.
    /// - Non-empty item: unwrap the marker and keep the content on the line.
    ///
    /// Returns `true` when the keystroke was handled (caller should consume
    /// the command). Requires ``ListStyle/helpersEnabled``.
    static func handleDeleteBackward(textView: NSTextView) -> Bool {
        let activeConfig = (textView as? NativeTextView)?.configuration ?? .default
        guard activeConfig.lists.helpersEnabled else { return false }

        let sel = textView.selectedRange()
        guard sel.length == 0 else { return false }

        let nsText = textView.string as NSString
        let caret = min(sel.location, nsText.length)
        guard caret >= 0 else { return false }

        // Mirror the insertion path: list helpers stay inert inside fences.
        if nsText.length > 0,
           MarkdownDetection.isInsideCodeBlock(location: caret, in: textView.string) {
            return false
        }

        let lineRange = nsText.lineRange(for: NSRange(location: caret, length: 0))
        let hasNewline = lineRange.length > 0
            && nsText.character(at: NSMaxRange(lineRange) - 1) == 0x0A
        // Match against the line BODY only — `listRegex`'s trailing `\s+`
        // would otherwise swallow the line-ending newline into the marker
        // prefix and push `contentStart` past the caret.
        let bodyLength = hasNewline ? lineRange.length - 1 : lineRange.length
        let bodyRange = NSRange(location: lineRange.location, length: bodyLength)
        let line = nsText.substring(with: bodyRange)
        let lineNS = line as NSString
        guard let match = listRegex.firstMatch(
            in: line,
            options: [],
            range: NSRange(location: 0, length: lineNS.length)
        ), match.range.location == 0 else { return false }

        let prefixLength = match.range.length
        let contentStart = lineRange.location + prefixLength
        // Only the content-origin caret — mid-marker edits keep raw control.
        guard caret == contentStart else { return false }

        let contentLength = max(0, (lineRange.location + bodyLength) - contentStart)
        let contentText = nsText
            .substring(with: NSRange(location: contentStart, length: contentLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = contentText.isEmpty

        if isEmpty, lineRange.location > 0,
           nsText.character(at: lineRange.location - 1) == 0x0A {
            // `\n` + marker (+ empty body). Leave any trailing newline after
            // the line alone so the following paragraph stays put.
            let removal = NSRange(
                location: lineRange.location - 1,
                length: (contentStart - lineRange.location) + 1
            )
            performEdit(textView, replace: removal, with: "")
            textView.setSelectedRange(NSRange(location: lineRange.location - 1, length: 0))
            return true
        }

        // Unwrap the marker in place (empty at doc start, or non-empty item).
        let removal = NSRange(location: lineRange.location, length: prefixLength)
        performEdit(textView, replace: removal, with: "")
        textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        return true
    }

    /// Mirror Enter-key quote continuation for multi-line pastes: when `location`
    /// sits on a blockquote line, prefix every line after the first with that
    /// line's `>` marker run so the whole paste stays inside the quote. Returns
    /// `pasted` unchanged when it has no newline or the caret isn't in a quote.
    static func blockquoteContinuedPaste(_ pasted: String, at location: Int, in document: String) -> String {
        guard pasted.contains("\n") else { return pasted }
        let ns = document as NSString
        guard location >= 0, location <= ns.length else { return pasted }
        let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
        let nsLine = ns.substring(with: lineRange) as NSString
        guard let match = blockquoteRegex.firstMatch(
            in: nsLine as String,
            range: NSRange(location: 0, length: nsLine.length)
        ) else { return pasted }
        let ws = nsLine.substring(with: match.range(at: 1))
        let markers = nsLine.substring(with: match.range(at: 2))
        let prefix = ws + markers + " "
        return pasted.replacingOccurrences(of: "\n", with: "\n" + prefix)
    }

    // MARK: - Input Handling

    /// `isInsideCodeBlock` is the caller's pre-parsed answer for
    /// `affectedCharRange.location` (the coordinator derives it from the
    /// keystroke's existing parse). `nil` — direct callers without a parse —
    /// falls back to deriving it here, which walks the whole document.
    static func handleInsertion(textView: NSTextView, affectedCharRange: NSRange, replacementString: String?, isInsideCodeBlock: Bool? = nil) -> Bool {
        guard let replacementString = replacementString else { return true }

        // Fast path: plain characters never trigger list/pair/arrow handling.
        if replacementString.count == 1,
           let ch = replacementString.first,
           ch != ">" && ch != "[" && ch != "(" && ch != "{" &&
           ch != "\t" && ch != " " && ch != "\n" {
            return true
        }

        let activeConfig = (textView as? NativeTextView)?.configuration ?? .default
        let listsEnabled = activeConfig.lists.helpersEnabled
        let autoClosePairsEnabled = activeConfig.lists.autoClosePairsEnabled

        func insertAutoPair(open openChar: String, close closeChar: String) -> Bool {
            let insertionLocation = affectedCharRange.location
            MarkdownLists.performEdit(textView, replace: affectedCharRange, with: "\(openChar)\(closeChar)")
            textView.setSelectedRange(NSRange(location: insertionLocation + openChar.count, length: 0))
            return false
        }

        let isInCodeBlock = isInsideCodeBlock ?? (
            textView.string.contains("`")
                ? MarkdownDetection.isInsideCodeBlock(location: affectedCharRange.location, in: textView.string)
                : false
        )

        if replacementString == ">" && affectedCharRange.length == 0 && !isInCodeBlock {
            let insertionLocation = affectedCharRange.location
            guard insertionLocation > 0 else { return true }
            let nsText = textView.string as NSString
            let previousCharRange = NSRange(location: insertionLocation - 1, length: 1)
            let previousChar = nsText.substring(with: previousCharRange)
            if previousChar == "-" {
                MarkdownLists.performEdit(textView, replace: previousCharRange, with: "→")
                textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
                return false
            }
        }

        // Autocomplete Obsidian-style node brackets and single square brackets
        if replacementString == "[" {
            let nsText = textView.string as NSString
            let insertionLocation = affectedCharRange.location
            if insertionLocation > 0 {
                let prevChar = nsText.substring(with: NSRange(location: insertionLocation - 1, length: 1))
                if prevChar == "[" {
                    let hasAutoCloseBracket = insertionLocation < nsText.length
                        && nsText.substring(with: NSRange(location: insertionLocation, length: 1)) == "]"
                    if hasAutoCloseBracket {
                        // Collapse auto-paired "[]" into "[[]]" without changing surrounding text.
                        MarkdownLists.performEdit(
                            textView,
                            replace: NSRange(location: insertionLocation - 1, length: 2),
                            with: "[[]]"
                        )
                    } else {
                        // If the char to the right is not "]" (e.g. newline), do not delete it.
                        MarkdownLists.performEdit(textView, replace: affectedCharRange, with: "[]]")
                    }
                    textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                    return false
                }
            }
            guard autoClosePairsEnabled else { return true }
            return insertAutoPair(open: "[", close: "]")
        }

        // Autocomplete parentheses / braces
        if replacementString == "(" || replacementString == "{" {
            guard autoClosePairsEnabled else { return true }
            let closeChar = (replacementString == "(") ? ")" : "}"
            return insertAutoPair(open: replacementString, close: closeChar)
        }

        // SPACE: bare-checkbox shorthand (opt-in) — a line that so far reads
        // `[]`, `[ ]`, or `- []` becomes an unchecked task item. Only the
        // text BEFORE the caret decides, so text after the caret is kept.
        if replacementString == " " && affectedCharRange.length == 0 && !isInCodeBlock {
            guard listsEnabled && activeConfig.lists.taskShorthandEnabled else { return true }
            let nsText = textView.string as NSString
            let caret = min(affectedCharRange.location, nsText.length)
            let currentLineRange = nsText.lineRange(for: NSRange(location: caret, length: 0))
            let prefixRange = NSRange(
                location: currentLineRange.location,
                length: caret - currentLineRange.location
            )
            let prefix = nsText.substring(with: prefixRange)
            let indent = prefix.prefix(while: { $0 == " " || $0 == "\t" })
            let token = prefix.dropFirst(indent.count)
            guard token == "[]" || token == "[ ]" || token == "- []" else { return true }
            let replacement = indent + "- [ ] "
            MarkdownLists.performEdit(textView, replace: prefixRange, with: String(replacement))
            textView.setSelectedRange(NSRange(
                location: prefixRange.location + (String(replacement) as NSString).length,
                length: 0
            ))
            return false
        }

        // TAB: indent list items (skip in code blocks)
        if replacementString == "\t" && !isInCodeBlock {
            guard listsEnabled else { return true }
            let nsText = textView.string as NSString
            let insertionLocation = affectedCharRange.location
            let safeLocTAB = min(affectedCharRange.location, nsText.length)
            let currentLineRange = nsText.lineRange(for: NSRange(location: safeLocTAB, length: 0))
            let currentLine = nsText.substring(with: currentLineRange)
            if MarkdownLists.listRegex.firstMatch(in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) != nil {
                if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) {
                    let ws = (currentLine as NSString).substring(with: wsMatch.range)
                    let level = MarkdownLists.indentLevel(from: ws)
                    if level >= MarkdownEditorConfiguration.default.lists.maximumNestingLevel {
                        return false
                    }
                }
                MarkdownLists.performEdit(textView, replace: NSRange(location: currentLineRange.location, length: 0), with: "\t")
                textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                return false
            }
            if MarkdownLists.dashNoSpaceRegex.firstMatch(in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) != nil {
                if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) {
                    let ws = (currentLine as NSString).substring(with: wsMatch.range)
                    let level = MarkdownLists.indentLevel(from: ws)
                    if level >= MarkdownEditorConfiguration.default.lists.maximumNestingLevel { return false }
                }
                MarkdownLists.performEdit(textView, replace: NSRange(location: currentLineRange.location, length: 0), with: "\t")
                textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                return false
            }
            return true
        }

        // ENTER: list continuation/outdent
        if replacementString == "\n" {
            let nsText = textView.string as NSString
            let safeLocENTER = min(affectedCharRange.location, nsText.length)
            let currentLineRange = nsText.lineRange(for: NSRange(location: safeLocENTER, length: 0))
            let currentLine = nsText.substring(with: currentLineRange).trimmingCharacters(in: .whitespacesAndNewlines)

            // Horizontal rules render via the styler; source stays literal `---` so files round-trip.

            if currentLine.range(of: "^```\\w*$", options: .regularExpression) != nil {
                // Non-overlapping ``` count before the line (what
                // components(separatedBy:).count-1 computed, without
                // materializing an O(doc) substring array).
                var openingCount = 0
                var searchLocation = 0
                while searchLocation < currentLineRange.location {
                    let found = nsText.range(of: "```", options: [],
                                             range: NSRange(location: searchLocation,
                                                            length: currentLineRange.location - searchLocation))
                    if found.location == NSNotFound { break }
                    openingCount += 1
                    searchLocation = NSMaxRange(found)
                }
                let afterLineStart = currentLineRange.location + currentLineRange.length
                let hasClosingAfter: Bool = {
                    guard afterLineStart < nsText.length else { return false }
                    let after = NSRange(location: afterLineStart, length: nsText.length - afterLineStart)
                    return nsText.range(of: "```", options: [], range: after).location != NSNotFound
                }()
                let lineEnd = currentLineRange.location + max(0, currentLineRange.length - 1)
                let cursorAtLineEnd = affectedCharRange.location >= lineEnd

                if openingCount.isMultiple(of: 2) && cursorAtLineEnd && !hasClosingAfter {
                    let insertionLocation = affectedCharRange.location
                    let completion = "\n\n```"
                    MarkdownLists.performEdit(textView, replace: affectedCharRange, with: completion)
                    textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                    return false
                }
            }

            // Skip list / blockquote continuation in code blocks.
            guard listsEnabled && !isInCodeBlock else { return true }

            // Blockquote continuation: `> foo` → `\n> `, `>>>` stays `>>>`, empty marker → exit.
            let quoteLine = nsText.substring(with: currentLineRange)
            if let quoteMatch = MarkdownLists.blockquoteRegex.firstMatch(
                in: quoteLine,
                range: NSRange(location: 0, length: quoteLine.utf16.count)
            ) {
                let ws = (quoteLine as NSString).substring(with: quoteMatch.range(at: 1))
                let markers = (quoteLine as NSString).substring(with: quoteMatch.range(at: 2))
                let prefixLength = quoteMatch.range.length
                let contentStart = quoteMatch.range.location + prefixLength
                let contentLength = quoteLine.utf16.count - contentStart
                let contentText = (quoteLine as NSString)
                    .substring(with: NSRange(location: contentStart, length: contentLength))
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if contentText.isEmpty {
                    return removeLinePrefixAndExit(
                        textView: textView,
                        currentLineRange: currentLineRange,
                        prefixLength: prefixLength
                    )
                }
                MarkdownLists.performEdit(textView, replace: affectedCharRange, with: "\n" + ws + markers + " ")
                return false
            }

            let listLine = nsText.substring(with: currentLineRange)
            if let match = MarkdownLists.listRegex.firstMatch(in: listLine, range: NSRange(location: 0, length: listLine.utf16.count)) {
                let contentStart = match.range.location + match.range.length
                let contentLength = listLine.utf16.count - contentStart
                let contentRangeLocal = NSRange(location: contentStart, length: contentLength)
                let contentText = (listLine as NSString).substring(with: contentRangeLocal).trimmingCharacters(in: .whitespacesAndNewlines)
                if contentText.isEmpty {
                    return removeLinePrefixAndExit(
                        textView: textView,
                        currentLineRange: currentLineRange,
                        prefixLength: match.range.location + match.range.length
                    )
                }
                let leadingWhitespace: String
                if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(in: listLine, range: NSRange(location: 0, length: listLine.utf16.count)) {
                    leadingWhitespace = (listLine as NSString).substring(with: wsMatch.range)
                } else {
                    leadingWhitespace = ""
                }
                let markerRaw = (listLine as NSString).substring(with: match.range(at: 1))
                let marker = markerRaw.trimmingCharacters(in: .whitespaces)
                let hasCheckbox = marker.range(of: #"\[[ xX]\]"#, options: .regularExpression) != nil
                let newListItem: String
                if match.range(at: 2).location != NSNotFound,
                   let number = Int((listLine as NSString).substring(with: match.range(at: 2))) {
                    if hasCheckbox {
                        newListItem = "\n" + leadingWhitespace + "\(number + 1). [ ] "
                    } else {
                        newListItem = "\n" + leadingWhitespace + "\(number + 1). "
                    }
                } else {
                    // Continue with the user's marker char (legacy `•` → `-`), keeping leading whitespace.
                    let bulletChar = (marker.first == "•") ? "-" : String(marker.prefix(1))
                    if hasCheckbox {
                        newListItem = "\n" + leadingWhitespace + bulletChar + " [ ] "
                    } else {
                        newListItem = "\n" + leadingWhitespace + bulletChar + " "
                    }
                }
                MarkdownLists.performEdit(textView, replace: affectedCharRange, with: newListItem)
                return false
            }
        }

        return true
    }
}
