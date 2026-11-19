//
//  TableWrappingTests.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 13.07.26.
//
//  Obsidian-style table layout: when a table's natural width exceeds the
//  available container width, columns share the available width and cell
//  text WRAPS onto multiple lines instead of growing the table sideways
//  (the horizontal-scroll overlay remains only for tables whose per-column
//  minimums genuinely don't fit).
//

import AppKit
import Foundation
import class SwiftUI.NSHostingView
import Testing
@testable import MarkdownEngine

@Suite("Table cell wrapping")
struct TableWrappingTests {

    private let wideSource = """
    | Rechtsform | Gründungskosten | Laufende Kosten |
    |---|---|---|
    | Einzelunternehmen (Kleingewerbe) | 20–60€ Gewerbeanmeldung, jeder Gesellschafter meldet einzeln an | ~0€, nur Steuerberater optional, dreihundert bis achthundert Euro |
    | GbR | Notar und Handelsregister etwa dreihundert bis fünfhundert Euro | Gesellschaftervertrag empfohlen, Anwalt fünfhundert bis eintausendfünfhundert |
    """

    private func render(_ source: String, availableWidth: CGFloat, style: TableStyle = .default) throws -> NSImage {
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let font = NSFont.systemFont(ofSize: 15)
        var ctx = MarkdownStyler.StylingContext(
            nsText: source as NSString,
            tokens: [],
            codeTokens: [],
            activeTokenIndices: [],
            baseFont: font,
            layoutBridge: nil,
            baseDefaultLineHeight: 18,
            codeBackgroundColor: .windowBackgroundColor,
            latexMarkerFont: font,
            configuration: MarkdownEditorConfiguration(table: style),
            wikiLinkIDProvider: { _ in nil }
        )
        ctx.scopeBounds = nil
        let aqua = try #require(NSAppearance(named: .aqua))
        return MarkdownStyler.tableImage(
            for: source, parsed: parsed, ctx: ctx,
            appearance: aqua, availableWidth: availableWidth
        ).image
    }

    @Test func wideTableWrapsToTheAvailableWidth() throws {
        let image = try render(wideSource, availableWidth: 650)
        #expect(image.size.width <= 650.5)
    }

    @Test func wrappingGrowsTheRowsInstead() throws {
        let narrowRender = try render(wideSource, availableWidth: 650)
        let wideRender = try render(wideSource, availableWidth: 4000)
        // Same content in less width must occupy more height (wrapped lines).
        #expect(narrowRender.size.height > wideRender.size.height + 10)
    }

    // W3C auto layout: columns never shrink below their longest unbreakable
    // word — when even those minimums don't fit, the table stays WIDER than
    // the container and the horizontal-scroll overlay takes over.
    @Test func manyColumnsFallBackToHorizontalScroll() throws {
        let source = """
        | Rechtsformvergleich | Gründungskostenaufstellung | Haftungsbeschränkung | Steuerberaterkosten | Handelsregistereintrag | Stammkapitalanforderung |
        |---|---|---|---|---|---|
        | Einzelunternehmen | Gewerbeanmeldung | unbeschränkt | optional | nein | keines |
        """
        let image = try render(source, availableWidth: 500)
        // The longest-word minimums of six columns can't fit in 500pt — the
        // table must stay wider and scroll horizontally, not crush the columns.
        #expect(image.size.width > 500.5)
    }

    @Test func columnsNeverShrinkBelowTheLongestWord() throws {
        let source = """
        | A | B |
        |---|---|
        | Donaudampfschifffahrtsgesellschaftskapitän | x |
        """
        let image = try render(source, availableWidth: 200)
        // The unbreakable word is wider than 200 — the table must exceed the
        // available width rather than break mid-word.
        #expect(image.size.width > 200.5)
    }

    @Test func smallTableKeepsItsNaturalWidth() throws {
        let source = "| a | b |\n|---|---|\n| 1 | 2 |"
        let image = try render(source, availableWidth: 650)
        // Far below the available width — no artificial stretching.
        #expect(image.size.width < 200)
    }

