# Numeric Oracle Tolerance Derivations

Status: issue #104 tolerance-bound ledger.

This document states the arithmetic model behind
`Tools/LottieOracle/oracle-tolerances.json` schema version 2. A tolerance is not
accepted because it made the diff pass. Each row is either DERIVED from the
stated model or ASSUMED with the missing proof named.

## Arithmetic Model

- DOCUMENTED: `Tools/LottieOracle/package-lock.json` pins `lottie-web` to
  5.13.0. Running `npm --prefix Tools/LottieOracle ci` materializes the exact
  source inspected for these claims.
- DOCUMENTED: lottie-web `player/js/utils/TransformProperty.js` samples
  transform scale with multiplier `0.01` and opacity with multiplier `0.01`.
- DOCUMENTED: lottie-web `player/js/utils/PropertyFactory.js` stores
  multidimensional animated property samples in `Float32Array` values.
- DOCUMENTED: lottie-web `player/js/utils/common.js` sets
  `defaultCurveSegments = 150` and `roundCorner = 0.5519`.
- DOCUMENTED: lottie-web `player/js/utils/bez.js` samples cubic length using
  `defaultCurveSegments`; `getNewSegment` rounds generated control points to
  `0.001`.
- STRUCTURAL: PureLottie compares source intent before PureLayer rendering.
  Lottie times remain source frames, and frame-to-second conversion is not part
  of these numeric oracle rows.
- STRUCTURAL: Direct matrix translation rows are emitted only when the curated
  fixture has direct animated or split position and no anchor, rotation, parent
  transform, precomp, shape transform, or time-remap coverage.
- STRUCTURAL: The matrix translation bound is valid only inside its domain
  (`|coordinate| < 64` CSS px, where the Float32 ulp is `2^-18`). That domain is
  enforced by `Tools/LottieOracle/tests/oracle-tolerances.test.mjs`, which fails
  if any direct-translation fixture's compared `matrix[12..13]` reaches `64`, so a
  future fixture cannot silently move the comparison outside the derived bound.

## Bounds

| Tolerance | Status | Bound | Reason |
| --- | --- | ---: | --- |
| `opacity.unit-interval.absolute` | DERIVED | `1e-12` | One lottie-web `0.01` scale and binary64 subtraction in unit interval. `16 * eps(1)` is below `4e-15`; `1e-12` is the ledger floor that still rejects authored-percent drift. |
| `matrix.translation.css-pixel.absolute` | DERIVED | `2^-18 = 0.000003814697265625` | Direct translation fixtures compare Float32 multidimensional position samples below 64 CSS px after fixed row-vector matrix composition. One Float32 ulp at that magnitude is `2^(5 - 23)`. |
| `frame.source-frame.absolute` | DERIVED | `1e-12` | Compared precomposition fixtures use source-frame subtraction/division without successful time-remap claims; binary64 error is below the ledger floor. |
| `bounds.css-pixel.absolute` | ASSUMED | `1e-5` | The oracle reads SVG `getBBox()` for path local bounds. Chromium does not expose a portable numeric error bound for this API in lottie-web source. |
| `path-length.css-pixel.absolute` | ASSUMED | `1e-6` | The oracle reads SVG `getTotalLength()`. lottie-web's internal 150-segment sampler is documented, but Chromium's SVG length algorithm is not the same trusted surface. |
| `trim.segment.unit-interval.absolute` | DERIVED | `1e-12` | Compared trim fields are scalar normalized values: start/end divided by 100, offset modulo 360 then divided by 360. The later 150-segment path sampler and `0.001` segment rounding do not enter these scalar comparisons. |
| `pixel.max-channel.exact` | DERIVED | `0` | The PNG comparator uses integer absolute difference on decoded 8-bit RGBA channels. With threshold zero, only exact channel equality is accepted. |

## Counterexample Tests

MEASURED on 2026-06-13 by the issue #104 test additions:

- `Tests/LottieOracleDiffTests/LottieNumericOracleDiffTests.swift` mutates
  committed lottie-web traces by each numeric tolerance's
  `counterexampleOffset` and requires `LottieNumericOracleDiff` to fail the
  matching comparison family.
- `Tests/LottieEvaluationTests/LottieWebIntentOracleTests.swift` mutates the
  path-length scalar by the ledger's `counterexampleOffset` and proves it lies
  outside the recorded path-length threshold.
- `Tools/LottieOracle/tests/compare-images.test.mjs` mutates one RGBA channel by
  the pixel tolerance's `counterexampleOffset` and requires the PNG comparator
  to report a mismatch.

## Remaining Assumptions

ASSUMED: `bounds.css-pixel.absolute` and `path-length.css-pixel.absolute` remain
asserted because their reference values come from Chromium SVG geometry APIs.
The missing proof is a portable numeric error bound for `getBBox()` and
`getTotalLength()` across the supported browser revision. Until that proof
exists, the ledger is explicit about the assumption and the tests prove only
that values outside the recorded threshold are rejected.
