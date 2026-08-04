//
//  TaskStylingTests.swift
//  MarkdownEngineTests
//
//  Checked-task treatment knobs: the strikethrough gate
//  (`TaskCheckboxStyle.strikethroughCompletedTasks`), the completed-label ink
//  (`MarkdownEditorTheme.completedTaskText`), and the checkbox tint slots.
//  Defaults must keep the historical rendering (strikethrough on, body ink).
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Task styling knobs")
struct TaskStylingTests {

    private let base: CGFloat = 16
    private var fontName: String { NSFont.systemFont(ofSize: 16).fontName }

    private func style(
        _ text: String,
        theme: MarkdownEditorTheme = .default,
        strikethrough: Bool = true
    ) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base,
            configuration: MarkdownEditorConfiguration(
                theme: theme,
                taskCheckbox: TaskCheckboxStyle(strikethroughCompletedTasks: strikethrough)
            )
        )
    }

    /// Whether any styled range covering `pos` sets a strikethrough.
    private func hasStrikethrough(in attrs: [StyledRange], at pos: Int) -> Bool {
        attrs.contains { range, a in
            NSLocationInRange(pos, range) && a[.strikethroughStyle] != nil
        }
    }

    /// Effective foreground at `pos` (last styled range wins).
    private func color(in attrs: [StyledRange], at pos: Int) -> NSColor? {
        var result: NSColor?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let c = a[.foregroundColor] as? NSColor { result = c }
        }
        return result
    }

    private let text = "- [x] done thing\n- [ ] open thing\n"
    private var donePos: Int { (text as NSString).range(of: "done").location }
    private var openPos: Int { (text as NSString).range(of: "open").location }

    // MARK: - Strikethrough gate

    @Test("the default keeps the historical strikethrough on checked labels")
    func defaultKeepsStrikethrough() {
        let attrs = style(text)
        #expect(hasStrikethrough(in: attrs, at: donePos))
        #expect(!hasStrikethrough(in: attrs, at: openPos))
        // And the label keeps the document ink — no foreground override.
        #expect(color(in: attrs, at: donePos) == nil)
    }

    @Test("strikethroughCompletedTasks = false drops the strikethrough")
    func gateOffDropsStrikethrough() {
        let attrs = style(text, strikethrough: false)
        #expect(!hasStrikethrough(in: attrs, at: donePos))
        #expect(!hasStrikethrough(in: attrs, at: openPos))
    }

    // MARK: - Completed label ink

    @Test("completedTaskText colors only the checked label")
    func completedInkColorsCheckedLabelOnly() {
        let muted = NSColor(calibratedWhite: 0.45, alpha: 1)
        let attrs = style(text, theme: MarkdownEditorTheme(completedTaskText: muted))
        #expect(color(in: attrs, at: donePos) == muted)
        #expect(color(in: attrs, at: openPos) == nil, "unchecked labels keep the document ink")
    }

    @Test("inline constructs inside a completed label keep their own ink")
    func inlineInkWinsInsideCompletedLabel() {
        let muted = NSColor(calibratedWhite: 0.45, alpha: 1)
        let linked = "- [x] see [docs](https://example.com) now\n"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: linked, fontName: fontName, fontSize: base,
            configuration: MarkdownEditorConfiguration(
                theme: MarkdownEditorTheme(completedTaskText: muted)
            )
        )
        let ns = linked as NSString
        #expect(color(in: attrs, at: ns.range(of: "see").location) == muted)
        // The link label appends after the task pass, so its ink wins.
        let linkPos = ns.range(of: "docs").location
        #expect(color(in: attrs, at: linkPos) == MarkdownEditorTheme.default.link)
    }

    // MARK: - Checkbox tint slots

    @Test("checkbox tint slots default to nil and carry custom inks")
    func checkboxTintSlots() {
        #expect(MarkdownEditorTheme.default.taskCheckboxChecked == nil)
        #expect(MarkdownEditorTheme.default.taskCheckboxUnchecked == nil)
        let brand = NSColor(calibratedRed: 1, green: 0.8, blue: 0.81, alpha: 1)
        let theme = MarkdownEditorTheme(taskCheckboxChecked: brand, taskCheckboxUnchecked: .gray)
        #expect(theme.taskCheckboxChecked == brand)
        #expect(theme.taskCheckboxUnchecked == .gray)
    }
}
