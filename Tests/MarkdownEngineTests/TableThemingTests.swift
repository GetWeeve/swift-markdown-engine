//
//  TableThemingTests.swift
//  MarkdownEngineTests
//
//  Table theming slots: `MarkdownEditorTheme.tableHeaderBackground` and
//  `MarkdownEditorTheme.tableRule`. Defaults (nil) must keep the historical
//  mutedText-derived fills, and the slots must participate in the render
//  cache key so themed and stock tables never share an image.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Table theming slots")
struct TableThemingTests {

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

    private func sample(_ image: NSImage, x: Int, y: Int) -> NSColor? {
        let size = image.size
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        // NSImage draws bottom-up; convert the top-down y used by the table
        // renderer into the bitmap's coordinate space.
        return bitmap.colorAt(x: x, y: y)
    }

    @Test("slots default to nil")
    func slotsDefaultToNil() {
        #expect(MarkdownEditorTheme.default.tableHeaderBackground == nil)
        #expect(MarkdownEditorTheme.default.tableRule == nil)
    }

    @Test("custom header fill and rule ink reach the rendered bitmap")
    func customColorsReachTheBitmap() throws {
        let source = "| head | col |\n|---|---|\n| a | b |"
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let aqua = try #require(NSAppearance(named: .aqua))

        var themed = MarkdownEditorConfiguration.default
        themed.theme.tableHeaderBackground = .red
        themed.theme.tableRule = .blue

        let (image, _) = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: themed),
            appearance: aqua, availableWidth: 2000
        )

        // Top-left interior of the header row (inside the 1pt border, away
        // from any glyph) carries the header fill.
        let headerPixel = try #require(sample(image, x: 3, y: 3))
        #expect(headerPixel.redComponent > 0.9)
        #expect(headerPixel.blueComponent < 0.3)

        // The outer border column carries the rule ink.
        let rulePixel = try #require(sample(image, x: 0, y: Int(image.size.height / 2)))
        #expect(rulePixel.blueComponent > 0.9)
        #expect(rulePixel.redComponent < 0.3)
    }

    // The cache key must cover the new slots — a theme differing only in a
    // table slot must be a miss, never the stock cached image.
    @Test("changing a table slot renders fresh instead of reusing the cache")
    func tableSlotChangeRendersFresh() throws {
        let source = "| iota | kappa |\n|---|---|\n| 11 | 12 |"
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let aqua = try #require(NSAppearance(named: .aqua))

        _ = MarkdownStyler.tableImage(
            for: source, parsed: parsed, ctx: makeContext(for: source),
            appearance: aqua, availableWidth: 2000
        )

        var ruled = MarkdownEditorConfiguration.default
        ruled.theme.tableRule = .systemPink
        let repainted = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: ruled),
            appearance: aqua, availableWidth: 2000
        )
        #expect(repainted.rendered)

        var filled = MarkdownEditorConfiguration.default
        filled.theme.tableHeaderBackground = .systemTeal
        let refilled = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: filled),
            appearance: aqua, availableWidth: 2000
        )
        #expect(refilled.rendered)
    }
}
