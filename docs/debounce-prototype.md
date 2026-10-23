# Original debounce prototype

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


