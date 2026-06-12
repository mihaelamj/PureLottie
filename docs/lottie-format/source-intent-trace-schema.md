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

Geometry records preserve the source primitive:

| Kind | Required payload |
| --- | --- |
| `rectangle` | `primitive = "rc"`, `parameters.center`, `parameters.size`, `parameters.roundness`. |
| `ellipse` | `primitive = "el"`, `parameters.center`, `parameters.size`. |
| `path` | A `path` object with `closed`, `vertices`, `inTangents`, and `outTangents`. |
| `unsupported` | A diagnostic with the unsupported JSON path. |

Style records preserve source style intent: fill/stroke kind, RGBA color,
opacity, stroke width, cap, join, miter, dash pattern, blend mode, and
provenance.

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
