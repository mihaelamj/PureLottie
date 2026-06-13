import Foundation
import LottieEvaluation
import LottieModel
import Testing

/// Bounded-exhaustive geometry exactness (issue #139, epic #137).
///
/// The geometry evaluator's ellipse contour is checked against an INDEPENDENT
/// closed form derived from the documented bodymovin/AE math
/// (docs/lottie-format/bodymovin-source-semantics.md), not against lottie-web
/// traces. Over a pinned grid of centers and sizes, the four cardinal vertices
/// must equal center +/- size/2 exactly, the bounds must equal the bounding box,
/// and the round-corner constant must be exactly 0.5519 (the truncated AE value,
/// not the textbook circle constant 0.5522847). lottie-web stays a corroborating
/// witness elsewhere; here the documented math is the spec, computed twice and
/// required to agree.
///
/// Status: theorem (bounded to the enumerated grid, to floating-point epsilon).
@Suite("Lottie ellipse geometry exactness")
struct LottieEllipseExactnessTests {
    private struct ExtractionFailure: Error {}

    @Test("ellipse vertices, bounds, and round-corner constant equal the closed form over a pinned grid")
    func ellipseContourMatchesClosedForm() throws {
        let centers: [(Double, Double)] = [(0, 0), (10, 20), (-5, 7)]
        let sizes: [(Double, Double)] = [(2, 2), (40, 20), (100, 3)]
        let epsilon = 1e-9
        var checked = 0

        for (cx, cy) in centers {
            for (sx, sy) in sizes {
                let animation = try decode(ellipseJSON(cx: cx, cy: cy, sx: sx, sy: sy))
                let ellipse = try requireEllipse(animation)
                let trace = LottieSourceGeometryEvaluator(animation: animation).evaluate(
                    ellipse,
                    at: 0,
                    sourcePath: "ellipse",
                    jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0)])
                ).value

                let rx = sx / 2
                let ry = sy / 2
                // Documented closed form: 4 cardinal vertices, clockwise from noon.
                let expected = [
                    [cx, cy - ry], // top
                    [cx + rx, cy], // right
                    [cx, cy + ry], // bottom
                    [cx - rx, cy], // left
                ]
                #expect(trace.vertices.count == 4)
                for index in 0 ..< 4 {
                    #expect(abs(trace.vertices[index][0] - expected[index][0]) < epsilon)
                    #expect(abs(trace.vertices[index][1] - expected[index][1]) < epsilon)
                }
                #expect(abs(trace.bounds.minX - (cx - rx)) < epsilon)
                #expect(abs(trace.bounds.maxX - (cx + rx)) < epsilon)
                #expect(abs(trace.bounds.minY - (cy - ry)) < epsilon)
                #expect(abs(trace.bounds.maxY - (cy + ry)) < epsilon)
                #expect(trace.constants.first { $0.name == "roundCorner" }?.value == 0.5519)
                // Out-tangent magnitude at the top vertex is rx * roundCorner.
                #expect(abs(abs(trace.outTangents[0][0]) - rx * 0.5519) < epsilon)
                checked += 1
            }
        }
        #expect(checked == 9, "pinned grid: 3 centers x 3 sizes = 9 ellipses")
    }

    private func ellipseJSON(cx: Double, cy: Double, sx: Double, sy: Double) -> String {
        """
        {"v":"5.7.4","fr":30,"ip":0,"op":30,"w":200,"h":200,"layers":[{"ty":4,"ind":1,"ip":0,"op":30,"ks":{},"shapes":[{"ty":"el","nm":"E","p":{"a":0,"k":[\(cx),\(
            cy
        )]},"s":{"a":0,"k":[\(sx),\(sy)]}}]}]}
        """
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }

    private func requireEllipse(_ animation: LottieAnimation) throws -> ShapeEllipse {
        guard case let .ellipse(ellipse) = try #require(animation.layers.first?.shapes?.first) else {
            Issue.record("expected ellipse shape")
            throw ExtractionFailure()
        }
        return ellipse
    }
}
