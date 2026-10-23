# Burst Control — Burst II Air for macOS

Native SwiftUI + IOKit app for Turtle Beach Burst II Air on macOS 13+.
No Windows, VM, Python backend, or input interception. USB receiver presence is
event-driven. While foregrounded, the app checks settings every three seconds
(skipping checks during another operation) to follow the physical DPI button
and wireless availability. Periodic checks pause when the app is inactive.
Quit after applying if you do not need live status.

Independent, unofficial open-source project. Not affiliated with or endorsed by
Turtle Beach. Vendor software, firmware, and downloaded binaries are not included.

## Run

Build from source using the instructions below, quit any running copy, run `./install-app.sh`, then open `~/Applications/Burst Control.app`. Connect the mouse by USB cable or plug in its 2.4 GHz receiver and wake it.
If macOS denies access, enable **Burst Control** in **System Settings → Privacy &
Security → Input Monitoring**, then quit and reopen. The configuration feature
report shares a HID interface with mouse input; the app never registers input
callbacks or records keys/clicks. Local development builds are ad-hoc signed;
rebuilding changes the signature and may leave a stale permission even when the
toggle is on. Remove the old Burst Control entry with the minus button, then use
plus to add `~/Applications/Burst Control.app`, enable it, and restart the app.
If removal does not clear it, `tccutil reset ListenEvent local.burstcontrol.app`
revokes only this app's Input Monitoring record; then add the installed app again.
Keep using the installed copy. A stable path avoids duplicate registrations,
but does not make ad-hoc signatures survive rebuilds. Distribution builds should
use a consistent signing identity.

Change controls and click **Apply to mouse**. Every write is backed up, then
read back and compared. **Backups → Load previous settings** stages the prior
values for review; click Apply to restore them. Backups live in
`~/Library/Application Support/Burst Control/`.

| Control | Supported values | Evidence / limit |
| --- | --- | --- |
| Debounce | 0–10 ms | Actual change from 2 to 0 read back successfully |
| Five DPI stage values | 50–26,000 in increments of 50 | Vendor encoding mapped; sensor block round-trip verified |
| Polling rate | 125, 250, 500, 1000 Hz | Vendor enumeration mapped; sensor block round-trip verified |
| Lift-off distance | Very low, Low | Vendor modes mapped; original-value write/read verified |
| Angle snapping | Off, On | Vendor field mapped; sensor block round-trip verified |
| Motion sync | Off, On | Vendor reads zero as off and any nonzero byte (including 255) as on; explicit edits write 0/1 |
| Battery | 0–100%, read only | Status block 0, byte 5; charging flag at byte 7 |
| Current profile | Read only | Profile changes during transactions are rejected |

DPI stage enabling and switching, wireless optimization, sleep interval, button
assignments and custom surface calibration remain unexposed until their full
semantics and supported values are verified. Unmapped bytes are preserved.
USB receiver `10f5:5004` and wired mouse `10f5:5002` are supported. Cable is preferred
when both are present. Bluetooth is unsupported. Battery percentage and charging
state come from the read-only device status block; invalid values display as unavailable.
Changing settings has not been benchmarked for physical input latency. A firmware
setting of 0 ms does not imply zero total latency. Power-cycle persistence is
not yet tested. The app never flashes firmware.

## Build and check

Requires Apple's Command Line Tools and Swift:

```sh
./build-app.sh
./test.sh
.build/release/BurstControl --read
```

`--verify-writes` rewrites the current sensor, debounce and lift-off values and
checks full snapshots. It performs real hardware writes; use only intentionally.
Protocol tests run against a captured fixture and do not need hardware.

## Protocol evidence

Recovered from the official BURST_II_AIR.dll 1.0.0.15. The Swift implementation
checks headers, checksums, profile consistency, and read-back. Configuration
transactions run serially on a worker actor, outside the UI and mouse input path.

Sensor block: kind 2, active profile, sub 1, 40 bytes. DPI values are little-endian
words at offsets 2/4/6/8/10, encoded as DPI/50−1. Byte 37 is angle snapping,
38 polling index, 39 motion sync. Lift-off: kind 7, read four bytes/write one.
Debounce: kind 6, one byte. Other bytes are preserved exactly.

Vendor setter addresses: DPI `0x180155dc0`, polling `0x1801580e0`, angle snapping
`0x180155400`, motion sync `0x180157f90`, lift-off `0x180155710`.

## Original debounce investigation

The optional Python prototype is independent of the native app. To use it:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python burst_debounce.py
```

Set 0 ms, or restore the original 2 ms:

```sh
.venv/bin/python burst_debounce.py --set-ms 0
.venv/bin/python burst_debounce.py --set-ms 2
```

## Verified result

On 2026-10-23, initial device read returned 2 ms. The explicit write to 0 ms
succeeded, as did immediate read-back and a fresh-process read after closing
and reopening the HID handle. Power-cycle persistence has not yet been tested.
This reads the firmware setting; it does not measure physical click latency.
This original Python utility was tested only with the dongle; the native app also supports cable. Neither updates firmware.

The captured settings fixture in `Tests/Fixtures/settings.json` contains device
configuration bytes only. Local investigation logs are excluded from this repository.
The Python prototype writes its own backups and transaction logs to `research/`.

## Protocol evidence

Recovered by static analysis of the official BURST_II_AIR.dll version 1.0.0.15:
https://cdn.turtlebeach.com/device/driver-dll/burst-ii-air/burst-ii-air_330-1.0.0.15-6400-v1.7z

The downloaded archive MD5 matches its updater manifest:
`412bb2c724a2d255291cd5fdc4c7a040`.

Relevant DLL virtual addresses:

- `0x18015c99f`: debounce read header construction.
- `0x18014ee00`: debounce write header construction.
- `0x18015d4d0`: read transport.
- `0x1801638c0`: write transport.
- `0x180162740`: dongle transaction acquire/release.

Use interface 1, vendor usage page 0xff00, HID feature report 3. Requests are
64 bytes: report ID, additive checksum of bytes 2–63, command, payload length,
zero, target (1 = wireless), then payload. macOS returns variable-length replies:
report ID, echoed command, status, payload length, zero, payload.

Acquire/release: commands 0x80/0x81, no payload. Transactions use command 0x82.
Read header: `40 00 06 00 00 00 00 01 00 00`.
Write header: `40 01 06 00 00 00 00 01 00 VV`, where VV is the setting/checksum.
Header reply appends the supported chunk size. Read data request: 0x81 plus
57 zeros. Reply: 0x81 plus debounce byte; verify against header checksum.
Write data: 0x81 plus debounce byte. Commit: 0xc0, expected reply `c0 00`.
Always release the transaction. No arbitrary command scanning or firmware writes
were used. Discovery GET_REPORT requests without a preceding command timed out;
valid transactions succeeded after reproducing the vendor handshake.


## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and protocol verification.
Original project code is available under the [MIT license](LICENSE).

Motion sync investigation: [protocol notes](docs/motion-sync.md).
The reproducible raster app icon is documented in [Assets](Assets/README.md).

Read [How the protocol was reverse engineered](docs/reverse-engineering.md) for the investigation, evidence, and limitations.
