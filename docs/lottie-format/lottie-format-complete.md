# The Lottie format, complete

This is the full field-by-field reference for the Lottie format: every object,
every property key, every enum value. It is built from the official machine
readable schema (`lottie/lottie-spec`, branch `main`, 81 schema files) and then
extended with the larger lottie-web / bodymovin superset that real exported files
contain but the official spec does not yet standardize. Nothing in the schema is
omitted; the gap between spec and superset is called out explicitly so a reader
knows exactly what is standardized and what is a de-facto extension.

Two layers of truth:

- **Official spec (`lottie-spec`)**: the standardized subset. Authoritative for
  what it covers, but it omits text, effects, layer styles, and several layer
  types that bodymovin exports.
- **Superset (lottie-web 5.x / bodymovin)**: what AfterEffects actually exports
  and what players actually read. Documented in the final section and in
  `bodymovin-source-semantics.md`.

Status note: a faithful importer must treat every key below as modeled-or-
reported (validation rule C6). Keys in the superset that the spec omits are
exactly the ones a spec-only importer drops silently.

---

## 0. Verification (the "100%" claim is checked, not asserted)

"100%, nothing left unsaid" is a claim, so it is mechanically verified rather than
trusted. `verify-coverage.sh` (in this folder) extracts every property key and
every enum const value from the pinned official schema and fails if any is absent
from this document **or** from `lottie-import-mapping.md` (so every key has both a
definition here and a model-or-report disposition there). Last run against
`lottie/lottie-spec @ 4b55957` (2026-06-13): **70/70 property keys present in both
docs, 28/28 enum const values present, 0 gaps, exit 0.**

Honest limits: this verifies the official `lottie-spec` schema only; the superset
in section 9 is prose (no machine schema exists for it). The single-character
const values (`a`,`b`,`c`,`d`,`g`,`i`,`n`,`o`,`s`,`v`) match loosely, so their
"present" result is weak; the integer and multi-character consts are firm. Status
of the completeness claim: `theorem (bounded to lottie-spec @4b55957)` for keys,
`witnessed` for the loosely-matched single-char consts.

## 1. Document structure

### Animation (root)

The root of a `.json` Lottie file. Extends Visual Object + Composition.

| key | title | type | required | notes |
| --- | --- | --- | --- | --- |
| `v`/`ver` | Specification Version | integer | no | 6-digit MMmmpp, min 10000 |
| `fr` | Framerate | number | yes | frames per second, > 0 |
| `ip` | In Point | number | yes | start frame (inclusive) |
| `op` | Out Point | number | yes | end frame (exclusive); duration = op - ip |
| `w` | Width | integer | yes | min 0 |
| `h` | Height | integer | yes | min 0 |
| `nm` | Name | string | no | from Visual Object |
| `assets` | Assets | array<all-assets> | no | referenceable assets |
| `layers` | Layers | array<all-layers> | yes | from Composition |
| `markers` | Markers | array<marker> | no | named sections |
| `slots` | Slots | object<id, slot> | no | themeable property substitution |
| `meta` | Metadata | metadata | no | authoring info |

### Composition

Just `{ layers: array<all-layers> }` (required). Animation and Precomposition
asset both extend it.

### Assets

- **all-assets**: `oneOf` [ precomposition, image ].
- **asset** (base): `id` (string, required), `nm` (from Visual Object).
- **image** (extends asset + slottable-object): `w`, `h`, `p` (file name or data
  URL), `u` (path), `e` (int-boolean: if 1, `p` is a data URL), `sid` (slot id).
  `w`/`h`/`p` required unless `sid` present. If `e=1`, `p` must match data-url.
- **precomposition** (extends asset + composition): `layers` (required) — an
  inline composition referenced by precomposition layers via `refId`.

---

## 2. Layers

All layers are unioned by **all-layers** (`oneOf` by `ty`). Inheritance chain:
`visual-object -> layer -> visual-layer -> concrete layer`.

### layer (base)

| key | title | type | required | notes |
| --- | --- | --- | --- | --- |
| `ty` | Type | integer | yes | layer type discriminator |
| `nm` | Name | string | no | from Visual Object |
| `hd` | Hidden | boolean | no | |
| `ind` | Index | integer | no | identity for parenting/expressions |
| `parent` | Parent Index | integer | no | the `ind` of another layer |
| `ip` | In Point | number | yes | visible while `ip <= t < op` |
| `op` | Out Point | number | yes | |

