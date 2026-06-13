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
    "command": "swift run LottieFrameDump --input fixture --output frames --frames 0,5 --lottie-web-intent intent.json"
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
      "path": "frames/frame_0000.00.png",
      "frameIndex": 0,
      "sourceFrame": 0,
      "timeSeconds": 0,
      "evidenceLinks": [
        {
          "kind": "lottie-web-intent",
          "path": "Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json",
          "frameIndex": 0,
          "sourceFrame": 0,
          "timeSeconds": 0,
          "rowAddress": "$.frames[0]",
          "note": "Browser source-intent row for the rendered source frame."
        },
        {
          "kind": "geometry-json",
          "path": "frames/purelayer-geometry.json",
          "frameIndex": 0,
          "sourceFrame": 0,
          "timeSeconds": 0,
          "rowAddress": "$.frames[0]",
          "note": "PureLayer geometry trace row for the rendered source frame."
        }
      ]
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

Each `png-frame` artifact also carries `evidenceLinks`. These are the direct
debugging chain for the rendered frame. A reviewer starts at the PNG artifact,
reads `sourceFrame` and `timeSeconds`, then follows:

1. a `lottie-web-intent` link to the numeric browser source-intent row for the
   same frame;
2. a geometry link (`geometry-json` or `geometry-csv`) to the PureLayer geometry
   row for the same frame;
3. optional `import-report`, `render-ir`, `backend-evidence`, or
   `validation-report` links when a finding explains why an artifact is
   ineligible or approximate.

Every evidence link repeats `frameIndex`, `sourceFrame`, and `timeSeconds` so a
manifest cannot silently point a rendered frame at a different source-intent
row. Source-intent and geometry links also carry `rowAddress`: a JSONPath for
JSON evidence, or a stable row selector for CSV evidence. The link `kind` and
`path` pair must also appear in `evidence.references`, which keeps the global
evidence inventory and the per-frame chain from drifting.

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

## Complete Review Frame Folders

A PNG sequence review folder is complete only when the files on disk agree with
both machine-readable records written beside them:

- `rendered-artifact-manifest.json` lists each `png-frame` artifact with its
  relative path, `frameIndex`, `sourceFrame`, and `timeSeconds`.
- `oracle-summary.json` carries `frameTiming`, whose samples explain why exactly
  that frame count was generated.

`LottieFrameDump` now treats `--frames` as mandatory. Omitting it would recreate
the one-frame placeholder failure mode, so the tool refuses to run without an
explicit source-frame list. After writing the PNGs, geometry trace, summary, and
manifest, the tool loads the folder back through `LottieReviewFrameFolder` and
fails if any postcondition is false.

The folder postcondition rejects:

- missing expected PNG files;
- zero-byte PNG files;
- unexpected extra PNG files left from an earlier run;
- manifest frame counts that disagree with `png-frame` artifacts;
- timing rationale counts that disagree with the manifest;
- per-frame `frameIndex`, `sourceFrame`, or `timeSeconds` drift between the
  manifest and `frameTiming.samples`;
- `png-frame` paths that are absolute or escape the reviewed folder;
- one-frame exports for multi-frame source windows.

The last rule is intentional. A single-frame review folder is valid only when
the Lottie source window itself spans one frame. A long animation sampled at one
frame is a diagnostic snapshot, not complete visual review evidence.

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
- `backend-evidence`
- `geometry-csv`
- `geometry-json`
- `import-report`
- `lottie-web-intent`
- `oracle-summary`
- `render-ir`
- `validation-report`

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
- Rendered artifact export generated frame count matches png frame artifacts
- Rendered artifact evidence links use stable kinds paths frame addresses and notes
- Rendered frame artifacts link to source-intent and geometry evidence for the same frame
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
- Review frame folders carry valid rendered artifact manifests and frame timing rationales
- Review frame folder generated frame count matches manifest artifacts and timing samples
- Review frame folder frame artifacts match timing sample frame indexes source frames and seconds
- Review frame folder png artifact paths stay inside the reviewed folder
- Review frame folder contains every expected png frame as a non-empty file
- Review frame folder contains no unexpected png frame files
- Review frame folder one-frame exports are backed by a one-frame source window

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

If any of those answers is missing, the manifest validator fails or the
`Tools/LottieOracle` comparison gate marks the artifact set ineligible before
pixel diffs are treated as evidence.
