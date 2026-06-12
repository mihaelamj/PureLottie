# Source-Intent Trace Schema

Status: v1 schema contract for issue #27.

PureLottie treats Lottie import as a compiler pipeline. The source-intent trace
is the durable JSON record between source evaluation and PureLayer lowering:

```text
Lottie JSON -> parse -> validate -> evaluate source frame -> source-intent trace
```

The trace is not a screenshot, a render artifact, or a PureLayer structure. It
records the measurable Lottie facts that must be true before any backend can be
trusted.

## Round-Trip Law

Every v1 trace carries this law:

```text
decode(encode(trace)) == trace
```

The trace also carries the source-to-intent law:

```text
Every render-affecting source fact is either represented in a typed field,
preserved for reconstruction, or listed in diagnostics/unrepresentedFields.
```

If a field is render-affecting and unsupported, it is not dropped. It appears as
a diagnostic with a JSON path and source path.

## Top-Level Object

`LottieSourceIntentTrace` has these fields:

| Field | Meaning |
| --- | --- |
| `schema` | Schema name and integer version. Current name is `purelottie.source-intent-trace`, version `1`. |
| `source` | Source identity, optional path, revision, hash, and byte count. |
| `composition` | Root Lottie composition fields: `w`, `h`, `ip`, `op`, `fr`, version, name, and frame-window law. |
| `frames` | One or more evaluated source-frame records. |
| `diagnostics` | Trace-level validation or evaluation diagnostics. |
| `roundTrip` | Laws and declared losses for this trace. |

## Provenance

Every composition, layer, transform, geometry, style, mask, matte, and diagnostic
record carries `LottieSourceIntentProvenance`:

| Field | Meaning |
| --- | --- |
| `sourcePath` | Human-readable source path, for example `root > layer 'Badge'`. |
| `jsonPath` | Authored Lottie JSON path rooted at `$`. |
| `sourceRange` | Source text range when the parsed source retained one. |
| `consumedFields` | JSON fields used to compute the evaluated fact. |
| `preservedFields` | JSON fields retained so source intent can be reconstructed. |
| `unrepresentedFields` | Render-affecting JSON fields that were not represented exactly. |

The provenance record is mandatory because visual output alone cannot explain a
wrong transform, missing trim, wrong matte, or unsupported effect.

## Frame Object

A frame record contains:

| Field | Meaning |
| --- | --- |
| `sourceFrame` | Lottie frame number, not seconds. |
| `localTimeSeconds` | Optional convenience value. It is derived, never the source clock. |
| `visibleLayers` | Back-to-front visible layer records for this frame. |
| `diagnostics` | Frame-local diagnostics. |

Lottie source timing remains frame-based. The root frame window uses
`ipInclusiveOpExclusive`, meaning `ip <= frame < op`.

## Layer Graph Trace

`LottieLayerGraphEvaluator` emits `LottieLayerGraphTrace` for a selected source
frame. `LottieRenderFrame.layerGraph` carries this trace so backend lowering,
debug dumps, and oracle comparisons can inspect graph facts before looking at
pixels or PureLayer objects.

The trace records the root frame window as `ip <= frame < op`, plus reference
semantics for lottie-web and the CoreAnimation/PureLayer lowering boundary.
CoreAnimation timing is not treated as source truth; the source evaluator keeps
Lottie frame units and the importer converts to seconds later.

Each layer graph record contains:

| Field | Meaning |
| --- | --- |
| `sourcePath`, `jsonPath` | Human-readable and JSON provenance for the layer. |
| `compositionPath`, `compositionStack` | Root/precomp composition context. |
| `arrayOffset`, `layerIndex`, `name`, `type` | Authored layer identity. |
| `participation` | `content`, `transformCarrier`, `precompositionBoundary`, `matteSource`, `hiddenMatteSource`, `hiddenParent`, `transformParticipant`, `skippedHidden`, or `skippedOutsideFrame`. |
| `renderOrder` | Back-to-front graph order for records that participate in output construction. Skipped records use `null`. |
| `visibility` | Selected frame, authored `ip`/`op`, `hd`, half-open rule, and ordinary-content visibility. |
| `timing` | Input frame, `st`, `sr`, frame rate, resulting local frame, and optional `tm` seconds/property trace. |
| `parentChain` | Transform-parent indices, paths, hidden flags, and frame-window membership. |
| `masks` | Mask source path, target layer path, mode, inversion, opacity, path payload, and diagnostics. |
| `matte` | Track-matte mode, resolved source layer path, target layer path, explicit/implicit source flag, and diagnostics. |
| `precomposition` | Referenced asset id/path, child composition path, local frame, size, and child count. |
| `diagnostics` | Layer-local graph diagnostics with source and target paths where an edge is involved. |