### visual-layer (adds, on top of layer)

| key | title | type | required | notes |
| --- | --- | --- | --- | --- |
| `ks` | Transform | transform | yes | layer transform |
| `ao` | Auto Orient | int-boolean | no | 1 = rotate to match motion path |
| `tt` | Matte Mode | matte-mode | no | track matte mode |
| `tp` | Matte Parent | integer | no | `ind` of matte layer; default = layer above |
| `masksProperties` | Masks | array<mask> | no | |
| `bm` | Blend Mode | blend-mode | no | default 0 |

### Concrete layer types (`ty`)

| ty | layer | extra keys |
| --- | --- | --- |
| 0 | Precomposition | `refId` (req), `w`, `h`, `sr` (time stretch, def 1), `st` (start time, def 0), `tm` (time remap, scalar-property) |
| 1 | Solid | `sw` (req), `sh` (req), `sc` (req, hexcolor) |
| 2 | Image | `refId` (req) |
| 3 | Null | (none beyond visual-layer) |
| 4 | Shape | `shapes` (req, array<all-graphic-elements>) |
| other | Unknown | any `ty` not in {0,1,2,3,4}; preserved, not an error |

(Superset adds ty 5 Text, 6 Audio, 13 Camera, and data/footage — see section 9.)

---

## 3. Transform (helper)

Used as `ks` on layers and as the `tr` shape. All sub-properties animatable.

| key | title | type | notes |
| --- | --- | --- | --- |
| `a` | Anchor Point | position-property | center for rotation/scale |
| `p` | Position | splittable-position-property | grouped or split x/y(/z) |
| `r` | Rotation | scalar-property | degrees clockwise |
| `s` | Scale | vector-property | [100,100] = identity |
| `o` | Opacity | scalar-property | 0..100 |
| `sk` | Skew | scalar-property | degrees |
| `sa` | Skew Axis | scalar-property | 0 = X, 90 = Y |

(3D rotation `rx`/`ry`/`rz`/`or` and separated `px`/`py`/`pz` are superset/AE,
see section 9 and `bodymovin-source-semantics.md`.)

---

## 4. Shapes (graphic elements)

A shape layer's `shapes` (and any group's `it`) is an array of **all-graphic-
elements** (`oneOf`). Inheritance: `visual-object -> graphic-element (ty, hd) ->
{ shape (adds d) | shape-style (adds o, bm) | modifier }`.

### Geometry shapes

| ty | shape | keys |
| --- | --- | --- |
| `sh` | Path | `ks` (req, bezier-property), `d` (direction) |
| `rc` | Rectangle | `p` (req), `s` (req), `r` (roundness), `d` |
| `el` | Ellipse | `p` (req), `s` (req), `d` |
| `sr` | PolyStar | `p` (req), `or` (req), `os` (req), `r` (req), `pt` (req), `sy` (star-type), `ir`+`is` (req when `sy=1`), `d` |

### Style shapes (extend shape-style: `o` opacity req, `bm` blend mode)

| ty | shape | keys |
| --- | --- | --- |
| `fl` | Fill | `c` (req, color-property), `r` (fill-rule) |
| `st` | Stroke | `c` (req) + base-stroke (`w` req, `lc`, `lj`, `ml`, `ml2`, `d` dashes) |
| `gf` | Gradient Fill | base-gradient (`g` req, `s` req, `e` req, `t` req, `h`, `a`) + `r` fill-rule |
| `gs` | Gradient Stroke | base-gradient + base-stroke |

base-stroke: `lc` (line-cap, def 2), `lj` (line-join, def 2), `ml` (miter, number),
`ml2` (animatable miter, scalar-property), `w` (width req), `d` (array<stroke-dash>).
base-gradient: `g` (gradient-property), `s` (start point), `e` (end point),
`t` (gradient-type), `h` (highlight length), `a` (highlight angle).
stroke-dash: `n` (stroke-dash-type d/g/o, def "d"), `v` (length, scalar-property), `nm`.

### Container / transform

| ty | shape | keys |
| --- | --- | --- |
| `gr` | Group | `np` (number of properties), `it` (array<all-graphic-elements>; ends with a `tr`) |
| `tr` | Transform (group) | all transform keys (`a`,`p`,`r`,`s`,`o`,`sk`,`sa`) |

