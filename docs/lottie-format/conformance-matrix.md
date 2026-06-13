# PureLottie Lottie Conformance Matrix

This document is the working contract for understanding original
Bodymovin/Lottie semantics before judging PureLayer output. Generated images are
not evidence unless every feature used by the source document is either lowered
correctly or reported with the offending layer/shape path.

## Primary Sources

- Lottie specification clone inspected at `/tmp/lottie-spec-source`.
  Relevant files: `docs/specs/composition.md`, `docs/specs/layers.md`,
  `docs/specs/shapes.md`, `docs/specs/properties.md`,
  `docs/specs/assets.md`, `docs/specs/helpers.md`, and `schema/**`.
- Original lottie-web clone inspected at `/tmp/lottie-web-source`.
  Relevant files: `player/js/elements/svgElements/SVGShapeElement.js`,
  `player/js/utils/TransformProperty.js`,
  `player/js/utils/PropertyFactory.js`,
  `player/js/utils/shapes/ShapeProperty.js`,
  `player/js/utils/shapes/TrimModifier.js`, and
  `player/js/utils/shapes/RepeaterModifier.js`.
- PureLottie current implementation inspected in `Sources/LottieModel` and
  `Sources/LottieEvaluation` plus `Sources/LottieImport`.

## Status Legend

- `lowered`: decoded and mapped into PureLayer/PureDraw behavior.
- `approx`: decoded and mapped with a known approximation recorded in
  `ImportReport`.
- `reported`: decoded or detected, then skipped/reported with source path.
- `modeled`: decoded into `LottieModel`, but not necessarily lowered.
- `gap`: observed in corpus but not faithfully modeled, lowered, or reported.
- `metadata`: non-rendering data; safe only when it cannot affect pixels.

## Original Semantics That Must Not Be Violated

- Composition `ip` is inclusive, `op` is exclusive, and duration is
  `(op - ip) / fr`.
- Layer visibility is `layer.ip <= frame < layer.op`.
- Hidden layers are not rendered normally, but can still contribute as parents
  or matte sources.
- Parent transforms compose as `CTM(parent) * Transform(child)`.
- Layer transform order is anchor translation, scale, skew, rotation, then
  position translation.
- Shape lists are scoped programs, not draw-order lists. lottie-web walks shape
  arrays from end to start; styles and modifiers apply to preceding shapes in
  scope.
- Multiple styles render the same shape multiple times.
- Multiple modifiers compose in reverse order.
- Group opacity is atomic: it applies to the composited group result, not to
  each child independently.
- Shapes without an applicable style are not rendered.
- Shape geometry and keyframe values must be evaluated at the requested frame,
  not just at initial value.
- A debugger trace must be tied to one selected source frame and must record the
  composition/layer/group/style/modifier/matte/precomp decisions made before
  backend lowering.
- Vector keyframe easing may use per-component `i/o.x` and `i/o.y` arrays.
- Property evaluation traces record source frame, selected keyframe span,
  linear progress, timing-curve result, and final value before lowering.
- lottie-web spatial `to`/`ti` tangents use sampled arc length for curved
  motion paths, and treat a straight segment as linear when both control
  points are collinear with the segment.

## Corpus Snapshot

Observed in `Tests/Fixtures/LottieCorpus`:

| Item | Count |
| --- | ---: |
| Lottie JSON fixtures | 857 |
| Unique JSON payloads by SHA-256 | 675 |
| Declared source frames, `sum(op - ip)` | 29,627,410 |
| Shape layers, including precomps | 12,537 |
| Precomp layers | 2,469 |
| Solid layers | 759 |
| Null layers | 576 |
| Image layers | 361 |
| Text layers | 222 |
| Masks | 1,336 |
| Track matte entries | 502 |
| Shape groups | 25,414 |
| Bezier paths | 23,836 |
| Solid fills | 18,014 |
| Strokes | 7,456 |
| Ellipses | 3,624 |
| Trim paths | 2,920 |
| Merge paths | 1,946 |
| Rectangles | 1,126 |
| Gradient fills | 508 |
| Polystars | 148 |
| Gradient strokes | 103 |
| Rounded corners | 58 |
| Repeaters | 56 |

