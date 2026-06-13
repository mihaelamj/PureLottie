# Lottie import mapping: every construct to its PureComposition / PureLayer target

This is the feature-support matrix the translation layer is built against. For
every Lottie construct in `lottie-format-complete.md`, it states the target in
PureComposition's `CompositionIR` (which lowers to PureLayer), and a status. It
operationalizes the model-or-report rule (C6): nothing is silently dropped.
Section/issue numbers (#42-#53) refer to the PureComposition language epic #41.

## Status legend

- **mapped**: expressible in `CompositionIR` today; lowers to PureLayer.
- **after #N**: mappable once language child #N lands.
- **baked**: parametric source baked to a bezier path by the importer (lossless
  except the documented `0.5519` ellipse constant).
- **approximated**: representable but lossy; the loss is named and statused.
- **report-only**: no PureComposition/PureLayer analogue; recorded in the import
  report with its path, never rendered as if supported.
- **blocked**: needs a backend capability that does not exist; recorded as a
  blocker, not faked.

## 1. Document and assets

| Lottie | target | status |
| --- | --- | --- |
| `fr`,`ip`,`op`,`w`,`h` | `CompositionDocument` frameRate/frameRange/size | mapped |
| precomposition asset + `ty:0` layer (`refId`,`sr`,`st`,`tm`) | inline the referenced composition as sublayers; time stretch `sr` and remap `tm` rescale child time | after a precomp-resolution step (gap: no issue yet); `tm` approximated |
| image asset + `ty:2` layer | layer `contents` | after #50 |
| `markers` | carry as document metadata | report-only |
| `slots` / `sid` | slot resolution before lowering | blocked (no slot system; resolve-then-import or report) |
| `meta`, `cs` | carry / ignore | report-only |

## 2. Layers

| Lottie | target | status |
| --- | --- | --- |
| `ks` transform (2D: `a`,`p`,`r`,`s`,`o`,`sk`,`sa`) | Layer transform | mapped (skew after a skew add) |
| 3D transform (`rx`/`ry`/`rz`/`or`, separated `px`/`py`/`pz`, `ddd`) | 3D transform | after #42 |
| `ty:3` null | empty container layer | mapped |
| `ty:1` solid (`sc`,`sw`,`sh`) | rect path + fill, or layer backgroundColor | after #51 |
| `ty:4` shape | shape layer (the core) | mapped |
| `masksProperties` (mode a/s/i, `inv`, `o`, `pt`) | layer mask | after #52 (add/subtract via mask; `inv` and animated mask path approximated) |
| `tt`/`tp` track matte: alpha | a layer used as alpha mask | after #52 (alpha matte ~ mask) |
| `tt` luma / inverted matte | luminance matte | blocked (no luma-matte backend) |
| `bm` blend mode | per-layer blend | report-only (no blend lowering yet) |
| `ao` auto-orient | rotate along motion path | after #46 + #47; approximated |
| `hd` hidden, `ind`, `parent` | layer flags / parenting | mapped |
| `ty:5` text, `ty:6` audio, `ty:13` camera, data/footage | text after #49; rest no analogue | #49 / report-only / blocked |

## 3. Shapes

| Lottie | target | status |
| --- | --- | --- |
| `sh` path (`ks` bezier) | `CompositionIR` Path (move/line/cubic/close) | mapped |
| `rc` rectangle (`p`,`s`,`r`) | bezier path | baked |
| `el` ellipse (`p`,`s`) | bezier path via `0.5519` | baked (ellipse constant is the only approximation) |
| `sr` polystar (`pt`,`ir`,`is`,`or`,`os`,`r`,`sy`) | bezier path via star/polygon divisors | baked |
| `fl` fill (`c`,`r`) | Fill (color + fill-rule) | mapped |
| `st` stroke (`c`,`w`,`lc`,`lj`,`ml`,`d`) | Stroke (color/width; caps/joins/dash) | mapped (caps/joins/dash after #53/grammar verify) |
| `gf` gradient fill (`g`,`s`,`e`,`t`,`h`,`a`) | gradient as fill paint | after #48 (`h`/`a` highlight approximated) |
| `gs` gradient stroke | gradient stroke | after #48 + stroke |
| `gr` group (`it`,`np`) + `tr` | group with sublayers + transform | mapped |
| `tm` trim path (`s`,`e`,`o`,`m`) | `strokeStart`/`strokeEnd` | after #53; parallel mapped, sequential/`o` offset approximated |
| `rd` rounded corners | path-rounding modifier | blocked (no IR path modifier) |
| `pb` pucker-bloat, `mm` merge, `op` offset, `rp` repeater (shape), `zz` zig-zag, `tw` twist | path modifiers | blocked (no IR path-modifier framework) |

Note: shape `rp` repeater is a path-level modifier and is distinct from the
*layer* ReplicatorLayer (#44); the latter does not cover shape repeaters.

## 4. Properties, keyframes, animation

| Lottie | target | status |
| --- | --- | --- |
| static property (`a:0`) | constant IR value | mapped |
| animated scalar/vector/position/color | keyframed IR property | opacity/position mapped today; the rest after #46 |
| gradient property (`g`) | gradient stops | after #48 |
| keyframe value `s`, time `t` | IR keyframe | mapped |
| temporal ease `i`/`o` (normalized bezier) | PureLayer `TimingFunction` (cubic bezier per segment) | after #47; faithful for the bezier form, but inherits bodymovin's influence/speed reparameterization and the delta=1 degeneracy (see `bodymovin-source-semantics.md`) -> approximated |
| spatial tangents `ti`/`to` (curved motion path) | sampled motion path | after #46; 150-vs-200 sampling mismatch -> approximated |
| hold `h:1` | discrete calculation mode | after #47 |
| split position (`s:true`,`x`,`y`) | per-axis animation | after #42/#46 |
| per-dimension ease (`x`/`y` arrays) | per-channel timing | after #47; if collapsed to scalar -> report the collapse |

## 5. Constants and values

Enums (blend, mask, matte, fill-rule, line cap/join, gradient type, star type,
dash type, trim, shape direction) map to the corresponding PureLayer enums where
one exists, else report-only. Values: bezier (relative tangents) -> IR path
(absolute) with the conversion the importer owns; color 0..1 -> PureLayer Color;
vector -> point; hexcolor (solid `sc`) -> Color; data-url image -> contents.

## 5b. Structural and plumbing keys (explicit disposition)

Model-or-report means *every* key has a disposition, including the structural
ones that are not themselves render features. For completeness (and so the
coverage check passes), these are stated explicitly:

| key | role | status |
| --- | --- | --- |
| `ty` | type discriminator (layer/shape/property) | mapped (drives importer dispatch) |
| `nm` | human name | mapped (carried onto the IR node) |
| `id` | asset id | mapped (asset resolution) |
| `assets` | asset table | mapped (resolved before layer import) |
| `layers` | layer array (composition/precomp) | mapped (traversed) |
| `shapes` | shape-layer shape array | mapped (traversed) |
| `k` | property payload (static value or keyframe list) | mapped (property machinery) |
| `v` | vector value / stroke-dash length | mapped (value decode; dash `v` after #53) |
| `mode` | mask blend mode (a/s/i/n) | after #52 (add/subtract; l/d/f report-only) |
| `n` | stroke-dash item type (d/g/o) | after #53 |
| `ml2` | animatable miter limit | after #53 |
| `u` | image file path | after #50 (with `refId`/`p`) |
| `cm`,`dr` | marker comment / duration | report-only (carried as document metadata) |
| `custom` | free metadata object | report-only |
| `ver` | spec version | report-only (recorded; may gate compatibility warnings) |

## 6. No analogue (always report-only or blocked)

`ef` effects (entire taxonomy), `sy` layer styles, `x` expressions, motion blur
`mb`, collapse transform `ct`, `fonts`/`chars` (beyond #49 text), audio `au`,
camera, blend mode 17, mask modes l/d/f. These have no PureComposition or
PureLayer representation; they must appear in the import report with their layer
or shape path so the file is never rendered silently wrong.

## Summary: what the importer can do, in order

1. **Mapped today**: geometry (paths + baked rect/ellipse/star), fill, stroke
   (solid), groups, transforms (2D), opacity/position animation, masks (add) after
   #52. This already renders a large class of real shape-layer Lottie files.
2. **After the #41 orbit/animation children** (#42 3D, #46 richer animate, #47
   timing/easing, #48 gradient fill, #53 stroke trim): most non-text shape
   animations, with the named easing/spatial approximations.
3. **After more children** (#49 text, #50 image, #51 solid/visual props): text and
   raster layers.
4. **Always report-only/blocked**: effects, layer styles, expressions, luma
   mattes, camera/audio, and the exotic shape modifiers. The importer reports
   them with provenance; it never pretends to render them.

This matrix is the acceptance backbone for PureComposition #21 (Lottie semantic
import): each row is a fixture that either renders (mapped/baked/approximated,
gated by `AliasingPixelDiff`) or appears in the import report (report-only/
blocked), and the coverage meta-test fails if any Lottie key has no row here.

That meta-test is real, not aspirational: `verify-coverage.sh` (this folder)
checks every property key in the pinned schema (`lottie-spec @4b55957`) against
this doc and fails on any key without a disposition. Last run: 70/70 keys have a
disposition, 0 gaps.
