# Numeric to pixel sufficiency (issue #130)

## Question

The numeric oracle (`LottieNumericOracleDiff`) compares source-intent quantities
against committed lottie-web traces: transform matrices, expanded geometry,
bounds, opacity, trim ranges. Issue #130 asks whether that numeric agreement is
*sufficient*: if the imported primitives match lottie-web numerically, do they
also render the same image? If yes, the numeric oracle alone certifies the
render and pixels are redundant. If no, a numeric pass can hide a render gap.

## Method

`Tools/LottieOracle/scripts/pixel-sufficiency.mjs` (run with
`npm --prefix Tools/LottieOracle run pixel-sufficiency`, after
`swift build --product LottieFrameDump` and `playwright install chromium`).

For every fixture in the numeric-eligible set (those carrying a committed
`lottie-web-intent` trace) it renders the imported PureLayer primitives
(`LottieFrameDump`) and lottie-web (`render-reference.mjs`) at the same frames
and scale, then compares.

The comparison metric matters and the first version got it wrong. PNG stores
straight (non-premultiplied) alpha, so a fully transparent pixel keeps an
arbitrary RGB. PureLayer leaves the fill color in transparent anti-aliased
fringe pixels; Chromium zeroes them. Comparing raw RGB therefore reported a
255/255 delta on invisible pixels and falsely failed nearly every fixture. The
corrected metric composites each pixel over **both** an opaque black and an
opaque white background and takes the max channel delta. Two pixels composite
identically over both backgrounds if and only if they have the same alpha and
the same premultiplied color, which is the exact cross-renderer equality we
want; transparent pixels then contribute nothing regardless of stored RGB.

A single max-delta still cannot tell anti-aliasing from a dropped feature: AA on
a curved or rotated edge touches only the ~1px boundary ring (a tiny share of
pixels at a high local delta), while an ignored mask or a missing dash pattern
differs over a whole region. So the gate also reports `diffPixelFraction`: the
share of pixels whose composited delta exceeds `AA_TOLERANCE` (32). Across the
curated set this fraction splits into two clusters with an empty gap between
them: anti-aliased curved and rotated edges stay at or below 0.32% of pixels,
while dropped or wrong features start at 0.88%. The sufficiency criterion is
`diffPixelFraction <= 0.005`, a cut that sits inside that gap rather than on a
renderer-specific magic number.

## Result: numeric agreement does NOT imply pixel agreement

94 frames over 31 fixtures. Six fixtures violate sufficiency: their source-intent
numbers match lottie-web (they are in the numeric-eligible set) yet their
rendered raster diverges structurally.

| Fixture | diff fraction | max composited delta | ImportReport |
| --- | --- | --- | --- |
| mask-add-rectangle | 16.11% | 255 | clean (0 findings) |
| split-position-ellipse | 4.10% | 242 | clean |
| rounded-rectangle | 1.46% | 242 | clean |
| stroke-dash | 1.27% | 255 | clean |
| raw-bezier-cubic | 0.98% | 255 | clean |
| stroke-caps-joins | 0.88% | 242 | clean |

The remaining anti-aliasing band (ellipses, polygons, stars, rotations, trim,
mattes) stays at or below 0.32% of pixels and is not a violation.

The worst case is diagnostic. `mask-add-rectangle` renders 660 visible pixels in
PureLayer versus 35 in lottie-web: PureLayer draws the whole rectangle and does
not clip to the mask. The mask survives into `RenderIR` (`maskCount: 1`), so the
importer carries it correctly. The loss is downstream, in lowering or render,
and **no `ImportReport` finding records it.** That violates the project
non-negotiable that the importer never renders silently wrong. The same shape
applies to `stroke-dash` (continuous stroke, dash pattern dropped) and the other
four.

## Status

- The six sufficiency violations are `witnessed`: a real lottie-web render backs
  each, with committed numeric agreement and a clean `ImportReport`.
- The metric (`AA_TOLERANCE`, `STRUCTURAL_FRACTION`) is `assumed`: cross-renderer
  anti-aliasing has no portable error bound, the same status the #115 tolerance
  audit recorded for bounds and path length. The cut is evidence-placed (it sits
  in a measured gap), not derived.

## Consequence

The numeric oracle is necessary but not sufficient. It compares source-intent
quantities and is structurally blind to whether a feature reached the raster, so
a pixel gate is required alongside it. The six violations are render or lowering
gaps with clean numeric and clean import status; each needs a recorded finding
or a fix so the render stops being silently wrong. They are filed as separate
issues.

The pixel gate as built still depends on Chromium and lottie-web as the
reference renderer. That dependency is acceptable today but is itself a
trust assumption: lottie-web is one implementation of the Lottie/bodymovin
semantics, with its own approximations. The independent direction is to derive
the reference raster from the format's own semantics (the AfterEffects model
that bodymovin serializes) rather than from a second renderer, so PureLottie can
certify its render without trusting a browser. That work is tracked separately.
