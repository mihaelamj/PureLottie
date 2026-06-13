# Lottie Oracle

`Tools/LottieOracle` is an external reference harness for comparing PureLottie/PureLayer frame output against pinned `lottie-web` behavior.

It is deliberately outside `Package.swift`. The Swift package still depends only on PureLayer; this tool owns browser rendering and PNG diff dependencies.

## Run

Install the pinned Node dependencies:

```sh
npm ci --prefix Tools/LottieOracle
```

Install the Chromium browser used by Playwright if it is not already present:

```sh
npx --prefix Tools/LottieOracle playwright install chromium
```

Run the selected fixture:

```sh
npm --prefix Tools/LottieOracle run oracle -- --fixture eligible-shape-position
```

Validate the curated corpus before trusting it as evidence:

```sh
npm --prefix Tools/LottieOracle run validate-fixtures
```

Run the numeric source-intent diff for the curated corpus:

```sh
npm --prefix Tools/LottieOracle run diff-intent -- --all
```

Run one fixture and write reports to an explicit directory:

```sh
npm --prefix Tools/LottieOracle run diff-intent -- --fixture eligible-shape-position --output /tmp/purelottie-numeric-diff
```

Numeric comparison tolerances are recorded in
`Tools/LottieOracle/oracle-tolerances.json`. Swift oracle tests load that ledger
by id for opacity, matrix translation, source-frame, bounds, path length, and
trim segment comparisons; the Node oracle tests pin the exact pixel-diff
tolerance. Do not introduce a new comparison threshold without adding a ledger
entry that names the feature, unit, comparison, threshold, and reason.

`diff-intent` writes deterministic machine and human reports:

| Path | Contents |
| --- | --- |
| `numeric-oracle-diff.json` | Per-field lottie-web expected value, PureLottie actual value, compared paths, tolerance id, tolerance, delta, and pass/fail result. |
| `numeric-oracle-diff.md` | Markdown table over the same comparisons for review. |

The command exits non-zero when any numeric comparison fails. It is the required
gate before PNG or APNG inspection: rendered artifacts are only useful after the
source-intent numbers say what Lottie expected.

Reference-engine divergences are recorded in
`Tools/LottieOracle/reference-divergences.json`. Any fixture with the
`engine-divergence` evidence role must list one or more `divergenceIDs` that
point to measured behavior, source pointers, and committed trace evidence.

Regenerate the curated corpus fixtures and committed lottie-web intent snapshots:

```sh
npm --prefix Tools/LottieOracle run build-corpus
```

Extract only the numeric lottie-web source-intent trace:

```sh
npm --prefix Tools/LottieOracle run extract-intent -- --input ../../Tests/Fixtures/LottieOracle/eligible-shape-position.json --frames 0,5,9 --output /tmp/eligible-shape-position.intent.json
```

Artifacts are written to `Tools/LottieOracle/artifacts/<fixture-id>/`:

| Path | Contents |
| --- | --- |
| `reference/` | PNG frames rendered by pinned `lottie-web`. |
| `purelayer/` | PNG frames rendered by `swift run LottieFrameDump`, plus `oracle-summary.json`, `rendered-artifact-manifest.json`, and post-export folder validation. |
| `diff/` | Pixel-difference PNGs, one per compared frame. |
| `lottie-web-intent.json` | Numeric lottie-web facts: layer matrices, opacity, SVG path data, styles, bounds, and sampled path bounds. |
| `semantic-traces.json` | RenderIR node, trace, and backend evidence summaries for every selected frame. |
| `mismatch-traces.json` | RenderIR trace and backend evidence summaries only for frames that differ. |
| `comparison-report.json` | Machine-readable report. |
| `comparison-report.md` | Human-readable report. |
| `numeric-diff/numeric-oracle-diff.json` | Curated-corpus numeric source-intent diff report. |
| `numeric-diff/numeric-oracle-diff.md` | Markdown rendering of the numeric source-intent diff report. |

## Eligibility Gate

The harness compares pixels only when all of these are true:

- `LottieValidator` reports no validation errors.
- `ImportReport` is clean, so PureLayer lowering did not skip or approximate a feature.
- RenderIR diagnostics are empty for the selected frames.
- RenderIR-to-PureLayer backend evidence is empty for the selected frames.
- Fixtures marked `expectReferenceNonEmpty` produce non-empty lottie-web reference frames.

A pretty image is not evidence by itself. The report records validation eligibility, import findings, RenderIR diagnostics, selected frame numbers, and the reason each frame was selected.

## Curated Fixture Corpus

The manifest `Tools/LottieOracle/oracle-fixtures.json` currently selects 31
vetted fixtures from `Tests/Fixtures/LottieOracle`. Each fixture has:

- a small source Lottie JSON file;
- selected source frames with rationale;
- coverage tags, evidence roles, purpose, and a bug-class explanation;
- a machine-readable validation record stating that the JSON parses, pinned
  lottie-web loads it, the numeric intent trace is committed, and selected
  reference frames are non-empty;
- a committed `purelottie.lottie-web-intent` snapshot under
  `Tests/Fixtures/LottieOracle/lottie-web-intent`;
- a semantic status of `modeled` or `diagnosed`.

Evidence role definitions live in
`docs/lottie-format/fixture-evidence-roles.md`.

The validation command reports failures with manifest paths and fixture ids. A
failing fixture is not evidence until the manifest records the failure reason or
the source/trace problem is fixed.

The raw 857-file corpus under `Tests/Fixtures/LottieCorpus` remains discovery
material. This curated set is the regression oracle.

The first fixture is `Tests/Fixtures/LottieOracle/eligible-shape-position.json`.

It declares `ip=0`, `op=10`, and `fr=10`. Lottie uses a half-open root frame window, so the integer source frames are `0...9`. The oracle selects:

| Frame | Why |
| ---: | --- |
| 0 | First visible source frame; proves the window includes `ip`. |
| 5 | Interior frame; samples animated layer position away from both endpoints. |
| 9 | Last visible integer frame before exclusive `op=10`. |
