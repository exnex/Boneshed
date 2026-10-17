# Worldgen prototype evidence — 2026-10-17

Engine: `4.7.2.stable.official.ed1daf0bf` (installed by `scripts/tooling/setup.sh`, SHA-512 verified), Linux x86_64 cloud container, headless.

| Run | Result |
| --- | --- |
| `bash scripts/tooling/test_worldgen.sh` | import, tests and demo exit 0; no engine errors; **80 / 80** checks ([log](worldgen_tests.log)); 16 committed example files regenerate byte-identically ([demo log](worldgen_demo.log)) |
| Mutation: replace saturating axis combination with a plain sum | 3 checks fail (`agreement_amplifies_but_saturates`, `last_word_dominates_close_conflict`, golden examples) |
| Mutation: share one random stream across jitter, themes and atmosphere | 2 checks fail (`extra_draws_do_not_leak_between_streams`, golden examples) |
| Mutation: change one data weight (`undertow` 0.6 → 0.61) | golden examples check fails |
| Existing `bash scripts/tooling/test.sh` on this branch | combat 30+ and three negative controls pass; graphical step **timed out at its 180 s cap** — identically on clean `origin/main` in this container, so environmental (4-core llvmpipe) |
| Graphical combat run on this branch with a 580 s timeout | **37 / 37** passed, 0 failed, 5 screenshots, renderer llvmpipe |

The mutations were applied to temporary copies and reverted; they are not in the branch.
FNV-1a and Mulberry32 reference vectors in the tests were computed with an independent
Python implementation; `mulberry32(0)` matches the published JavaScript value 1144304738.
