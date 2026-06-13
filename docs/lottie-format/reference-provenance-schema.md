# Reference Provenance Schema

Status: issue #58 machine-readable provenance schema and validation contract.

The canonical machine-readable manifest is
`docs/lottie-format/reference-provenance.json`. It complements the prose ledger:
the ledger explains the research state, while the manifest makes the required
facts mechanically checkable.

## Manifest Shape

```text
schema
entries[]
  id
  kind
  path
  source { type, value }
  revision { status, value?, followUp? }
  license { status, value?, followUp? }
  purpose
  classifications[]
  validation { status, evidence[] }
  measurements?
```

`revision` and `license` facts use `status: known` when a durable value exists.
They use `status: unknown` only when the entry also records a follow-up action.
Unknown facts are valid only when the entry validation status is
`usable-with-unknowns`.

## Stable Vocabularies

| Field | Values |
| --- | --- |
| `kind` | `raw-corpus-source`, `curated-corpus`, `numeric-trace-corpus`, `golden-trace`, `tool`, `executable-tool`, `documentation-set`, `dependency`, `documentation-reference`, `validation-idiom` |
| `source.type` | `git`, `local`, `npm`, `swift-package`, `documentation`, `canonical-rule` |
| fact `status` | `known`, `unknown` |
| `classifications` | `discovery`, `raw-corpus`, `curated-oracle`, `numeric-intent`, `source-intent`, `tooling`, `documentation`, `target-oracle`, `validation-idiom`, `unknown-tracked` |
| `validation.status` | `usable`, `usable-with-unknowns`, `documented-only` |

## Default Validation Set

`ReferenceProvenanceValidator` follows the same OpenAPIKit-style idiom as the
Lottie source validator: validations are composable values with positive
descriptions, path-bearing errors, a default set, a blank validator, and fluent
`validating` / `withoutValidating` methods.

The default set checks these exact positive descriptions:

| Rule description |
| --- |
| Reference provenance schema is purelottie.reference-provenance version 1 |
| Reference provenance manifest contains at least one entry |
| Reference provenance entry ids are unique |
| Reference provenance entries declare id, kind, path, and purpose |
| Reference provenance entry kinds use the stable vocabulary |
| Reference provenance classifications are non-empty and use the stable vocabulary |
| Reference provenance entry purposes describe the evidence in at least 40 characters |
| Reference provenance entries with unknown facts use usable-with-unknowns validation status |
| Reference provenance source types use the stable vocabulary |
| Reference provenance sources declare a durable value |
| Reference provenance facts use known or unknown status |
| Known reference provenance facts declare a value |
| Unknown reference provenance facts declare a follow-up |
| Reference provenance validation statuses use the stable vocabulary |
| Reference provenance validation records contain evidence commands or tests |

`ReferenceProvenanceManifest.decodeValidated(from:)` maps malformed typed JSON,
such as a missing required key, into the same `ValidationErrorCollection`
channel. The error path points at the missing or malformed field before the
default validator runs.

## Validation Boundary

The manifest validates provenance metadata, not Lottie rendering semantics. Per
fixture source-intent evidence remains in `Tools/LottieOracle/oracle-fixtures.json`.
The provenance manifest records that corpus as a reference set and the oracle
manifest validates each curated fixture individually.

PureLayer and PureDraw stay target oracles. This schema records how PureLottie
depends on them; it does not change either repository.