    @Test func filledTablesUseTheSuppliedWidthAndMinimumRowHeight() throws {
        let style = TableStyle(fillsAvailableWidth: true, minimumRowHeight: 35, boldHeaders: false, showsRules: false)
        let source = "| Day | Review |\n|---|---|\n| Mon | Plan |\n| Fri | Progress |"
        for width: CGFloat in [296, 255.5, 480] {
            let image = try render(source, availableWidth: width, style: style)
            #expect(image.size == NSSize(width: width, height: 105))
        }
        let natural = try render(source, availableWidth: 296)
        #expect(natural.size.width < 296)
        #expect(natural.size.height < 105)
    }

    @Test func filledTablesRetainWrappingAndUnbreakableColumnFloors() throws {
        let style = TableStyle(fillsAvailableWidth: true, minimumRowHeight: 35)
        let narrow = try render(wideSource, availableWidth: 575.5, style: style)
        let wide = try render(wideSource, availableWidth: 1100, style: style)
        #expect(narrow.size.width == 575.5)
        #expect(narrow.size.height > wide.size.height)
        let word = String(repeating: "unbroken", count: 12)
        let overflow = try render("| A | B |\n|---|---|\n| " + word + " | C |", availableWidth: 250, style: style)
        #expect(overflow.size.width > 250)
    }

    @Test func ultraNarrowFilledTablesUseOnlyTheirUnbreakableFloors() throws {
        let source = "| A | B |\n|---|---|\n| several short words | repeated short words |"
        let minimum = try render(source, availableWidth: 12, style: TableStyle(fillsAvailableWidth: true))
        let natural = try render(source, availableWidth: 400)
        let historical = try render(source, availableWidth: 12)
        #expect(minimum.size.width < natural.size.width)
        #expect(minimum.size.height > natural.size.height)
        #expect(historical.size == natural.size)
    }

