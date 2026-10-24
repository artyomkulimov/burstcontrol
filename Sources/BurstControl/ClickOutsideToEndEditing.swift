import AppKit
import SwiftUI

// Non-focusable labels and empty areas don't normally end NSTextField editing.
// Observe only clicks delivered to this app, without swallowing the clicked control's event.
struct ClickOutsideToEndEditing: NSViewRepresentable {
    let isEditing: Bool
    let endEditing: () -> Void

    func makeNSView(context: Context) -> ClickObserverView { ClickObserverView() }

    func updateNSView(_ view: ClickObserverView, context: Context) {
        view.endEditing = endEditing
        view.isEditing = isEditing
        view.updateMonitor()
    }

    static func dismantleNSView(_ view: ClickObserverView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class ClickObserverView: NSView {
        var isEditing = false
        var endEditing: (() -> Void)?
        private var monitor: Any?

        // This is a geometry anchor behind the field, never an input target.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        func updateMonitor() {
            guard isEditing, window != nil else { stopMonitoring(); return }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, self.isEditing, let window = self.window,
                      event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.visibleRect.contains(point) {
                    self.endEditing?()
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
