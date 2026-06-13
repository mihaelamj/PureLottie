# Lottie translation completeness: what is proven, and what is not

This is the definitive, evidence-backed answer to "can we translate Lottie?" It
does not give a single yes/no, because the honest answer is layered and each
layer carries its own status. Every claim below cites the check that backs it;
no claim is `assumed` where a stronger status is written.

## The question, decomposed

"Translate Lottie" means four separable things. Three are proven; the fourth is
proven incomplete and its path is named.

1. **Read it**: decode every field, drop nothing silently.
2. **Map-or-report it**: every field is either modeled with a typed home or
   recorded as unsupported, never silently ignored.
3. **Compute it exactly**: the definitional geometry and transforms equal the
   documented closed form, independent of any reference renderer.
4. **Render it equivalently**: the rendered pixels match an independent
   reference. This is the one that is NOT proven.

## Proven (1, 2, 3)

### Format coverage is complete (theorem, bounded to lottie-spec @4b55957)

Every property key the official schema defines is modeled or reported, and the
model decodes exactly the modeled keys (a partition theorem, both directions).
Separately, the typed decode rejects the malformed inputs tested and traps on
none of a 1000+ input deterministic fuzz; that robustness is `sampled` (it does
not prove totality over all inputs).
- Evidence: `LottieFeatureCoverageTests` (key-set guard, modeled decode-backing,
  partition theorem), `LottieModelDecodeTotalityTests` (malformed rejection +
  fuzz), `docs/lottie-format/verify-coverage.sh` (70/70 keys, 28/28 enums, pinned).
- Status: coverage and partition are `theorem (bounded to lottie-spec @4b55957)`
  (exhaustive over all 70 keys); fuzz robustness is `sampled`. (Closed #138.)

The checks bit, which is why this is trusted: they caught four registry lies
(`g`, `np`, `u`, `ver` falsely marked modeled) and the typed-decode fuzz gap that
the parse-layer fuzz had left open.

### Numeric translation matches an exact closed form (closed form is a theorem; the implementation is sampled)

The closed forms are exact for all inputs by construction (algebraic
vertex/matrix formulas with the documented constants). The geometry evaluator's
contours and the layer transform matrix are checked against those closed forms,
to floating-point epsilon, at a pinned grid of sampled points, lottie-web
consulted in none. The grids sample a continuous parameter space rather than
enumerate it, so the implementation's agreement is `sampled`, not a
bounded-exhaustive theorem:
- ellipse (`LottieEllipseExactnessTests`), polygon + star
  (`LottiePolystarExactnessTests`), rectangle (`LottieRectangleExactnessTests`),
  transform matrix (`LottieTransformExactnessTests`).
- The `0.5519` round-corner constant, the `floor(pt)*2` star divisor, the `-pi/2`
  start offset, and the row-vector `translate(-anchor) . scale . rotateZ(-r) .
  translate(position)` order are all locked to the documented values.
- Status: closed form `theorem` (exact by construction); implementation
  `sampled` at the pinned grids, to FP epsilon. (Closed #139.)

The transform check bit hardest: it failed all 96 cases first, forcing a real
row-vector-handedness reconciliation rather than a copied (and silently wrong)
formula.

### Loss is explicit and complete (theorem over the corpus / measured)

Every reversibility fixture is classified exactly once (exact xor recorded-loss),
zero exclusions, zero unrecorded mismatches, and every loss is path-bearing; the
contract doc's measured counts are re-derived live from the report and cannot
drift.
- Evidence: `LottieSourceIntentReversibilityCorpusGateTests`,
  `LottieSourceIntentRoundTripGateTests`, `LottieLossContractTests`.
- Status: `theorem (curated corpus)` for completeness; the measured counts are
  `measured` and drift-guarded. (Part of #141.)

## Not proven: render pixel-equivalence (4)

This is the honest frontier, and it is proven *incomplete*, not open-by-omission:

- **#130 proved numeric agreement does not imply pixel agreement.** A corrected
  composite metric showed six numeric-eligible fixtures whose pixels diverge.
- **#134 records six features that render wrong with a clean numeric oracle and a
  clean ImportReport** (mask not applied, dash dropped, +4).
- Therefore a claim of "100% render-equivalent translation" is false, and the
  project's own gates would catch it.

Closing this requires, and is blocked on:
- **#140** an independent pixel oracle (an analytic rasterizer, or pinned
  AfterEffects golden frames) so render-equivalence is checked against something
  other than the subject itself or a single browser. We have no programmatic AE,
  so this may land partly `blocked`.
- **Phase 3 / PureComposition #21** the actual Lottie -> CompositionIR front-end,
  which is built on the agent side and gated by the PureComposition #41 language
  constructs.

The sampled layer (spatial Bezier arc length 150 vs 200, the influence/speed-to-
Bezier easing reparameterization) carries `sampled`/`witnessed` status; its
numeric *bounds* are still to be measured (the remainder of #141).

## Bottom line

We can prove, to 100% and bounded to the pinned schema, that PureLottie
faithfully **reads and maps-or-reports every field** (a coverage theorem) and
**accounts for every loss explicitly** (a corpus theorem); and that its
**geometry and transforms match closed forms that are exact by construction**,
verified at sampled grid points. That is "we can translate the Lottie format" in
the read/map/account/compute sense: coverage and loss are theorems, and the
numeric agreement is `sampled` against forms that are themselves exact. None of
it is bare assertion, and none of it is overclaimed as a bounded-exhaustive
numeric theorem.

We cannot prove, and do not claim, **render-equivalent** translation: we have
proven the opposite for at least six features, and the path to closing that gap
(#140 + #21) is named, not hand-waved. Saying otherwise would be the one shortcut
this whole effort exists to forbid.
