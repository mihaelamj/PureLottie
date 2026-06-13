# CI Platform Matrix

## Status (2026-06-13)

The local full Swift gate remains authoritative while GitHub runner credentials
and private PureLayer dependency access are being settled. The committed
workflows still encode the platform proof surface so the repository has a
repeatable target state.

## Proof Surfaces

| Surface | Targets | Runner coverage | Command |
| --- | --- | --- | --- |
| Full package | `LottieModel`, `LottieEvaluation`, `LottieImport`, `LottieOracleDiff`, frame/APNG tools, and all tests | Local macOS always; GitHub macOS only when `PURELAYER_TOKEN` or `PURELAYER_DEPLOY_KEY` is configured | `swiftformat . --config .swiftformat && swiftlint --config .swiftlint.yml --strict && swift build && swift test --no-parallel` |
| Semantic package | `LottieModel`, `LottieEvaluation`, `LottieOracleDiff`, model tests, evaluation tests, oracle-diff tests, committed fixtures/docs/oracle manifests, and uncompiled `Tests/LottieImportTests` evidence files | macOS, Linux, Windows | `swift scripts/ci-semantic-only.swift && swift test --package-path .build/ci/semantic-only` |
| Windows semantic package | Same as semantic package | Windows | `./scripts/ci-semantic-only.ps1; swift test --package-path .build/ci/semantic-only` |
| Wasm semantic build | `LottieModel`, `LottieEvaluation`, `LottieOracleDiff` | Linux runner with Swift Wasm SDK | `swift build --package-path .build/ci/semantic-only --swift-sdk swift-6.3.2-RELEASE_wasm --target LottieOracleDiff` |
| lottie-web oracle | Node harness, Playwright/Chromium, curated fixture manifest, live `lottie-web` loadability | Linux | `npm --prefix Tools/LottieOracle test && npm --prefix Tools/LottieOracle run validate-fixtures` |

## Current Blockers

- Full package GitHub CI cannot be a required merge gate until the repository
  has `PURELAYER_TOKEN` or `PURELAYER_DEPLOY_KEY` configured for the private
  PureLayer dependency and any private transitive dependencies.
- Linux and Windows do not run `LottieImport` or the frame/APNG tools because
  those targets import PureLayer. The semantic package deliberately excludes
  PureLayer-backed targets and tests.
- Wasm currently builds the semantic targets only. The workflow does not run
  the Swift test runner under WASI, so semantic test execution is covered by
  macOS, Linux, and Windows while Wasm proves compile-time portability.

## Invariants

- `LottieModel` remains PureLayer-free and format-faithful.
- `LottieEvaluation` and `LottieOracleDiff` remain PureLayer-free so semantic
  compiler evidence can run on every host platform before backend lowering.
- `LottieImport` remains the only layer that maps evaluated semantics onto
  PureLayer, and unsupported backend facts must be reported instead of rendered
  silently wrong.
