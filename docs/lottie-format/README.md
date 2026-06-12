# Lottie format reference (official)

Vendored copies of the official Lottie format documentation. **`LottieModel`**
implements a subset of this spec; these files are the authoritative reference
for JSON field names, semantics, and schema shape.

PureLottie does not modify upstream repos. Refresh with:

```bash
./scripts/fetch-lottie-reference-docs.sh
```

## What is documented in-repo today

| Layer | Documentation |
|---|---|
| **`LottieModel`** | Inline doc comments on public types; module role in [README](../README.md), [AGENTS.md](../AGENTS.md), [design/purelottie.md](../design/purelottie.md). No separate API catalog yet. |
| **Official Lottie format** | This directory — mirrored from upstream (below). |

When extending `LottieModel`, start with the official spec prose and schema,
then add decode types, validation rules, and tests.

## Upstream sources

### [lottie-spec](lottie-spec/) — community specification (authoritative)

| | |
|---|---|
| **Repository** | [github.com/lottie/lottie-spec](https://github.com/lottie/lottie-spec) |
| **Online** | [lottie.github.io/lottie-spec](https://lottie.github.io/lottie-spec/) |
| **License** | [Community Specification License v1](lottie-spec/Community_Specification_License-v1.md) |
| **Pinned commit** | See [lottie-spec/SOURCE_COMMIT](lottie-spec/SOURCE_COMMIT) |

Contains:

- `docs/specs/` — normative specification (Lottie v1.0 baseline PureLottie targets)
- `schema/` — machine-readable JSON schema fragments

This is the spec referenced by PureLottie goals (**G1** in
[design/purelottie.md](../design/purelottie.md)).

### [lottie-docs](lottie-docs/) — human-readable guide (companion)

| | |
|---|---|
| **Repository** | [github.com/LottieFiles/lottie-docs](https://github.com/LottieFiles/lottie-docs) |
| **Online** | [lottiefiles.github.io/lottie-docs](https://lottiefiles.github.io/lottie-docs/) |
| **License** | [CC-BY-4.0](lottie-docs/COPYING) |
| **Pinned commit** | See [lottie-docs/SOURCE_COMMIT](lottie-docs/SOURCE_COMMIT) |

Contains:

- `docs/` — narrative guides (format overview, layers, shapes, properties)
- `schema/` — consolidated schema used by the LottieFiles doc site

Useful for reading order and examples; **`lottie-spec` wins on normative conflicts**.

## Reading order

1. [lottie-docs/docs/Introduction.md](lottie-docs/docs/Introduction.md) — format overview
2. [lottie-spec/docs/specs/1.0/](lottie-spec/docs/specs/) — v1.0 specification
3. [lottie-spec/schema/root.json](lottie-spec/schema/root.json) — root document schema
4. PureLottie source: `Sources/LottieModel/` — what is actually decoded today

## Not included

Runtime/player docs (lottie-web, lottie-ios, etc.) and Adobe After Effects /
Bodymovin export guides. PureLottie is a file-format + import library, not a
player.
