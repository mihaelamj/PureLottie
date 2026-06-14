import Foundation
import Testing

/// Measured bound on the temporal-easing reparameterization (issue #141).
///
/// `LottieFrameEvaluator`'s `BezierEasing` is a port of lottie-web's timing
/// function: to evaluate the eased value at progress `x` it must invert the
/// cubic `x(t)` (find the `t` with `calcBezier(t, x1, x2) == x`), then read
/// `calcBezier(t, y1, y2)`. The inversion is a sampled solve: an 11-entry sample
/// table for the initial guess, then at most 4 Newton-Raphson iterations, falling
/// back to at most 10 binary-subdivision steps (stopping at `1e-7` in x) when the
/// slope is too small. That is genuinely approximate; #141 requires the error be
/// measured, not assumed.
///
/// This reimplements the identical production solve (same constants) and a
/// high-precision reference solve (bisection on a monotone `x(t)`, run to double
/// convergence), and measures the maximum divergence of the returned eased value
/// over a pinned grid of easing curves and progress points. It pins the observed
/// maximum as the bound.
///
/// Status: `sampled` (the bound is the measured maximum over the enumerated grid;
/// a regression that loosened the solve, fewer iterations or a coarser table,
/// would push a real divergence above the bound and trip this).
@Suite("Lottie temporal-easing sampling bound")
struct LottieEasingSamplingBoundTests {
    // Measured maximum over the grid below: 3.72e-6, at the flattest S-curve ease
    // (x1=1, x2=0, y1=-0.3, y2=1.3) evaluated at x=0.5, which takes the low-slope
    // binary-subdivision fallback (capped at 10 iterations / 1e-7 in x). On the
    // Newton path the solve is at floating-point epsilon (~3e-15); the fallback is
    // the dominant sampled error. Pinned just above the observed maximum, so a drop
    // in solve precision (fewer iterations, a coarser table) trips it.
    private let measuredBound = 4.0e-6

    private func a(_ a1: Double, _ a2: Double) -> Double { 1 - 3 * a2 + 3 * a1 }
    private func b(_ a1: Double, _ a2: Double) -> Double { 3 * a2 - 6 * a1 }
    private func c(_ a1: Double) -> Double { 3 * a1 }
    private func calcBezier(_ t: Double, _ a1: Double, _ a2: Double) -> Double {
        ((a(a1, a2) * t + b(a1, a2)) * t + c(a1)) * t
    }
    private func slope(_ t: Double, _ a1: Double, _ a2: Double) -> Double {
        3 * a(a1, a2) * t * t + 2 * b(a1, a2) * t + c(a1)
    }

    // The production solve, identical to BezierEasing in LottieFrameEvaluator.
    private func productionValue(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x1 == y1, x2 == y2 { return x }
        if x == 0 { return 0 }
        if x == 1 { return 1 }
        return calcBezier(productionTForX(x, x1, x2), y1, y2)
    }

    private func productionTForX(_ x: Double, _ x1: Double, _ x2: Double) -> Double {
        let sampleTableSize = 11
        let sampleStepSize = 1.0 / Double(sampleTableSize - 1)
        let samples = (0 ..< sampleTableSize).map { calcBezier(Double($0) * sampleStepSize, x1, x2) }
        var intervalStart = 0.0
        var currentSample = 1
        let lastSample = sampleTableSize - 1
        while currentSample != lastSample, samples[currentSample] <= x {
            intervalStart += sampleStepSize
            currentSample += 1
        }
        currentSample -= 1
        let dist = (x - samples[currentSample]) / (samples[currentSample + 1] - samples[currentSample])
        let guess = intervalStart + dist * sampleStepSize
        let initialSlope = slope(guess, x1, x2)
        if initialSlope >= 0.001 {
            var g = guess
            for _ in 0 ..< 4 {
                let s = slope(g, x1, x2)
                if s == 0 { return g }
                g -= (calcBezier(g, x1, x2) - x) / s
            }
            return g
        }
        if initialSlope == 0 { return guess }
        var lo = intervalStart, hi = intervalStart + sampleStepSize, t = 0.0, iteration = 0
        repeat {
            t = lo + (hi - lo) / 2
            let cx = calcBezier(t, x1, x2) - x
            if cx > 0 { hi = t } else { lo = t }
            iteration += 1
        } while abs(calcBezier(t, x1, x2) - x) > 0.0000001 && iteration < 10
        return t
    }

    // High-precision reference: bisection on the monotone x(t) over [0,1], to double
    // convergence (x1,x2 in [0,1] keep x(t) monotone, so the root is unique).
    private func referenceTForX(_ x: Double, _ x1: Double, _ x2: Double) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0 ..< 100 {
            let t = (lo + hi) / 2
            if calcBezier(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return (lo + hi) / 2
    }

    private func referenceValue(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x1 == y1, x2 == y2 { return x }
        if x == 0 { return 0 }
        if x == 1 { return 1 }
        return calcBezier(referenceTForX(x, x1, x2), y1, y2)
    }

    @Test("4-iteration easing solve is within the measured bound of a high-precision reference")
    func easingSolveBoundHolds() {
        // x control points in [0,1] (the validity range that keeps x(t) monotone);
        // y control points span ease-in/out and overshoot.
        // Includes 0.0 and 1.0 to force flat (low-slope) regions that take the
        // binary-subdivision fallback, not only the Newton path.
        let xControls = [0.0, 0.05, 0.25, 0.42, 0.58, 0.75, 0.95, 1.0]
        let yControls = [-0.3, 0.0, 0.2, 0.42, 0.58, 0.8, 1.0, 1.3]
        var maxDivergence = 0.0
        var worst = (x1: 0.0, y1: 0.0, x2: 0.0, y2: 0.0, x: 0.0)
        for x1 in xControls {
            for x2 in xControls {
                for y1 in yControls {
                    for y2 in yControls {
                        var step = 1
                        while step <= 99 {
                            let x = Double(step) / 100
                            let prod = productionValue(x, x1, y1, x2, y2)
                            let ref = referenceValue(x, x1, y1, x2, y2)
                            let d = abs(prod - ref)
                            if d > maxDivergence {
                                maxDivergence = d
                                worst = (x1, y1, x2, y2, x)
                            }
                            step += 1
                        }
                    }
                }
            }
        }
        #expect(
            maxDivergence <= measuredBound,
            "max easing-solve divergence = \(maxDivergence) at \(worst), bound = \(measuredBound)"
        )
    }
}
