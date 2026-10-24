import AppKit
import SwiftUI

// Keep the window on a standard backdrop, with Liquid Glass above it for controls.
// System materials follow the desktop, appearance, contrast, and accessibility settings.
struct WindowBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                DesktopMaterial()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DesktopMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = BackdropView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    private final class BackdropView: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.backgroundColor = .clear
            window?.isOpaque = false
        }
    }
}

struct GlassControls<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}

extension View {
    func controlGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(ControlGlass(shape: shape, interactive: interactive))
    }

    func glassAction(prominent: Bool = false) -> some View {
        modifier(GlassAction(prominent: prominent))
    }
}

private struct ControlGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content
                    .background(Color(nsColor: .controlBackgroundColor), in: shape)
                    .overlay(shape.strokeBorder(.primary.opacity(0.2), lineWidth: 1))
            } else if #available(macOS 26.0, *) {
                content.glassEffect(.regular.interactive(interactive), in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
                    .overlay(shape.strokeBorder(.primary.opacity(0.12), lineWidth: 1))
            }
        }
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(.primary.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

private struct GlassAction: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}