    @MainActor @Test(arguments: [false, true])
    func mountedTableRespondsToResizeInsetsAndStyleChanges(fitted: Bool) async throws {
        _ = NSApplication.shared
        let source = "Intro\n\n| Day | Review |\n|---|---|\n| Monday | Plan the rest of the week |"
        let filled = TableStyle(fillsAvailableWidth: true, minimumRowHeight: 35, boldHeaders: false, showsRules: false)
        func wrapper(_ style: TableStyle, inset: CGFloat) -> NativeTextViewWrapper {
            NativeTextViewWrapper(text: .constant(source), configuration: .init(table: style,
                scrollers: .hidden, textInsets: .init(horizontal: inset), heightBehavior: fitted ? .fitsContent : .scrolls), documentId: "table", isEditable: false)
        }
        let host = NSHostingView(rootView: wrapper(filled, inset: 12))
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 460, 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func editor(in node: NSView) -> NativeTextView? {
            node as? NativeTextView ?? node.subviews.lazy.compactMap(editor).first
        }
        let view = try #require(editor(in: host))
        func settledSize(width: CGFloat, natural: Bool = false) async throws -> NSSize {
            let deadline = ContinuousClock.now + .seconds(2)
            var actual: NSSize?
            repeat {
                host.layoutSubtreeIfNeeded()
                if let storage = view.textStorage {
                    storage.enumerateAttribute(.latexImage, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
                        if let image = value as? NSImage { actual = image.size; stop.pointee = true }
                    }
                }
                if let size = actual, natural ? size.width < width : size.width == width { return size }
                await withCheckedContinuation { resume in DispatchQueue.main.async { resume.resume() } }
            } while ContinuousClock.now < deadline
            Issue.record("Expected table at width \(width), natural \(natural), received \(String(describing: actual)); viewport \(String(describing: view.bounds))")
            return try #require(actual)
        }
        let wide = try await settledSize(width: 436)
        let scroll = try #require(view.enclosingScrollView)
        let initialHeight = scroll.intrinsicContentSize.height
        window.setContentSize(NSSize(width: 235, height: 300))
        let wrapped = try await settledSize(width: 211)
        #expect(wrapped.height > wide.height)
        if fitted {
            #expect(scroll.intrinsicContentSize.height >= initialHeight + wrapped.height - wide.height - 1)
        }
        window.setContentSize(NSSize(width: 460, height: 300))
        #expect(try await settledSize(width: 436) == wide)
        if fitted { #expect(abs(scroll.intrinsicContentSize.height - initialHeight) <= 1) }
        host.rootView = wrapper(filled, inset: 24)
        #expect(try await settledSize(width: 412).width == 412)
        host.rootView = wrapper(filled, inset: 12)
        #expect(try await settledSize(width: 436) == wide)
        host.rootView = wrapper(.default, inset: 12)
        #expect(try await settledSize(width: 436, natural: true).height < wide.height)
        host.rootView = wrapper(filled, inset: 12)
        #expect(try await settledSize(width: 436) == wide)
        #expect(editor(in: host) === view && view.string == source)
    }

    @MainActor @Test func filledTableStaysVisibleInANarrowFixedReadingColumn() async throws {
        _ = NSApplication.shared
        let source = "Intro\n\n| Key | Value |\n|---|---|\n| Time | Monday |"
        let config = MarkdownEditorConfiguration(table: TableStyle(fillsAvailableWidth: true), scrollers: .hidden,
                                                 textInsets: .init(horizontal: 12), readingWidth: 600)
        let host = NSHostingView(rootView: NativeTextViewWrapper(text: .constant(source), configuration: config,
                                                                 documentId: "column", isEditable: false))
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 650, 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func editor(in node: NSView) -> NativeTextView? {
            node as? NativeTextView ?? node.subviews.lazy.compactMap(editor).first
        }
        let view = try #require(editor(in: host))
        let storage = try #require(view.textStorage)
        for (viewport, expected): (CGFloat, CGFloat) in [(650, 600), (300, 276), (650, 600)] {
            window.setContentSize(NSSize(width: viewport, height: 300))
            let deadline = ContinuousClock.now + .seconds(2)
            var width: CGFloat?
            repeat {
                host.layoutSubtreeIfNeeded()
                storage.enumerateAttribute(.latexImage, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
                    if let image = value as? NSImage { width = image.size.width; stop.pointee = true }
                }
                if width == expected { break }
                await withCheckedContinuation { resume in DispatchQueue.main.async { resume.resume() } }
            } while ContinuousClock.now < deadline
            #expect(width == expected)
            #expect(view.textContainer?.size.width == 600)
        }
    }

    @Test func differentAvailableWidthsRenderFreshImages() throws {
        let source = "| wrapcache | test |\n|---|---|\n| some fairly long sentence that needs wrapping in narrow layouts | x |"
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let font = NSFont.systemFont(ofSize: 15)
        let ctx = MarkdownStyler.StylingContext(
            nsText: source as NSString,
            tokens: [], codeTokens: [], activeTokenIndices: [],
            baseFont: font, layoutBridge: nil, baseDefaultLineHeight: 18,
            codeBackgroundColor: .windowBackgroundColor, latexMarkerFont: font,
            configuration: .default, wikiLinkIDProvider: { _ in nil }
        )
        let aqua = try #require(NSAppearance(named: .aqua))

        let first = MarkdownStyler.tableImage(for: source, parsed: parsed, ctx: ctx, appearance: aqua, availableWidth: 300)
        let second = MarkdownStyler.tableImage(for: source, parsed: parsed, ctx: ctx, appearance: aqua, availableWidth: 900)
        let third = MarkdownStyler.tableImage(for: source, parsed: parsed, ctx: ctx, appearance: aqua, availableWidth: 300)

        #expect(first.rendered)
        #expect(second.rendered)          // width is part of the cache key
        #expect(!third.rendered)          // same width again → cache hit
        #expect(first.image.size.width != second.image.size.width)
    }
}
