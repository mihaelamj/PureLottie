# Numeric Claim Reliability

Status: issue #103 witness classification report.

PureLottie separates three different claims that used to be easy to conflate:

- `witnessed`: a committed lottie-web intent trace produced by pinned
  lottie-web in Chromium backs the numeric fact.
- `asserted`: PureLottie or its evaluator states the fact, but no committed
  lottie-web trace backs it yet.
- `blocked`: the fact cannot currently be witnessed, with the blocker named.

## Current Counts

MEASURED on 2026-06-13 from `swift run LottieNumericOracleDiff --all --output /tmp/purelottie-issue103-numeric-diff`:

| Surface | Witnessed | Asserted | Blocked | Total | Meaning |
| --- | ---: | ---: | ---: | ---: | --- |
| Curated numeric diff comparisons | 346 | 0 | 0 | 346 | Every compared expected value is read from a committed lottie-web intent trace. |
| Reference divergence ledger records | 17 | 0 | 0 | 17 | Every divergence record cites one or more committed lottie-web intent traces. |
| Oracle tolerance thresholds | 0 | 7 | 0 | 7 | Threshold numbers are author assertions until issue #104 derives arithmetic bounds. |

MEASURED on 2026-06-13 from repository files:

| Corpus | Count |
| --- | ---: |
| Curated oracle manifest fixtures | 31 |
| Curated committed lottie-web intent traces | 31 |
| Raw corpus Lottie JSON files | 857 |
| Wider witness-corpus entries | 5 |
| Wider witness-corpus committed lottie-web traces | 5 |
| Wider witness-corpus sampled frames | 25 |
| Wider witness-corpus layer rows | 460 |
| Wider witness-corpus path rows | 1430 |
| Wider witness-corpus mask rows | 55 |
| Wider witness-corpus precomposition rows | 25 |

## Files That Carry The Classification

- `Sources/LottieEvaluation/LottieClaimWitness.swift` defines the typed witness
  object shared by ledgers and reports.
- `Tools/LottieOracle/oracle-tolerances.json` records all tolerance thresholds
  as `asserted`.
- `Tools/LottieOracle/reference-divergences.json` records all divergence facts
  as `witnessed` and names the lottie-web trace files.
- `Tools/LottieOracle/witness-corpus.json` records the wider corpus witness set.
- `Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent/` stores the
  committed wider-corpus lottie-web traces.
- `LottieNumericOracleDiff` writes witness counts and per-comparison witness
  classifications into `numeric-oracle-diff.json` and `numeric-oracle-diff.md`.

## Wider Corpus Witness Set

The wider witness corpus is not a PureLayer conformance claim. It is committed
browser-engine evidence for source Lottie files outside the small curated oracle
set. It prevents the project from pretending that the wider corpus has no
reference numbers.

The current entries are:

| ID | Source | Frames | Trace |
| --- | --- | ---: | --- |
| `ripple` | `Tests/Fixtures/LottieCorpus/airbnb-lottie-web/test/animations/ripple.json` | 5 | `Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent/ripple.json` |
| `lights` | `Tests/Fixtures/LottieCorpus/airbnb-lottie-web/test/animations/lights.json` | 5 | `Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent/lights.json` |
| `starfish` | `Tests/Fixtures/LottieCorpus/airbnb-lottie-web/test/animations/starfish.json` | 5 | `Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent/starfish.json` |
| `gatin` | `Tests/Fixtures/LottieCorpus/airbnb-lottie-web/demo/gatin/data.json` | 5 | `Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent/gatin.json` |
| `dalek` | `Tests/Fixtures/LottieCorpus/airbnb-lottie-web/test/animations/dalek.json` | 5 | `Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent/dalek.json` |

Regenerate them with:

```sh
npm --prefix Tools/LottieOracle run build-witness-corpus
```

The trace model preserves lottie-web runtime facts even when they are not yet
conformance comparisons. For example, the wider `dalek` trace includes the
lottie-web layer-opacity sentinel `-999999` for hidden renderer elements and
zero-area empty SVG path data transformed to a nonzero origin. Those are
reference-engine observations, not PureLottie successes.

## Current Trust Boundary

The curated numeric diff can currently say:

> For the 31 curated fixtures and 346 compared fields, every expected numeric
> value is witnessed by a committed lottie-web trace, and PureLottie matches all
> 346 fields under the current tolerance ledger.

It cannot yet say:

> The tolerance thresholds are derived bounds.

That is why all 7 tolerance thresholds remain `asserted` and issue #104 exists.
