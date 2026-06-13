# Reference Provenance Ledger

Status: issue #54 inventory ledger for the references and fixtures that support
PureLottie tests and Lottie-format documentation.

This ledger is not a conformance claim. It is the audit map that says where each
reference came from, why it exists, how it is validated today, and which facts
are still unknown. A source may be useful only when unknowns are visible and
actionable.

## Ledger Rules

- Every fixture or reference used by tests must have a source, revision or
  version when known, purpose, license/provenance note, and validation status.
- Unknown source facts are recorded as `UNKNOWN` with a follow-up action; they
  are never implied to be safe.
- Raw fixture files are discovery material. Curated oracle fixtures are the
  regression corpus.
- Rendered PNG/APNG artifacts are inspection evidence only after source-intent
  and reference-oracle numbers exist.
- PureLayer and PureDraw are target dependencies and oracles. They are not
  modified from PureLottie.

## Inventory Summary

| Reference set | Path | Count | Purpose | Validation status |
| --- | --- | ---: | --- | --- |
| Raw public Lottie corpus | `Tests/Fixtures/LottieCorpus` | 857 JSON files | Discovery corpus for observed Lottie fields and unsupported-feature evidence. | `FixtureCorpusTests` checks root Lottie keys; `CorpusSemanticLedgerTests` checks counts, unique payloads, source counts, licenses, field classification, and eligibility reasons. |
| Raw corpus licenses | `Tests/Fixtures/LottieCorpus/_licenses` | 6 files | Preserve upstream license text beside copied fixtures. | `CorpusSemanticLedgerTests.testCorpusSourceProvenanceIsPinned` checks required license files. |
| Curated source-intent oracle corpus | `Tests/Fixtures/LottieOracle` | 31 source JSON files | Vetted regression corpus with small source fixtures and selected frame rationales. | `LottieOracleCorpusTests` checks manifest size, coverage families, frame lists, and lottie-web intent alignment. |
| Committed lottie-web numeric traces | `Tests/Fixtures/LottieOracle/lottie-web-intent` | 31 JSON traces | Browser-side numeric reference facts before PNG comparison. | `LottieOracleCorpusTests.everyCorpusFixtureHasCommittedLottieWebNumericIntentSnapshot` checks schema, renderer, lottie-web version, size, selected frames, and path counts. |
| Golden source-intent trace | `Tests/Fixtures/SourceIntentTrace` | 1 JSON trace | Stable v1 source-intent schema round-trip fixture. | `LottieSourceIntentTraceTests` checks decode, provenance, vocabularies, and JSON coding round trip. |
| lottie-web oracle tool | `Tools/LottieOracle` | 1 Node tool package | External browser/reference harness kept outside `Package.swift`. | `npm --prefix Tools/LottieOracle test` checks fixture manifest, eligibility gates, package pins, image comparison helpers, and package isolation. |
| Frame dump tools | `Tools/LottieFrameDump`, `Tools/LottieAPNGDump` | 2 Swift executables | Emit PureLayer frames/APNGs with semantic summaries after source-intent gates. | Built by `swift build`; covered by import/APNG/oracle tests and oracle filename checks. |
| Lottie format docs | `docs/lottie-format` | 3 checked-in files before this ledger | Human-readable source-intent, conformance, and matrix contracts. | Swift/Node tests pin referenced fixture counts and trace behavior; this ledger records remaining documentation provenance gaps. |

## Raw Corpus Sources

The raw corpus contains public fixture files copied from upstream example and
test repositories. Only JSON files with root Lottie keys `v`, `fr`, `ip`, `op`,
`w`, `h`, and `layers` are admitted.

| Directory | Upstream source | Revision | JSON files | License/provenance | Purpose | Validation status |
| --- | --- | --- | ---: | --- | --- | --- |
| `Tests/Fixtures/LottieCorpus/airbnb-lottie-android` | `https://github.com/airbnb/lottie-android` | `05ea92e` | 451 | `_licenses/airbnb-lottie-android-LICENSE` | Broad Bodymovin/Lottie feature discovery from Android project fixtures. | Root-document gate, semantic-ledger classification, source-count pin. |
| `Tests/Fixtures/LottieCorpus/airbnb-lottie-ios` | `https://github.com/airbnb/lottie-ios` | `c10b740` | 186 | `_licenses/airbnb-lottie-ios-LICENSE` | Cross-engine fixture discovery from iOS project fixtures. | Root-document gate, semantic-ledger classification, source-count pin. |
| `Tests/Fixtures/LottieCorpus/Samsung-rlottie` | `https://github.com/Samsung/rlottie` | `bf689b7` | 105 | `_licenses/Samsung-rlottie-COPYING` | Native renderer fixture discovery. | Root-document gate, semantic-ledger classification, source-count pin. |
| `Tests/Fixtures/LottieCorpus/TelegramMessenger-rlottie` | `https://github.com/TelegramMessenger/rlottie` | `67f103b` | 97 | `_licenses/TelegramMessenger-rlottie-COPYING` | Native renderer fixture discovery from Telegram rlottie fork/use. | Root-document gate, semantic-ledger classification, source-count pin. |
| `Tests/Fixtures/LottieCorpus/airbnb-lottie-web` | `https://github.com/airbnb/lottie-web` | `bede03d` | 17 | `_licenses/airbnb-lottie-web-LICENSE.md` | Browser-engine fixture discovery. | Root-document gate, semantic-ledger classification, source-count pin. |
| `Tests/Fixtures/LottieCorpus/LottieFiles-lottie-react` | `https://github.com/LottieFiles/lottie-react` | `0082d3d` | 1 | `_licenses/LottieFiles-lottie-react-LICENSE` | React wrapper fixture discovery. | Root-document gate, semantic-ledger classification, source-count pin. |

