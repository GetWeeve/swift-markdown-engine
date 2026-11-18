//
//  NativeTextView.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//
//  AppKit `NSTextView` subclass used by the markdown editor. Stored state
//  lives here; behavior is split across `NativeTextView+<Feature>.swift`
//  files in this folder (frame & overscroll, caret workarounds, click remap,
//  paste handling, drag-select boost, task checkbox, spelling policy).
//
//  Bottom-overscroll math lives in `BottomOverscrollPolicy.swift`.
//  Pasteboard image inspection lives in `PasteboardImageReader.swift`.
//

import AppKit
import UniformTypeIdentifiers

final class NativeTextView: NSTextView {
    private var hasInsertionFocus = false

    var editingParagraph: NSRange? {
        guard hasInsertionFocus, isEditable, configuration.theme.editingParagraphText != nil else { return nil }
        let selection = selectedRange()
        let source = string as NSString
        guard selection.length == 0, selection.location <= source.length else { return nil }
        return source.paragraphRange(for: selection)
    }

    func updateEditability(_ editable: Bool) {
        guard isEditable != editable else { return }
        let oldParagraph = editingParagraph
        isEditable = editable
        guard let coordinator = delegate as? NativeTextViewCoordinator else { return }
        refreshEditingParagraph(oldParagraph ?? editingParagraph)
        if editable {
            let parsed = coordinator.parsedDocument(for: string)
            let selection = selectedRange()
            let active = coordinator.activeTokenIndices(parsed: parsed, selection: selection, in: string as NSString, suppressed: false)
            coordinator.resolvedCaretColor = coordinator.caretColor(at: selection.location, tokens: parsed.tokens, active: active)
        }
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        hasInsertionFocus = true
        refreshEditingParagraph(editingParagraph)
        return true
    }

    override func resignFirstResponder() -> Bool {
        let previous = editingParagraph
        guard super.resignFirstResponder() else { return false }
        hasInsertionFocus = false
        refreshEditingParagraph(previous)
        return true
    }

    private func refreshEditingParagraph(_ range: NSRange?) {
        guard let range, range.length > 0, let coordinator = delegate as? NativeTextViewCoordinator else { return }
        coordinator.restyleParagraphs([range], in: self)
    }

    // MARK: Frame & overscroll state
    var baseContentHeight: CGFloat = 0
    var activeBottomOverscroll: CGFloat = 0
    var isApplyingManagedFrameSize = false
    /// Set on switch/resize to force full-layout height measurement until the cascade settles.
    var pendingFullLayoutMeasure = false
    /// Coalesces wide-table overlay updates to once per runloop (resize fires many per frame).
    var pendingWideTableOverlayUpdate = false
    var suppressAutoRevealOnce: Bool = false
    // Set by clickedOnLink during a mouseDown: did the delegate fire (so
    // mouseDown can re-dispatch a click AppKit dropped), and did it navigate
    // (so the pre-click caret is restored — a link click isn't caret placement).
    var linkClickDidFire = false
    var linkClickDidNavigate = false

    // MARK: Configuration
    var configuration: MarkdownEditorConfiguration = .default {
        didSet {
            overscrollPercent = configuration.overscroll.percent
            maxOverscrollPoints = configuration.overscroll.maxPoints
            minOverscrollPoints = configuration.overscroll.minPoints
        }
    }
    var overscrollPercent: CGFloat = MarkdownEditorConfiguration.default.overscroll.percent
    var maxOverscrollPoints: CGFloat = MarkdownEditorConfiguration.default.overscroll.maxPoints
    var minOverscrollPoints: CGFloat = MarkdownEditorConfiguration.default.overscroll.minPoints

    // MARK: Editor wiring
    var onPasteImage: ((NSPasteboard) -> String?)?
    weak var layoutBridge: LayoutBridge?
    var baseFont: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    // MARK: Caret-workaround state
    var caretIndicatorObservation: NSKeyValueObservation?
    weak var observedCaretIndicator: NSView?
    var isApplyingCaretShift: Bool = false

    // MARK: Cursor-tracking state
    /// Keeps hover cursors (checkbox hand, read-only link hand) alive while
    /// the window isn't key; installed by `updateTrackingAreas` in
    /// `NativeTextView+CursorRects.swift`.
    var inactiveWindowCursorTrackingArea: NSTrackingArea?

    // MARK: Drag-select state
    var dragStartMouseScreenLoc: NSPoint?

    // MARK: Placeholder state
    /// Click-through ghost-text label shown while the document is empty;
    /// managed by `NativeTextView+Placeholder.swift`.
    weak var placeholderView: PlaceholderLabelView?

    // MARK: Cursor exclusion
    /// Embedder-supplied predicate that suppresses the I-beam cursor in edit mode.
    /// Called on every mouse-move with the event location in window coordinates.
    /// Return `true` to show the arrow cursor instead of the edit-mode I-beam.
    var isCursorExcluded: ((CGPoint) -> Bool)?

    // MARK: Wide-table overlay state
    /// Live NSScrollView per wide table; keyed by source-ID hash.
    var wideTableOverlays: [Int: WideTableOverlay] = [:]
    /// Persisted horizontal scroll offset per wide table; survives restyles.
    var tableHorizontalScrollOffsets: [Int: CGFloat] = [:]

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Forward appearance changes to the embedder's highlighter via its registered notification.
        if let name = configuration.services.syntaxHighlighter.appearanceDidChangeNotification {
            NotificationCenter.default.post(name: name, object: self)
        }
    }

    // setMarkedText skips textDidChange, so restyle the marked paragraph to apply markdown attrs.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        guard hasMarkedText(),
              let coord = delegate as? NativeTextViewCoordinator else { return }
        let marked = markedRange()
        guard marked.location != NSNotFound, marked.length > 0 else { return }
        // The composition mutated the storage without textDidChange, and
        // shouldChangeTextIn's own parse re-cached the PRE-edit string at the
        // current generation — bump so the restyle below reparses instead of
        // serving that stale document (same-length composition updates).
        coord.parseGeneration &+= 1
        // Census bookkeeping never saw this mutation → next census full-scans.
        coord.backtickCensusNeedsRescan = true
        let nsText = self.string as NSString
        let paragraph = nsText.paragraphRange(for: marked)
        coord.restyleParagraphs([paragraph], in: self)
    }

    deinit { caretIndicatorObservation?.invalidate() }
}
