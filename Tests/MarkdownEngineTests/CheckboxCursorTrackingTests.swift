//
//  CheckboxCursorTrackingTests.swift
//  MarkdownEngineTests
//
//  The app-wide cursor tracking area that keeps the checkbox pointing hand
//  (and the read-only link hand) alive while the editor's window isn't key.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Checkbox cursor tracking")
struct CheckboxCursorTrackingTests {

    @Test("updateTrackingAreas installs one app-active mouse-moved area")
    func trackingAreaInstalled() {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.updateTrackingAreas()
        let area = view.inactiveWindowCursorTrackingArea
        #expect(area != nil)
        if let area {
            #expect(view.trackingAreas.contains(area))
            #expect(area.options.contains(.mouseMoved))
            #expect(area.options.contains(.mouseEnteredAndExited))
            #expect(area.options.contains(.activeInActiveApp))
            #expect(area.options.contains(.inVisibleRect))
        }
    }

    @Test("repeated updates replace the area instead of stacking")
    func trackingAreaReplaced() {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.updateTrackingAreas()
        let first = view.inactiveWindowCursorTrackingArea
        view.updateTrackingAreas()
        let second = view.inactiveWindowCursorTrackingArea
        #expect(second != nil)
        #expect(first !== second)
        if let first {
            #expect(!view.trackingAreas.contains(first))
        }
        let ours = view.trackingAreas.filter { $0.options.contains(.activeInActiveApp) }
        #expect(ours.count == 1)
    }
}
