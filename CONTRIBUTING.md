# Contributing

The app is a Swift package targeting macOS 13+. Install Apple's Command Line
Tools. Python is only required for the optional debounce prototype.

- `swift build` compiles a development executable.
- `./test.sh` checks captured protocol packets, DPI encoding, bounds, and
  preservation of unrelated bytes without connecting to hardware.
- `./build-app.sh` creates a release app bundle in `dist/` for local use.
- `.build/debug/BurstControl --read` reads a connected supported mouse.

Use semantic commit messages, such as `feat: add verified setting` or
`fix: reject malformed replies`.

## Hardware changes

Keep transactions serialized and preserve unknown bytes. Verify command meaning,
value range, and profile scope before exposing a writable control. Document the
source of the mapping and distinguish packet read-back from measured behavior.
Do not guess command IDs or flash firmware. Capture a baseline and verify the
complete settings snapshot after a write.

`--verify-writes` performs real writes of the current values. It is a manual
hardware diagnostic, not part of the offline test suite. Do not run it in CI.

Include macOS version, connection type, and reproduction steps with bug reports.
Remove serial numbers, personal paths, and other private details from logs.
Do not contribute proprietary vendor binaries, firmware, updater credentials,
or downloaded installers. The `research/` directory is intentionally ignored.
