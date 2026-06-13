# Fixture Evidence Roles

Status: issue #57 vocabulary for curated Lottie oracle fixtures.

Fixture roles explain why a curated fixture exists. They are not validation
statuses. Validation says whether a fixture is usable; roles say what kind of
evidence the fixture is allowed to provide.

Every curated entry in `Tools/LottieOracle/oracle-fixtures.json` must have:

- `evidenceRoles`: one or more roles from the stable vocabulary below.
- `purpose`: a sentence that names source-intent coverage and the protected
  test purpose.
- `coverage`: source-intent feature families exercised by the fixture.
- selected frames with rationale.

## Stable Vocabulary

| Role | Meaning | Required evidence |
| --- | --- | --- |
| `conformance` | The fixture proves a modeled Lottie semantic in the supported source-intent subset. | `semanticStatus` is `modeled`, coverage names the semantic, and tests compare source-intent facts. |
| `regression` | The fixture protects a known bug class or previously weak assumption. | `bugClass` and `purpose` state the protected failure. |
| `unsupported-feature` | The fixture marks a feature boundary that must be diagnosed rather than silently lowered. | `semanticStatus` is `diagnosed`, validation eligibility is false, and the report explains the unsupported feature. |
| `visual-inspection` | The fixture may produce PNG/APNG artifacts for human review after numeric source intent is already available. | `expectReferenceNonEmpty` is true and committed lottie-web intent has visible painted paths. |
| `engine-divergence` | The fixture guards a place where PureLottie must match measured lottie-web behavior instead of an intuitive geometry guess. | Committed lottie-web numeric intent records the source-frame behavior being compared. |

## Role Rules

- A modeled fixture must carry `conformance`.
- A diagnosed fixture must carry `unsupported-feature`.
- A fixture with `visual-inspection` must never use rendered pixels as the first
  source of truth; numeric lottie-web intent must exist first.
- `engine-divergence` does not mean PureLottie is currently wrong. It means the
  fixture exists to prevent divergence from measured reference-engine behavior.
- `purpose` must mention at least one coverage tag so the fixture can be audited
  back to a source-intent feature family.

## Update Rule

When adding, changing, or removing a curated fixture, update the role list,
purpose, coverage, selected frame rationale, committed lottie-web trace, and
review evidence together. If a fixture loses its role or purpose, it is no
longer evidence.