This is the measurable layer-language answer before rendering:

- A normal visible layer is `content`.
- A visible null layer is `transformCarrier`.
- A visible precomp layer is `precompositionBoundary`; its children are evaluated
  in the precomp composition stack at the layer's local frame.
- Hidden parent layers are `hiddenParent` when a visible descendant references
  them.
- Matte source layers are `matteSource` or `hiddenMatteSource`; they participate
  in compositing and are recorded separately from ordinary content.
- Non-hidden layers outside their half-open `ip`/`op` window are
  `skippedOutsideFrame`; hidden layers with no active graph role are
  `skippedHidden`.

Mask and matte diagnostics are not pixel judgments. They record source/target
edges so a later backend can prove it handled or reported the exact compositing
relationship.

## lottie-web Intent Trace

`Tools/LottieOracle/scripts/extract-intent.mjs` loads a fixture through the
pinned `npm:lottie-web@5.13.0` SVG renderer and emits
`purelottie.lottie-web-intent` JSON. This is the numeric browser-side reference
used before PNG comparison.

Each trace records:

| Field | Meaning |
| --- | --- |
| `schema` | Trace name and version. |
| `lottieWeb` | Exact npm package and version. |
| `renderer` | Renderer used for extraction; currently `svg`. |
| `frames` | Selected source frames extracted with `goToAndStop(frame, true)`. |
| `frames[].layers` | lottie-web renderer layer internals: authored name/type/index/window, rendered frame, opacity, final transform matrix, and layer element bounds. |
| `frames[].paths` | SVG path facts: `d`, path length, local and sampled composition bounds, computed fill/stroke style, CTM, and ancestor transform chain. |

Committed oracle fixtures live under
`Tests/Fixtures/LottieOracle/lottie-web-intent/`. Swift tests compare these
browser facts against `LottieRenderIRBuilder` output: transform translation,
opacity, source-geometry bounds, path length, and style facts. Rendered PNGs are
therefore checked only after the numeric intent layer is inspectable.

## Property Evaluation Trace

`LottieFrameEvaluator` returns a typed `LottiePropertyEvaluationTrace` beside
each scalar or vector value it evaluates. This trace is the measurable state
used before RenderIR or PureLayer lowering. It records:

| Field | Meaning |
| --- | --- |
| `propertyPath` | JSON path for the property, for example `$.layers[0].ks.p`. |
| `sourceFrame` | Caller-selected Lottie source frame. |
| `offsetFrame` | Layer/start-time offset applied to authored keyframe times. |
| `localFrame` | `sourceFrame + offsetFrame`, the authored keyframe domain sampled. |
| `mode` | Fixed, before/after keyframes, selected keyframe span, hold keyframe, or split position. |
| `finalValue` | Evaluated scalar or vector components before lowering. |
| `span` | Selected keyframe span evidence when the value is animated. |
| `childTraces` | Split-position child traces for `x`, `y`, and optional `z`. |

The span record contains authored and evaluated start/end frames, start/end
values, linear progress, timing-curve progress, interpolation space, hold flag,
and the timing curve handles used for every component. For spatial position
segments with `to`/`ti`, `interpolationSpace` is `spatialArcLength` and the
trace additionally records the out/in tangents, cubic control points, 150
lottie-web sample segments, total measured segment length, selected distance,
sample point index, and intra-sample progress.

If required non-hold timing handles or spatial tangents are incomplete or
dimensionally inconsistent, evaluation returns a semantic diagnostic instead of
claiming exact behavior.

## Layer Object

A layer record contains:

| Field | Meaning |
| --- | --- |
| `id` | Stable trace id such as `render#1`. |
| `name`, `index`, `type` | Authored layer identity and type. |
| `renderOrder` | Back-to-front order inside the evaluated frame. |
| `localFrame` | Layer-local frame after start time, stretch, and time remap. |
| `opacity` | Evaluated opacity in `[0, 1]`. |
| `transform` | Evaluated transform values and matrix. |
| `geometry` | Evaluated source geometry records. |
| `styles` | Fill, stroke, gradient, or unsupported style records. |
| `masks` | Evaluated masks attached to this layer. |
| `matte` | Matte edge if the layer consumes a track matte. |
| `diagnostics` | Layer-local diagnostics. |
| `provenance` | Source path and JSON path evidence. |

