# Reversibility Compiler Contract

Status: issue #88 compiler-boundary and loss-taxonomy contract.

PureLottie treats a Lottie file as source code. The compiler pipeline is:

```text
source -> parse -> validate -> normalize/evaluate -> lower -> decompile -> source-intent
```

The result of this pipeline is not a picture. The result is a checked set of
source-intent facts, diagnostics, and loss records that can be compared before
PureLayer or PureDraw rasterization is inspected.

## Sources of Truth

- Lottie JSON is the source language. `LottieModel` mirrors that source format
  and does not know PureLayer.
- lottie-web numeric traces are the external reference for current Lottie
  runtime behavior. They come from pinned `npm:lottie-web@5.13.0` through
  `Tools/LottieOracle`.
- `LottieEvaluation` owns source-frame evaluation, layer graph facts,
  transforms, geometry, trim facts, RenderIR construction, source-intent
  decompilation, and round-trip reports.
- PureLayer and PureDraw are target oracles. They are unchanged by PureLottie
  work. If a target capability is missing, PureLottie reports it or files a
  target issue; it does not silently change the target.
- PNG and APNG files are downstream inspection artifacts. They are useful only
  after numeric source-intent and backend evidence say what the frame was meant
  to contain.

## Measured State

These values are empirical claims for this repository state.

| Claim | Value | Evidence |
| --- | ---: | --- |
| Curated fixture manifest entries | 31 | MEASURED: `jq 'length' Tools/LottieOracle/oracle-fixtures.json` on 2026-06-13. |
| Reversibility fixture count | 31 | MEASURED: `jq '.fixtureCount' Tests/Fixtures/LottieOracle/reversibility-gate/report.json` on 2026-06-13. |
| Reversibility selected frame count | 94 | MEASURED: `jq '.selectedFrameCount' Tests/Fixtures/LottieOracle/reversibility-gate/report.json` on 2026-06-13. |
| Reversibility exclusions | 0 | MEASURED: `jq '.excludedFixtureCount' Tests/Fixtures/LottieOracle/reversibility-gate/report.json` on 2026-06-13. |
| Exact fixtures | 22 | MEASURED: `jq '.exactFixtureCount' Tests/Fixtures/LottieOracle/reversibility-gate/report.json` on 2026-06-13. |
| Fixtures with recorded loss | 9 | MEASURED: `jq '.recordedLossFixtureCount' Tests/Fixtures/LottieOracle/reversibility-gate/report.json` on 2026-06-13. |
| Unrecorded source-intent mismatches | 0 | MEASURED: `jq '.findingCount' Tests/Fixtures/LottieOracle/reversibility-gate/report.json` on 2026-06-13. |
| Path-bearing loss records | 105 | MEASURED: `jq '.lossCount' Tests/Fixtures/LottieOracle/reversibility-gate/report.json` on 2026-06-13. |
| Reconstructed facts | 1308 | MEASURED: `jq '.reconstructedFactCount' Tests/Fixtures/LottieOracle/reversibility-gate/report.json` on 2026-06-13. |
| Unique source paths in reversibility report | 48 | MEASURED: `jq '.sourcePathCount' Tests/Fixtures/LottieOracle/reversibility-gate/report.json` on 2026-06-13. |

When any value in this table changes, the change must come from the executable
gate and the prose must be updated in the same PR.

## Phase Contract

### Parse

The parse phase decodes JSON into `LottieModel` types. It preserves Lottie frame
units exactly as authored. It does not convert frames to seconds, does not lower
to PureLayer, and does not make backend decisions.

A parse failure belongs to the parse phase and must carry a JSON path when a
path can be known.

### Validate

Validation runs after parsing. The validation idiom is the OpenAPIKit-style
positive-rule model used throughout this repository: composable `Validation`
values, stable rule IDs, positive descriptions, type-directed dispatch, and
path-bearing errors.

Validation is not a renderer. A validation error states which source or semantic
rule is not satisfied and where it failed.

### Normalize/Evaluate

Evaluation samples Lottie at selected source frames before any target objects
exist. This phase owns:

- frame-window semantics: `ip <= frame < op`;
- property keyframe selection and easing;
- layer and group transform matrices;
- parent chains and layer graph participation;
- shape geometry, style scope, trim ranges, masks, mattes, and precompositions;
- semantic diagnostics for facts that are not representable yet.

