# Native engine combined integration 0.0.4

This is original engine development, not a finished GTA V port. User confirmed 0.0.3 static sector rendering on iPhone. 0.0.4 groups several systems into one device build.

Implemented together:
- Bounded YDD dictionary reader and drawable decoding at tagged root pointers.
- Verified base/time YTYP archetype-to-drawable aliases.
- Cached district asset index (released on memory warning).
- Three real YMAP sectors with world transforms; loading/decompression on loader actor, outside renderer.
- Transactional GPU uploads and explicit 96 MiB mesh cap, independent of total process memory.
- Orbit/free-flight camera, touch hold movement, reset and background input release.
- Conservative frustum culling per sector bounds (not occlusion culling or per-object visibility).
- FPS, CPU frame-callback p95 interval and mesh buffer bytes. These are not GPU timings or process resident RAM.
- Load/coverage/error diagnostics export. Active GPU scene is retained on memory warning; this is not a full streaming/eviction policy.

Local read-only format/geometry audit: 41 archives, 314 YDD dictionaries, 3282 indexed hashes; three integration maps resolve/decode 232/248 entities; 16 absent in district index; no supported-geometry decode errors; combined mesh buffers estimated 8,386,932 bytes. Python audit cross-checks layout; ASan tests exercise production Swift/C on synthetic fixtures. Real-device GPU validation is still needed for this build.

NOT COMPLETED: materials/textures, animation/skinning, world LOD selection and continuous streaming, collision world, player controller, NPC/vehicle simulation, game audio, native gameplay functions, script VM and mission execution, save compatibility. Free-flight camera is not a controllable GTA protagonist. No claim of full GTA gameplay.

## Combined device test
Select existing user data, tap `Thử tổng hợp`. This loads all three supported sectors together. Use `Bay / Xoay`, hold movement buttons and swipe view; pinch changes orbit zoom or flight speed. Toggle culling to compare scene consistency; reset camera; background/restore and verify movement stops. Data > export log shares coverage/errors. Single-model and single-sector views remain available.

## Rollback
Tag `checkpoint-sector-0.0.3` preserves the last device-confirmed version. Original game data never modified. No game files or asset keys included in source or IPA.

## Format references
Binary layouts were independently implemented, consulting public format facts, without copying implementation:
https://github.com/dexyfex/CodeWalker/blob/master/CodeWalker.Core/GameFiles/Resources/Drawable.cs
https://github.com/dexyfex/CodeWalker/blob/master/CodeWalker.Core/GameFiles/MetaTypes/MetaTypes.cs
