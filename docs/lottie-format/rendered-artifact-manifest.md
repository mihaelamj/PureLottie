# Rendered Artifact Manifest

`purelottie.rendered-artifact-manifest` is the machine-readable contract for
PNG and APNG evidence generated after Lottie source intent has already been
measured. The manifest does not prove geometry by itself. It records enough
links for a reviewer to move from a visual artifact back to source timing,
source-intent traces, PureLayer geometry traces, and every reported finding.

Rendered images stay last in the proof chain:

1. Parse the Lottie source.
2. Validate the typed Lottie source model.
3. Evaluate source intent in source-frame units.
4. Lower the evaluated frame through the supported backend path.
5. Render PNG or APNG artifacts.
6. Write this manifest beside the artifacts.

## Schema

The root object is a `LottieRenderedArtifactManifest`.

```json
{
  "schema": {
    "name": "purelottie.rendered-artifact-manifest",
    "version": 1
  },
  "source": {
    "fixtureID": "eligible-shape-position",
    "path": "Tests/Fixtures/LottieOracle/eligible-shape-position.json",
    "animationName": "Position",
    "width": 100,
    "height": 100,
    "frameRate": 10,
    "inPoint": 0,
    "outPoint": 10
  },
  "renderer": {
    "name": "LottieFrameDump",
    "backend": "PureLayer",
    "version": "local",
    "command": "swift run LottieFrameDump --input fixture --output frames --frames 0,5"
  },
  "export": {
    "kind": "png-sequence",
    "policy": "explicit source-frame list",
    "scale": 2,
    "requestedFPS": 10,
    "generatedFrameCount": 2
  },
  "artifacts": [
    {
      "kind": "png-frame",
      "path": "frames/frame_0000000.00.png",
      "frameIndex": 0,
      "sourceFrame": 0,
      "timeSeconds": 0
    }
  ],
  "evidence": {
    "references": [
      {
        "kind": "lottie-web-intent",
        "path": "Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json",
        "frameIndex": 0,
        "sourceFrame": 0,
        "note": "Measured browser source intent for the exported source frame."
      },
      {
        "kind": "geometry-json",
        "path": "frames/purelayer-geometry.json",
        "frameIndex": 0,
        "sourceFrame": 0,
        "note": "PureLayer geometry trace for the exported frame set."
      }
    ]
  },
  "findings": [
    {
      "phase": "validation",
      "ruleID": "lottie.root.frame-window",
      "path": "$.op",
      "sourcePath": "composition",
      "reason": "The finding reason is copied into the manifest.",
      "severity": "note"
    }
  ]
}
```

## Field Meaning

`schema` declares the manifest format. The only supported value is name
`purelottie.rendered-artifact-manifest` and version `1`.

`source` identifies the Lottie fixture and records root timing and dimensions in
Lottie frame units. `frameRate`, `inPoint`, and `outPoint` are copied from the
source model and are not converted to seconds here.

`renderer` identifies the local renderer command that produced the artifact set.
For this repository the backend is expected to describe PureLayer-rendered
output, while the manifest model itself stays in `LottieEvaluation` and imports
no PureLayer or PureDraw symbols.

`export` records the artifact policy. Issue #95 extends this section with the
full derivation for why exactly the exported frame count exists. In version 1,
the section already carries the export kind, policy label, scale, requested FPS,
and generated frame count.

`artifacts` lists generated files. `png-frame` artifacts must be frame-addressed
with `frameIndex`, `sourceFrame`, and `timeSeconds`. APNG artifacts record the
movie path once; later timing manifests supply per-frame timing evidence.

`evidence.references` links the visual output back to measured numeric facts.
A valid manifest must include at least one `lottie-web-intent` reference and at
least one geometry reference (`geometry-json` or `geometry-csv`).

`findings` carries validation, import, RenderIR, and backend findings that were
known when the artifact was generated. Findings may be empty only when the
artifact set is clean; when present, every finding must have a stable phase,
severity, rule id, path, and reason.

## Stable Vocabularies

Export kinds:

- `apng`
- `png-sequence`

Artifact kinds:

- `apng`
- `geometry-csv`
- `geometry-json`
- `manifest`
- `png-frame`
- `report`

Evidence kinds:

- `apng-report`
- `geometry-csv`
- `geometry-json`
- `import-report`
- `lottie-web-intent`
- `oracle-summary`
- `render-ir`

Finding phases:

- `backend`
- `import`
- `renderIR`
- `validation`

Finding severities:

- `error`
- `note`
- `warning`

## Default Validation Rules

The validator follows the OpenAPIKit-style validation idiom used in this repo:
rules are composable values, descriptions state the correct state, and failures
carry JSON paths.

- Rendered artifact manifest schema name is purelottie.rendered-artifact-manifest and version is 1
- Rendered artifact source identity timing and dimensions are present
- Rendered artifact renderer identity backend and command are present
- Rendered artifact export policy declares kind scale fps and generated frame count
- Rendered artifact records are path-bearing unique and frame-addressed when needed
- Rendered artifact evidence references use stable kinds non-empty paths and notes
- Rendered artifact evidence includes source-intent and geometry references
- Rendered artifact findings contain stable phase severity rule id path and reason

## Proof Boundary

This manifest is not a pixel oracle. It is the ledger that prevents a PNG folder
from being disconnected from the measurable source-intent step before it. A
rendered artifact set is useful only when the manifest lets a reviewer answer:

- Which source fixture produced it?
- Which local command produced it?
- Which frame policy selected the frames?
- Which files were generated?
- Which source-intent and geometry evidence backs the files?
- Which validation, import, RenderIR, or backend findings were known?

If any of those answers is missing, the manifest validator must fail or the
artifact set must be marked ineligible by a later issue.
