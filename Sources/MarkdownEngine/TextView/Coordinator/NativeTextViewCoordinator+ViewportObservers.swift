import AppKit

extension NativeTextViewCoordinator {
    /// Watches the clip view for viewport resizes and scrolls, the way
    /// `makeNSView` always has. The observers hold the views and this
    /// coordinator weakly, and their tokens are kept so `removeAllObservers()`
    /// can release them when SwiftUI dismantles the editor. Registered inline
    /// with strong captures and no tokens, every editor ever created stayed in
    /// memory and registered for the life of the app.
    func installViewportObservers(scrollView: ClampedScrollView, textView: NativeTextView) {
        removeViewportObservers()
        let center = NotificationCenter.default
        let clipView = scrollView.contentView
        var lastObservedViewportWidth = clipView.bounds.width
        viewportObservers.append(center.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: clipView,
            queue: nil
        ) { [weak self, weak scrollView, weak textView] _ in
            guard let self, let scrollView, let textView else { return }
            // Refresh code-block overlays only on real viewport width changes, not on TextKit height-only echoes during typing.
            let newWidth = scrollView.contentView.bounds.width
            if abs(newWidth - lastObservedViewportWidth) > 0.5 {
                lastObservedViewportWidth = newWidth
                // Re-center the column by position (no redraw) so it stays smooth during live resize.
                // Read readingWidth from the live textView.configuration (a class, captured by
                // reference) instead of the struct `configuration` captured by value at
                // makeNSView time — the embedder may change readingWidth between updates.
                if textView.configuration.readingWidth != nil {
                    textView.centerReadingColumn(forClipWidth: newWidth)
                }
                self.didEnsureLayoutForCurrentDocument = false
                self.updateCodeBlockSelection(textView: textView)
            }
            // Only react with overscroll recalc when the viewport itself resizes
            // (window resize). Without this guard, TextKit-induced frame changes echo
            // back here and re-trigger recalcOverscroll, causing a 149pt height
            // oscillation after clicks. Compare the CONTAINER (the document view) height
            // to the viewport — it tracks the viewport for short docs.
            guard let container = scrollView.documentView as? NativeTextViewContainer else { return }
            // Read heightBehavior from the live textView.configuration (a class,
            // captured by reference) — not the struct `configuration` captured by
            // value at makeNSView time. Without this, a runtime .fitsContent→.scrolls
            // switch leaves this closure permanently early-returning, so viewport-
            // resize-driven recalcOverscroll is skipped → stale overscroll.
            if textView.configuration.heightBehavior == .fitsContent {
                // In .fitsContent the container is content-tall (not viewport-tall),
                // so the container-vs-viewport guard below is always true — which
                // would fire recalcOverscroll on every clip-view frame change. Only
                // width changes need a re-measure (text re-wraps); height-only
                // changes are already handled by the width-change block above.
                return
            }
            guard abs(container.frame.height - scrollView.contentView.bounds.height) > 1 else { return }
            textView.recalcOverscroll(for: scrollView)
            scrollView.clampToInsets()
        })
        viewportObservers.append(center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: nil
        ) { [weak self, weak scrollView, weak textView] _ in
            guard let self, let scrollView, let textView else { return }
            textView.ensureVisibleLayout()
            if self.isWritingToolsActive {
                self.fixWritingToolsChildWindowIfNeeded(textView: textView)
            }
            scrollView.clampToInsets()
            self.refreshActiveLinkCaretRect()
            self.updateCodeBlockSelection(textView: textView)
        })
    }

    /// Drops the viewport observers registered by `installViewportObservers`.
    func removeViewportObservers() {
        viewportObservers.forEach(NotificationCenter.default.removeObserver(_:))
        viewportObservers.removeAll()
    }

    /// Everything this coordinator registered with the notification center,
    /// for when its editor goes away.
    func removeAllObservers() {
        removeViewportObservers()
        removeBusObservers()
    }
}
