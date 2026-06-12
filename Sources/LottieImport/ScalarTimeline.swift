//
//  ScalarTimeline.swift
//  PureLottie
//

import LottieModel
import PureLayer

/// One point of a sampled scalar timeline, in seconds from the composition's
/// in-point.
struct TimelineSample: Equatable {
    var time: Double
    var value: Double
}

/// Converts Lottie scalar keyframes into PureLayer `KeyframeAnimation`s.
///
/// PureLayer keyframes interpolate linearly (no per-segment timing functions),
/// so Lottie's cubic-bezier easing is baked in by supersampling each eased
/// segment into dense linear sub-keyframes; hold keyframes become a value held
/// to just before the next key time.
enum ScalarTimeline {
    /// Interior samples baked into one eased segment.
    private static let easedSteps = 8
    /// The step used to fake a discontinuity with linear interpolation.
    static let holdEpsilon = 0.002

    /// Samples one dimension of the keyframes, in seconds relative to
    /// `startFrame`, applying `map` to every raw value (unit conversion).
    static func samples(
        from keyframes: [LottieKeyframe<[Double]>],
        dimension: Int,
        frameRate: Double,
        startFrame: Double,
        map: (Double) -> Double
    ) -> [TimelineSample] {
        guard frameRate > 0, !keyframes.isEmpty else { return [] }
        func seconds(_ frame: Double) -> Double {
            (frame - startFrame) / frameRate
        }

        var out: [TimelineSample] = []
        var carried = keyframes[0].startValue?.component(dimension) ?? 0
        for index in keyframes.indices {
            let keyframe = keyframes[index]
            let value0 = keyframe.startValue?.component(dimension) ?? carried
            guard index < keyframes.count - 1 else {
                out.append(TimelineSample(time: seconds(keyframe.time), value: map(value0)))
                break
            }
            let next = keyframes[index + 1]
            let value1 = next.startValue?.component(dimension)
                ?? keyframe.endValue?.component(dimension)
                ?? value0
            let time0 = seconds(keyframe.time)
            let time1 = seconds(next.time)
            out.append(TimelineSample(time: time0, value: map(value0)))
            if keyframe.isHold {
                out.append(TimelineSample(time: max(time0, time1 - holdEpsilon), value: map(value0)))
            } else if let easeOut = keyframe.easeOut, let easeIn = keyframe.easeIn, !isLinear(easeOut, easeIn, dimension: dimension) {
                for step in 1 ..< easedSteps {
                    let x = Double(step) / Double(easedSteps)
                    let y = easedProgress(at: x, c1: easeOut, c2: easeIn, dimension: dimension)
                    out.append(TimelineSample(time: time0 + (time1 - time0) * x, value: map(value0 + (value1 - value0) * y)))
                }
            }
            carried = value1
        }
        return out
    }

    /// A linear interpolation over the samples, held flat outside their range.
    static func interpolate(_ samples: [TimelineSample], at time: Double) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        for index in samples.indices.dropLast() {
            let a = samples[index]
            let b = samples[index + 1]
            if time >= a.time, time <= b.time {
                let span = b.time - a.time
                guard span > 0 else { return b.value }
                let fraction = (time - a.time) / span
                return a.value + (b.value - a.value) * fraction
            }
        }
        return last.value
    }

    /// Gates the samples to a visibility window: 0 before `window.start`, the
    /// sampled value inside, 0 from `window.end` on. Edges are faked with
    /// `holdEpsilon` linear steps.
    static func gated(
        _ samples: [TimelineSample],
        window: (start: Double, end: Double),
        duration: Double
    ) -> [TimelineSample] {
        var out: [TimelineSample] = []
        if window.start > 0 {
            out.append(TimelineSample(time: 0, value: 0))
            out.append(TimelineSample(time: max(0, window.start - holdEpsilon), value: 0))
        }
        out.append(TimelineSample(time: window.start, value: interpolate(samples, at: window.start)))
        for sample in samples where sample.time > window.start && sample.time < window.end - holdEpsilon {
            out.append(sample)
        }
        if window.end < duration {
            out.append(TimelineSample(time: window.end - holdEpsilon, value: interpolate(samples, at: window.end - holdEpsilon)))
            out.append(TimelineSample(time: window.end, value: 0))
            out.append(TimelineSample(time: duration, value: 0))
        } else {
            out.append(TimelineSample(time: window.end, value: interpolate(samples, at: window.end)))
        }
        return out
    }

    /// A `KeyframeAnimation` spanning the whole scene, with key times
    /// normalized over `sceneDuration` and the first/last values pinned at the
    /// scene boundaries so `fillMode` never has to extrapolate.
    static func animation(
        keyPath: String,
        samples: [TimelineSample],
        sceneDuration: Double,
        beginTime: Double = 0
    ) -> KeyframeAnimation? {
        guard sceneDuration > 0, samples.count >= 2 else { return nil }
        var padded = samples
        if let first = samples.first, first.time > 0 {
            padded.insert(TimelineSample(time: 0, value: first.value), at: 0)
        }
        if let last = padded.last, last.time < sceneDuration {
            padded.append(TimelineSample(time: sceneDuration, value: last.value))
        }
        let animation = KeyframeAnimation(keyPath: keyPath, timing: Timing(beginTime: beginTime, duration: sceneDuration, fillMode: .both))
        animation.values = padded.map(\.value)
        animation.keyTimes = padded.map { min(max($0.time / sceneDuration, 0), 1) }
        animation.calculationMode = .linear
        return animation
    }

    private static func isLinear(_ easeOut: EasingHandle, _ easeIn: EasingHandle, dimension: Int) -> Bool {
        abs(easeOut.xComponent(dimension) - easeOut.yComponent(dimension)) < 0.0001
            && abs(easeIn.xComponent(dimension) - easeIn.yComponent(dimension)) < 0.0001
    }

    /// The eased value fraction at time fraction `x`, on the cubic bezier
    /// through (0,0), `c1`, `c2`, (1,1). `x(u)` is monotonic for valid easing
    /// handles, so `u` is recovered by bisection.
    private static func easedProgress(at x: Double, c1: EasingHandle, c2: EasingHandle, dimension: Int) -> Double {
        func coordinate(_ p1: Double, _ p2: Double, _ u: Double) -> Double {
            // Cubic bezier with endpoints 0 and 1.
            let inverse = 1 - u
            return 3 * inverse * inverse * u * p1 + 3 * inverse * u * u * p2 + u * u * u
        }
        var low = 0.0
        var high = 1.0
        for _ in 0 ..< 24 {
            let mid = (low + high) / 2
            if coordinate(c1.xComponent(dimension), c2.xComponent(dimension), mid) < x {
                low = mid
            } else {
                high = mid
            }
        }
        let u = (low + high) / 2
        return coordinate(c1.yComponent(dimension), c2.yComponent(dimension), u)
    }
}

extension [Double] {
    /// The value at `index`, or the last component when the vector is shorter
    /// (Lottie scalars often arrive as single-element arrays).
    func component(_ index: Int) -> Double? {
        if indices.contains(index) { return self[index] }
        return last
    }
}
