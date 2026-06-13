# bodymovin source semantics: the ground truth for the self-oracle

## Why this document exists

Lottie is not a rendering specification. It is the serialization that the
bodymovin After Effects exporter writes from an After Effects composition.
bodymovin is the encoder; lottie-web, lottie-ios, and PureLottie are decoders.
So the *source of truth* for what a Lottie file means is the AfterEffects model
that bodymovin serializes, not any one player's playback. lottie-web is a
reference *player* with its own sampling and rasterization approximations; it is
useful as a runnable corroboration, but it is not the definition.

The #130 pixel-sufficiency probe showed why this matters: numeric agreement with
lottie-web does not imply pixel agreement, and the gate still trusts Chromium as
the reference renderer. To "measure ourselves" we must implement the exact
bodymovin/AE math and treat it as definitional, keeping lottie-web only as a
witness. This document records that math, extracted from the pinned
`lottie-web@5.13.0` decoder (which mirrors the encoder bit for bit), with file
and line provenance.

bodymovin exports a known, finite feature set: paths, ellipses, rectangles,
stars and polygons, fills, strokes, gradient fills and strokes, dashes, trim
paths, rounded corners, transforms (position, anchor, rotation, scale, opacity,
skew), and masks in additive, subtractive, and inverted modes. Anything it
cannot translate is dropped or flattened to a static image. That finite set is
exactly the surface PureLottie must model or report.

## Definitional math (exact, no tolerance)

These are closed-form constructions. A faithful decoder reproduces them exactly;
the self-oracle asserts vertex-for-vertex equality with no pixel tolerance.

### The ellipse constant is 0.5519, not the circle constant

`utils/common.js:44`: `const roundCorner = 0.5519;`

bodymovin approximates an ellipse with four cubic Bezier segments using the
control-handle fraction `0.5519`. This is **not** the mathematically correct
circle approximation `4/3 * (sqrt(2) - 1) = 0.5522847498...`; it is a truncated
constant baked into AE/bodymovin. A self-oracle that uses the "correct" circle
constant disagrees with every Lottie ellipse. Fidelity to the source means using
`0.5519` exactly and labeling it as an AE approximation, not a derived value.

The same `roundCorner` constant drives rounded-corner modifiers and offset-path
joins (`utils/shapes/RoundCornersModifier.js`, `OffsetPathModifier.js`).

### Ellipse construction

`utils/shapes/ShapeProperty.js` `convertEllToPath`: a 4-vertex closed path with
vertices at top, right, bottom, left of the bounding box `(p +/- s/2)`, tangents
scaled by `s0 * cPoint` and `s1 * cPoint`. Direction is `_cw = (d !== 3)`:
`d === 3` means the counterclockwise authored direction, anything else clockwise.
The tangent assignment swaps sign with `_cw`, so direction is part of the
definition, not a rendering choice.

### Star and polygon construction

`convertStarToPath`: `numPts = floor(pt) * 2`, `angle = 2*PI / numPts`,
`currentAng = -PI/2 + rotation`, `dir = (d === 3 ? -1 : 1)`. It alternates outer
radius `or` and inner radius `ir`; the Bezier tangent length on each point is
`perimSegment * roundness * dir`, where `longPerimSegment = 2*PI*or / (numPts*2)`
(and the short variant uses `ir`), `roundness` is the outer/inner roundness
`os`/`is`, and the tangent direction is the unit perpendicular `(y, -x)/|p|`.

`convertPolygonToPath`: `numPts = floor(pt)`, and the perimeter segment divisor is
`numPts * 4` (not `* 2` as for stars). Same perpendicular-tangent rule.

These divisor and `numPts` differences are exact and easy to get wrong; they are
the definition, not an implementation detail.

### Transform matrix composition

`utils/TransformProperty.js` builds the layer/group matrix as a row-vector
product in this exact order, with these exact sign conventions:

1. `translate(-anchor)`
2. `scale(s)`
3. `skewFromAxis(-skew, skewAxis)`
4. 2D: `rotate(-rotation)`; 3D: `rotateZ(-rz).rotateY(ry).rotateX(rx)` then the
   orientation `rotateZ(-or.z).rotateY(or.y).rotateX(or.x)`
