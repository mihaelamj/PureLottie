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

`export` records the artifact policy. In version 1, the section carries the
export kind, policy label, scale, requested FPS, and generated frame count.
The generated report beside the artifact set additionally carries
`frameTiming`, a `LottieArtifactFrameTiming` object that explains why that
count exists.

`artifacts` lists generated files. `png-frame` artifacts must be frame-addressed
with `frameIndex`, `sourceFrame`, and `timeSeconds`. APNG artifacts record the
movie path once; the sibling APNG report supplies per-frame timing evidence in
`frameTiming.samples`.

## Frame Timing Rationale

Every generated PNG/APNG report must answer: why exactly this many frames?
`LottieArtifactFrameTiming` is the shared answer. It has five parts:

- `policy`: either `apng-half-open-window` or `explicit-source-frame-list`.
- `source`: the Lottie root `fr`, `ip`, and `op` timing facts in source-frame
  units, plus the derived source duration in seconds.
- `request`: the exporter's input. APNG uses `startSeconds`,
  `exclusiveEndSeconds`, `outputFPS`, and `outputFrameIntervalSeconds`.
  Still-frame dumps use `sourceFrames`.
- `derivation`: the count formula, time formula, source-frame formula, generated
  frame count, effective sample endpoints when applicable, and prose rationale.
- `samples`: one row per generated frame with `index`, `timeSeconds`, and
  `sourceFrame`.

APNG exports preserve the Lottie half-open root window `ip <= frame < op`.
Given requested start `s`, requested exclusive end `e`, and output FPS `f`, the
tool computes:

```text
outputFrameIntervalSeconds = 1 / f
effectiveInclusiveEndSeconds = max(s, e - outputFrameIntervalSeconds)
generatedFrameCount = max(1, round(max(0, effectiveInclusiveEndSeconds - s) * f) + 1)
```

The samples are then linearly spaced from `s` to
`effectiveInclusiveEndSeconds`, inclusive. Each selected Lottie source frame is:

```text
sourceFrame = ip + timeSeconds * fr
```

Example: `ip=100`, `fr=10`, `s=0`, `e=1`, `f=5` gives an output interval of
`0.2s`, an inclusive sample end of `0.8s`, `5` generated frames, times
`0, 0.2, 0.4, 0.6, 0.8`, and source frames `100, 102, 104, 106, 108`.

Still-frame dumps do not resample time. Their count is exactly:

```text
generatedFrameCount = requestedSourceFrames.count
timeSeconds = max(0, (sourceFrame - ip) / fr)
```

Example: `ip=100`, `fr=10`, and requested source frames `100, 105, 109` produce
`3` frames with seconds `0, 0.5, 0.9`.

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
- Artifact frame timing source frame rate is positive and frame window is ordered
- Artifact frame timing derivation records formulas and a specific rationale
- Artifact frame timing generated frame count matches the sample list
- Artifact frame timing samples use contiguous zero-based indexes
- Artifact frame timing samples match the declared source frame and time formulas
- APNG artifact frame timing records start exclusive end output fps and inclusive sample end
- Explicit artifact frame timing records the requested source-frame list

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
