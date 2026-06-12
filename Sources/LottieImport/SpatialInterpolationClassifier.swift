//
//  SpatialInterpolationClassifier.swift
//  PureLottie
//

import LottieModel

enum SpatialInterpolationClassifier {
    private static let epsilon = 0.0001

    static func containsUnsupportedSpatialInterpolation(_ keyframes: [LottieKeyframe<[Double]>]) -> Bool {
        guard keyframes.count > 1 else { return false }
        return keyframes.indices.dropLast().contains { index in
            let keyframe = keyframes[index]
            guard let spatialOut = keyframe.spatialOut else { return false }
            let spatialIn = keyframe.spatialIn ?? []
            guard hasSpatialTangent(spatialOut) || hasSpatialTangent(spatialIn) else { return false }
            guard let start = keyframe.startValue, let end = keyframes[index + 1].startValue else {
                return true
            }
            return !isEffectivelyLinearSpatialSegment(
                start: start,
                end: end,
                spatialOut: spatialOut,
                spatialIn: spatialIn
            )
        }
    }

    private static func hasSpatialTangent(_ values: [Double]) -> Bool {
        values.contains { abs($0) > epsilon }
    }

    private static func isEffectivelyLinearSpatialSegment(
        start: [Double],
        end: [Double],
        spatialOut: [Double],
        spatialIn: [Double]
    ) -> Bool {
        switch start.count {
        case 2:
            isLinear2D(start: start, end: end, spatialOut: spatialOut, spatialIn: spatialIn)
        case 3:
            isLinear3D(start: start, end: end, spatialOut: spatialOut, spatialIn: spatialIn)
        default:
            false
        }
    }

    private static func isLinear2D(start: [Double], end: [Double], spatialOut: [Double], spatialIn: [Double]) -> Bool {
        guard
            let startX = start.exactComponent(0),
            let startY = start.exactComponent(1),
            let endX = end.exactComponent(0),
            let endY = end.exactComponent(1),
            let outX = spatialOut.exactComponent(0),
            let outY = spatialOut.exactComponent(1),
            let inX = spatialIn.exactComponent(0),
            let inY = spatialIn.exactComponent(1)
        else { return false }

        if approximatelyEqual(startX, endX), approximatelyEqual(startY, endY) {
            return approximatelyZero(outX) && approximatelyZero(outY)
                && approximatelyZero(inX) && approximatelyZero(inY)
        }

        return pointOnLine2D(startX, startY, endX, endY, startX + outX, startY + outY)
            && pointOnLine2D(startX, startY, endX, endY, endX + inX, endY + inY)
    }

    private static func isLinear3D(start: [Double], end: [Double], spatialOut: [Double], spatialIn: [Double]) -> Bool {
        guard
            let startX = start.exactComponent(0),
            let startY = start.exactComponent(1),
            let startZ = start.exactComponent(2),
            let endX = end.exactComponent(0),
            let endY = end.exactComponent(1),
            let endZ = end.exactComponent(2),
            let outX = spatialOut.exactComponent(0),
            let outY = spatialOut.exactComponent(1),
            let outZ = spatialOut.exactComponent(2),
            let inX = spatialIn.exactComponent(0),
            let inY = spatialIn.exactComponent(1),
            let inZ = spatialIn.exactComponent(2)
        else { return false }

        if approximatelyEqual(startX, endX), approximatelyEqual(startY, endY), approximatelyEqual(startZ, endZ) {
            return approximatelyZero(outX) && approximatelyZero(outY) && approximatelyZero(outZ)
                && approximatelyZero(inX) && approximatelyZero(inY) && approximatelyZero(inZ)
        }

        return pointOnLine3D(
            startX,
            startY,
            startZ,
            endX,
            endY,
            endZ,
            startX + outX,
            startY + outY,
            startZ + outZ
        )
            && pointOnLine3D(
                startX,
                startY,
                startZ,
                endX,
                endY,
                endZ,
                endX + inX,
                endY + inY,
                endZ + inZ
            )
    }

    private static func pointOnLine2D(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) -> Bool {
        let determinant = (x1 * y2) + (y1 * x3) + (x2 * y3) - (x3 * y2) - (y3 * x1) - (x2 * y1)
        return abs(determinant) < 0.001
    }

    private static func pointOnLine3D(
        _ x1: Double,
        _ y1: Double,
        _ z1: Double,
        _ x2: Double,
        _ y2: Double,
        _ z2: Double,
        _ x3: Double,
        _ y3: Double,
        _ z3: Double
    ) -> Bool {
        if approximatelyZero(z1), approximatelyZero(z2), approximatelyZero(z3) {
            return pointOnLine2D(x1, y1, x2, y2, x3, y3)
        }

        let dist1 = distance3D(x1, y1, z1, x2, y2, z2)
        let dist2 = distance3D(x1, y1, z1, x3, y3, z3)
        let dist3 = distance3D(x2, y2, z2, x3, y3, z3)
        let diffDist: Double = if dist1 > dist2 {
            if dist1 > dist3 {
                dist1 - dist2 - dist3
            } else {
                dist3 - dist2 - dist1
            }
        } else if dist3 > dist2 {
            dist3 - dist2 - dist1
        } else {
            dist2 - dist1 - dist3
        }
        return abs(diffDist) < 0.0001
    }

    private static func distance3D(
        _ x1: Double,
        _ y1: Double,
        _ z1: Double,
        _ x2: Double,
        _ y2: Double,
        _ z2: Double
    ) -> Double {
        let x = x2 - x1
        let y = y2 - y1
        let z = z2 - z1
        return (x * x + y * y + z * z).squareRoot()
    }

    private static func approximatelyEqual(_ left: Double, _ right: Double) -> Bool {
        abs(left - right) <= epsilon
    }

    private static func approximatelyZero(_ value: Double) -> Bool {
        abs(value) <= epsilon
    }
}

private extension [Double] {
    func exactComponent(_ index: Int) -> Double? {
        if indices.contains(index) { return self[index] }
        return nil
    }
}
