# Live settings

Receiver presence uses IOHIDManager matching/removal callbacks without opening
an input stream. Foreground active-stage checks use the serialized MouseService actor with a
75 ms scheduling interval and at most one stage request in flight. The stage path
reads profile, sensor block, and profile again; it does not fetch unrelated settings
or battery. Full snapshots run every 15 seconds, or on reconnect/failure. Wired
read exchanges use a 10 ms settle delay validated on this mouse; receiver exchanges
retain 50 ms. Writes keep their original timing. This is faster polling, not an
instant event subscription, and receiver updates can take longer. Busy reads/writes
are skipped rather than queued by the timer.
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
