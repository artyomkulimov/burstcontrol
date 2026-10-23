# How Burst Control talks to the mouse

Burst Control reimplements the mouse configuration protocol on macOS. The mouse
already knows how to store DPI, debounce, and other settings; Windows software
normally sends it the commands. We needed to learn those commands and reproduce
them through Apple's HID APIs. We did not modify or replace the mouse firmware.

## 1. Identify the USB device and its interfaces

We inspected macOS's USB registry and HID enumeration. The wireless receiver
uses vendor/product IDs `10f5:5004`; the mouse connected by cable uses
`10f5:5002`. Both have multiple HID collections. A normal mouse collection carries
movement and buttons, while a vendor-defined collection on interface 1 exposes
feature report 3 for configuration. Matching usage page `0xff00`, usage 1 selects
that configuration interface.

This distinction matters: “send bytes to the mouse” is not specific enough.
The interface, report type, report ID, packet format, and ordering must all match.

## 2. Inspect the official configuration module without running Windows

We downloaded the official Swarm II distribution and extracted its Burst II Air
module, `BURST_II_AIR.dll` version 1.0.0.15. Device modules are distributed separately
by the updater. The module archive's MD5 matched the updater manifest; this was
an integrity cross-check, not proof that MD5 is a secure signature.

The DLL contains compiled x86-64 instructions. `pefile` let us inspect its Windows
PE layout, imports, and data; Capstone translated machine instructions into
assembly. Strings such as setting names and battery debug messages gave us starting
points. We followed references from those strings to UI handlers, setters, and
USB read/write functions. Vendor binaries and updater configuration are kept out
of this repository.

This was **static analysis**, followed by real-device experiments. We did not
capture traffic from a running Windows VM or claim access to the vendor's source.

## 3. Reconstruct the packet envelope and transaction

A request is a 64-byte HID feature report:

| Offset | Meaning |
| --- | --- |
| 0 | Report ID: 3 |
| 1 | Sum of bytes 2–63, modulo 256 |
| 2 | Command |
| 3 | Payload length |
| 4 | Reserved, zero |
| 5 | Target: 0 for cable, 1 for wireless mouse |
| 6 onward | Payload followed by zero padding |

The receiver uses command `0x80` to acquire a transaction and `0x81` to release
it. The wired path skips those commands: the vendor function at `0x180162740`
returns immediately unless the connection type is 1. Sending the wireless
handshake over cable initially failed; following this branch explained why.

Command `0x82` carries a settings-block transaction. A read starts with a ten-byte
header specifying block kind, profile, sub-index, and length. The response includes
the data checksum and chunk size. Subsequent requests fetch numbered chunks.
Writes send a header, numbered data chunks, and a `0xc0` commit. The reply must
acknowledge success, then we read the complete data back.

The reply layout differs from the request, and macOS returns variable-length
replies. Assuming every reply was also 64 bytes would reject valid responses.

## 4. Work backward from controls to byte offsets

A UI setter reveals which byte changes; its caller reveals what that byte means.
We checked both, rather than attaching names to bytes that merely changed.

| Field | Location / encoding |
| --- | --- |
| Debounce | Block 6, one byte, 0–10 ms |
| DPI stages | Block 2, little-endian words at offsets 2, 4, 6, 8, 10; `(word + 1) × 50` DPI |
| Active DPI stage | Block 2, byte 1, zero-based; display only |
| Angle snapping | Block 2, byte 37 |
| Polling | Block 2, byte 38; indices for 125, 250, 500, 1000 Hz |
| Motion sync | Block 2, byte 39; nonzero means on |
| Lift-off mode | Block 7; read four bytes, write the first byte |
| Battery | Block 0, ten bytes; percentage at offset 5, charging flag at offset 7 |

An instructive mistake was motion sync. The first app only recognized 0 and 1,
but this mouse returned 255. We initially disabled the control. Further analysis
showed the vendor UI uses `cmp ... 0` followed by `setne`: **any nonzero value is
true**. We corrected the UI while preserving 255 until an explicit edit. We still
do not know why that firmware originally stored 255 instead of 1.

For battery, the debug string `refresh_battery_status level: ... charging: ...`
led to reads from state offsets `0x110` and `0x112`. The status reader at
`0x18015cdf0` fetches block 0 with length 10 and copies it to state offset `0x10b`.
Subtracting the base gives status offsets 5 and 7. We therefore display the
reported percentage directly, not an estimate from voltage or elapsed time.
USB connection alone is not treated as proof that the charging flag is set.

## 5. Validate on hardware in small steps

The first successful debounce read returned 2 ms. We wrote 0 ms, checked the
acknowledgment, read it back, closed the HID handle, and read it again from a fresh
process. The setting still returned 0 ms. That confirms a configuration value,
not a measurement of physical click latency or a power-cycle persistence test.

For additional blocks, we first rewrote the existing values and compared complete
snapshots. This checks transport and byte preservation without changing the user's
chosen configuration. Wired reads also matched the existing settings, and the
first wired battery read returned 51%. Live battery values may change thereafter.

Offline tests use captured configuration bytes to check packet checksums, DPI
encoding, value bounds, active-stage interpretation, edit merging, and preservation
of unrelated bytes. They cannot substitute for connecting each supported transport.

## 6. Build a native client

The initial experiment used Python and hidapi. The application uses SwiftUI and
IOKit directly, with configuration transactions serialized on a worker actor.
It neither intercepts nor synthesizes mouse movement. USB arrival/removal events
update connection state; foreground checks keep the active stage and battery
current. Automatic reads never apply staged edits.

Battery and transport are separate from editable settings, so a battery change
cannot cause a false settings conflict or enter a settings write. If a status read
fails or contains an invalid percentage, battery becomes unavailable rather than
showing a fabricated value.

macOS requires Input Monitoring to open this composite HID interface even though
we do not subscribe to its movement/keyboard reports. Locally ad-hoc-signed builds
change identity on rebuild. An enabled but stale permission entry caused real
failures; the TCC logs showed the old and new signature hashes did not match.
Removing that app-specific permission record and granting access to the installed
build fixed it. A stable release signing identity is still needed for smooth
public updates.

## Limits

- Bluetooth is not implemented.
- The app supports one selected mouse; it prefers cable over a receiver.
- Packet read-back does not prove latency, battery accuracy, or every sensor effect.
- Unknown settings remain untouched. Firmware updates and arbitrary command scans
  are outside this implementation.
- DLL addresses refer to the inspected version and may move in later releases.

The transport implementation is in `Sources/BurstControl/HID.swift`; field mappings
and preservation rules are in `Settings.swift`. The repository contains original
client code and protocol notes, not vendor software or firmware.