Current measured totals:

| Measurement | Value |
| --- | ---: |
| Raw corpus JSON files | 857 |
| Unique raw JSON payloads | 675 |

## Curated Oracle Corpus

The curated corpus is the regression set selected from authored fixtures under
`Tests/Fixtures/LottieOracle`. It is intentionally small and reviewable.

| Field | Value |
| --- | --- |
| Manifest | `Tools/LottieOracle/oracle-fixtures.json` |
| Source fixtures | 31 JSON files in `Tests/Fixtures/LottieOracle` |
| Numeric browser traces | 31 JSON files in `Tests/Fixtures/LottieOracle/lottie-web-intent` |
| Semantic status split | 30 `modeled`, 1 `diagnosed` |
| Renderer | `svg` |
| lottie-web package | `lottie-web@5.13.0` |
| Source provenance | Local PureLottie-authored regression fixtures tracked by Git and identified by manifest `id`. |
| Fixture revision | Repository history plus manifest path; external browser behavior is pinned by `lottie-web@5.13.0`. |
| License/provenance note | PureLottie test fixtures, not copied from the raw external corpus. |
| Purpose | Numeric source-intent and browser-reference checks before PNG/APNG inspection. |
| Validation | Manifest tests, committed-intent tests, RenderIR comparison tests, source-intent lowering gate, APNG pre-export source-intent gate. |

Every manifest entry records a fixture id, description, protected bug class,
coverage tags, semantic status, source fixture path, lottie-web trace path,
selected frames with rationale, renderer, and reference non-empty/validation
expectations.

## Oracle Tool Dependencies

`Tools/LottieOracle` is deliberately outside the Swift package graph. Its
dependencies are pinned in `Tools/LottieOracle/package-lock.json`.

| Dependency | Version | Purpose | Validation status |
| --- | --- | --- | --- |
| `lottie-web` | `5.13.0` | Browser reference renderer and numeric intent source. | `oracle dependencies are exact external pins` Node test. |
| `playwright` | `1.60.0` | Browser automation for reference rendering and intent extraction. | `oracle dependencies are exact external pins` Node test. |
| `pngjs` | `7.0.0` | PNG read/write for frame comparison tests. | `PNG comparison records exact matches and mismatches` Node test. |

## Swift Target Dependencies

PureLottie has one declared package dependency:

| Dependency | Source | Revision | Purpose | Validation status |
| --- | --- | --- | --- | --- |
| PureLayer | `https://github.com/mihaelamj/PureLayer.git`, branch `main` | `UNKNOWN` in checked-in repo because `Package.resolved` is not committed | Target layer/compositor/rendering oracle for `LottieImport`; PureDraw arrives transitively through PureLayer. | Local and CI Swift gates resolve and build it; PureLottie must not modify PureLayer or PureDraw. |

Action: issue #58 should decide whether reference validation records a resolved
dependency revision externally without committing transient build output.

## Documentation References

The conformance and source-intent docs cite these research references:

| Reference | Source | Revision | Used by | Purpose | Validation status |
| --- | --- | --- | --- | --- | --- |
| Lottie specification snapshot | `docs/lottie-format/conformance-matrix.md` cites `/tmp/lottie-spec-source` and specific spec/schema paths | `UNKNOWN` in checked-in ledger | Conformance matrix and source-format rules | Original source-format contract. | Documentation citation only; needs a durable revision record in #56/#58. |
| lottie-web source snapshot | `docs/lottie-format/conformance-matrix.md` cites `/tmp/lottie-web-source` and specific player files | `UNKNOWN` in checked-in ledger | Transform, property, shape, trim, and renderer behavior notes | Reference implementation semantics before browser extraction. | Numeric behavior is checked through pinned `npm:lottie-web@5.13.0`; source checkout revision still needs durable recording in #56/#58. |
| OpenAPIKit validation idiom | Canonical mihaela-agents validation rule references `https://github.com/mattpolzin/OpenAPIKit` | Rule text records upstream `1d42ea6477` as last analysed | Validation architecture for LottieModel | Validation style and error-path discipline. | Enforced by existing validation tests and rule loading; not vendored in this repo. |

## Known Unknowns

| Unknown | Why it matters | Follow-up |
| --- | --- | --- |
| Durable checked-in revision for the lottie-spec source snapshot | Docs cite local `/tmp` paths, which cannot be re-resolved by a fresh checkout. | #56 documents the update/audit workflow; #58 should make this machine-checkable. |
| Durable checked-in revision for the lottie-web source snapshot used by prose research | Browser behavior is pinned by npm package version, but prose citations to source files need a source checkout revision. | #56/#58. |
| Checked-in resolved PureLayer/PureDraw dependency revision | `Package.swift` tracks PureLayer `main`; build logs resolve a commit but the repo does not pin it. | #58 should decide how provenance validation records target-oracle revisions without changing dependency policy. |

## Issue #54 Completion Criteria

This ledger covers the current references and fixtures used by tests and docs,
records known source/revision/purpose/validation facts, and makes unknowns
explicit. Later #37 child issues turn this inventory into stricter validation,
fixture usability checks, role classification, and an update workflow.
