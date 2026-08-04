//
//  TableRowFillTests.swift
//  MarkdownEngineTests
//
//  `MarkdownEditorTheme.tableRowBackground`: fills the rendered table's body
//  rows (below the header). `nil` keeps the historical unfilled body. The
//  fill clips inside a rounded wrapper, rules stroke on top, and the slot
//  participates in the render cache key.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Table row fill")
struct TableRowFillTests {

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

    private let source = "| head | col |\n|---|---|\n| a | b |\n| c | d |"

    private func render(
        rowFill: NSColor?,
        cornerRadius: CGFloat = 0
    ) throws -> NSBitmapImageRep {
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let aqua = try #require(NSAppearance(named: .aqua))
        var config = MarkdownEditorConfiguration.default
        config.theme.tableRowBackground = rowFill
        config.table.cornerRadius = cornerRadius
        let (image, _) = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: config),
            appearance: aqua, availableWidth: 2000
        )
        return try #require(bitmap(image))
    }

    /// A body-cell probe point: past the header band, away from text glyphs
    /// and rules — just inside the left border at three quarters height.
    private func bodyProbe(_ rep: NSBitmapImageRep) -> (x: Int, y: Int) {
        (x: 4, y: rep.pixelsHigh * 3 / 4)
    }

    @Test("default keeps the body unfilled")
    func defaultBodyUnfilled() throws {
        let rep = try render(rowFill: nil)
        let (x, y) = bodyProbe(rep)
        let color = try #require(rep.colorAt(x: x, y: y))
        #expect(color.alphaComponent < 0.1)
    }

    @Test("the slot fills body rows but not the header")
    func rowFillPixels() throws {
        let rep = try render(rowFill: .red)
        let (x, y) = bodyProbe(rep)
        let body = try #require(rep.colorAt(x: x, y: y))
        #expect(body.alphaComponent > 0.9)
        #expect(body.redComponent > 0.8)
        #expect(body.greenComponent < 0.2)

        // Header band keeps the header fill (default muted, not red).
        let header = try #require(rep.colorAt(x: x, y: 6))
        #expect(header.redComponent < 0.8 || header.alphaComponent < 0.9)
    }

    @Test("the fill clips inside rounded corners")
    func rowFillClipsToRadius() throws {
        let rep = try render(rowFill: .red, cornerRadius: 8)
        // The bottom-left pixel is outside the rounded path: no fill ink.
        let corner = try #require(rep.colorAt(x: 0, y: rep.pixelsHigh - 1))
        #expect(corner.alphaComponent < 0.1)
        // Mid-height on the left edge stays filled right up to the border.
        let (x, y) = bodyProbe(rep)
        let body = try #require(rep.colorAt(x: x, y: y))
        #expect(body.redComponent > 0.8)
    }

    @Test("changing the slot renders fresh instead of reusing the cache")
    func slotChangeRendersFresh() throws {
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let aqua = try #require(NSAppearance(named: .aqua))

        _ = MarkdownStyler.tableImage(
            for: source, parsed: parsed, ctx: makeContext(for: source),
            appearance: aqua, availableWidth: 2000
        )

        var filled = MarkdownEditorConfiguration.default
        filled.theme.tableRowBackground = .systemTeal
        let repainted = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: filled),
            appearance: aqua, availableWidth: 2000
        )
        #expect(repainted.rendered)
    }
}
