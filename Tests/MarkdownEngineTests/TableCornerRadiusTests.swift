//
//  TableCornerRadiusTests.swift
//  MarkdownEngineTests
//
//  `TableStyle.cornerRadius`: the rendered table wrapper is clipped to a
//  rounded shape with the outer border rule stroked along the rounded path.
//  The default (0) keeps the historical square-cornered rendering, and the
//  radius participates in the render cache key.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Table corner radius")
struct TableCornerRadiusTests {

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
        return bitmap.colorAt(x: x, y: y)
    }

    @Test("default radius is zero and negatives clamp")
    func defaults() {
        #expect(TableStyle.default.cornerRadius == 0)
        #expect(MarkdownEditorConfiguration.default.table.cornerRadius == 0)
        #expect(TableStyle(cornerRadius: -3).cornerRadius == 0)
    }

    @Test("a radius empties the corner and keeps the mid-edge rule crisp")
    func roundedCornerPixels() throws {
        let source = "| head | col |\n|---|---|\n| a | b |"
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let aqua = try #require(NSAppearance(named: .aqua))

        var square = MarkdownEditorConfiguration.default
        square.theme.tableRule = .blue
        var rounded = square
        rounded.table.cornerRadius = 6

        let (squareImage, _) = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: square),
            appearance: aqua, availableWidth: 2000
        )
        let (roundedImage, _) = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: rounded),
            appearance: aqua, availableWidth: 2000
        )

        // The square wrapper inks the very corner; the rounded wrapper leaves
        // it empty.
        let squareCorner = try #require(sample(squareImage, x: 0, y: 0))
        let roundedCorner = try #require(sample(roundedImage, x: 0, y: 0))
        #expect(squareCorner.alphaComponent > 0.4)
        #expect(roundedCorner.alphaComponent < 0.1)

        // Mid-edge border rule stays inked (crisp rule along the rounded path).
        let midEdge = try #require(sample(roundedImage, x: 0, y: Int(roundedImage.size.height / 2)))
        #expect(midEdge.alphaComponent > 0.4)
        #expect(midEdge.blueComponent > 0.9)

        // The corner curve reconnects with the border within the radius: a
        // pixel just inside the corner diagonal is inked again.
        let onCurve = try #require(sample(roundedImage, x: 2, y: 2))
        #expect(onCurve.alphaComponent > 0.2)
    }

    @Test("changing the radius renders fresh instead of reusing the cache")
    func radiusChangeRendersFresh() throws {
        let source = "| rho | sigma |\n|---|---|\n| 21 | 22 |"
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let aqua = try #require(NSAppearance(named: .aqua))

        _ = MarkdownStyler.tableImage(
            for: source, parsed: parsed, ctx: makeContext(for: source),
            appearance: aqua, availableWidth: 2000
        )

        var rounded = MarkdownEditorConfiguration.default
        rounded.table.cornerRadius = 4
        let repainted = MarkdownStyler.tableImage(
            for: source, parsed: parsed,
            ctx: makeContext(for: source, configuration: rounded),
            appearance: aqua, availableWidth: 2000
        )
        #expect(repainted.rendered)
    }
}
