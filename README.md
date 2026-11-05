# Mugoat independently authored native engine — IN DEVELOPMENT

Own Swift/Metal code, not a renamed GTA IPA. Current implemented components: bounded RPF7 reader with native AES tables, resource decompression, static Float3 drawable geometry decoding, normals, ray/triangle collision, fixed-step clock and direct Metal mesh rendering. The iOS lab imports a data folder, lists actual drawable assets and lets the user orbit/zoom them.

**This does not yet run GTA V gameplay.** World placement/streaming, materials/textures, skeletal animation, player/vehicle behavior, gameplay natives/scripts, missions and audio are NOT COMPLETED. A model viewer is not counted as project completion.

Developer data is never edited, copied into this repo or uploaded. CI uses synthetic geometry and a public fake test key only. The private asset key is derived locally from the owner's existing runtime data section; no WASM instructions or supplied IPA engine are executed by this project. Private keys and locally extracted mesh files remain under ignored build/.

Build on macOS with Xcode and XcodeGen: `xcodegen generate`, then build the MugoatOwnEngine scheme. A manual/push workflow validates the parser with ASan and builds an unsigned iPhone lab app. Device rendering and FPS are NOT TESTED until exercised on an iPhone.

Format references: https://github.com/dexyfex/CodeWalker (format facts only; no implementation copied). Zstandard is the BSD-licensed 1.5.7 dependency under Vendor/zstd, with its original notices. All other original code in this repository is MIT licensed.

## Documents data discovery (Lab 0.0.2)

Copy/move the existing game folder with the iOS Files app to On My iPhone > Mugoat Own Engine Lab > game, so it directly contains data/ and b/. The app now discovers it at startup/foreground without requiring the picker or making a second copy. Data > Find in Documents rescans; Data > Choose folder remains available. A small instruction file ensures the app Documents location is visible. Discovery is metadata-only and skips asset directories. Diagnostic errors are no longer overwritten by the FPS counter. Preserve the bundle ID and install the update over the app to retain existing Documents data.
