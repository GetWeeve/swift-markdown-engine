//
//  TableRuleOrientationTests.swift
//  MarkdownEngineTests
//
//  `TableStyle.verticalRules`: the full-grid look (default) draws interior
//  column separators; turning it off keeps only the outer border and the
//  horizontal rules between rows, spanning the full inner width. The knob
//  participates in the render cache key, and interior rules stroke in the
//  themed rule color.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Table rule orientation")
struct TableRuleOrientationTests {

    private func makeContext(
        for source: String,
        configuration: MarkdownEditorConfiguration = .default
    ) -> MarkdownStyler.StylingContext {
        let font = NSFont.systemFont(ofSize: 15)
        return MarkdownStyler.StylingContext(
            nsText: source as NSString,
            tokens: [],
            codeTokens: [],
            activeTokenIndices: [],
            baseFont: font,
            layoutBridge: nil,
            baseDefaultLineHeight: 18,
            codeBackgroundColor: .windowBackgroundColor,
            latexMarkerFont: font,
            configuration: configuration,
            wikiLinkIDProvider: { _ in nil }
        )
    }

    private func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
        let size = image.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func isRuleBlue(_ color: NSColor?) -> Bool {
        guard let color else { return false }
        return color.alphaComponent > 0.4 && color.blueComponent > 0.8 && color.redComponent < 0.3
    }

    /// Renders the sample table with a blue rule color so rule pixels are
    /// unambiguous against the fill and text inks.
    private func render(source: String, verticalRules: Bool) throws -> NSBitmapImageRep {
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let aqua = try #require(NSAppearance(named: .aqua))
        var config = MarkdownEditorConfiguration.default
        config.theme.tableRule = .blue
        config.table.verticalRules = verticalRules
        let (image, _) = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: config),
            appearance: aqua, availableWidth: 2000
        )
        return try #require(bitmap(image))
    }

    /// Interior horizontal-rule rows: y positions strictly inside the image
    /// where the pixel at mid-x is rule-colored.
    private func interiorRuleRows(_ rep: NSBitmapImageRep) -> [Int] {
        let midX = rep.pixelsWide / 2
        return (2..<(rep.pixelsHigh - 2)).filter { isRuleBlue(rep.colorAt(x: midX, y: $0)) }
    }

    private let source = "| head | col | third |\n|---|---|---|\n| a | b | c |\n| d | e | f |"

    @Test("default keeps the full grid")
    func defaults() {
        #expect(TableStyle.default.verticalRules)
        #expect(MarkdownEditorConfiguration.default.table.verticalRules)
    }

    @Test("grid off leaves no interior vertical-rule pixels")
    func noVerticalRulePixels() throws {
        let grid = try render(source: source, verticalRules: true)
        let rows = try render(source: source, verticalRules: false)

        // Probe a row strictly between two horizontal rules (mid body row):
        // halfway between the first two interior rule rows, or below the last
        // one when the header fill occupies the first band.
        let gridRules = interiorRuleRows(grid)
        let rowsRules = interiorRuleRows(rows)
        #expect(!gridRules.isEmpty)
        #expect(!rowsRules.isEmpty)
        let probeY = try #require(zip(rowsRules.dropFirst(), rowsRules).map { ($0 + $1) / 2 }.first)

        func interiorVerticalHits(_ rep: NSBitmapImageRep, y: Int) -> Int {
            (2..<(rep.pixelsWide - 2)).filter { isRuleBlue(rep.colorAt(x: $0, y: y)) }.count
        }
        // The full grid inks column separators inside the row band; the
        // rows-only look inks nothing between the borders there.
        #expect(interiorVerticalHits(grid, y: probeY) >= 2)
        #expect(interiorVerticalHits(rows, y: probeY) == 0)
    }

    @Test("horizontal rules stay and span the full inner width")
    func horizontalRulesSpanFullWidth() throws {
        let rows = try render(source: source, verticalRules: false)
        let ruleRows = interiorRuleRows(rows)
        // Header/body rule plus one rule between the two body rows.
        #expect(ruleRows.count >= 2)
        for y in ruleRows {
            #expect(isRuleBlue(rows.colorAt(x: 2, y: y)))
            #expect(isRuleBlue(rows.colorAt(x: rows.pixelsWide - 3, y: y)))
        }
    }

    @Test("outer border still draws on all four sides")
    func outerBorderIntact() throws {
        let rows = try render(source: source, verticalRules: false)
        let midX = rows.pixelsWide / 2
        let midY = rows.pixelsHigh / 2
        #expect(isRuleBlue(rows.colorAt(x: midX, y: 0)))
        #expect(isRuleBlue(rows.colorAt(x: midX, y: rows.pixelsHigh - 1)))
        #expect(isRuleBlue(rows.colorAt(x: 0, y: midY)))
        #expect(isRuleBlue(rows.colorAt(x: rows.pixelsWide - 1, y: midY)))
    }

    @Test("interior rules stroke in the themed rule color, not black")
    func interiorRulesUseThemeColor() throws {
        // Regression guard: the rounded-wrapper change moved the outer
        // border's setStroke below the separator pass, which left interior
        // rules on the context's default black.
        let grid = try render(source: source, verticalRules: true)
        let ruleRows = interiorRuleRows(grid)
        #expect(!ruleRows.isEmpty)
    }

    @Test("flipping the knob renders fresh instead of reusing the cache")
    func knobChangeRendersFresh() throws {
        let source = "| tau | ups |\n|---|---|\n| 31 | 32 |"
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let aqua = try #require(NSAppearance(named: .aqua))

        _ = MarkdownStyler.tableImage(
            for: source, parsed: parsed, ctx: makeContext(for: source),
            appearance: aqua, availableWidth: 2000
        )

        var rowsOnly = MarkdownEditorConfiguration.default
        rowsOnly.table.verticalRules = false
        let repainted = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: rowsOnly),
            appearance: aqua, availableWidth: 2000
        )
        #expect(repainted.rendered)
    }
}
