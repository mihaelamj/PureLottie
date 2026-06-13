//
//  LottieFaultInjector.swift
//  PureLottie
//

import Foundation

/// Representative faults that can be injected into the evaluation, lowering, and decompiler phases.
public enum LottieFault: String, Sendable, CaseIterable {
    /// Injects an off-by-one error when selecting keyframe segments in LottieFrameEvaluator.
    case offByOneKeyframeIndex
    /// Swaps the left and right operands in LottieTransformMatrix multiplication.
    case wrongMatrixMultiplicationOrder
    /// Drops the final segment of a trim path in LottieSourceTrimEvaluator.
    case droppedTrimSegment
    /// Swaps mask mode "a" (add) and "s" (subtract) in LottieSourceIntentDecompiler.
    case swappedMaskMode
    /// Rounds away transcendental math precision to 2 decimal places in LottieMath sin and cos.
    case roundedAwayPrecision
    /// Inverts the control points and sequence of Bezier contours in LottieSourceGeometryEvaluator.
    case reversedBezierDirection
    /// Skips precomposition time-remap evaluation in LottieLayerGraphEvaluator.
    case skippedPrecompTimeRemap
}

/// A thread-safe, task-local harness for calibrating PureLottie tests with controlled fault injection.
public enum LottieFaultInjector {
    @TaskLocal
    public static var activeFault: LottieFault? = nil

    /// Runs the specified block of code with the injected fault active.
    public static func inject(_ fault: LottieFault, during work: () throws -> Void) rethrows {
        try $activeFault.withValue(fault) {
            try work()
        }
    }

    /// Returns whether the specified fault is currently active on the calling task.
    public static func isActive(_ fault: LottieFault) -> Bool {
        activeFault == fault
    }
}
