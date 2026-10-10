# Findings

1. `lootData` belongs to the sandboxed quickloot module. Cross-module reads now use an explicit API; unavailable configuration disables the control rather than fabricating a profile.
2. Legacy `setCurrentView`/`setLevelSeparator` shims did not render satellite floors. New native Surface controls feed the existing PNG renderer.
3. Opening Cyclopedia used unnecessary global OTMM save/load and opened Items before Map. Both paths were removed.
4. Tab changes destroyed children but left their panel parents alive. The old panel is now destroyed.
5. Closing/hiding a real minimap synthesized custom region clicks. Hiding now only closes its flag dialog.
6. Static real-map markers were eagerly converted into widgets in 125-marker batches. The user's profiler shows this consuming about 81-82% of callback time. Fixed by one reusable spatial data index, a bounded nearest/priority query and at most 128 visible icon widgets, with at most 16 new icons / a 4 ms admission deadline per slice. This is not a hard real-time guarantee for texture creation or OS scheduling.
7. Legacy region-discovery/donation APIs are compatibility shims in this 8.60 client. No modern Canary discovery/donation functionality is claimed or invented here.
8. Map setup requested two balances every open although local resource values were available. Those requests were removed; pan/zoom/radios/labels/slider are local operations.
9. Map close called auto-aim profile serialization unconditionally. Persistence is now dirty-driven; actual edits are still saved.
10. A real-minimap flag editor destroyed its own map before creating a dialog. It now keeps the same map alive and restores it on confirmation/cancel. Marks use stable IDs and deduplication; deleting one no longer risks overwriting another through array-length-based IDs.
11. Filter button state did not match persisted ignored paths, and Show All inverted individual filters. Both now set the intended state explicitly and coalesce one viewport refresh.
12. Review follow-ups: legacy positional `ignoreFlag` settings are initialized/applied to the virtualized catalog; fullMinimap view names are preserved; House previews use a single selected surface floor instead of Map's explicit composite mode; automatic underground/surface transitions save and restore per-view zoom.
13. Optional town metadata parsing must not prevent publishing a complete PNG/OTMM pack. A dedicated parse exception is caught for optional labels only; world-hash mismatch, write errors, and incomplete terrain outputs still fail the build.
