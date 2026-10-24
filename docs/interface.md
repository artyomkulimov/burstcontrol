# Interface

The interface uses SwiftUI's native macOS toolbar and grouped settings form.
Device status, battery, and the device menu live in the toolbar. Sensitivity comes
first, with all five editable stages visible and the active stage identified by
text, an underline, and an accent background. Editing a stage does not switch it.

On macOS 26, the floating Apply/Revert control uses SwiftUI's real `glassEffect`
with the regular Liquid Glass material. Settings cards remain ordinary content
surfaces. On macOS 13–15 the action bar uses regular material; Reduce Transparency
uses an opaque system-colored background and border. Native controls follow the
system appearance. No custom motion or continuously animated effects are added.

References:

- [Apple Human Interface Guidelines: materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

Build with Xcode 26 or newer for the Liquid Glass APIs. The deployment target
remains macOS 13; the new API is availability-guarded.

For hardware-free UI inspection, a debug build supports `--preview`. It loads
`Tests/Fixtures/settings.json` from the source checkout, labels the connection as
a preview, and skips device monitoring, reads, writes, and backup restoration.
Apply in this mode discards the draft instead of writing to hardware. This
fixture-loading entry point is excluded from release builds.
