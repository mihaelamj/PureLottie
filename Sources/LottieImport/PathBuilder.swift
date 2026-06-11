//
//  PathBuilder.swift
//  PureLottie
//

import LottieModel
import PureLayer

/// Builds PureDraw paths from Lottie geometry.
enum PathBuilder {
    /// The bezier as a path. Lottie tangents are relative to their vertex; the
    /// segment `n -> n+1` uses controls `v[n] + out[n]` and `v[n+1] + in[n+1]`.
    static func path(from bezier: LottieBezier, into path: inout Path) {
        let vertices = bezier.vertices.map(point)
        guard let first = vertices.first else { return }
        path.move(to: first)
        for index in 0 ..< max(vertices.count - 1, 0) {
            addSegment(from: index, to: index + 1, bezier: bezier, vertices: vertices, into: &path)
        }
        if bezier.isClosed, vertices.count > 1 {
            addSegment(from: vertices.count - 1, to: 0, bezier: bezier, vertices: vertices, into: &path)
            path.closeSubpath()
        }
    }

    /// A rectangle primitive: centered on `position`, optionally rounded.
    static func rectangle(_ shape: ShapeRectangle, into path: inout Path) {
        let size = shape.size.initialValue
        let center = shape.position.initialValue
        let width = size.component(0) ?? 0
        let height = size.component(1) ?? 0
        let rect = Rect(
            x: (center.component(0) ?? 0) - width / 2,
            y: (center.component(1) ?? 0) - height / 2,
            width: width,
            height: height
        )
        let roundness = min(shape.roundness?.initialValue ?? 0, min(width, height) / 2)
        if roundness > 0 {
            path.addRoundedRect(in: rect, cornerWidth: roundness, cornerHeight: roundness)
        } else {
            path.addRect(rect)
        }
    }

    /// An ellipse primitive, centered on `position`.
    static func ellipse(_ shape: ShapeEllipse, into path: inout Path) {
        let size = shape.size.initialValue
        let center = shape.position.initialValue
        let width = size.component(0) ?? 0
        let height = size.component(1) ?? 0
        path.addEllipse(in: Rect(
            x: (center.component(0) ?? 0) - width / 2,
            y: (center.component(1) ?? 0) - height / 2,
            width: width,
            height: height
        ))
    }

    private static func addSegment(from: Int, to: Int, bezier: LottieBezier, vertices: [Point], into path: inout Path) {
        let outTangent = bezier.outTangents.indices.contains(from) ? bezier.outTangents[from] : []
        let inTangent = bezier.inTangents.indices.contains(to) ? bezier.inTangents[to] : []
        let outX = outTangent.component(0) ?? 0
        let outY = outTangent.component(1) ?? 0
        let inX = inTangent.component(0) ?? 0
        let inY = inTangent.component(1) ?? 0
        if abs(outX) < 0.0001, abs(outY) < 0.0001, abs(inX) < 0.0001, abs(inY) < 0.0001 {
            path.addLine(to: vertices[to])
        } else {
            path.addCurve(
                to: vertices[to],
                control1: Point(x: vertices[from].x + outX, y: vertices[from].y + outY),
                control2: Point(x: vertices[to].x + inX, y: vertices[to].y + inY)
            )
        }
    }

    private static func point(_ components: [Double]) -> Point {
        Point(x: components.component(0) ?? 0, y: components.component(1) ?? 0)
    }
}
