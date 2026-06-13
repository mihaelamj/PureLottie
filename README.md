# PureLottie

> **Continuing this work?** Read [`CONTINUATION.md`](CONTINUATION.md) first and re-read it every work cycle. It defines the build and test gate, the non-negotiable rules, and the current work queue.

[![macOS CI](https://github.com/mihaelamj/PureLottie/actions/workflows/macos-ci.yml/badge.svg)](https://github.com/mihaelamj/PureLottie/actions/workflows/macos-ci.yml)
[![Linux CI](https://github.com/mihaelamj/PureLottie/actions/workflows/linux-ci.yml/badge.svg)](https://github.com/mihaelamj/PureLottie/actions/workflows/linux-ci.yml)
[![Windows CI](https://github.com/mihaelamj/PureLottie/actions/workflows/windows-ci.yml/badge.svg)](https://github.com/mihaelamj/PureLottie/actions/workflows/windows-ci.yml)
[![Wasm CI](https://github.com/mihaelamj/PureLottie/actions/workflows/wasm-ci.yml/badge.svg)](https://github.com/mihaelamj/PureLottie/actions/workflows/wasm-ci.yml)
[![Oracle CI](https://github.com/mihaelamj/PureLottie/actions/workflows/oracle-ci.yml/badge.svg)](https://github.com/mihaelamj/PureLottie/actions/workflows/oracle-ci.yml)

PureLottie is a typed Lottie document model and importer.

- `LottieModel` mirrors the Lottie JSON format and has no PureLayer knowledge.
- `LottieImport` maps validated Lottie documents onto PureLayer and records unsupported features in `ImportReport` instead of rendering silently wrong.
- Frame values stay in Lottie frame units inside `LottieModel`; importer code performs frame to second conversion.

## CI

| Badge | Workflow | What it proves |
| --- | --- | --- |
| macOS CI | `.github/workflows/macos-ci.yml` | Semantic tests for `LottieModel`, `LottieEvaluation`, and `LottieOracleDiff` run on macOS. The full package gate also runs when PureLayer credentials are configured. |
| Linux CI | `.github/workflows/linux-ci.yml` | Semantic tests for `LottieModel`, `LottieEvaluation`, and `LottieOracleDiff` run on Linux without resolving PureLayer. |
| Windows CI | `.github/workflows/windows-ci.yml` | Semantic tests for `LottieModel`, `LottieEvaluation`, and `LottieOracleDiff` run on Windows without resolving PureLayer. |
| Wasm CI | `.github/workflows/wasm-ci.yml` | The semantic package through `LottieOracleDiff` compiles for `wasm32-unknown-wasi`. |
| Oracle CI | `.github/workflows/oracle-ci.yml` | `Tools/LottieOracle` validates the curated fixture manifest and live-loads every curated fixture through pinned `lottie-web`. |

The macOS full package gate requires access to the private PureLayer dependency. Configure one of these repository secrets to enable it:

- `PURELAYER_TOKEN`: a GitHub token with read access to `mihaelamj/PureLayer` and any private transitive dependencies.
- `PURELAYER_DEPLOY_KEY`: an SSH deploy key for `mihaelamj/PureLayer`. Prefer `PURELAYER_TOKEN` if transitive dependencies are private too.

macOS, Linux, and Wasm semantic jobs intentionally run through `scripts/ci-semantic-only.swift`; Windows uses the equivalent `scripts/ci-semantic-only.ps1` because Swift script JIT is not reliable on the Windows runner. Both scripts create `.build/ci/semantic-only`, a temporary package containing `Sources/LottieModel`, `Sources/LottieEvaluation`, `Sources/LottieOracleDiff`, their PureLayer-free tests, committed fixtures, conformance docs, oracle manifests, and `Tests/LottieImportTests` as uncompiled evidence files for ledger path validation. This keeps cross-platform semantic checks honest while PureLayer resolution is still a dependency-gated full-package concern.

The exact platform matrix and current blockers are tracked in `docs/ci-platform-matrix.md`.

## VM Debugger

`LottieCompositionVM` emits backend-independent trace records in source-frame
units. `LottieVMDebugger` consumes those records and provides deterministic
step into, step over, step out, step back, breakpoint, and watch semantics for
tests and a future IDE. VM results, trace records, debugger steps, breakpoints,
watches, checkpoints, source ranges, and JSON paths round trip through JSON
coding so a web or native debugger can consume the same evidence. Debugging
stays inside `LottieEvaluation`; it does not import PureLayer or PureDraw.

## Source-Intent Evaluation

`LottieFrameEvaluator` evaluates modeled Lottie properties before backend
lowering and returns typed `LottiePropertyEvaluationTrace` evidence with the
source frame, offset/local frame, selected keyframe span, linear progress,
Bezier timing result, final value, and spatial arc-length data when position
`to`/`ti` tangents form a motion path. Spatial position follows lottie-web's
sampled 150-segment arc-length algorithm for curved paths; incomplete tangent
or timing-handle sets become semantic diagnostics instead of exact claims.
`LottieTransformEvaluator` evaluates layer and shape-group transforms into
lottie-web row-vector matrices, with trace records for authored initial values,
sampled frame values, normalized matrix operands, operation order, parent
chains, and point application before any PureLayer lowering.
`LottieSourceGeometryEvaluator` expands paths, rectangles, ellipses, polygons,
and stars into frame-sampled source-space contours with vertices, relative and
absolute tangents, exact cubic bounds, source JSON paths, direction evidence,
and lottie-web compatibility constants. RenderIR carries this trace beside its
compatibility geometry payload, and the PureLayer lowerers consume the same
trace-derived Bezier path so source intent and rendered input stay comparable.
`LottieSourceTrimEvaluator` measures trim-path intent over those contours before
lowering: original path lengths, normalized start/end/offset, parallel versus
sequential selection order, selected segment ranges, resulting Bezier paths, and
the named lottie-web sampling/rounding approximations used to compute them.

## Reversibility Contract

The compiler contract lives in
`docs/lottie-format/reversibility-compiler-contract.md`. It defines the
`source -> parse -> validate -> normalize/evaluate -> lower -> decompile ->
source-intent` boundary, the loss taxonomy, required path-bearing evidence, and
the rule that PNG/APNG files are inspection artifacts only after the numeric
source-intent gates pass.

## Rendered Artifact Manifest

Rendered PNG and APNG evidence must be accompanied by the manifest contract in
`docs/lottie-format/rendered-artifact-manifest.md`. The manifest records source
fixture identity, renderer identity, export policy, generated artifact paths,
per-frame source-intent evidence links, geometry evidence links, and any
validation/import/backend findings. It lives in `LottieEvaluation`, imports no
PureLayer or PureDraw symbols, and validates with path-bearing OpenAPIKit-style
rules. PNG review folders are loaded back through `LottieReviewFrameFolder`
after export, so local commands fail on missing, empty, or unexpected extra
frame PNGs and on one-frame placeholders for multi-frame source windows.

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
swift test --no-parallel
```

Run the semantic-only gate used by macOS, Linux, and Windows CI:

```sh
swift scripts/ci-semantic-only.swift
swift test --package-path .build/ci/semantic-only
```

Run the semantic-only gate used by Windows CI from PowerShell:

```powershell
./scripts/ci-semantic-only.ps1
swift test --package-path .build/ci/semantic-only
```

Run the Wasm semantic build after installing the Swift 6.3.2 Wasm SDK from Swift.org:

```sh
swift scripts/ci-semantic-only.swift
swift build --package-path .build/ci/semantic-only --swift-sdk swift-6.3.2-RELEASE_wasm --target LottieOracleDiff
```

## lottie-web Oracle

`Tools/LottieOracle` is the external frame-comparison harness. It pins
`lottie-web` outside the Swift package graph, renders deterministic browser
reference PNGs, runs `LottieFrameDump` for PureLayer PNGs, and writes reports
with validation eligibility, selected frame rationale, pixel diffs, and RenderIR
trace context.

```sh
npm ci --prefix Tools/LottieOracle
npx --prefix Tools/LottieOracle playwright install chromium
npm --prefix Tools/LottieOracle test
npm --prefix Tools/LottieOracle run validate-fixtures
npm --prefix Tools/LottieOracle run build-witness-corpus
npm --prefix Tools/LottieOracle run oracle -- --fixture eligible-shape-position
```

Numeric oracle reliability is tracked in
`docs/lottie-format/numeric-claim-reliability.md`. The current curated
source-intent diff reports 31 fixtures and 346 compared fields; all 346
expected values are witnessed by committed lottie-web traces, with 0 asserted or
blocked comparison rows. The tolerance ledger remains deliberately asserted
until #104 derives arithmetic bounds. A separate witness-only wider corpus
records five lottie-web traces over 25 frames from the raw corpus.

The harness compares pixels only when validation, `ImportReport`, RenderIR
diagnostics, RenderIR-to-PureLayer backend evidence, `oracle-summary.json`,
`rendered-artifact-manifest.json`, and `lottie-web-intent.json` all agree on the
selected source frames. Generated artifacts live under
`Tools/LottieOracle/artifacts/`.

The curated fixture manifest records parse/load/intent/non-empty validation
status for each fixture. The validation command emits fixture ids and manifest
paths for failures, so a fixture is not trusted merely because it exists in the
tree.

## APNG Export

`LottieAPNGDump` evaluates each sampled Lottie source frame into `RenderIR`,
lowers that frame into PureLayer, renders it through PureLayer/PureDraw at time
zero, and packages those exact rendered frames as an animated PNG.

```sh
swift run LottieAPNGDump \
  --input Tests/Fixtures/LottieOracle/eligible-shape-position.json \
  --output .build/exports/lottie-apng/eligible-shape-position.png \
  --fps 12 \
  --scale 2
```

The command writes a sibling `.report.json` with frame count, frame-timing
rationale, pixel size, validation errors, legacy importer findings, and RenderIR
lowering findings. The `frameTiming` section records the source `fr`/`ip`/`op`,
the requested exclusive time window, the effective inclusive sample endpoint,
the count formula, and one `timeSeconds`/`sourceFrame` row per generated APNG
frame. Validation/import findings explain what the old direct importer still
rejects; RenderIR lowering findings explain what the PureLayer backend could
not represent for the sampled frames. It also writes sibling `.geometry.json`
and `.geometry.csv` files that compare evaluated Lottie composition
coordinates, scale-adjusted expected output coordinates, and PureLayer draw-list
coordinates for every generated APNG sample.

APNG chunks (`acTL`, `fdAT`) prove that a playable animation was written. A
geometry trace whose `deltaToExpectedOutputBounds` values are zero proves that
the frame was placed at the expected coordinates before visual inspection. A
clean legacy import report is not required for export, but every RenderIR
approximation or unsupported backend feature must appear in the RenderIR
lowering findings with VM trace, RenderIR term, layer graph, and artifact
evidence. Layer-graph evidence includes timing fields such as source frame,
local precomposition frame, start time, stretch, time-remap seconds, and
precomposition asset paths when those facts affect lowering.

`LottieFrameDump` writes the same geometry evidence next to still-frame dumps:

```sh
swift run LottieFrameDump \
  --input Tests/Fixtures/LottieOracle/eligible-shape-position.json \
  --output .build/exports/lottie-frames/eligible-shape-position \
  --frames 0,5,9 \
  --scale 1 \
  --lottie-web-intent Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json
```

`--frames` is mandatory. The output folder must contain exactly the selected
PNG frames listed by `rendered-artifact-manifest.json`; stale PNGs from a prior
run are rejected instead of being silently ignored.
