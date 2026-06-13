# Reference Provenance Ledger

Status: issue #54-#58 inventory ledger, update workflow, evidence-role
classification, and machine-readable validation for the references and fixtures
that support PureLottie tests and Lottie-format documentation.

This ledger is not a conformance claim. It is the audit map that says where each
reference came from, why it exists, how it is validated today, and which facts
are still unknown. A source may be useful only when unknowns are visible and
actionable.

## Ledger Rules

- Every fixture or reference used by tests must have a source, revision or
  version when known, purpose, license/provenance note, and validation status.
- Additions, updates, and removals follow
  [Reference Update and Audit Workflow](reference-update-audit-workflow.md).
- Curated fixture purpose uses
  [Fixture Evidence Roles](fixture-evidence-roles.md).
- Machine-readable provenance uses
  [Reference Provenance Schema](reference-provenance-schema.md) and
  `reference-provenance.json`.
- Unknown source facts are recorded as `UNKNOWN` with a follow-up action; they
  are never implied to be safe.
- Raw fixture files are discovery material. Curated oracle fixtures are the
  regression corpus.
- Rendered PNG/APNG artifacts are inspection evidence only after source-intent
  and reference-oracle numbers exist.
- Reversibility and loss-taxonomy rules are centralized in
  [Reversibility Compiler Contract](reversibility-compiler-contract.md).
- PureLayer and PureDraw are target dependencies and oracles. They are not
  modified from PureLottie.

## Inventory Summary

| Reference set | Path | Count | Purpose | Validation status |
| --- | --- | ---: | --- | --- |
| Raw public Lottie corpus | `Tests/Fixtures/LottieCorpus` | 857 JSON files | Discovery corpus for observed Lottie fields and unsupported-feature evidence. | `FixtureCorpusTests` checks root Lottie keys; `CorpusSemanticLedgerTests` checks counts, unique payloads, source counts, licenses, field classification, and eligibility reasons. |
| Raw corpus licenses | `Tests/Fixtures/LottieCorpus/_licenses` | 6 files | Preserve upstream license text beside copied fixtures. | `CorpusSemanticLedgerTests.testCorpusSourceProvenanceIsPinned` checks required license files. |
| Curated source-intent oracle corpus | `Tests/Fixtures/LottieOracle` | 31 source JSON files | Vetted regression corpus with small source fixtures and selected frame rationales. | `LottieOracleCorpusTests` checks manifest size, coverage families, frame lists, validation statuses, and lottie-web intent alignment; `npm --prefix Tools/LottieOracle run validate-fixtures` live-loads every curated fixture through pinned lottie-web. |
| Committed lottie-web numeric traces | `Tests/Fixtures/LottieOracle/lottie-web-intent` | 31 JSON traces | Browser-side numeric reference facts before PNG comparison. | `LottieOracleCorpusTests.everyCorpusFixtureHasCommittedLottieWebNumericIntentSnapshot` checks schema, renderer, lottie-web version, size, selected frames, and path counts. |
| Golden source-intent trace | `Tests/Fixtures/SourceIntentTrace` | 1 JSON trace | Stable v1 source-intent schema round-trip fixture. | `LottieSourceIntentTraceTests` checks decode, provenance, vocabularies, and JSON coding round trip. |
| Machine-readable provenance manifest | `docs/lottie-format/reference-provenance.json` | 18 entries | Typed provenance index for reference sets, tools, docs, dependency oracles, unknown facts, and validation evidence. | `ReferenceProvenanceManifestValidationTests` validates schema, vocabularies, required facts, unknown follow-ups, path-bearing diagnostics, and repository paths. |
| lottie-web oracle tool | `Tools/LottieOracle` | 1 Node tool package | External browser/reference harness kept outside `Package.swift`. | `npm --prefix Tools/LottieOracle test` checks fixture manifest, eligibility gates, package pins, image comparison helpers, path-bearing validation diagnostics, and package isolation; `npm --prefix Tools/LottieOracle run validate-fixtures` checks live lottie-web fixture usability. |
| Wider lottie-web witness corpus | `Tools/LottieOracle/witness-corpus.json`; traces under `Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent` | 5 trace files over 25 sampled frames | Browser-measured witness-only numeric facts from the raw corpus, separate from curated conformance claims. | `LottieWitnessCorpusManifestTests` and `witness-corpus.test.mjs` validate manifest paths, frame lists, lottie-web version, and committed trace identities. |
| Frame dump tools | `Tools/LottieFrameDump`, `Tools/LottieAPNGDump` | 2 Swift executables | Emit PureLayer frames/APNGs with semantic summaries after source-intent gates. | Built by `swift build`; covered by import/APNG/oracle tests and oracle filename checks. |
| Lottie format docs | `docs/lottie-format` | 12 checked-in files including this ledger | Human-readable source-intent, reversibility compiler, rendered artifact, loss taxonomy, conformance, matrix, provenance, numeric reliability, evidence role, update workflow, and reference schema contracts. | Swift/Node tests pin referenced fixture counts, trace behavior, reversibility contract language, rendered artifact manifest rules, role vocabulary, provenance schema, numeric claim witness counts, and referenced workflow commands. |

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
| Source-intent reversibility report | `Tests/Fixtures/LottieOracle/reversibility-gate/report.json` with 31 fixtures, 94 selected frames, 0 exclusions, 0 mismatches, 105 path-bearing losses, 1,308 reconstructed facts, and 48 unique source paths |
| Reversibility compiler contract | `docs/lottie-format/reversibility-compiler-contract.md` defining phase boundaries, loss taxonomy, owner evidence, path-bearing rules, and executable gates |
| RenderIR-to-PureLayer lowering report | `Tests/Fixtures/LottieOracle/lowering-gate/report.json` with 31 fixtures, 94 selected frames, 0 exclusions, and 45 backend findings |
| Semantic status split | 30 `modeled`, 1 `diagnosed` |
| Evidence role split | 30 `conformance`, 31 `regression`, 31 `visual-inspection`, 24 `engine-divergence`, 1 `unsupported-feature` |
| Renderer | `svg` |
| lottie-web package | `lottie-web@5.13.0` |
| Source provenance | Local PureLottie-authored regression fixtures tracked by Git and identified by manifest `id`. |
| Fixture revision | Repository history plus manifest path; external browser behavior is pinned by `lottie-web@5.13.0`. |
| License/provenance note | PureLottie test fixtures, not copied from the raw external corpus. |
| Purpose | Numeric source-intent and browser-reference checks before PNG/APNG inspection. |
| Validation | Manifest tests, committed-intent tests, RenderIR comparison tests, checked-in source-intent reversibility report, checked-in lowering-gate report, APNG pre-export source-intent gate, and live lottie-web usability validation. |

