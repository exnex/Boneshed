# Asset and licensing checklist (characters, rigs, animation)

Part of the [animation pipeline proposal](../ANIMATION_PIPELINE.md). This is a working
checklist, not legal advice. A commercial release needs a qualified review. AGENTS.md
still applies: **no third-party asset, dependency or licensing commitment is added without
explicit human approval.**

## Before an asset enters the repository

- [ ] **Source pinned**: URL plus immutable revision (commit SHA, release tag or order ID),
      and the SHA-256 of every file (pattern: [`data/animation_lab/trial_asset.json`](../../data/animation_lab/trial_asset.json)).
- [ ] **Licence text captured**: the actual LICENSE file or EULA at that revision, not a
      README sentence or a store-page badge. If only a README states it, record that as a
      weaker claim (the Mesh2Motion trial asset is in this state).
- [ ] **Rights chain traced** for each layer that applies: mesh, textures, rig, skin
      weights, each animation clip, any mocap source (CMU, SMPL-X, Mixamo), and any model
      weights or checkpoints used to generate it. "MIT code" never licenses the weights or
      the art.
- [ ] **Commercial use allowed**, including the paid game, trailers, store pages and streaming.
- [ ] **Redistribution checked**. Boneshed may ship moddable data or Tower snapshots, so
      check whether raw files can be extracted from the build. Mixamo's FAQ forbids
      redistributing raw characters or animations as the product.
- [ ] **Modification allowed** (retiming, retargeting, cleanup) and no share-alike terms
      that would bind our own assets (CC BY-SA, GPL art).
- [ ] **Attribution** requirements written into a credits file, even for CC0 (courtesy, and
      provenance).
- [ ] **Non-commercial or research-only terms rejected**: UniMate checkpoints (CC BY-NC 4.0),
      DeepMotion's free tier, Cascadeur's free tier, gated SMPL-X defaults.
- [ ] **AI-generated content disclosed** where storefronts require it (e.g. Steam's
      AI-content disclosure), with the tool, version and prompt and input provenance recorded.
- [ ] **Likeness and trademarks**: no real-person likeness from mocap or video without a
      release; no branded weapons or armour.
- [ ] **Excluded subsets noted**: for example, Mesh2Motion's `human-mocap-animations.glb`
      and its CMU folder are excluded from the trial because CMU data has separate terms.

## Before an asset ships

- [ ] Editable source kept (`.blend`), plus the exported `.glb` and the manifest entry.
- [ ] Automated import checks pass (see [WORKFLOW_AND_STANDARDS.md §1](WORKFLOW_AND_STANDARDS.md#1-workflow)).
- [ ] Human visual sign-off recorded in the PR, with rendered clips.
- [ ] Credits and licence files updated.

## Status of sources reviewed in this task

| Source | Licence evidence | Commercial | Redistribution | Status |
| --- | --- | --- | --- | --- |
| Mesh2Motion human base/addon GLBs @ `653a969` | README states CC0 art; **no LICENSE file** | Claimed yes | Claimed yes | **Evaluation only**, fetched outside the checkout; vendoring needs approval and ideally a LICENSE confirmation from the maintainer |
| Quaternius Universal Animation Library 1/2 | Publisher pages and OpenGameArt state CC0 | Yes (claimed) | Yes (claimed) | Candidate; not downloaded (site unreachable from the cloud sandbox) |
| Mixamo | Adobe FAQ/ToS (2022 FAQ quoted in community posts) | Yes inside a project | **No** for raw files | Not recommended |
| Cascadeur | Vendor plans | Paid tiers only | n/a (tool) | Optional tool |
| Video-to-motion services | Per vendor | Paid tiers | Per vendor | Reference/blocking only |
| UniMate checkpoints | CC BY-NC 4.0 | **No** | — | Rejected |