## Matrix Convention

Every transform states its matrix convention explicitly. The v1 golden fixture
uses `LottieSourceIntentMatrixConvention.lottieWebRowVector4x4`:

```text
storageOrder: row-major-4x4
vectorConvention: row-vector
concatenationOrder: left-to-right
pointApplication: x'=x*m0+y*m4+z*m8+m12; y'=x*m1+y*m5+z*m9+m13
```

This is recorded because transform comparisons are meaningless unless origin,
axis direction, storage order, multiplication order, and point application are
known.

The matrix payload is a single JSON array, but the Swift model decodes it through
`LottieSourceIntentMatrix` and rejects any array that does not contain exactly
16 values.

## Transform Matrix Trace

`LottieTransformEvaluator` emits `LottieTransformTrace` records for layer
transforms and shape-group transforms before any PureLayer lowering. A trace
contains:

| Field | Meaning |
| --- | --- |
| `scope` | `local` for a single layer or group, `world` after composing a layer parent chain. |
| `transformPath` | JSON path of the transform object, for example `$.layers[0].ks` or `$.layers[0].shapes[0].it[1]`. |
| `sourceFrame` | Lottie source frame sampled by the evaluator. |
| `matrixConvention` | Always explicit; current evaluator output uses `lottieWebRowVector4x4`. |
| `components` | Anchor, position, scale, and rotation evidence. |
| `operations` | Matrix operations in lottie-web order: translate anchor, scale, rotate Z, translate position. |
| `parentChain` | Parent layer component traces, matrix conventions, matrices, and operations appended while computing a world transform. |
| `resultingMatrix` | Accumulated matrix after all operations and parent matrices. |

Each component trace separates authored, sampled, and matrix-ready values:

| Field | Meaning |
| --- | --- |
| `rawValue` | Authored initial value when the property exists. Missing properties use `nil`. |
| `evaluatedValue` | Value sampled at `sourceFrame`, still in Lottie units. |
| `matrixValue` | Normalized operand used by the matrix operation: anchor `[-x, -y, z]`, position `[x, y, -z]`, scale `[x / 100, y / 100, z / 100]`, rotation `[-degrees * pi / 180]`. |
| `defaultValue` | Lottie default used when the property is absent. |
| `usedDefault` | `true` only when the property is absent. |
| `propertyTrace` | Underlying scalar/vector `LottiePropertyEvaluationTrace` when the component was authored. |

World transforms use row-vector application. A source-space point is transformed
with the lottie-web formula:

```text
x' = x*m0 + y*m4 + z*m8  + m12
y' = x*m1 + y*m5 + z*m9  + m13
z' = x*m2 + y*m6 + z*m10 + m14
```

2D authored vectors do not duplicate their last component. Missing `z` is
normalized as `0` for anchor and position, and `100` percent for scale before
matrix conversion.

## Geometry And Style

`LottieSourceGeometryEvaluator` expands modeled Lottie geometry into a contour
trace before any PureDraw or PureLayer object is created. The trace records the
primitive, source frame, source path, JSON path, consumed fields, direction
branch, closed flag, vertices, relative in/out tangents, absolute in/out
control points, cubic bounds, and compatibility constants.

Primitive geometry follows the lottie-web algorithms inspected in
`player/js/utils/shapes/ShapeProperty.js`:

- Ellipses start at noon. `d == 3` reverses the side order while preserving the
  noon start vertex.
- Rectangles start on the right edge. When `d` is missing, lottie-web takes the
  reversed rectangle branch; `d == 1 || d == 2` uses the forward branch. Rounded
  rectangle radius is clamped by `min(width / 2, height / 2, r)` and uses
  `roundCorner = 0.5519`.
- Polystars use `sy == 1` for star and `sy == 2` for polygon, floor `pt`, start
  at `rotation - 90deg`, advance angle by `d == 3 ? -1 : 1`, and scale `os/is`
  roundness percentages by `0.01`.
- Raw `sh` paths preserve the authored `v/i/o/c` arrays. The `d` field is
  retained as evidence, but lottie-web does not regenerate raw Bezier path order
  from `d`.

Geometry records preserve the source primitive:

