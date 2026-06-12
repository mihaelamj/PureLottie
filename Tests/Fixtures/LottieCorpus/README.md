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
