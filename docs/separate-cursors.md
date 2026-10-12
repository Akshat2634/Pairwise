# Separate cursors in PairDesk 0.4.0

The pairing goal is that each person can point at code independently, while only
one action stream changes the shared Mac at a time. macOS applications still have
one keyboard focus and one native mouse. This is not separate desktop sessions or
simultaneous editing at two insertion points.

## Current behavior

- The sharing Mac keeps its native cursor. Each viewer has a coloured arrow and
  name rendered by a transparent, click-through panel on the selected display.
  The panel cannot activate PairDesk or intercept clicks. It is included in the
  shared video, so everyone sees the same pointers.
- A viewer moving the mouse sends cursor presence. Hover does not acquire a
  control lease, inject mouse movement, change focus, or keep another person out
  of control. Idle cursors refresh once per second; leaving the viewer hides the
  pointer, and disconnected/stale pointers expire after three seconds.
- Clicks, drags, scrolls, and typing still use the authenticated two-second
  control lease. Remote drags use the native pointer for the action; after button
  release it returns to the owner's saved position. An owner mouse action takes
  priority over this restoration. Scroll events target the viewer's pointer.
- An owner click, key, scroll, or movement during a remote drag revokes remote
  input and clears pending actions. A 400 ms quiet interval avoids fighting the
  owner's current action. The viewer retries with a fresh click or key; input
  rejected during takeover is not replayed later.
- The viewer's native cursor is hidden only inside the shared image when this
  mode is advertised. Its coloured cursor arrives through the video and therefore
  has media-path latency. Letterbox margins and other apps retain normal cursors.

## Protocol and compatibility

The host advertises an optional `cursorSession` epoch in the existing
`pairdesk.control.v1` availability message. A viewer sends `cursor` packets only
to that host, without a control grant. The host accepts packets only from current
authenticated call participants, for the active display-share epoch, with valid
normalized coordinates and increasing sequence numbers. Old-share and reordered
packets cannot resurrect a stale pointer.

Cursor traffic is lossy, limited to 30 updates per second, and coalesced to one
pending update. It does not enter the reliable ordered action queue. Closing the
share or call destroys the panel and clears presence, tasks, and session state.

Install 0.4.0 on both ends for independent pointers. Older hosts do not advertise
the mode, so new viewers keep the existing shared-cursor behavior. Older viewers
continue using the legacy input protocol when connected to a new host. Window
sharing stays view-only. On macOS 15.2+, the selected display ID comes directly
from the picker filter; on earlier macOS versions remote input is enabled only
when the display can be mapped safely (one connected display).

## Validation and remaining acceptance

Unit checks cover hover versus drag routing, authenticated sender/session/sequence
validation, invalid coordinates, cursor exit, owner-busy availability, and global
display-to-AppKit coordinate mapping. Snapshot fixtures cover arrow hotspots,
participant labels, and labels near display edges.

Two-Mac acceptance is still required: verify the host overlay appears in captured
video; both people can hover without moving the other's pointer; clicks, typing,
dragging, and scroll work; the owner can interrupt; Stop/Resume, hangup, reconnect,
sleep/wake and changing displays release all held input and remove overlays. Test
Retina scaling, multiple displays, full-screen apps, and mixed old/new versions.
Do not treat a rendered fixture or a passing unit test as proof of native input
delivery. Remote keyboard input was confirmed by the team on 0.3.9; the new cursor
mode has not yet been accepted between two physical Macs.

## Inspiration

[Tuple's multi-cursor explanation](https://tuple.app/blog/three-player-improvements)
describes one cursor per participant. PairDesk's implementation above is its own
incremental design, with the shared macOS action and video-latency limitations
made explicit.