| Kind | Required payload |
| --- | --- |
| `rectangle` | `primitive = "rc"`, consumed `p`, `s`, `r`, `d`, expanded contour, radius clamp, and direction branch. |
| `ellipse` | `primitive = "el"`, consumed `p`, `s`, `d`, expanded contour, and `roundCorner`. |
| `path` | `primitive = "sh"`, `closed`, `vertices`, `inTangents`, `outTangents`, and retained direction evidence. |
| `polygon` | `primitive = "sr"`, `sy == 2`, consumed `pt`, `p`, `r`, `or`, `os`, `d`, expanded contour, and point floor. |
| `star` | `primitive = "sr"`, `sy == 1`, consumed `pt`, `p`, `r`, `or`, `os`, `ir`, `is`, `d`, expanded contour, and point floor. |
| `unsupported` | A diagnostic with the unsupported JSON path. |

Style records preserve source style intent: fill/stroke kind, RGBA color,
opacity, stroke width, cap, join, miter, dash pattern, blend mode, and
provenance.

## Trim Path Trace

`LottieSourceTrimEvaluator` evaluates `tm` modifiers over expanded source
geometry before any PureLayer or PureDraw object is created. It follows the
trim code inspected in `player/js/utils/shapes/TrimModifier.js` and
`player/js/utils/bez.js`:

- `s` and `e` are authored as percentages and converted to fractions.
- `o` is authored in degrees, reduced modulo `360`, and converted to turns.
- Start/end fractions are clamped to `[0, 1]`, offset is added, reversed ranges
  are swapped, and both boundaries are rounded to 4 decimals.
- `m == 1` is parallel mode: every path receives the same normalized range.
- `m == 2` is sequential mode: paths are measured as one continuous sequence in
  lottie-web processing order.
- Cubic length uses lottie-web's default 150 sample points. Generated trim
  subsegment control points are rounded to 0.001 like `bez.getNewSegment`.

Each trim trace records:

| Field | Meaning |
| --- | --- |
| `sourcePath`, `jsonPath`, `sourceFrame` | Modifier provenance and selected Lottie frame. |
| `authoredMultiple`, `mode` | Authored `m` value and resolved `parallel`/`sequential` mode. |
| `normalization` | Authored start/end/offset, raw fractions, offset turns, normalized rounded fractions, swapped flag, empty/full flags. |
| `inputPaths` | One record per source path: source path, JSON path, primitive, closure, total length, and per-cubic lengths. |
| `totalLength` | Sum of measured input lengths, used by sequential mode. |
| `sequenceOrder` | The source path order used for sequential selection. |
| `selectedSegments` | Path-level selected ranges with local/global lengths, fractions, sequence ordinal, and per-cubic selected ranges. |
| `resultPaths` | Generated Bezier paths for the selected ranges, still in Lottie source-space terms. |
| `approximations` | Named compatibility approximations/constants, currently `lottieWebDefaultCurveSegments`, `lengthParameterization`, and `trimmedCubicRoundingDecimals`. |

This trace is the measurable answer to "what did Lottie intend?" for trim
paths. Backend lowering may still be approximate; the trace must remain present
so the backend result can be compared against source intent rather than judged
from pixels alone.

## Diagnostics

Diagnostics carry:

| Field | Meaning |
| --- | --- |
| `ruleID` | Stable rule identifier. |
| `severity` | `error`, `warning`, or `note`. |
| `phase` | `parse`, `source`, `semantic`, or `lowering`. |
| `classification` | `exact`, `approximate`, `reported`, `metadata`, or `gap`. |
| `reason` | Human-readable explanation. |
| `evidence` | Optional source or engine evidence. |
| `provenance` | The exact source fact being diagnosed. |

Unsupported render-affecting facts must be diagnostics, not comments and not
silent omissions.

`severity`, `phase`, and `classification` are typed schema vocabularies in Swift,
not free-form strings. Unknown values fail JSON decoding instead of becoming
silent evidence typos.

## Golden Fixture

The first golden fixture is:

```text
Tests/Fixtures/SourceIntentTrace/shape-position.frame-0.trace.json
```

It records a shape layer with one rectangle, one fill style, one identity matrix,
and one explicit unsupported transform-skew diagnostic. The Swift tests decode
it, assert provenance fields, assert unsupported fact reporting, and perform a
JSON encode/decode round trip through `LottieSourceIntentTrace`.