Every selected frame needs a rationale. "First", "middle", or "last" is not a
rationale unless it explains the semantic boundary being tested.

### Lower

Lowering maps evaluated RenderIR facts into PureLayer and PureDraw target
objects. Lowering is the only phase that may convert Lottie frame time into
seconds for the target timeline.

The lowerer must not re-run Lottie semantics. If RenderIR says a layer position,
matrix, geometry, trim range, mask edge, or matte edge has a value, the lowerer
either maps that value correctly or records a finding with the source path and
JSON path that caused the gap.

### Decompile

Decompilation maps evaluated RenderIR back to source-intent facts. It is the
reverse edge used to prove the compiler has not lost source meaning before
rendering. The current executable edge is
`LottieSourceIntentTransformTimingRoundTripGate`.

The decompiler output must validate with:

- a schema name and version;
- source identity and source frame count;
- composition facts;
- per-frame source facts;
- per-layer source and JSON paths;
- explicit losses for any fact that cannot be reconstructed exactly.

### Artifact

`LottieFrameDump` and `LottieAPNGDump` can write PNG and APNG files after the
numeric gates run. An artifact can help a human inspect a symptom, but it is not
the first debugging surface. The first debugging surface is the measurable
source-intent report.

## Round-Trip Laws

### Law 1: Exact Facts Survive

For a supported source fact, compile then decompile yields the same source
intent. Examples include source-frame number, layer identity, layer transform,
geometry count, style count, mask count, matte presence, and trim trace count
where those facts are modeled.

### Law 2: Loss Is Explicit

If a fact cannot survive exactly, the compiler emits a loss record. Dropping a
render-affecting source fact without a loss record is a correctness bug.

### Law 3: Reports Are Deterministic

The committed report at
`Tests/Fixtures/LottieOracle/reversibility-gate/report.json` is byte-compared by
`LottieSourceIntentReversibilityCorpusGateTests`. A changed report is reviewed
as data, not explained away by a regenerated image.

### Law 4: Evidence Is Path-Bearing

Every source fact, finding, loss, and exclusion must be addressable. Required
evidence fields are:

| Field | Meaning |
| --- | --- |
| `sourcePath` | Human-readable Lottie source location, for example `root > layer 'Box'`. |
| `jsonPath` | Authored JSON location rooted at `$`. |
| `phase` | Compiler phase that produced the record: `parse`, `source`, `semantic`, `lowering`, or `decompile`. |
| `owner` | Responsible boundary: source format, PureLottie compiler, target backend, or external oracle. Current decompiler loss records derive this from `phase` and `classification`; backend findings also carry backend-gap ownership evidence. |
| `ruleID` | Stable machine-readable rule identifier. |
| `reason` | Human-readable explanation of the exact lost or rejected fact. |
| `reconstructability` | Whether the source fact is `exact`, `reconstructedWithLoss`, or `notReconstructable`. |

Pathless loss records are invalid. The round-trip and corpus gate tests contain
negative cases for missing frame rationales and pathless loss records.

#### Owner Mapping

The owner must be recoverable without interpretation. Current records use this
mapping:

| Boundary | Owner | Evidence |
| --- | --- | --- |
| Authored Lottie fields and specification facts | source format | `sourcePath`, `jsonPath`, and source-frame rationale. |
| Parser, validator, evaluator, RenderIR builder, and decompiler facts | PureLottie compiler | `phase`, `classification`, `ruleID`, and validation error path. |
| RenderIR-to-PureLayer or PureDraw capability gaps | target backend | `ImportReport` finding plus `LottieBackendGapEvidence` owner, RenderIR term, and artifact path when available. |
| lottie-web runtime facts and known engine divergences | external oracle | committed `purelottie.lottie-web-intent` trace, divergence ledger ID, and fixture manifest entry. |

If a record cannot identify one of these owners, it is incomplete and must not
support a conformance claim.

### Law 5: Visual Evidence Is Downstream

A PNG/APNG mismatch is a symptom. It becomes actionable only after the preceding
numeric records say:

- what lottie-web intended for the same source frame;
- what PureLottie evaluated from the Lottie source;
- what RenderIR handed to the lowerer;
- what the PureLayer/PureDraw target reported or could not represent.

## Loss Taxonomy

`LottieDecompiledSourceIntentLoss` is the current source-intent loss record. It
has these required semantic fields:

