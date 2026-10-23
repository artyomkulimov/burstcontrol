# Motion sync boolean interpretation

The original UI disabled this setting for raw values above 1. That was too strict.
Static analysis of the official BURST_II_AIR.dll 1.0.0.15 shows:

- `0x1801461e0`: refreshes the motion-sync control after fetching the active sensor block via `0x180153410`.
- `0x180146297`: compares sensor byte `0x27` (39) with zero.
- `0x18014629b`: `setne dl` converts **any nonzero value** into true for the UI.
- `0x180143da3`: the control handler calls the setter `0x180157f90`.
- `0x180157ff9`: writes the supplied boolean to sensor byte 39.
- `0x1801580a1`: reset writes 1 to that byte.

Thus the captured value 255 is displayed as **On** by the vendor software. It is
not evidence that motion sync is unavailable. We have not established why the
firmware originally stored 255 rather than 1, nor measured the sensor's physical
behavior. This evidence establishes the vendor's interpretation and encoding.

Burst Control now follows that interpretation. Merely reading or editing another
setting preserves the original byte. Explicitly toggling writes 0 or 1, with the
existing full-block preservation and read-back checks. Restoring a backup uses
its boolean meaning. Offline regression checks cover 255, 0, 1, and preservation
of all other sensor bytes. No motion-sync hardware change was required to identify
this UI bug.

Vendor binaries and disassembly dumps are not distributed with this project.
