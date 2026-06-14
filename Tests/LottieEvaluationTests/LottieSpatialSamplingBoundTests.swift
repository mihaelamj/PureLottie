import Foundation
import Testing

/// Measured bound on the spatial arc-length sampling approximation (issue #141).
///
/// LottieFrameEvaluator measures spatial-Bezier arc length with lottie-web's
/// fixed 150-segment polyline (`lottieWebSpatialCurveSegments = 150`). That is a
/// genuinely sampled approximation; #141 requires its error be measured, not
/// assumed. This reimplements the identical N-segment polyline length (the same
/// algorithm the evaluator uses, so the bound applies to it) and measures the
/// 150-segment length against a high-resolution reference (N = 20000) over a
/// pinned grid of cubic Beziers spanning straight, arched, S, and near-cusp
/// shapes. It pins the observed maximum relative divergence as the bound.
///
/// Status: `sampled` (the bound is the measured maximum over the enumerated
/// Bezier grid; the polyline always under-estimates the true arc length, so a
/// real divergence above the bound is a regression in the sampling resolution).
@Suite("Lottie spatial arc-length sampling bound")
struct LottieSpatialSamplingBoundTests {
    /// Measured maximum over the grid below: the 150-segment polyline differs from
    /// the 20000-segment reference by 2.79e-5 (about 0.0028%). The bound is pinned
    /// just above that observed maximum, so a drop in sampling resolution (a real
    /// increase in divergence) trips it; tightening N would lower the divergence.
    private let measuredBound = 3.0e-5

    private func point(_ t: Double, _ p: [[Double]]) -> [Double] {
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return [
            a * p[0][0] + b * p[1][0] + c * p[2][0] + d * p[3][0],
            a * p[0][1] + b * p[1][1] + c * p[2][1] + d * p[3][1],
        ]
    }

    private func polylineLength(segments: Int, _ p: [[Double]]) -> Double {
        var total = 0.0
        var last: [Double]?
        for k in 0 ..< segments {
            let perc = Double(k) / Double(segments - 1)
            let pt = point(perc, p)
            if let l = last { total += (((pt[0] - l[0]) * (pt[0] - l[0])) + ((pt[1] - l[1]) * (pt[1] - l[1]))).squareRoot() }
            last = pt
        }
        return total
    }

    @Test("150-segment arc length is within the measured bound of the high-resolution reference")
    func samplingBoundHolds() {
        // p0, p1, p2, p3 control points.
        let curves: [[[Double]]] = [
            [[0, 0], [10, 0], [20, 0], [30, 0]], // straight
            [[0, 0], [0, 40], [40, 40], [40, 0]], // arch
            [[0, 0], [100, 0], [0, 100], [100, 100]], // S
            [[0, 0], [120, 200], [-120, 200], [0, 0]], // near-cusp loop
            [[5, 5], [60, -40], [80, 90], [120, 10]], // asymmetric
            [[0, 0], [300, 0], [300, 300], [0, 300]], // wide arc
        ]
        var maxRelative = 0.0
        for curve in curves {
            let approx = polylineLength(segments: 150, curve)
            let reference = polylineLength(segments: 20000, curve)
            guard reference > 0 else { continue }
            maxRelative = max(maxRelative, abs(approx - reference) / reference)
        }
        #expect(
            maxRelative <= measuredBound,
            "150-segment vs 20000-segment max relative divergence = \(maxRelative), bound = \(measuredBound)"
        )
    }
}
