# Interface

Burst Control uses SwiftUI and AppKit. On macOS 26, its control surfaces use
Apple's native Liquid Glass: glassEffect, GlassEffectContainer, and the
glass / glassProminent button styles.

The window has a standard AppKit backdrop that blends with the desktop.
Glass sits above it on the five-stage DPI control, the Response and Tracking
controls, the device button, and the Apply/Revert actions. Glass surfaces are
grouped for rendering and aren't nested inside other glass surfaces. There is
no animated wallpaper, continuous visual timer, or custom rendering loop.

The active DPI stage comes from the mouse. Clicking a value edits that stage's
stored sensitivity; it never switches the active stage. All changes remain a
draft until Apply. The active stage has a label and underline as well as color.
Clicking outside a text field ends editing without consuming the destination
control's click. Invalid values revert to the last valid value.

The interface follows light/dark appearance and the system accent color.
Reduce Transparency substitutes opaque control surfaces; Increase Contrast
adds visible boundaries. On macOS 13–15, controls use standard materials and
button styles. Build with Xcode 26 or later; Liquid Glass API calls are guarded
by availability checks.

Native UI inspection uses an isolated fixture app in ignored build output.
Its model cannot access HID and its Apply action only updates in-memory
fixtures. Mouse settings are not changed to exercise the interface.

References:

- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
