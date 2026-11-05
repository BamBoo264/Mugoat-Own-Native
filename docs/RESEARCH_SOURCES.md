# Format/API research

- Drawable and resource field-layout facts: https://github.com/dexyfex/CodeWalker/blob/master/CodeWalker.Core/GameFiles/Resources/Drawable.cs
- RPF7 header/encryption/prefix facts: https://github.com/dexyfex/CodeWalker/blob/master/CodeWalker.Core/GameFiles/RpfFile.cs
- Public key fingerprint only, not a key: https://github.com/dexyfex/CodeWalker/blob/master/CodeWalker.Core/GameFiles/Utils/GTAKeys.cs
- MetalKit view and render scheduling: https://developer.apple.com/documentation/metalkit/mtkview
- CommonCrypto platform AES implementation (system library).

No CodeWalker parser or engine implementation was copied. Previously authored independent Reborn resource readers were reused with an actual AES path and in-archive opaque prefix support. Zstandard 1.5.7 is retained under its upstream notices in Vendor/zstd.