| Field | Contract |
| --- | --- |
| `kind` | Classifies the loss shape. |
| `reconstructability` | States whether source intent is exact, lossy, or not reconstructable. |
| `phase` | Names the compiler phase that produced the loss. |
| `classification` | Mirrors the feature classification: `exact`, `approximate`, `reported`, `metadata`, or `gap`. |
| `modelPath` | Location in the decompiled source-intent report. |
| `sourcePath` | Lottie source location when applicable. |
| `jsonPath` | Authored JSON location when applicable. |
| `sourceRange` | Source text range when available. |
| `ruleID` | Stable rule identifier. |
| `reason` | Explanation of the lost or unsupported source fact. |
| `evidence` | Optional supporting detail such as timing mode or backend evidence. |

The current loss kinds are:

| Kind | Meaning |
| --- | --- |
| `diagnostic` | A diagnostic fact was preserved as a non-exact record. |
| `missingSourceFact` | The decompiler could not reconstruct an authored source fact from the lower edge. |
| `approximation` | The compiler reconstructed a usable fact but admits loss of exact semantics. |
| `unsupported` | The source fact is known, render-affecting, and not supported by the current compiler or target boundary. |
| `intentionallyDropped` | A fact is intentionally absent from the reconstructed surface and must still be justified. |

The current reconstructability values are:

| Value | Meaning |
| --- | --- |
| `exact` | Source intent survived without semantic loss. |
| `reconstructedWithLoss` | Source intent was reconstructed but the record admits a known approximation. |
| `notReconstructable` | Source intent cannot be reconstructed from the current pipeline and needs a loss record. |

Loss records must not be used to hide incomplete modeling. They are allowed only
when the record is specific enough for a later issue or PR to move the fact from
loss into exact representation.

## Executable Gates

The written contract is backed by these checks:

| Gate | What it proves |
| --- | --- |
| `LottieSourceIntentDecompilerTests` | RenderIR decompiles to path-bearing source-intent facts; semantic diagnostics become loss records. |
| `LottieSourceIntentRoundTripGateTests` | Transform, timing, path, style, trim, mask, and matte facts round-trip or produce path-bearing losses. |
| `LottieSourceIntentReversibilityCorpusGateTests` | The curated corpus produces the deterministic checked-in reversibility report. |
| `LottieOracleCorpusTests` | Curated fixtures have frame rationales, committed lottie-web intent, and validation status. |
| `npm --prefix Tools/LottieOracle run validate-fixtures` | Each curated fixture live-loads through pinned lottie-web and matches its manifest validation record. |

The contract is valid only while these gates remain green. If a future phase
adds a new source fact, the tests and this document must move together.

## Example: Time Remap Loss

The `time-remap-precomp-diagnosed` fixture is intentionally diagnosed. The
source has an authored `tm` time-remap property. Evaluation can compute a local
source frame, but current decompilation cannot reconstruct the authored `tm`
property from decompiled layer timing facts.

The loss record therefore uses:

- `kind`: `missingSourceFact`;
- `reconstructability`: `notReconstructable`;
- `phase`: `decompile`;
- `classification`: `gap`;
- `ruleID`: `lottie.decompile.timing.time-remap-loss`;
- `sourcePath`: the remapped precomposition layer path;
- `jsonPath`: the authored `tm` property path;
- `reason`: the exact statement that `tm` is evaluated but not reconstructable.

That is a valid loss record because it is measurable, path-bearing, and tied to
one rule. It is not permission to ignore time remap forever.

## Example: Stroke Style Backend Loss

Stroke dash, cap, join, and miter facts are decoded and evaluated. When the
current target boundary cannot represent the exact style fact, the corpus report
records rule IDs such as `lottie.round-trip.style.stroke-dash-loss` with the
stroke source path and JSON path.

That is a backend or lower-edge loss, not a Lottie source-language mystery. A
future PureLayer capability can move the fact from recorded loss to exact
round-trip without changing the source fixture.

## Review Rule

A PR that changes parser, validator, evaluator, lowerer, decompiler, fixture, or
oracle behavior must answer these questions before merge:

1. Which source facts are newly exact?
2. Which source facts are newly reported as loss?
3. Which selected frames prove the change, and why those frames?
4. Which executable gate would fail if the claim were false?
5. Were PureLayer and PureDraw left unchanged?

If those questions cannot be answered with paths and commands, the change is not
reversible enough for this repository.
