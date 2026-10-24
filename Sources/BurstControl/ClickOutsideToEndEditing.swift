import AppKit
import SwiftUI

// Non-focusable labels and empty areas don't normally end NSTextField editing.
// Observe only clicks delivered to this app, without swallowing the clicked control's event.
struct ClickOutsideToEndEditing: NSViewRepresentable {
    func makeNSView(context: Context) -> ClickObserverView { ClickObserverView() }

    func updateNSView(_ view: ClickObserverView, context: Context) {
        view.updateMonitor()
    }

    static func dismantleNSView(_ view: ClickObserverView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class ClickObserverView: NSView {
        private var monitor: Any?

        // Attach once outside the glass hierarchy, which can reparent its views.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        func updateMonitor() {
            guard window != nil else { stopMonitoring(); return }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let window = self?.window, event.window === window,
                      let editor = window.firstResponder as? NSTextView,
                      editor.isFieldEditor else { return event }
                // The real AppKit editor remains the source of truth even when
                // SwiftUI lifts the surrounding controls into a glass layer.
                let field = (editor.delegate as? NSView) ?? editor
                let fieldRect = field.convert(field.bounds, to: nil)
                if !fieldRect.contains(event.locationInWindow) {
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
