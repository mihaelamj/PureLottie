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

macOS, Linux, and Wasm model jobs intentionally run through `scripts/ci-model-only.swift`; Windows uses the equivalent `scripts/ci-model-only.ps1` because Swift script JIT is not reliable on the Windows runner. Both scripts create `.build/ci/model-only`, a temporary package containing `Sources/LottieModel`, `Tests/LottieModelTests`, `Tests/Fixtures`, and conformance docs needed by model tests. This keeps cross-platform model checks honest while PureLayer resolution is still a dependency-gated full-package concern.

## VM Debugger

`LottieCompositionVM` emits backend-independent trace records in source-frame
units. `LottieVMDebugger` consumes those records and provides deterministic
step into, step over, step out, step back, breakpoint, and watch semantics for
tests and a future IDE. Debugging stays inside `LottieEvaluation`; it does not
import PureLayer or PureDraw.

## Source-Intent Evaluation

`LottieFrameEvaluator` evaluates modeled Lottie properties before backend
lowering and returns typed `LottiePropertyEvaluationTrace` evidence with the
source frame, offset/local frame, selected keyframe span, linear progress,
Bezier timing result, final value, and spatial arc-length data when position
`to`/`ti` tangents form a motion path. Spatial position follows lottie-web's
sampled 150-segment arc-length algorithm for curved paths; incomplete tangent
or timing-handle sets become semantic diagnostics instead of exact claims.

## Backend Gap Evidence

`LottieRenderIRLowerer` reports unsupported PureLayer/PureDraw backend behavior
as `ImportReport` findings with optional `LottieBackendGapEvidence`. Evidence
records include the source fixture when known, source frame, Lottie path, JSON
path, source range when available, VM trace identity, RenderIR node and term
details, and lottie-web/PureLayer frame artifact paths when the oracle provides
them. Evidence ownership distinguishes backend capability gaps from intentional
approximations and PureLottie semantic investigations.

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

## lottie-web Oracle

`Tools/LottieOracle` is the external frame-comparison harness. It pins
`lottie-web` outside the Swift package graph, renders deterministic browser
reference PNGs, runs `LottieFrameDump` for PureLayer PNGs, and writes reports
with validation eligibility, selected frame rationale, pixel diffs, and RenderIR
trace context.

```sh
npm install --prefix Tools/LottieOracle
npx --prefix Tools/LottieOracle playwright install chromium
npm --prefix Tools/LottieOracle run oracle -- --fixture eligible-shape-position
```

The harness compares pixels only when validation, `ImportReport`, RenderIR
diagnostics, and RenderIR-to-PureLayer backend evidence are clean. Generated
artifacts live under
`Tools/LottieOracle/artifacts/`.

## APNG Export

`LottieAPNGDump` imports a validated Lottie file into PureLayer and writes an
animated PNG using PureLayer's `MovieExporter`.

```sh
swift run LottieAPNGDump \
  --input Tests/Fixtures/LottieOracle/eligible-shape-position.json \
  --output .build/exports/lottie-apng/eligible-shape-position.png \
  --fps 12 \
  --scale 2
```

The command writes a sibling `.report.json` with frame count, timing, pixel
size, and import findings. A clean report plus APNG chunks (`acTL`, `fdAT`) is
the direct proof that Lottie imported through PureLayer into a playable
animation.
