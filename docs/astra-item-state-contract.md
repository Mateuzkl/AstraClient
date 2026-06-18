# Astra item state contract

Astra item state is feature gated by the server. The client must only consume the new state when the server advertises the matching features:

- `GameDisplayItemDuration`: item duration bytes may be present.
- `GameDisplayItemCharges`: item charges bytes may be present.
- `GamePackedPlayerInventory`: opcode `0xF5` contains the packed inventory snapshot.

If `GamePackedPlayerInventory` is not enabled, the client clears any snapshot cache and ignores `0xF5` if it arrives. Actionbar item counts then fall back to old behavior: it must not gray out or block equip/use only because the snapshot count is missing.

If duration or charges features are not enabled, item parsing must not read those extra bytes. This keeps AstraClient compatible with servers that do not enable the new item-state contract and prevents packet desync with older behavior.

The server should only advertise these features to authenticated Astra clients with `astraItemStateEnabled` enabled and an active non-spectator player protocol.