5. `translate(position)` (with `-z` in 3D)

Anchor, skew, and z-rotation are negated; position is not. Parenting composes
parent-before-child in the same row-vector convention. Auto-orient replaces the
rotation step with `rotate(-atan2(dy, dx))` along the motion path. Any deviation
in order or sign produces a wrong matrix that still "type-checks," which is why
the transform fixtures must assert the matrix, not just that a transform exists.

### Mask modes

`player/js/mask.js`: mask `mode` is `a` (add), `s` (subtract), `i` (intersect),
`n` (none, ignored), with an `inv` (invert) flag and per-mask opacity `o`.
Subtract and intersect paint black/white fills into the mask buffer
(`mode === 's' ? '#000000' : '#ffffff'`) and the layer is composited through it;
a clip-path fast path is used only when every mask is plain additive, opaque,
and non-inverted. The #134 `mask-add-rectangle` gap is a plain additive mask that
PureLottie carries into RenderIR (`maskCount: 1`) but never applies, so the
layer renders unclipped. The mask boolean algebra above is the definition the
render must honor.

### Dashes and trim

`utils/shapes/DashProperty.js`: the dash array is the ordered `n`/`v` pairs
(`d` dash, `g` gap) plus a separate `o` offset, applied along the stroked
contour. `TrimModifier.js` selects sub-segments of a contour by normalized
start/end/offset, parallel or sequential across multiple paths. Both operate on
the exact contour produced above, so they are exact once the contour is exact.

## Sampled or approximate (explicit bound required)

Not everything in the source is closed-form. These carry a `sampled` or
`assumed` status and an error bound, never `theorem`:

- **Spatial Bezier motion paths.** lottie-web samples arc length over 150
  segments to invert distance-to-t (`getValue`/`PolynomialBezier`). This is an
  approximation in the reference itself; the self-oracle matches the sampling
  rule and records it as `sampled`.
- **Temporal easing.** Keyframe ease is a cubic Bezier solved numerically
  (`3rd_party/BezierEaser.js`); reproducible but iterative.
