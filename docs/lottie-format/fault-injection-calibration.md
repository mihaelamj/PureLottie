# Fault Injection and Test Calibration

Status: `witnessed` (The fault-injection calibration suite verifies detection by executing the actual shipped gates under each fault on every test run)

This document describes the fault-injection catalog, calibration strategy, and test detection gates used to guarantee that PureLottie's test suite and conformance oracles are not vacuous.

## Calibration Principle

A test suite that passes on every run is only as reliable as its ability to fail when the implementation is incorrect. To ensure that our tolerance thresholds, decompiler checks, and oracle diff comparisons are active and sensitive, we inject controlled faults (mutations) into critical compiler phases and verify that existing shipped gates fail under them.

## Fault Catalog and Detection Matrix

The catalog of faults is defined in [LottieFaultInjector.swift](file:///Volumes/Code/DeveloperExt/public/PureLottie/Sources/LottieEvaluation/LottieFaultInjector.swift) and checked in [LottieFaultInjectionCalibrationTests.swift](file:///Volumes/Code/DeveloperExt/public/PureLottie/Tests/LottieEvaluationTests/LottieFaultInjectionCalibrationTests.swift):

| Injected Fault | Target Phase | Description of Mutation | Detecting Shipped Gate | Calibration Test Witness | Status |
| --- | --- | --- | --- | --- | --- |
| `.offByOneKeyframeIndex` | **Evaluation** | Shifts the selected keyframe segment index by 1 (wrapped) in `LottieFrameEvaluator`. | `LottieOracleCorpusTests.corpusSnapshotsLineUpWithRenderIRRootLayerFacts` (checks opacity and translation against the reference oracle). | Verifies that evaluated layer translation under the fault exceeds the oracle translation tolerance. | `witnessed` |
| `.wrongMatrixMultiplicationOrder` | **Evaluation / Transform** | Reverses the operand order in `LottieTransformMatrix` concatenation. | `LottieOracleCorpusTests.corpusSnapshotsLineUpWithRenderIRRootLayerFacts` (composes parent-child transforms). | Verifies that the composed world matrix translation of a child layer under the fault exceeds the oracle translation tolerance. | `witnessed` |
| `.droppedTrimSegment` | **Evaluation / Geometry** | Drops the last trim segment during path trimming in `LottieSourceTrimEvaluator`. | `LottieLoweringSourceIntentGateTests` (checks shape geometry matches expected shape snapshots). | Verifies that the bounding box of the lowered shape under the fault differs from the normal bounds. | `witnessed` |
| `.swappedMaskMode` | **Decompile** | Swaps mask mode `"a"` (add) and `"s"` (subtract) during mask decompilation. | `LottieSourceIntentTransformTimingRoundTripGate` (compares decompiled mask modes against original nodes). | Verifies that decompiled mask modes mismatch original node mask modes, producing round-trip findings. | `witnessed` |
| `.roundedAwayPrecision` | **Evaluation** | Rounds `sin` and `cos` outputs in `LottieMath` to exactly 2 decimal places. | `LottieWebIntentOracleTests` (checks path lengths and bounds for geometry). | Verifies that the evaluated ellipse shape bounds under the fault exceed the oracle bounds tolerance. | `witnessed` |
| `.reversedBezierDirection` | **Evaluation / Geometry** | Swaps the tangents and reverses the vertex sequence in `LottieSourceGeometryEvaluator`. | `LottieLoweringSourceIntentGateTests` (compares shape geometry vertices and tangents). | Verifies that the evaluated shape vertices under the fault differ from the normal vertices. | `witnessed` |
| `.skippedPrecompTimeRemap` | **Evaluation / Timing** | Bypasses time-remap (`tm`) evaluation and falls back to normal time stretch. | `LottieLoweringSourceIntentGateTests` (asserts precomposition reference facts, checking boundary localFrame). | Verifies that the precomposition local frame under the fault deviates from the expected frame in the reference trace. | `witnessed` |

## Mutation Test Reproducibility

Every fault is applied task-locally using Swift's `@TaskLocal` context propagation. This guarantees:
- **Thread-Safety**: Concurrently running tests do not affect each other's execution context.
- **Precision**: Faults can be turned on and off for extremely granular code paths inside specific test blocks.
- **Reproducibility**: The mutation checks run deterministically on every `swift test` invocation, certifying that the compiler gates are calibrated and sensitive.
