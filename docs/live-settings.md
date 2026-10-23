# Live settings

Receiver presence uses IOHIDManager matching/removal callbacks without opening
an input stream. Foreground checks every three seconds read configuration through
the serialized MouseService actor. Busy reads/writes are never queued by the timer.
The app checks again on foreground activation; periodic checks stop when inactive.
A receiver being present is not treated as proof the wireless mouse is responding.
Failed transactions display “Mouse not responding” rather than claiming powered-off.

The active stage is sensor byte 1, zero-based. In vendor DLL 1.0.0.15,
0x180146143 reads that byte for the DPI UI; 0x1800c4287 adds one for the displayed
stage number. The app never writes a requested stage switch.

Reads preserve staged edits. A physical stage change is merged without conflict;
other external changes require choosing the mouse values or keeping the edited
fields on the new baseline. Cross-profile edits cannot be carried over. Apply
rechecks the snapshot, preserves the latest active stage, and verifies writes.
A hardware change during a write still causes a read-back failure, not silent success.

Hardware reconnect and physical-button behavior require manual testing; offline
tests cover stage decoding, edit merging, and preservation of external changes.