Every manifest entry records a fixture id, description, protected bug class,
evidence roles, purpose, coverage tags, semantic status, source fixture path,
lottie-web trace path, selected frames with rationale, renderer, and reference
non-empty/validation expectations. The role vocabulary is documented in
[Fixture Evidence Roles](fixture-evidence-roles.md).

Every manifest entry also records a machine-readable fixture usability record:

| Validation field | Current value | Meaning | Checked by |
| --- | --- | --- | --- |
| `validation.status` | `usable` for 31 fixtures | The fixture is allowed to serve as curated oracle evidence. | `validate-fixtures.mjs`, `LottieOracleCorpusTests` |
| `validation.sourceJSON` | `parses` for 31 fixtures | The source fixture parses as JSON and has required Lottie root keys. | `validate-fixtures.mjs` |
| `validation.lottieWeb` | `loads` for 31 fixtures | The source fixture live-loads in pinned `lottie-web@5.13.0` with the manifest renderer. | `npm --prefix Tools/LottieOracle run validate-fixtures` |
| `validation.numericIntent` | `committed` for 31 fixtures | The selected source frames have committed lottie-web numeric intent traces. | `validate-fixtures.mjs`, `LottieOracleCorpusTests` |
| `validation.referenceNonEmpty` | `passed` for 31 fixtures | Each selected frame has visible painted lottie-web path evidence when `expectReferenceNonEmpty` is true. | `validate-fixtures.mjs` |
| `validation.failureReasons` | empty for 31 fixtures | A usable fixture carries no unresolved usability failure reason. | `validate-fixtures.mjs` |

