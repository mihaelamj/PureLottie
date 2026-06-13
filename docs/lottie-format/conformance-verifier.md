# Independent Conformance Verifier and Trusted Surface

Status: `witnessed` (The independent verifier passes on every test run and proves conformance claims from committed evidence without running compiler logic)

This document details the minimal-trusted-surface design of the independent conformance verifier, which certifies that PureLottie's conformance claims are correct without relying on or executing the compiler's own evaluation pipeline.

## Verification Principle

A compiler cannot trustworthily certify its own correctness. If the same evaluator code that translates Lottie matrices and opacities is also used to compare them against reference values, a systematic bug in that evaluator (such as wrong matrix multiplication order or skipped time-remap) could pass the tests unnoticed.

To solve this, the verifier is built as a separate, minimal target (`LottieConformanceVerifier`) that re-verifies conformance and round-trip claims from committed evidence files only.

## Trusted Surface

The verifier assumes the validity of:
1. **Committed Browser Reference Traces**: The lottie-web trace JSONs under `Tests/Fixtures/LottieOracle/lottie-web-intent/` are assumed to be authentic records of lottie-web 5.13.0 behavior in Chromium.
2. **Committed Reversibility Report**: The `reversibility-gate/report.json` is assumed to be the authentic representation of the compiler's output and decompiler's round-trip metrics.
3. **JSON Decoder & Foundation**: The Swift Standard Library and Foundation JSON parsing are assumed correct.
4. **Basic Arithmetic Model**: Double-precision floating-point arithmetic is assumed to behave according to IEEE 754.

The verifier does **NOT** trust or import:
- The compiler (`LottieImport`)
- The frame or shape evaluators (`LottieFrameEvaluator`, `LottieSourceGeometryEvaluator`)
- The RenderIR builder (`LottieRenderIRBuilder`)
- The private backend packages (`PureLayer`, `PureDraw`)

## Verification Steps

For each Lottie regression fixture, the verifier:
1. Re-checks **Numeric Conformance** by directly comparing the compiler's evaluated layer opacities, matrix translation values, and precomp frames stored in `reversibility-gate/report.json` against the reference values in the `lottie-web-intent` traces under the exact tolerance thresholds from `oracle-tolerances.json`.
2. Re-checks **Round-Trip Equality** by asserting that for all exact fixtures, `findingCount` is 0 and the decompiled properties (opacity, position, scale, rotation, matrix, matte, shape/style/trim counts) are identical to the original properties.
3. Re-checks **Witness Status** by verifying that all witness corpus entries declare a `witnessed` status backed by committed Chromium trace files.

## Running the Verifier

The verifier can be run as a standalone executable:
```bash
swift run LottieConformanceVerifier
```
Or executed as part of the normal test suite:
```bash
swift test --filter LottieConformanceVerifierTests
```
If the verifier detects any difference or out-of-tolerance value between the committed compiler report and the reference trace, it exits with a non-zero exit code, failing the conformance gate.
