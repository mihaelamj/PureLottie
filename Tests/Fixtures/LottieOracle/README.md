# Lottie Oracle Fixture Corpus

This directory contains the curated source-intent oracle corpus for PureLottie.
Every fixture is intentionally small enough for review and has a committed
`purelottie.lottie-web-intent` snapshot produced by
`Tools/LottieOracle/scripts/extract-intent.mjs` with pinned
`npm:lottie-web@5.13.0`.

The large raw corpus under `Tests/Fixtures/LottieCorpus` is discovery material.
The files in this directory are the vetted regression set: each one isolates a
specific semantic bug class, selected source frames, and the numeric browser
trace used before any PNG comparison.

| Fixture | Status | Coverage | Bug class protected | Frames |
| --- | --- | --- | --- | --- |
| `eligible-shape-position` | modeled | `animated-position`, `rectangle`, `fill`, `transform` | Animated layer position was previously judged from shifted PNGs instead of numeric translation. | 0, 5, 9 |
| `static-rectangle-fill` | modeled | `static-position`, `rectangle`, `fill` | Baseline geometry and fill color must be correct before animation is considered. | 0, 5, 9 |
| `animated-position-linear` | modeled | `animated-position`, `rectangle`, `fill`, `transform` | Linear position in-betweens must match source-frame interpolation, not image inspection. | 0, 5, 9 |
| `split-position-ellipse` | modeled | `split-position`, `ellipse`, `fill`, `transform` | Split-position values must rejoin into one evaluated layer position before lowering. | 0, 5, 9 |
| `anchor-rotation-rectangle` | modeled | `anchor`, `rotation`, `rectangle`, `fill` | Anchor translation and clockwise rotation order must agree with lottie-web matrices. | 0, 5, 9 |
| `scale-rotation-anchor` | modeled | `anchor`, `scale`, `rotation`, `rectangle` | Scale, anchor, and rotation composition must be measurable before target backend assignment. | 0, 5, 9 |
| `animated-opacity-rectangle` | modeled | `opacity`, `rectangle`, `fill` | Opacity must be sampled numerically at the source frame, not inferred from raster alpha by eye. | 0, 5, 9 |
| `group-transform-rectangle` | modeled | `shape-transform`, `rectangle`, `fill` | Shape transforms are scoped to the group and must not be mistaken for layer transforms. | 0, 5, 9 |
| `group-opacity-two-shapes` | modeled | `shape-group`, `group-opacity`, `rectangle`, `ellipse` | Group opacity is an atomic compositing fact and must not be flattened silently per shape. | 0, 5, 9 |
| `parent-null-transform-child` | modeled | `parent-transform`, `null-layer`, `rectangle`, `fill` | Parent transform composition must use the parent layer matrix before the child matrix. | 0, 5, 9 |
| `parent-animated-transform-child` | modeled | `parent-transform`, `animated-position`, `null-layer`, `rectangle` | Animated parent matrices must affect the child world matrix at every sampled frame. | 0, 5, 9 |
| `ellipse-fill` | modeled | `ellipse`, `fill` | Ellipse noon-start geometry and bounds must be captured in source space. | 0, 5, 9 |
| `ellipse-reversed-direction` | modeled | `ellipse`, `direction`, `fill` | Direction changes trim and path ordering even when the untrimmed bounds look identical. | 0, 5, 9 |
| `rounded-rectangle` | modeled | `rectangle`, `roundness`, `fill` | Rounded rectangle control points require the lottie-web radius clamp and roundCorner constant. | 0, 5, 9 |
| `raw-bezier-triangle` | modeled | `path`, `fill` | Raw path vertices and tangents must be preserved without primitive regeneration. | 0, 5, 9 |
| `raw-bezier-cubic` | modeled | `path`, `stroke` | Cubic path length and bounds must come from authored tangents, not a polyline guess. | 0, 5, 9 |
| `polygon-five` | modeled | `polygon`, `polystar`, `fill` | Polygon point flooring, rotation, and direction must match lottie-web source geometry. | 0, 5, 9 |
| `star-five` | modeled | `star`, `polystar`, `fill` | Star inner and outer radii must survive source evaluation before any PureDraw lowering. | 0, 5, 9 |
| `fill-rule-evenodd` | modeled | `path`, `fill-rule`, `fill` | Fill-rule style facts must be retained because identical vertices can rasterize differently. | 0, 5, 9 |
| `stroke-basic-line` | modeled | `path`, `stroke` | Stroke color, opacity, and width must be measured as style facts separate from fill. | 0, 5, 9 |
| `stroke-caps-joins` | modeled | `path`, `stroke`, `line-cap`, `line-join` | Line caps and joins are render-affecting stroke facts and must not disappear from the trace. | 0, 5, 9 |
| `stroke-dash` | modeled | `path`, `stroke`, `dash` | Dash arrays are numeric stroke facts and must be represented or reported before pixels. | 0, 5, 9 |
| `animated-stroke-width` | modeled | `path`, `stroke`, `animated-width` | Animated stroke width must be sampled from source frames before lowerer decisions. | 0, 5, 9 |
| `trim-rectangle-half` | modeled | `rectangle`, `stroke`, `trim` | Trim start/end percentages must map to contour length, not an arbitrary quadrant guess. | 0, 5, 9 |
| `trim-ellipse-quadrant` | modeled | `ellipse`, `stroke`, `trim` | Ellipse trim direction and noon-start ordering must be measurable numerically. | 0, 5, 9 |
| `animated-trim-path` | modeled | `path`, `stroke`, `trim`, `animated-trim` | Animated trim must produce source-frame segment facts before rendered output is trusted. | 0, 5, 9 |
| `layer-window-in-out` | modeled | `frame-window`, `rectangle`, `fill` | Layer ip/op semantics must be proven at numeric frame boundaries. | 2, 3, 8, 9 |
| `mask-add-rectangle` | modeled | `mask`, `rectangle`, `fill` | Mask path, mode, inversion, and opacity are source graph facts before backend masking. | 0, 5, 9 |
| `alpha-matte-rectangle` | modeled | `matte`, `rectangle`, `ellipse`, `fill` | Track matte source-target relationship must be explicit instead of guessed from layer order. | 0, 5, 9 |
| `precomp-static-child` | modeled | `precomp`, `animated-position`, `rectangle`, `fill` | Precomp boundaries and child composition paths must be visible in source intent. | 0, 5, 9 |
| `time-remap-precomp-diagnosed` | diagnosed | `precomp`, `time-remap`, `diagnostic`, `animated-position` | Time remap is a diagnosed semantic boundary until lowering consumes the evaluator exactly. | 0, 5, 9 |
