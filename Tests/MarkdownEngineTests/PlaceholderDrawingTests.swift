import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
struct PlaceholderDrawingTests {
    @Test func promptTracksFontSmoothingWhileKeepingItsTextAndVisibility() throws {
        _ = NSApplication.shared
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 40)
        let view = NativeTextView(frame: bounds)
        let prompt = NSAttributedString(string: "Write a note", attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.gray,
        ])
        view.setPlaceholder(prompt, usesFontSmoothing: MarkdownEditorConfiguration.default.paragraph.usesFontSmoothing)
        let label = try #require(view.placeholderView)
        #expect(label.usesFontSmoothing && !label.isHidden)
        label.frame = bounds
        let smooth = try bitmap { bounds in label.draw(bounds) }
        let expectedSmooth = try bitmap { bounds in
            prompt.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        #expect(smooth == expectedSmooth)
        view.setPlaceholder(prompt, usesFontSmoothing: false)
        #expect(view.placeholderView === label && !label.usesFontSmoothing)
        label.frame = bounds
        let unsmoothed = try bitmap { bounds in label.draw(bounds) }
        let expected = try bitmap { bounds in
            NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
            prompt.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        #expect(unsmoothed == expected)
        #expect(label.attributedText == prompt && !label.isHidden)
        view.string = "A note"
        view.refreshPlaceholderVisibility()
        #expect(label.isHidden)
        view.setPlaceholder(nil, usesFontSmoothing: false)
        #expect(label.superview == nil)
    }

    private func bitmap(draw: (CGRect) -> Void) throws -> Data {
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 800, bitsPerPixel: 32))
        let graphics = try #require(NSGraphicsContext(bitmapImageRep: image))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        graphics.cgContext.setAllowsFontSmoothing(true)
        graphics.cgContext.setShouldSmoothFonts(true)
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 40)
        NSColor.white.setFill()
        bounds.fill()
        draw(bounds)
        graphics.cgContext.flush()
        return Data(bytes: try #require(image.bitmapData), count: image.bytesPerRow * image.pixelsHigh)
    }
}