- **Rasterization.** Anti-aliasing and coverage have no portable cross-renderer
  bound (the #115 audit and the #130 probe both record this as `assumed`).

## What Knuth would do (the oracle plan)

1. **Read the definitive source, not the hearsay.** The definition lives in the
   bodymovin/AE math above, captured here with provenance, not in blog posts or
   in one player's pixels. The constant is `0.5519`, measured from the source,
   not recalled.
2. **Partition exact from approximate.** The definitional geometry, transforms,
   and mask algebra are exact: prove them by bounded-exhaustive vertex/matrix
   equality with zero tolerance. The sampled layer (arc length, easing, AA)
   carries an explicit bound and an honest status. Never blend the two into one
   fuzzy pixel tolerance.
3. **The checker is smaller than what it checks (K5).** Build a small,
   independent implementation of the exact bodymovin math (the `0.5519` ellipse,
   the star/polygon divisors, the transform order, the mask modes) and use it as
   the oracle. Do not certify PureLayer by comparing it to PureLayer, and do not
   make lottie-web the foundation; demote lottie-web to a corroborating witness
   and a regression baseline.
4. **Prove for all inputs, not for the fixtures.** Enumerate the definitional
   space (radii, point counts, directions, anchor/rotation/scale combinations,
   mask mode products) up to a stated bound and assert exact agreement, rather
   than trusting the curated corpus.
5. **Disclose every approximation.** Where bodymovin/AE itself approximates
   (`0.5519`, 150-segment arc length), say so in the trace with the named
   approximation, so a skeptic can see exactly where exactness ends.

The end state: PureLottie certifies its own geometry, transforms, and masks
against an independent, inspectable implementation of the bodymovin definition,
with lottie-web kept only as corroboration and a small set of AE-rendered golden
frames pinned once as the absolute pixel anchor. That removes Chromium from the
trust base for everything except the explicitly-bounded rasterization layer.

## AfterEffects records far more than the common subset

The familiar Lottie surface (a few layer types, basic shapes, fills, strokes,
additive masks) is a small slice of what AfterEffects records and what bodymovin
can serialize. The schema and the lottie-web parser carry a much larger surface.
The danger is not the features PureLottie reports as unsupported; it is the ones
it decodes past silently. The `LottieModel` audit splits the surface three ways:
modeled, reported-unsupported, and **absent** (no type and no report, so the
field is dropped on decode with no trace). The absent set is a direct C6
violation (validation must be complete over the input model) and breaks the
never-render-silently-wrong rule, because a file using these looks clean.

### Under-known features that AE records and PureLottie currently drops silently

- **Variable slots (`slots` + per-property `sid`).** A recent Lottie feature
  (lottie-web ships `utils/SlotManager.js`): any property can carry a slot id
  `sid` that points into a document-level `slots` dictionary, so a theme can
  override colors, positions, text, and more at load time. PureLottie has no
  `sid` and no `slots`; a themeable file silently loses its overrides and
  renders the authored defaults. This is the clearest "never heard of" case.
- **Layer styles (`sy`).** AE layer styles (drop shadow, inner shadow, outer and
  inner glow, bevel and emboss, satin, color/gradient/pattern overlay, stroke)
  serialize as a `sy` array. Absent in the model. A styled layer renders with no
  style and no report.
- **Expressions (`x`).** A property can carry an AE expression string in `x`.
  bodymovin with the expressions plugin exports them; lottie-web evaluates them.
  Absent: an expression-driven property silently falls back to its static value.
- **Camera (ty 13), lights, audio (ty 6), data (ty 14), footage/video (ty 7, 15)
  layers.** Only precomp/solid/null/shape are modeled; image and text are
  reported. The rest are absent: a composition with a camera or audio layer
  drops it with no trace.
- **Motion blur (`mb`)** at layer level and composition shutter angle/phase/
  samples. Absent. A motion-blurred animation renders crisp with no report.
- **Collapse transform / continuous rasterization (`ct`)** on precomps. Changes
  how a precomp composites; absent.

### Recorded but flattened to a single mode (the long tail of enums)

These are modeled enough to parse but the importer handles only the common value
and reports the rest, so at least they are not silent. Worth knowing they exist:

- **Blend modes 0 to 17.** Not just normal/multiply/screen: also color dodge,
  color burn, hard/soft light, difference, exclusion, hue, saturation, color,
  luminosity, add, hard mix. Only normal is mapped.
- **Track matte modes 0 to 4.** Normal, alpha, inverted alpha, luma, inverted
  luma, plus the newer explicit matte-parent reference `tp`. Only the absence of
  a matte is handled; all real mattes are reported-unsupported.
- **Mask modes `n` `a` `s` `i` `l` `d` `f`.** Add and none are handled; subtract,
  intersect, lighten, darken, and difference are reported. (Lighten/darken/
  difference masks are rare even in AE, but they are in the schema.)
- **Gradient types 1 linear, 2 radial, 3 conic**, with highlight length and
  angle. Gradient fills and strokes themselves are reported-unsupported.
- **Effects taxonomy.** Tint (20), Fill (21), Stroke (22), Tritone (23), Pro
  Levels (24), Drop Shadow (25), Radial Wipe (26), Displacement Map (27), Set
  Matte (28), Gaussian Blur (29), Mesh Warp (31), Wavy (32), Spherize (33),
  Puppet (34), plus custom effects. All effects are reported-unsupported.
- **Text.** The full text document (font list with system/embedded/google/typekit
  origin, `chars` baked glyph paths, text animators, range selectors with
  shape/units/grouping/based/justify/caps, path options, per-character 3D). Text
  layers are reported-unsupported wholesale.
- **Shape modifiers** beyond trim: repeater (with composite order, copies,
  offset), merge paths, round corners, offset path, pucker-bloat, zig-zag, twist.
  All reported-unsupported.

### Document-level facts AE records that are recognized but not decoded

`markers` (named sections, with `cm` comment payloads that interactivity tooling
parses as JSON), `chars`, `fonts`, `meta`/metadata (author, description, theme
color, generator, keywords), and color space `cs`. The validator acknowledges
the keys but the model does not carry them.

### Consequence for the coverage rule (C6)

Every field above must be either modeled with its validations or reported as
unsupported with the path where it was found. The absent set (slots/`sid`,
layer styles, expressions, camera/light/audio/data/footage layers, motion blur,
collapse transform, separated `px`/`py`/`pz`, document `cs`) is the gap: those
are silently dropped today. Closing it does not mean implementing them; it means
detecting the unknown or unmodeled key and recording it, backed by a coverage
registry and a meta-test that fails when any schema field lacks a rule. That is
the difference between "passed the corpus" and "complete over the input model."

## The translation layer: target PureComposition's IR, not PureLayer directly

PureLottie today translates Lottie straight into PureLayer: `LottieImport` lowers
to a `RenderIR` and then to PureLayer primitives. That point-to-point shape is
where the gaps live. The render losses in #130/#134 are private lowering bugs,
and the silently-dropped AE surface above has nowhere to be recorded because the
importer owns both the parse and the backend mapping with no validated waypoint
between them.

The sibling `PureComposition` repo already is the missing waypoint. It is a
renderer-independent composition interlingua:

- `PureCompositionLanguage/CompositionIR.swift` is a typed, source-mapped
  composition IR, not tied to any backend.
- `PureCompositionPureLayer` (and the PureDraw VM emit) are lowering adapters
  from that IR to the backends, so the IR lowers to PureLayer, PureDraw, and
  future PureFilters through one validated pipeline.
- `PureCompositionDebugger` steps that IR, and `ShowcaseSupport/AliasingPixelDiff`
  is a pixel oracle already living in the same repo.
- `Docs/CAARResearch.md` specifies the importer pattern: decode the source graph,
  build an intermediate document that records every decoded class, key path,
  value, and unsupported field, validate it with the OpenAPIKit-style machinery,
  translate known constructs into the IR, and emit an import report for every
  unmapped feature. Its rule is explicit: "No importer failure may fall through
  as a wrong picture. Unknowns stay visible in diagnostics and fixture reports."

A Lottie front-end is the same shape as the CAAR front-end. CAAR is an archived
Core Animation composition graph; Lottie is an archived AfterEffects composition
graph. Both should become an intermediate document that records every field
(modeled or not), validate, translate the known subset into `CompositionIR`, and
report the rest. The translation layer we need is therefore:

```
Lottie JSON --(LottieModel: faithful typed parse)--> bodymovin/AE semantics
   --(Lottie front-end, CAAR-style: record-all + validate + report-unmapped)-->
   CompositionIR  --(existing adapters)-->  PureLayer / PureDraw / PureFilters
```

This is the layer that fixes the structural problems, not just the symptoms:

- The silently-dropped set (slots/`sid`, layer styles, expressions, camera/audio/
  light/data/footage layers, motion blur, collapse transform, `cs`) cannot fall
  through, because the front-end's contract is record-or-report, enforced by a
  coverage registry and meta-test (C6). Model-or-report becomes structural rather
  than per-feature discipline.
- The render losses (mask not applied, dash dropped) move out of a bespoke
  per-importer lowering into the one shared IR-to-backend pipeline that
  PureComposition already validates and pixel-tests, so a fix lands once and is
  checked by `AliasingPixelDiff` rather than only by the Chromium oracle.
- The exact bodymovin/AE math in this document (the `0.5519` ellipse, the star/
  polygon divisors, the transform order and signs, the mask algebra) is what the
  Lottie front-end must produce when it builds IR geometry, and what the
  independent self-oracle checks vertex-for-vertex.

PureLottie keeps `LottieModel` as the faithful, backend-free parse and the
bodymovin/AE semantic authority; the translation layer is a new front-end that
lowers that parse into PureComposition's IR instead of into PureLayer directly.

## Encoder: AfterEffects to bodymovin to Lottie JSON, and what is lost

Read from the actual exporter source (`bodymovin-extension/bundle/jsx/`), not the
player. The exporter walks the AE DOM via ExtendScript (`renderManager` ->
`elements/layerElement` -> `utils/keyframeHelper`, `utils/transformHelper`,
shape helpers -> `dataManager`) and emits JSON.

### Keyframe easing is reparameterized, and that is the main loss

AE stores each keyframe's ease as a `(influence%, speed)` pair, per in/out and
per dimension (`keyInTemporalEase`/`keyOutTemporalEase`). Lottie stores a
normalized cubic-Bezier timing handle per segment, `o:{x,y}` (out) and `i:{x,y}`
(in). `utils/keyframeHelper.jsx` converts, per dimension, over a segment of
`duration = (key.time - lastKey.time) / stretch`:

- `o.x = easeOut.influence / 100`, `i.x = 1 - easeIn.influence / 100`
- `delta = key.value - lastKey.value` (times 255 for color); **if `|delta| < 1e-7`, `delta` is forced to 1**
- `o.y = (easeOut.speed * easeOut.influence/100 * duration) / delta`
- `i.y = 1 - (easeIn.speed * easeIn.influence/100 * duration) / delta`

For spatial position, `delta` is replaced by the arc length of the spatial
Bezier **sampled at 200 segments** (`getCurveLength`), and the handles use
`speed / averageSpeed`. Hold keyframes export as `h:1`. A fully linear segment
exports with `i`/`o` on the diagonal (`y = x`).

Losses, grounded in the source:

1. **Easing reparameterization.** The y-handle encodes velocity relative to the
   value delta and duration. A player that treats `i`/`o` as pure timing curves
   (lottie-web does) reproduces AE motion only if it re-derives the same average
   speed. This is the documented "easing discrepancy."
2. **The delta=1 degeneracy.** For a near-constant channel (`|delta| < 1e-7`) the
   exporter fabricates the y-handle, so an almost-flat channel's eased timing is
   arbitrary.
3. **Spatial sampling mismatch.** The exporter measures arc length at **200**
   segments; lottie-web re-derives motion at playback with **150** (see
   `numeric-claim-reliability.md`). Two discretizations of the same curve ->
   spatial-timing drift. Structural, not a bug.
4. **Rounding.** Geometry, tangents, and time to 3 decimals; color to 12.

### Shapes export parametrically, so geometry is lossless at encode

Native shapes export as parametric `ty:rc`/`el`/`sr` with their AE parameters;
Bezier paths export as `{i, o, v, c}` with **relative** tangents
(`getPropertyValue` SHAPE), rounded to 3 decimals. The `0.5519` ellipse
approximation is introduced only at **decode** (the player), not at encode, which
is why the encoder and decoder sections here stay consistent.

### bodymovin reports what it cannot translate (model-or-report at the source)

The exporter ships a `reports/` subsystem (`effectsReport`, `layerStylesReport`,
`failedLayerReport`, per-layer and per-shape reports). Per the canonical support
matrix (`airbnb/lottie/after-effects.md`) it does not export expressions (unless
baked through `keyframeBakerHelper`), any effects-menu effect, blend modes, luma
mattes, or layer styles; alpha mattes and path-keyframe animation are supported
but flagged for performance. It detects and reports these rather than dropping
them silently. That is the same model-or-report discipline the translation layer
must adopt; the loss is disclosed at the source and only becomes dangerous if a
downstream importer ignores the report.

## Provenance

The decode-side math was read from `Tools/LottieOracle/node_modules/lottie-web@5.13.0`:
`utils/common.js`, `utils/TransformProperty.js`, `utils/shapes/ShapeProperty.js`,
`utils/shapes/DashProperty.js`, `utils/shapes/TrimModifier.js`, and
`player/js/mask.js`. The encode-side facts were read from the
`bodymovin/bodymovin-extension` repo at `bundle/jsx/`: `renderManager.jsx`,
`elements/layerElement.jsx`, `utils/keyframeHelper.jsx`, `utils/transformHelper.jsx`,
`utils/PropertyFactory.jsx`, the `enums/` and `reports/` subsystems, plus the
canonical support matrix `airbnb/lottie/after-effects.md`. The two sides agree on
the field set by construction: bodymovin writes exactly what these players read.
