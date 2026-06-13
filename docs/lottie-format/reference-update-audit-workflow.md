# Reference Update and Audit Workflow

Status: issue #56 workflow for adding, updating, and removing Lottie references,
curated fixtures, lottie-web numeric traces, and rendered inspection artifacts.

This workflow exists to keep research reversible. A reference is useful only when
a fresh checkout can identify its source, regenerate its derived evidence, and
explain every remaining unknown.

## Reversibility Contract

The canonical compiler-boundary and loss-taxonomy document is
`docs/lottie-format/reversibility-compiler-contract.md`.

Every curated reference follows this chain:

```text
source fixture -> manifest entry -> generated trace -> validation -> review evidence
```

The chain must be reversible:

- A generated lottie-web numeric trace must name a checked-in source fixture,
  selected source frames, renderer, and lottie-web version. The manifest entry
  must link the fixture id to that trace, and workflow review evidence must
  record the command that generated or refreshed the trace.
- A rendered PNG or APNG artifact is inspection evidence only after numeric
  source intent exists. It must be tied to the same fixture id and source frames
  as the numeric trace.
- A source fixture must be recoverable from a durable source URL/path and
  revision, or it must explicitly record `UNKNOWN` plus a follow-up issue.
- Anonymous downloads, temporary paths, local browser state, and uncommitted
  generated files are not durable provenance.
- PureLayer and PureDraw are target oracles. Do not modify PureLayer or PureDraw
  while updating PureLottie references.

## Required Reference Record

Every added or changed reference needs these facts before it can support a test
or conformance claim:

| Field | Required content |
| --- | --- |
| Source | Durable URL or checked-in path for the source fixture or document. |
| Revision | Commit SHA, package version, document version, or `UNKNOWN` with follow-up. |
| License/provenance | Upstream license path, local fixture authorship note, or explicit unknown. |
| Purpose | The exact behavior, bug class, or conformance row this reference proves. |
| Validation | Positive-rule status and path-bearing diagnostics for failures. |
| Review evidence | PR summary listing changed sources, generated traces, commands, and residual unknowns. |

Use positive validation names. A failed check should say which rule was expected,
where it failed, and which fixture id or document path caused it.

Record the same facts in `docs/lottie-format/reference-provenance.json` using
the schema documented in `docs/lottie-format/reference-provenance-schema.md`.
The prose ledger explains the state; the JSON manifest is the machine gate.

## Adding a Curated Fixture

1. Add the source Lottie JSON under `Tests/Fixtures/LottieOracle`.
2. Add a manifest entry to `Tools/LottieOracle/oracle-fixtures.json` with id,
   description, protected bug class, evidence roles, purpose, coverage tags,
   semantic status, source path, lottie-web trace path, selected frames, frame
   rationales, renderer, expected non-empty behavior, and validation fields.
3. Generate or refresh the committed lottie-web numeric trace with:

   ```sh
   npm --prefix Tools/LottieOracle run extract-intent -- --input ../../Tests/Fixtures/LottieOracle/<fixture>.json --frames <frames> --output ../../Tests/Fixtures/LottieOracle/lottie-web-intent/<fixture>.json
   ```

4. Run the numeric source-intent diff before rendering evidence:

   ```sh
   npm --prefix Tools/LottieOracle run diff-intent -- --fixture <fixture-id>
   ```

   The generated `numeric-oracle-diff.json` and `numeric-oracle-diff.md` must
   name every compared lottie-web expected path, PureLottie actual path,
   tolerance id, expected value, actual value, delta, and pass/fail result.
   Any failed numeric comparison is a source-intent bug until proven otherwise.

5. Run the oracle checks:

   ```sh
   npm --prefix Tools/LottieOracle test
   npm --prefix Tools/LottieOracle run validate-fixtures
   ```

6. Run the Swift checks that consume the committed trace:

   ```sh
   swift scripts/ci-model-only.swift
   swift test --package-path .build/ci/model-only --no-parallel
   swift build
   swift test --no-parallel
   ```

7. Review the diff as a single reversible unit: source fixture, manifest entry,
   generated trace, docs, and tests move together.

## Updating a Curated Fixture

Treat an update as replacing one reversible chain with another:

1. State the reason for the update in the PR: corrected source behavior, broader
   coverage, fixture simplification, or changed external reference version.
2. Regenerate every derived trace from the checked-in source fixture. Do not edit
   generated lottie-web intent by hand.
3. Update selected frame rationales when frames change. The rationale must say
   why those source frames are sufficient for the protected behavior.
4. Update evidence roles and purpose when coverage or test intent changes.
5. Re-run the numeric diff, oracle checks, and Swift checks from the adding
   workflow.
6. Confirm old generated artifacts are removed when they no longer correspond to
   the manifest entry.

## Adding or Updating Raw Corpus References

Raw corpus files are discovery material, not regression oracles. For each source
directory:

- Record upstream source URL, revision, file count, and license path in
  `docs/lottie-format/reference-provenance-ledger.md`.
- Record or update the matching machine entry in
  `docs/lottie-format/reference-provenance.json`.
- Keep copied license text under `Tests/Fixtures/LottieCorpus/_licenses`.
- Update tests that pin source counts, unique payload counts, license files, and
  observed-field classification.
- Do not promote a raw corpus file into visual-oracle evidence until it has a
  curated manifest entry and numeric lottie-web trace.

## Generated Traces and Rendered Artifacts

Generated numeric traces live under
`Tests/Fixtures/LottieOracle/lottie-web-intent`. They are source-intent evidence,
not PureLayer output.

Rendered PNG/APNG outputs are review artifacts. They may be attached to an issue
or PR, but they do not replace the numeric trace. A visual mismatch is actionable
only when the preceding source-intent numbers say what Lottie expected.

## Cleanup and Stale References

When removing or deprecating a reference:

- Remove the source fixture, manifest entry, committed trace, rendered artifact
  references, machine provenance entry, and ledger references in the same
  change.
- If a reference cannot be traced to a durable source, either repair the source
  record or remove the reference from tests and conformance claims.
- Leave an `UNKNOWN` only when it has a concrete follow-up issue and does not
  create a silent correctness claim.
- Re-run the same validation commands used for additions.

## Required Commands

Run these before committing reference workflow changes:

```sh
npm --prefix Tools/LottieOracle ci
npm --prefix Tools/LottieOracle test
npm --prefix Tools/LottieOracle run validate-fixtures
npm --prefix Tools/LottieOracle run diff-intent -- --all
swift scripts/ci-model-only.swift
swift test --package-path .build/ci/model-only
swiftformat . --config .swiftformat
swiftlint --config .swiftlint.yml --strict
swift build
swift test --no-parallel
```

## Review Evidence

The PR or issue comment must record:

- source/revision/license facts added or changed
- generated trace paths and selected frame rationale
- validation command results
- rendered artifact paths when visual inspection is used
- remaining `UNKNOWN` facts and their follow-up issue
- confirmation that PureLayer and PureDraw were not modified