The validator reports failures as positive-rule diagnostics with the manifest
path and fixture id, for example
`oracle-fixtures.json[0].validation` for a bad usability record.

## Wider Witness Corpus

The wider witness corpus is not a conformance oracle. It records lottie-web
browser facts from raw corpus files so numeric claims can say whether an
expected value is witnessed, asserted, or blocked.

| Field | Value |
| --- | --- |
| Manifest | `Tools/LottieOracle/witness-corpus.json` |
| Trace directory | `Tests/Fixtures/LottieOracle/witnessed-corpus/lottie-web-intent` |
| Source fixtures | 5 raw-corpus Lottie files |
| Trace files | 5 JSON traces |
| Sampled frames | 25 |
| Layer rows | 460 |
| Path rows | 1,430 |
| Mask rows | 55 |
| Precomposition rows | 25 |
| Renderer | `svg` |
| lottie-web package | `lottie-web@5.13.0` |
| Validation | `LottieWitnessCorpusManifestTests` decodes the manifest and every trace; `witness-corpus.test.mjs` checks manifest shape and trace identity. |

These traces widen witnessed browser coverage. They become conformance evidence
only when a separate diff maps an expected Lottie fact to a PureLottie fact and
records the comparison result.

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

Action: `reference-provenance.json` records this as an explicit unknown with a
follow-up action. The dependency revision must be recorded externally before the
entry can be promoted from `usable-with-unknowns` to `usable`.

## Documentation References

The conformance and source-intent docs cite these research references:

| Reference | Source | Revision | Used by | Purpose | Validation status |
| --- | --- | --- | --- | --- | --- |
| Lottie specification snapshot | `docs/lottie-format/conformance-matrix.md` cites `/tmp/lottie-spec-source` and specific spec/schema paths | `UNKNOWN` in checked-in ledger and manifest | Conformance matrix and source-format rules | Original source-format contract. | Documentation citation only; `reference-provenance.json` records the missing durable revision and license/provenance note as explicit unknowns with follow-ups. |
| lottie-web source snapshot | `docs/lottie-format/conformance-matrix.md` cites `/tmp/lottie-web-source` and specific player files | `UNKNOWN` in checked-in ledger and manifest | Transform, property, shape, trim, and renderer behavior notes | Reference implementation semantics before browser extraction. | Numeric behavior is checked through pinned `npm:lottie-web@5.13.0`; `reference-provenance.json` records the source checkout revision as an explicit unknown with a follow-up. |
| OpenAPIKit validation idiom | Canonical mihaela-agents validation rule references `https://github.com/mattpolzin/OpenAPIKit` | Rule text records upstream `1d42ea6477` as last analysed | Validation architecture for LottieModel | Validation style and error-path discipline. | Enforced by existing validation tests and rule loading; not vendored in this repo. |

## Known Unknowns

| Unknown | Why it matters | Follow-up |
| --- | --- | --- |
| Durable checked-in revision for the lottie-spec source snapshot | Docs cite local `/tmp` paths, which cannot be re-resolved by a fresh checkout. | `reference-provenance.json` entry `lottie-spec-documentation-reference` records `revision.status: unknown`, `license.status: unknown`, and follow-up actions. |
| Durable checked-in revision for the lottie-web source snapshot used by prose research | Browser behavior is pinned by npm package version, but prose citations to source files need a source checkout revision. | `reference-provenance.json` entry `lottie-web-source-reference` records `revision.status: unknown` and a follow-up action. |
| Checked-in resolved PureLayer/PureDraw dependency revision | `Package.swift` tracks PureLayer `main`; build logs resolve a commit but the repo does not pin it. | `reference-provenance.json` entry `purelayer-dependency` records `revision.status: unknown` and a follow-up action without changing dependency policy. |

## Issue #54-#58 Completion Criteria

This ledger covers the current references and fixtures used by tests and docs,
records known source/revision/purpose/validation facts, and makes unknowns
explicit. The linked update workflow defines reversible add/update/remove rules,
required validation commands, stale-reference cleanup, and review evidence. The
linked fixture role vocabulary classifies curated fixtures by evidence purpose.
The linked schema and manifest make provenance validation machine-readable with
composable positive-rule validation, path-bearing diagnostics, stable
vocabularies, and explicit unknown follow-ups.
