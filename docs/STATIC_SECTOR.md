# Static sector milestone 0.0.3
Independent PRD0/YMAP decoder validates blocks, pointer spans, CEntityDef transforms and inverse rotations. Static Downtown preview resolves exact-name YDR hashes only and reports missing/unsupported references. No dummy geometry is substituted. Existing model viewer remains available.

Not completed: YTYP aliases, YDD dictionaries, MLO, texture/materials, world streaming, gameplay, free-fly camera and visibility culling. Sector geometry is baked once under explicit caps; no asset loading in the frame loop. It is not a complete GTA engine.

Local audit: 41 Downtown archives / 1879 YDR entries, dt1_01 has six entities and one directly resolved YDR. Other five are explicitly unresolved. No game assets or keys committed.

Format references (facts only; no implementation copied): https://github.com/dexyfex/CodeWalker/blob/master/CodeWalker.Core/GameFiles/MetaTypes/Meta.cs and MetaTypes.cs.
