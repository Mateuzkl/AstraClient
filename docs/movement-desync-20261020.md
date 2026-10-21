# Movement desynchronization investigation (20 October 2026)

## Confirmed defects

The TFS 8.60 `0xC7` ItemDetails payload ends after its counted NPC records.
Both Astra handlers used to guess a trailing string and drain the remaining
network frame. A following `0x6D` movement could therefore disappear. Lua and
the native fallback now stop at the counted boundary. Native description pairs
are also read in explicit order: two `getString()` function arguments did not
guarantee wire-order evaluation in C++.

`0xC6` ItemValues is already count-delimited (`U16`, then six bytes per entry).
No transport change or separate-frame workaround is required. The regression
suite covers large ItemValues batches and chained metadata followed by movement.
The native regression uses the exact reader called by ProtocolGame and rejects
every truncated prefix of a representative payload, including NPC strings.

The parser fixes from PR #221 are now included from main. This branch retains
its additional native framing assertions; the LuaJIT reserved-word correction
and the rarity/relog lifecycle fixes from main are preserved.

## Cross-repository finding

On a dense player tile, TFS's tile description could omit top items or substitute
the viewer while its stack lookup counted the unmodified tile. The companion
server change makes descriptions, creature/item indices and incoming client
stack lookups use one bounded, allocation-free stack. This does not raise the
ten-thing protocol limit or change the viewport.

## Opt-in diagnostics

Enable Astra's existing `debugWalking` extra only during reproduction.
`[NetworkWalkTrace]` records include the runtime player ID, client milliseconds,
opcode offsets before/after Lua and native parsing, unread bytes, map center,
aware-range dimensions and mapped position/stack lookup results.
Trace diagnostics are limited to eight grants per frame and 32 per second
(at most two opcode-boundary lines per grant), including repeated large frames.

On the companion TFS branch, set `TFS_WALK_TRACE_PLAYER_GUID` before starting
the process to the numeric GUID of one test character. The server logs the same
runtime player ID, movement positions, old/new stacks, teleport status, opcode,
output-buffer offset and payload length. Unset the variable and restart to
disable tracing. No login credentials, IPs or decrypted packet contents are
included in these new diagnostics. Treat existing packet.log files as private.

## Reproduction still required

The exact Saike occurrence has not been reproduced on a live server. These fixes
prove specific parser/stack defects, not which one caused that occurrence.
Run 30 repetitions of login, fast walking during the first second, NPC entry,
death/respawn, teleport and reconnect using identical map/character/routes.
Compare default 18x14 logical awareness with larger visual panels (unchanged
awareness), and colorized loot enabled/disabled. Do not change the logical
viewport to 32x24 without a matching server protocol.

Retain commits, timestamps, both traces and the affected tile stacks from before
the first error. A `0xC6` trace ending at the following `0x6D` rules out an
ItemValues over-read in that frame. Do not infer causation from temporal overlap.

Battle Pass malformed-message drains and rejected Store chunks still merit a
separate versioned/framed protocol audit; neither is demonstrated as the cause
of Saike's valid movement stream. No speculative changes are made to those
formats. Arbitrary optional fields on alternative servers require explicit
negotiation, not probing the remainder of a shared frame.

## Focused checks

```sh
luajit .github/tests/item_details_opcode_framing.lua modules/game_protocol/protocol.lua src/client/protocolgameparse.cpp
c++ -std=c++17 -Wall -Wextra -Werror -pedantic -I. .github/tests/item_details_framing.cpp -o /tmp/item_details_framing
/tmp/item_details_framing
```

The same native test can be run with `-fsanitize=address,undefined`.
The complete native application and existing spectator harness are built with
CMake; the focused checks also run in Content validation.
The harness now executes the real native `parseCustomItemDetails`, ItemValues
and creature movement handlers on coalesced input and runs in Windows CI. The
standalone reader check is additional coverage, not a substitute for that test.

## Rarity refresh and relog lifecycle

Changing None/Frames/Corners now schedules a coalesced refresh immediately.
The full-refresh branch uses explicit control flow: `true and nil or dirtyIds`
always selects dirtyIds in Lua and previously prevented a full repaint.

The rarity registry stores records backed by native weak widget references,
not weak Lua userdata keys. Two userdata values may represent the same C++
widget; transient userdata can also be collected while that widget remains
visible. Destruction hooks now invalidate the shared record without indexing
the destroyed widget. Refresh resolves and retains a live native object, checks
its destroyed flag through an already-bound method, and only then accesses UI
fields. Old-session callbacks are generation-guarded before touching any state.

Regression coverage includes aliases, Lua GC, native weak expiration, live
Frames/Corners/None changes, destruction and callbacks already dequeued at relog.
The screenshot identifies the failing refresh path; reproducing the exact
Windows fatal exception with the user's running executable remains a manual
check after recompiling the updated client (the native weak-reference API is new).
