# PureLottie

[![macOS CI](https://github.com/mihaelamj/PureLottie/actions/workflows/macos-ci.yml/badge.svg)](https://github.com/mihaelamj/PureLottie/actions/workflows/macos-ci.yml)
[![Linux CI](https://github.com/mihaelamj/PureLottie/actions/workflows/linux-ci.yml/badge.svg)](https://github.com/mihaelamj/PureLottie/actions/workflows/linux-ci.yml)
[![Windows CI](https://github.com/mihaelamj/PureLottie/actions/workflows/windows-ci.yml/badge.svg)](https://github.com/mihaelamj/PureLottie/actions/workflows/windows-ci.yml)
[![Wasm CI](https://github.com/mihaelamj/PureLottie/actions/workflows/wasm-ci.yml/badge.svg)](https://github.com/mihaelamj/PureLottie/actions/workflows/wasm-ci.yml)

PureLottie is a typed Lottie document model and importer.

- `LottieModel` mirrors the Lottie JSON format and has no PureLayer knowledge.
- `LottieImport` maps validated Lottie documents onto PureLayer and records unsupported features in `ImportReport` instead of rendering silently wrong.
- Frame values stay in Lottie frame units inside `LottieModel`; importer code performs frame to second conversion.

## CI

| Badge | Workflow | What it proves |
| --- | --- | --- |
| macOS CI | `.github/workflows/macos-ci.yml` | `LottieModel` builds and tests on macOS. The full package gate also runs when PureLayer credentials are configured. |
| Linux CI | `.github/workflows/linux-ci.yml` | `LottieModel` builds and tests on Linux without resolving PureLayer. |
| Windows CI | `.github/workflows/windows-ci.yml` | `LottieModel` builds and tests on Windows without resolving PureLayer. |
| Wasm CI | `.github/workflows/wasm-ci.yml` | `LottieModel` compiles for `wasm32-unknown-wasi`. |

The macOS full package gate requires access to the private PureLayer dependency. Configure one of these repository secrets to enable it:

- `PURELAYER_TOKEN`: a GitHub token with read access to `mihaelamj/PureLayer` and any private transitive dependencies.
- `PURELAYER_DEPLOY_KEY`: an SSH deploy key for `mihaelamj/PureLayer`. Prefer `PURELAYER_TOKEN` if transitive dependencies are private too.

macOS, Linux, and Wasm model jobs intentionally run through `scripts/ci-model-only.swift`; Windows uses the equivalent `scripts/ci-model-only.ps1` because Swift script JIT is not reliable on the Windows runner. Both scripts create `.build/ci/model-only`, a temporary package containing only `Sources/LottieModel`, `Tests/LottieModelTests`, and `Tests/Fixtures`. This keeps cross-platform model checks honest while PureLayer resolution is still a dependency-gated full-package concern.

## Local Gate

Run the full local gate before committing code changes:

```sh
swiftformat . --config .swiftformat
swiftlint --config .swiftlint.yml --strict
swift build
swift test
```

Run the model-only gate used by macOS, Linux, and Wasm CI:

```sh
swift scripts/ci-model-only.swift
swift test --package-path .build/ci/model-only
```

Run the model-only gate used by Windows CI from PowerShell:

```powershell
./scripts/ci-model-only.ps1
swift test --package-path .build/ci/model-only
```

Run the Wasm model build after installing the Swift 6.3.2 Wasm SDK from Swift.org:

```sh
swift scripts/ci-model-only.swift
swift build --package-path .build/ci/model-only --swift-sdk swift-6.3.2-RELEASE_wasm --target LottieModel
```
