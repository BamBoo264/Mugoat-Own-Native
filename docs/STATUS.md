# Independently authored native engine

This project does not load or relabel any supplied GTA IPA executable. It reuses only the independent RPF/resource readers previously authored for Reborn. The own engine is IN DEVELOPMENT, not a completed GTA V compatibility engine.

Target dataset: E:\game (5814 manifest files). Initial audit found encrypted RPF tables, which require a correct private-key input/decryption path; no plaintext spoof is accepted. The unencrypted E:\GTAV_IOS data may be read only for resource-format research while that path is developed. Neither dataset is modified or bundled/published.

Required completion gates include full world/assets, character animation, physics/collision, vehicles, native/script behavior, mission/cutscene execution, audio and sustained device benchmarks. A model viewer alone does not satisfy gameplay completion.

Confirmed milestone: a model was decoded from the actual encrypted E:\game archive using locally derived private-key input: ng_proc_beerbottle_01a.ydr, 188 vertices and 192 triangles, with finite positions and valid indices. This is asset parsing, not proof of world rendering or gameplay. Its in-archive prefix is opaque (not standalone RSC7) and its frame is Zstandard. The reader validates decompressed sizes and resource pointer spans.

The native renderer, geometry, collision math and fixed timestep are now authored in source. The laboratory iOS app is only a component verification tool and cannot be called the finished requested engine.