### Modifiers (extend modifier; reorder/transform preceding shapes)

| ty | modifier | keys |
| --- | --- | --- |
| `tm` | Trim Path | `s` (start req), `e` (end req), `o` (offset req), `m` (trim-multiple 1 parallel / 2 sequential) |
| `rd` | Rounded Corners | `r` (radius req) |
| `pb` | Pucker / Bloat | `a` (amount %) |
| (unknown) | Unknown Shape | any `ty` not in the known set; preserved |

(Superset adds `mm` merge-paths, `op`/`rp` offset-path & repeater, `zz` zig-zag,
`tw` twist — see section 9.)

---

## 5. Properties and keyframes

The animated-vs-static spine of the format. Every animatable value is a property
with an `a` flag and a `k` payload, optionally `ty` (property-type) and `sid`
(slot id), inheriting from **slottable-property** (when `sid` is set, `a`/`k` are
optional fallbacks).

### Property objects

| ty | property | static `k` (a=0) | animated `k` (a=1) |
| --- | --- | --- | --- |
| `s` | Scalar | number | array<vector-keyframe> |
| `v` | Vector | vector | array<vector-keyframe> |
| `v2` | Position | vector | array<position-keyframe> |
| `c` | Color | color | array<color-keyframe> |
| `b` | Bezier (shape) | bezier | array<bezier-keyframe> |
| `g` | Gradient | (via gradient-stops) | — |

- **gradient-property**: `p` (color-stop count, req), `k` (gradient-stops), `ty="g"`.
- **gradient-stops**: `a` (req), `k` (gradient value or array<gradient-keyframe>, req).
- **splittable-position-property**: `oneOf` [ position-property (grouped, `s:false`),
  split-position ]. **split-position**: `s:true` (req), `x` (scalar-property req),
  `y` (scalar-property req) — animate axes independently.

### Keyframes

base-keyframe: `t` (time/frame, req), `h` (hold int-boolean; `h=1` holds value to
next keyframe), `i` (in easing-handle), `o` (out easing-handle). Typed keyframes
add `s` (value): vector-keyframe (vector), color-keyframe (color), bezier-keyframe
(array of exactly one bezier), gradient-keyframe (gradient). **position-keyframe**
extends vector-keyframe with `ti` (spatial in-tangent, vector) and `to` (spatial
out-tangent, vector) for curved motion paths.

### Easing handle (`i`/`o`)

`x` (time component, 0..1) and `y` (value component) — each a scalar **or an
array** (per-dimension easing for multi-dim properties). This is the normalized
cubic-Bezier timing handle that bodymovin computes from AE's influence/speed (see
`bodymovin-source-semantics.md` for the exact conversion and its losses).

Two distinct tangent systems, do not conflate: `i`/`o` are **temporal** (timing of
interpolation); `ti`/`to` are **spatial** (shape of the position path).

---

## 6. Helpers

- **mask**: `pt` (shape, bezier-property, req), `mode` (mask-mode, def "i"),
  `o` (opacity, scalar-property, def 100), `inv` (invert), `x` (expansion), `nm`.
- **marker**: `cm` (comment/name), `tm` (time), `dr` (duration).
- **metadata**: `g` (generator), `a` (author), `d` (description), `k` (keywords
  array), `custom` (free object, unvalidated).
- **slot**: `p` (property value, req; type must match every `sid` that references it).
- **slottable-object**: `sid` (slot id). **slottable-property**: `sid` + optional
  `a`/`k` fallback.
- **visual-object**: `nm` (name). Base of nearly everything.

---

## 7. Constants (every enum value)

- **blend-mode** (int): 0 Normal, 1 Multiply, 2 Screen, 3 Overlay, 4 Darken,
  5 Lighten, 6 Color Dodge, 7 Color Burn, 8 Hard Light, 9 Soft Light,
  10 Difference, 11 Exclusion, 12 Hue, 13 Saturation, 14 Color, 15 Luminosity,
  16 Add. (Superset/lottie-web also defines 17 Hard Mix.)
- **mask-mode** (string): "n" None, "a" Add, "s" Subtract, "i" Intersect.
  (Superset also: "l" Lighten, "d" Darken, "f" Difference.)
