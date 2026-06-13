# Fault Injection and Test Calibration

Status: `witnessed` (The fault-injection calibration suite verifies detection on every test run)

This document describes the fault-injection catalog, calibration strategy, and test detection gates used to guarantee that PureLottie's test suite and conformance oracles are not vacuous.

## Calibration Principle

A test suite that passes on every run is only as reliable as its ability to fail when the implementation is incorrect. To ensure that our tolerance thresholds, decompiler checks, and oracle diff comparisons are active and sensitive, we inject controlled faults (mutations) into critical compiler phases and verify that the test suite catches them.

## Fault Catalog and Detection Matrix

The catalog of faults is defined in [LottieFaultInjector.swift](file:///Volumes/Code/DeveloperExt/public/PureLottie/Sources/LottieEvaluation/LottieFaultInjector.swift) and checked in [LottieFaultInjectionCalibrationTests.swift](file:///Volumes/Code/DeveloperExt/public/PureLottie/Tests/LottieEvaluationTests/LottieFaultInjectionCalibrationTests.swift):

| Injected Fault | Target Phase | Description of Mutation | Detecting Gate / Test |
| --- | --- | --- | --- |
| `.offByOneKeyframeIndex` | **Evaluation** | Shifts the selected keyframe segment index by 1 in `LottieFrameEvaluator`. | `LottieFaultInjectionCalibrationTests` verifies that the evaluated progress values diverge. |
| `.wrongMatrixMultiplicationOrder` | **Evaluation / Transform** | Reverses the operand order in `LottieTransformMatrix` concatenation. | `LottieFaultInjectionCalibrationTests` verifies that the concatenated matrices diverge. |
| `.droppedTrimSegment` | **Evaluation / Geometry** | Drops the last trim segment during path trimming in `LottieSourceTrimEvaluator`. | `LottieFaultInjectionCalibrationTests` verifies that the count of trim result paths is decremented. |
| `.swappedMaskMode` | **Decompile** | Swaps mask mode `"a"` (add) and `"s"` (subtract) during mask decompilation. | `LottieFaultInjectionCalibrationTests` verifies that decompiled mask modes mismatch. |
| `.roundedAwayPrecision` | **Evaluation** | Rounds `sin` and `cos` outputs in `LottieMath` to exactly 2 decimal places. | `LottieFaultInjectionCalibrationTests` verifies that precision loss is detected. |
| `.reversedBezierDirection` | **Evaluation / Geometry** | Swaps the tangents and reverses the vertex sequence in `LottieSourceGeometryEvaluator`. | `LottieFaultInjectionCalibrationTests` verifies that absolute vertex positions differ. |
| `.skippedPrecompTimeRemap` | **Evaluation / Timing** | Bypasses time-remap (`tm`) evaluation and falls back to normal time stretch. | `LottieFaultInjectionCalibrationTests` verifies that precomposition local frame evaluation diverges. |

## Mutation Test Reproducibility

Every fault is applied task-locally using Swift's `@TaskLocal` context propagation. This guarantees:
- **Thread-Safety**: Concurrently running tests do not affect each other's execution context.
- **Precision**: Faults can be turned on and off for extremely granular code paths inside specific test blocks.
- **Reproducibility**: The mutation checks run deterministically on every `swift test` invocation, certifying that the compiler gates are calibrated and sensitive.