## Conformance Matrix

| Area | Original Lottie semantics | Corpus evidence | PureLottie model | PureLottie import | PureLayer/PureDraw target | Status | Required validation |
| --- | --- | ---: | --- | --- | --- | --- | --- |
| Composition timing | Root `ip` inclusive, `op` exclusive, `fr` converts frames to seconds. | 857 files | `LottieAnimation` decodes `fr`, `ip`, `op`, `w`, `h`, `layers`, `assets`; `LottieEvaluation` keeps source-frame answers. | `ImportContext.duration` uses `(op - ip) / fr`; frame-to-second conversion is centralized. | `LottieScene.duration`, `Timing`, frame sampling. | lowered | Unit tests for `op` exclusivity and source frame selection. |
| Root size and clipping | Root composition defines viewport; output clipped to `w` x `h`. | 857 files | `width`, `height`. | Root layer bounds set to composition and `masksToBounds = true`. | `Layer.bounds`, `masksToBounds`. | lowered | Pixel test with content outside bounds. |
| Layer order | Lottie lists top layer first; renderer composites bottom to top. | 16,931 layer records | `LottieLayer` preserves input order; `LottieLayerGraphEvaluator` emits back-to-front graph records and render-order ordinals. | RenderIR carries the layer graph and still emits backend nodes separately. | `Layer.addSublayer` order. | modeled | Layer graph render-order test with overlapping layer order. |
| Layer visibility | Layer visible for `ip <= frame < op`. | 16,928 `ip`, 16,931 `op` | `inPoint`, `outPoint`; `LottieLayerGraphEvaluator` records the half-open window, selected frame, ordinary-content visibility, and lottie-web/CoreAnimation boundary notes. | `visibilityWindow` gates opacity in seconds until lowering consumes graph timing directly. | `opacity` animation. | modeled | Boundary tests at `ip`, `op - 1`, and `op`, including `op` exclusivity. |
| Hidden layers | `hd` hides normal rendering but hidden layers still matter for parents and mattes. | 204 layer `hd` keys | `isHidden`; layer graph classifies `hiddenParent`, `hiddenMatteSource`, and `skippedHidden` separately. | Binding preserves hidden parent/matte references before normal rendering skips hidden layers. | Layer omission plus binding graph. | modeled | Parent and matte fixtures where source layer is hidden but semantically active. |
| Parent transforms | Child CTM is parent CTM multiplied by child transform, transitively. | 5,842 `parent` keys | `parent`, `index`; `LottieTransformEvaluator.worldTransform` composes child-local row-vector matrices with parent-local matrices and records each parent's component traces, matrix convention, matrix, and operations in `parentChain`. | Wraps child in parent holder layers. | Nested `Layer` transforms. | approx | Matrix oracle tests for multi-parent chain, animated parents, hidden parents, parent-chain component trace, and lottie-web point application. |
| 2D layer transform | Apply `-anchor`, scale, skew, rotation, position. Rotation is clockwise in Lottie/lottie-web matrix convention. | 16,900 anchors, 16,929 positions, 16,454 scales, 16,329 rotations | Anchor, position including split `z`, scale, rotation, opacity; `LottieTransformEvaluator` emits source-frame row-vector matrices with authored initial values, evaluated values, normalized matrix operands, operation traces, parent chains, and lottie-web point application. | Importer consumes evaluated transform state for anchor, position, z, scale, and rotation before assigning PureLayer fields; animated components still lower to PureLayer key paths. | `Layer.anchorPoint`, `anchorPointZ`, `position`, `zPosition`, `transform`, animations. | approx | Matrix comparison against lottie-web for static, animated, 2D-vector, point-application, and parent-chain transform cases. |
| Skew transform | `sk` and `sa` skew around skew axis between scale and rotation. | 136 layer `sk`, 137 layer `sa`, 23,555 shape `sk/sa` | Layer `sk`/`sa` decoded; transform evaluator emits structured unsupported-skew diagnostics. Shape transform skew remains a gap. | Default validation rejects/report-blocks skew before lowering; importer does not silently lower it. | Affine transform with skew. | reported | Layer model fields, semantic diagnostic tests, shape skew model/report work. |
| 3D layer transform | `rx`, `ry`, `rz`, `or` produce 3D rotation/orientation; Lottie is 2.5D. | 103 each of `rx`, `ry`, `rz`; 101 `or` | Layer `ddd`, `rx`, `ry`, `rz`, and `or` decoded; transform evaluator emits structured unsupported-3D diagnostics. | Default validation rejects/report-blocks 3D transforms before lowering; importer does not silently lower them. | PureLayer 2.5D transform if available; otherwise report. | reported | Model fields, semantic diagnostic tests, and PureLayer 2.5D lowering fixtures. |
| Auto orient | `ao` rotates layer to follow motion path tangent. | 14,262 `ao` keys | `autoOrient` decoded; transform evaluator emits structured unsupported-auto-orient diagnostics. | Default validation rejects/report-blocks auto-orient before lowering. | Rotation animation derived from position path. | reported | Motion-path fixture with tangent orientation. |
| Blend modes | `bm` maps to CSS compositing blend modes. | 14,621 layer `bm`; many shape `bm` keys | Layer `bm` and fill/stroke style `bm` are decoded as authored compositing facts. | Non-zero layer/fill/stroke blend modes are reported during RenderIR-to-PureLayer lowering with backend capability evidence. | PureLayer compositing/filter support or report. | reported | Blend-mode source fixtures and ImportReport assertions for layer and style terms. |
| Solid layers | `ty:1` solid rectangle with `sw`, `sh`, `sc`. | 759 | Solid fields decoded. | Creates `Layer` with bounds and background color. | `Layer.backgroundColor`, `bounds`. | lowered | Solid color/bounds pixel test. |
| Null layers | `ty:3` contributes transform hierarchy without pixels. | 576 | Decoded as `null`. | Creates transparent layer with comp bounds. | Empty `Layer` for transform carrier. | approx | Parent/null chain matrix tests. |
| Precomp layers | `ty:0` instantiates asset layers with local timing, stretch, remap. | 2,469 | `refId`, `w`, `h`, `sr`, `st`, `tm`; asset layers. `LottieLayerGraphEvaluator` records precomp local frame, asset path, child count, size, and time-remap seconds/property trace. | Builds asset layers; reports non-1 stretch and time remap until lowering consumes local-frame evaluation. | Nested `Layer`, time-shifted animations. | modeled | Precomp local-frame and time-remap source graph fixtures. |
| Time stretch | `sr` changes layer local time: `t' = t / sr - st`. | 14,692 `sr` keys | `stretch`; `LottieEvaluation.localFrame` applies `st` and `sr` in source-frame space. | Reports stretch when not 1, but still renders unstretched. | Animation timing scaling. | reported | Expected report plus no silent render claim. |
| Time remap | `tm` remaps layer time in seconds, multiplied by `fr` to local frames. | 135 layer `tm` | `timeRemap`; `LottieEvaluation.localFrame` evaluates scalar remap and clamps exact `op` to `op - 1` like lottie-web. | Reports `time remap` until lowering consumes the evaluator. | Animation local-time evaluator. | reported | Model field, evaluator, and ImportReport tests. |
| Composition VM trace | For a selected source frame, traversal must expose composition, layer, group, style, modifier, matte, precomp, semantic decision, evaluated value, and emitted render node state before rendering. | All composition/layer fixtures | `LottieCompositionVM` runs independently of PureLayer, with explicit VM instructions, frame clock, composition/layer/transform/style/opacity/matte stacks, JSON paths, source ranges when available, diagnostics, checkpoints, deterministic render node ids, and debugger step/breakpoint/watch APIs. | Not a backend lowering step; the importer remains separate. The VM emits trace records and placeholder render nodes for future RenderIR/PureLayer lowering. | RenderIR and IDE debugger stepping. | modeled | Swift Testing coverage for readable debug traces, fast traces, JSON path links, trim modifiers, masks, precomps, skipped layers, render ids, checkpoints, step into/over/out/back, breakpoints, and watches. |
| Layer graph trace | A selected source frame must expose graph participation before backend nodes exist: visible content, transform carriers, precomp boundaries, hidden parents, matte sources, skipped hidden layers, skipped frame-window layers, masks, mattes, and local frames. | All composition/layer fixtures | `LottieLayerGraphEvaluator` emits `LottieLayerGraphTrace` with frame-window reference semantics, per-layer participation, render order, timing, parent chain, mask/matte source-target paths, precomp local frame, and diagnostics. | `LottieRenderFrame.layerGraph` carries the trace for lowerers and oracle dumps. | Backend graph/compositing input. | modeled | Swift Testing coverage for render order, `op` exclusivity, hidden parent, precomp time remap, mask diagnostics, matte diagnostics, and Codable round trip. |
| RenderIR frame boundary | A selected source frame must become backend-ready semantic IR before any PureLayer/PureDraw object is created. Every node retains source path, JSON path, trace identity, layer graph trace, evaluated transform, opacity, masks/mattes, shape draws, placeholders, and diagnostics. | All composition/layer fixtures | `LottieRenderIRBuilder` emits `LottieRenderFrame` from `LottieEvaluation` without importing PureLayer. Shape geometry/style/masks/trims are evaluated at the selected frame and retain provenance. | `LottieRenderIRLowerer` is a backend pass from RenderIR to PureLayer. It does not re-run Lottie semantics; unsupported backend capabilities become `ImportReport` findings with structured owner, fixture, source-frame, Lottie/JSON path, source-range, VM trace, RenderIR node/term, layer graph, and oracle artifact evidence. | `Layer`, `ShapeLayer`, PureDraw `Path`, and backend-gap diagnostics. | approx | Swift Testing coverage proves RenderIR emission is PureLayer-free, lowerer receives evaluated values and layer graph facts, backend gaps report exact RenderIR source paths, and evidence distinguishes backend capability gaps from intentional approximations. |
| lottie-web oracle | Reference frames and numeric source intent must come from pinned lottie-web behavior; pixel comparison is only meaningful after semantic eligibility and numeric intent are proven. | 31 curated oracle fixtures plus 857 raw corpus files available for expansion. | `LottieValidator` decides eligibility; `LottieRenderIRBuilder` supplies trace context per selected source frame; committed `purelottie.lottie-web-intent` traces compare browser matrices, path counts, opacity, direct translation facts, and selected style/geometry facts to PureLottie source facts. | `LottieFrameDump` emits PureLayer PNGs plus validation/import/RenderIR summaries and per-frame RenderIR backend evidence; `Tools/LottieOracle` renders pinned lottie-web PNGs, extracts numeric intent JSON, writes comparison reports, and regenerates the curated corpus with `npm --prefix Tools/LottieOracle run build-corpus`. | External browser harness, lottie-web numeric trace, PNG diff, semantic trace artifacts, backend evidence artifacts, curated fixture manifest. | modeled | Node harness tests pin every committed trace and coverage family; Swift corpus tests decode all 31 fixtures and snapshots; selected-frame rationale, validation gate, mismatch artifacts, RenderIR traces, and backend-evidence comparison blocking. |
| Corpus semantic ledger | Every observed corpus field must be classified before a fixture can influence conformance claims. | 857 files, 675 unique payloads, source/license counts pinned. | Test ledger classifies observed fields as lowered, approximated, reported, metadata, or gap. | Fixture eligibility is derived conservatively from field classifications before visual oracle use. | Corpus gate and conformance matrix vocabulary. | modeled | `CorpusSemanticLedgerTests` fails on unclassified fields, count drift, missing licenses, status-vocabulary drift, and reports eligibility reasons. |
| Image layers | `ty:2` references image asset; asset may be external or embedded data URL. | 361 | Type known, asset image payload not modeled. | Reports `layer type 2`. | Image-backed layer or report. | reported | Fixture checks include asset path and layer path in report. |
| Text layers | `ty:5` has text document and animators. | 222 | Type known, text payload not modeled. | Reports `layer type 5`. | Text drawing or report. | reported | Fixture checks include text layer path in report. |
| Masks | Layer masks support add, subtract, intersect, lighten/darken/difference variants, opacity, inversion. | 1,336 masks; modes `a`, `f`, `s`, `n`, `i`, `l`, `d` | Mode, path, opacity, inversion decoded; layer graph records mask source path, target layer path, opacity, path payload, and mode/inversion diagnostics. | Supports one non-inverted additive mask; reports multiple, unsupported modes, inverted, animated path/opacity as approximate. | `Layer.mask` with `ShapeLayer`. | modeled | Per-mode graph fixtures plus backend report tests. |
| Track mattes | `tt`, `tp`, `td` connect matte layer to target layer. Hidden matte sources can still contribute. | 502 `tt`, 357 `td`, 9 `tp` | `trackMatteType`, `trackMatteParent`, `trackMatteSource`; layer graph resolves implicit/explicit source path, target path, source JSON path, and hidden matte source participation. | Binding resolves matte edges and reports unsupported matte lowering with source path/range. | Layer mask/compositing graph. | modeled | Source graph tests for alpha matte edges, hidden matte source participation, and source-target diagnostics; lowering tests for backend reports. |
| Shape scope/order | Shape arrays are programs: reverse walk, styles/modifiers apply to preceding shapes in scope. | 25,414 groups, 25,412 transforms | `LottieShape` preserves item arrays; `LottieShapeProgram` exposes inspectable style runs, geometry fragments, modifiers, and transform stacks without PureLayer/PureDraw. | The importer first builds `LottieShapeProgram`, bridges diagnostics into `ImportReport`, then lowers to `DrawingProgram`/PureLayer. | PureDraw `Path` plus PureLayer shape/compositing layers. | approx | Semantic program tests plus DrawingProgram/lottie-web shape scope examples. |
| Shape groups | Groups scope transforms, styles, modifiers; group opacity is atomic. | 25,414 | `ShapeGroup.items`; `LottieShapeProgram.Group` keeps source path, transform, opacity, pass-through/atomic compositing mode, and child nodes. | Recurses; wraps in transparency layer when opacity static and not 1; animated group opacity reported. | Nested `Layer` for group opacity. | approx | Group opacity compositing pixel tests. |
| Shape transforms | Shape-level transform affects geometry and style transforms separately. | 25,412 `tr` | Anchor, position, scale, rotation, opacity decoded; `LottieTransformEvaluator.groupTransform` emits the same source-frame matrix and operation trace for shape transform paths; skew missing. | Static transforms baked into path; animated transforms reported; multiple transforms approximated. | `AffineTransform` on PureDraw path; group layers for opacity. | approx | Transform-order, group-transform path trace, and style-transform fixtures. |
| Paths | `sh` Bezier vertices with relative tangents; animated paths morph at frame time. | 23,836 | Static and keyframed Bezier decoded; direction `d` is retained as source evidence. `LottieSourceGeometryEvaluator` emits source-frame vertices, relative/absolute tangents, closure, direction evidence, and exact cubic bounds. | Static contour lowered through the source-geometry trace; animated path reports `path morph`. | PureDraw `Path`. | approx | Morph tests using lottie-web reference frames plus source-geometry trace tests for raw vertex preservation. |
| Rectangles | `rc` centered rectangle; rounded rectangle follows lottie-web Bezier algorithm and direction. | 1,126 | Position, size, roundness, and direction decoded. `LottieSourceGeometryEvaluator` expands the right-edge start contour, radius clamp, direction branch, and `roundCorner = 0.5519`. | Static contour lowered through the source-geometry trace; animated geometry reported by static importer. | PureDraw path from generated Bezier. | approx | Direction, top-right/right-edge start, radius clamp, tangent, and RenderIR source-geometry tests. |
| Ellipses | `el` centered ellipse; direction matters for trim path stroke order. | 3,624 | Position, size, and direction decoded. `LottieSourceGeometryEvaluator` expands the noon-start contour and records `roundCorner = 0.5519`. | Static contour lowered through the source-geometry trace; animated geometry reported by static importer. | PureDraw path from generated Bezier. | approx | Noon-start, direction, bounds, and trim-order fixtures. |
| Polystar | `sr` star/polygon with points, radii, roundness, rotation, direction. | 148 | `sy`, `pt`, `p`, `r`, `or`, `os`, `ir`, `is`, and `d` decoded. `LottieSourceGeometryEvaluator` expands polygon/star contours using lottie-web point floor, rotation offset, direction multiplier, and roundness scaling. | Static contour lowered through the source-geometry trace; animated geometry reported by static importer. | PureDraw path from generated Bezier. | approx | Source-geometry tests for polygon/star vertices, point floor, roundness constants, and RenderIR trace carrying. |
| Solid fill | `fl` style applies color/opacity/fill rule to preceding shapes in scope. | 18,014 | Color, opacity, fill rule decoded. | Static color/opacity lowered; animated color/opacity reported. | `ShapeLayer.fillColor`, `fillRule`. | approx | Style-scope tests; animated color report tests. |
| Stroke | `st` style applies color, opacity, width, caps, joins, miter, dash, and blend mode. | 7,456 | Color, opacity, width, caps, joins, miter limits, dash entries, and style blend mode are decoded. | Static color/width lowered; animated color/opacity/width and PureLayer-missing caps/joins/miter/dash/blend are reported. | `ShapeLayer.strokeColor`, `lineWidth`, future stroke style surface. | approx | Cap/join/dash fixtures; PureLayer #157 before exact lowering. |
| Gradient fill | `gf` style defines linear/radial gradient plus opacity stops. | 508 | Unsupported shape type. | Reports `shape type 'gf'`. | PureLayer/PureDraw gradient or report. | reported | Gradient stop parser and reference tests. |
| Gradient stroke | `gs` gradient stroke with stroke styling. | 103 | Unsupported shape type. | Reports `shape type 'gs'`. | Gradient stroke layer or report. | reported | Same as gradient fill plus stroke semantics. |
| Trim path | `tm` modifies preceding shapes by path length, with start/end/offset and parallel/sequential modes. lottie-web scales start/end percentages to fractions, normalizes offset degrees to turns, clamps, swaps reversed ranges, rounds to 4 decimals, and samples cubic lengths with 150 points. | 2,920 | Start/end/offset/multiple decoded. `LottieSourceTrimEvaluator` records original path lengths, normalized start/end/offset, path sequence order, selected segment ranges, generated result paths, and named length/rounding approximations before lowering. | RenderIR carries trim traces on shape draws. Stroke trim still lowers to `strokeStart`/`strokeEnd`; sequential mode, offset, and trimmed fills remain reported/approximate backend behavior. | Source-intent trim trace first; `ShapeLayer.strokeStart`, `strokeEnd` as limited backend target. | approx | Swift Testing coverage for ellipse quadrant selection, rectangle perimeter, arbitrary cubic path, wrapped offset, empty trim, full trim, reversed ranges, and parallel/sequential multi-path behavior. |
| Merge paths | `mm` boolean path operations. | 1,946 | Unsupported shape type. | Reports `shape type 'mm'`. | PureDraw boolean operations or report. | reported | Boolean geometry fixtures for add/subtract/intersect/exclude. |
| Repeater | `rp` clones preceding elements with transform and opacity interpolation. | 56 | Unsupported shape type. | Reports `shape type 'rp'`. | Layer replication or generated draw commands. | reported | Repeater source fixtures before lowering. |
| Rounded corners modifier | `rd` modifies preceding path corners. | 58 | Unsupported shape type. | Reports `shape type 'rd'`. | Path modifier. | reported | Corner modifier geometry tests. |
| Animated scalar/vector properties | Keyframes ordered by `t`, easing via `i/o`, hold via `h`; vector easing can be per component; position `to`/`ti` tangents define sampled spatial motion paths; values hold outside keyframe span. | Corpus-wide | `AnimatedDouble`, `AnimatedVector`, `LottieKeyframe`; `EasingHandle` preserves scalar or per-component handles; `LottieEvaluation` evaluates hold, lottie-web BezierEaser curves, lottie-web spatial sampled arc-length paths, and emits `LottiePropertyEvaluationTrace` with source frame, span, timing, spatial, and final-value facts. | `ScalarTimeline` still samples each PureLayer dimension separately for backend animations; exact source-intent traces now exist before lowering, while incomplete timing handles or spatial tangent sets produce semantic diagnostics. | `KeyframeAnimation`. | approx | Direct evaluator tests against lottie-web for easing, hold, per-component easing, spatial arc length, trace fields, incomplete timing handles, and incomplete-tangent diagnostics. |
| Animated Bezier properties | Path keyframes interpolate vertices/tangents at frame time. | Many `sh.ks` keyframes | `AnimatedBezier` decodes keyframes; `LottieEvaluation` emits a path-morph diagnostic and returns the initial path until exact morphing exists. | Reports `path morph`, uses initial path. | Frame-evaluated PureDraw path animation if supported. | reported | Morph oracle tests before lowering. |
| Slots | `slots` substitute property values by `sid`. | Root `slots` observed rarely/not yet classified | Not decoded. | Not reported. | Pre-import property substitution. | gap | Slot substitution validator tests. |
| Effects/expressions | lottie-web supports effects and expressions outside core spec/security-sensitive. | 355 `ef`; expressions possible | Not decoded. | Not reported. | Report-only unless explicitly supported. | gap | Detect and report with path. |
| Metadata/markers/fonts/chars | Mostly non-rendering except fonts/chars can affect text rendering. | Present across corpus | Mostly not decoded. | Not reported. | Metadata ignore; text/font report. | gap | Distinguish harmless metadata from text-rendering inputs. |

## Immediate Conclusions

1. The APNG corpus output is not a conformance result. It is only a symptom
   browser for the current importer.
2. The largest silent-risk class is not image quality; it is missing model fields
   that cannot be reported because they are dropped before `LottieImport`.
   Track matte fields have moved out of that class: they are decoded, bound, and
   reported when unsupported by lowering.
3. The next useful test gate is semantic, not visual:
   decode each feature, classify it, and assert either exact lowering or an
   `ImportReport` finding with the source path.
4. Visual comparison becomes meaningful only after a lottie-web reference frame
   exists for the same source frame list and every unsupported feature in that
   source file is known.

## Required Next Work

1. Add a corpus semantic ledger test that fails on any observed rendering field
   not classified as `lowered`, `approx`, `reported`, `metadata`, or `gap`.
2. Move every `gap` that can change pixels into either model+report or
   model+lowering.
3. Build a lottie-web reference renderer outside the package dependency graph.
4. Compare PureLayer frames only for fixtures whose matrix rows are all
   `lowered` or intentionally `approx`.
5. Keep PureDraw and PureLayer canonical. If a target capability is missing
   there, file an issue; do not change them from PureLottie.