- **matte-mode** (int): 0 Normal (no matte), 1 Alpha, 2 Inverted Alpha, 3 Luma,
  4 Inverted Luma.
- **fill-rule** (int): 1 Non Zero, 2 Even Odd.
- **gradient-type** (int): 1 Linear, 2 Radial, 3 Conic.
- **line-cap** (int): 1 Butt, 2 Round (def), 3 Square.
- **line-join** (int): 1 Miter, 2 Round (def), 3 Bevel.
- **shape-direction** (int): 1 Normal (CW), 3 Reversed (CCW).
- **star-type** (int): 1 Star, 2 Polygon.
- **stroke-dash-type** (string): "d" Dash, "g" Gap, "o" Offset.
- **trim-multiple-shapes** (int): 1 Parallel, 2 Sequential.
- **property-type** (string): "s" Scalar, "v" Vector, "v2" Position, "c" Color,
  "b" Bezier, "g" Gradient.

---

## 8. Values (encodings)

- **bezier**: `{ c: bool (closed), v: array<vector> (vertices), i: array<vector>
  (in tangents, RELATIVE to vertices), o: array<vector> (out tangents, relative) }`.
  `i`, `o`, `v` are equal-length; tangents are offsets from their vertex.
- **color**: array of 3 or 4 numbers in [0,1] (RGB or RGBA). **Not** 0..255.
- **vector**: array of numbers, variable length ([x,y], [x,y,z], scale, ...).
- **gradient**: flat number array. Color stops `[offset, r, g, b]` then optional
  alpha stops `[offset, alpha]`; offset and channels in [0,1]. Stop count comes
  from the gradient-property `p`.
- **hexcolor**: string `^#[0-9a-fA-F]{6}$` (used by solid layer `sc`).
- **data-url**: string `^data:([\w/]+)(;base64)?,(.+)$` (embedded image `p`).
- **int-boolean**: integer 0 (false) or 1 (true).

---

## 9. Beyond the official spec (the lottie-web / bodymovin superset)

Real exported files contain features the official `lottie-spec` does not yet
standardize. A complete importer must model-or-report all of these; a spec-only
parser drops them silently (the C6 danger). Detail and provenance in
`bodymovin-source-semantics.md`.

- **Layer types**: `ty:5` Text (full text document `t`: document, animators,
  range selectors, path options, more-options, per-char 3D; plus top-level
  `fonts` and `chars` baked glyphs), `ty:6` Audio (`au`), `ty:13` Camera, and
  data/footage layers. The spec models only 0..4.
- **Effects** (`ef`): the AE effects taxonomy — Tint(20), Fill(21), Stroke(22),
  Tritone(23), Pro Levels(24), Drop Shadow(25), Radial Wipe(26), Displacement
  Map(27), Set Matte(28), Gaussian Blur(29), Mesh Warp(31), Wavy(32),
  Spherize(33), Puppet(34), plus custom. Not in the spec at all.
- **Layer styles** (`sy`): drop/inner shadow, outer/inner glow, bevel & emboss,
  satin, color/gradient/pattern overlay, stroke. Not in the spec.
- **Expressions** (`x` on a property): AE expression strings. Not in the spec.
- **Shape modifiers** beyond trim/round/pucker: merge paths (`mm`), offset path
  (`op`), repeater (`rp`), zig-zag (`zz`), twist (`tw`).
- **3D and separated transform**: `rx`/`ry`/`rz`/`or` (3D rotation), separated
  `px`/`py`/`pz`, `ddd` (3D layer flag), `zPosition` ordering.
- **Document/layer extras**: `cs` (color space), layer html hints `cl`/`ln`,
  collapse-transform `ct`, motion blur `mb`, `markers` payloads (`cm` carrying
  JSON for interactivity), blend mode 17 (Hard Mix), mask modes l/d/f.

---

## Provenance

Sections 1-8 were read directly from the official schema, repo `lottie/lottie-spec`
at `schema/` (81 files: `root.json`, `composition/*`, `assets/*`, `layers/*`,
`shapes/*`, `properties/*`, `helpers/*`, `constants/*`, `values/*`), branch `main`.
Section 9 (the superset) is cross-checked against lottie-web 5.13.0 and the
bodymovin exporter, documented field by field in `bodymovin-source-semantics.md`.
Where the spec and a player disagree, the spec is authoritative for standardized
behavior and the superset documents what real files carry.
