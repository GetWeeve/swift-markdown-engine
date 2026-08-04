//
//  TaskCheckboxRendererTests.swift
//  MarkdownEngineTests
//
//  The TaskCheckboxRenderer service: embedders can replace the pixels of the
//  drawn task checkbox while the engine keeps geometry and hit-testing.
//

import AppKit
import Testing
@testable import MarkdownEngine

@Suite("TaskCheckboxRenderer service")
struct TaskCheckboxRendererTests {

    @Test("Default services carry the system renderer, which defers")
    func defaultRendererDefers() {
        let services = MarkdownEditorServices.default
        #expect(services.taskCheckboxes is SystemTaskCheckboxRenderer)
        #expect(services.taskCheckboxes.image(checked: false, size: 20, appearance: nil) == nil)
        #expect(services.taskCheckboxes.image(checked: true, size: 20, appearance: NSAppearance(named: .darkAqua)) == nil)
    }

    struct RecordingRenderer: TaskCheckboxRenderer {
        final class Log: @unchecked Sendable {
            var calls: [(checked: Bool, size: CGFloat, appearanceName: NSAppearance.Name?)] = []
        }
        let log = Log()
        func image(checked: Bool, size: CGFloat, appearance: NSAppearance?) -> NSImage? {
            log.calls.append((checked, size, appearance?.name))
            return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                (checked ? NSColor.systemRed : NSColor.systemGray).setFill()
                rect.fill()
                return true
            }
        }
    }

    @Test("A custom renderer is carried by the configuration and receives the box state")
    func customRendererIsReachableThroughConfiguration() {
        let renderer = RecordingRenderer()
        var services = MarkdownEditorServices()
        services.taskCheckboxes = renderer
        let config = MarkdownEditorConfiguration(services: services)

        let image = config.services.taskCheckboxes.image(
            checked: true, size: 20, appearance: NSAppearance(named: .aqua)
        )
        #expect(image != nil)
        #expect(image?.size == NSSize(width: 20, height: 20))
        #expect(renderer.log.calls.count == 1)
        #expect(renderer.log.calls.first?.checked == true)
        #expect(renderer.log.calls.first?.size == 20)
        #expect(renderer.log.calls.first?.appearanceName == .aqua)
    }
}
