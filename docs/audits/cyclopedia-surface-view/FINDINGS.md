# Findings

1. `lootData` belongs to the sandboxed quickloot module. Cross-module reads now use an explicit API; unavailable configuration disables the control rather than fabricating a profile.
2. Legacy `setCurrentView`/`setLevelSeparator` shims did not render satellite floors. New native Surface controls feed the existing PNG renderer.
3. Opening Cyclopedia used unnecessary global OTMM save/load and opened Items before Map. Both paths were removed.
4. Tab changes destroyed children but left their panel parents alive. The old panel is now destroyed.
5. Closing/hiding a real minimap synthesized custom region clicks. Hiding now only closes its flag dialog.
6. Static real-map markers were eagerly converted into widgets in 125-marker batches. The user's profiler shows this consuming about 81-82% of callback time. This is the primary pending performance fix, not evidence of server bandwidth saturation.
7. Legacy region-discovery/donation APIs are compatibility shims in this 8.60 client. No modern Canary discovery/donation functionality is claimed or invented here.
