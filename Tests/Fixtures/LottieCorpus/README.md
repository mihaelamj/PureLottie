# Lottie Corpus Fixtures

This directory contains public Lottie JSON fixtures copied from upstream test
and example repositories. The files are intentionally stored under
`Tests/Fixtures` so importer regressions can be reproduced locally without
modifying PureLayer or PureDraw.

Only JSON files with the root Lottie document keys `v`, `fr`, `ip`, `op`, `w`,
`h`, and `layers` were copied.

| Source | Commit | Files |
| --- | --- | ---: |
| https://github.com/airbnb/lottie-android | `05ea92e` | 451 |
| https://github.com/airbnb/lottie-ios | `c10b740` | 186 |
| https://github.com/Samsung/rlottie | `bf689b7` | 105 |
| https://github.com/TelegramMessenger/rlottie | `67f103b` | 97 |
| https://github.com/airbnb/lottie-web | `bede03d` | 17 |
| https://github.com/LottieFiles/lottie-react | `0082d3d` | 1 |

Total: 857 Lottie JSON files, about 70 MiB.

License files from each source repository are preserved in `_licenses/`.

## Semantic Ledger Gate

`CorpusSemanticLedgerTests` scans this directory on every full test run. The
gate pins:

- total fixture count: 857 JSON files
- unique payload count: 675 byte-identical JSON payloads
- source-level fixture counts and preserved license files
- every observed field classified as lowered, approximated, reported, metadata,
  or explicit gap
- conservative visual-oracle eligibility reasons per fixture

Adding a fixture with a new rendering-affecting field fails until that field is
classified in the ledger and, when applicable, reflected in the conformance
matrix vocabulary.
