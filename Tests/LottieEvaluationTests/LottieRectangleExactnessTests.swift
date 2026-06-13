import Foundation
import LottieEvaluation
import LottieModel
import Testing

/// Bounded-exhaustive rectangle exactness (issue #139, epic #137).
///
/// Sibling to the ellipse/polystar/transform exactness tests. The geometry
/// evaluator's non-rounded rectangle (`r = 0`) vertices are checked against an
/// INDEPENDENT closed form from the documented bodymovin/AE math: for direction
/// 1 (clockwise) the contour starts at the right-top corner and proceeds
/// right-top -> right-bottom -> left-bottom -> left-top, each at center +/-
/// size/2. Rounding is fixed to 0 to keep the closed form unambiguous (the
/// rounded form adds eight vertices with radius handles). lottie-web is not
/// consulted; the documented math is the spec, computed twice, required to agree
/// to FP epsilon.
///
/// Status: sampled (a pinned grid of points, to floating-point epsilon). The
/// closed form is exact for all inputs by construction; this samples the
/// implementation's agreement with it at the enumerated points, it does not
/// exhaustively enumerate the continuous parameter space.
@Suite("Lottie rectangle geometry exactness")
struct LottieRectangleExactnessTests {
    private struct ExtractionFailure: Error {}
    private let epsilon = 1e-9

    @Test("non-rounded rectangle vertices and bounds equal the closed form over a pinned grid")
    func rectangleContourMatchesClosedForm() throws {
        let centers: [(Double, Double)] = [(0, 0), (50, 50), (-10, 5)]
        let sizes: [(Double, Double)] = [(2, 2), (40, 20), (100, 3)]
        var checked = 0

        for (cx, cy) in centers {
            for (sx, sy) in sizes {
                let trace = try evaluateRectangle(rectangleJSON(cx: cx, cy: cy, sx: sx, sy: sy))
                let hw = sx / 2
                let hh = sy / 2
                // Documented closed form, direction 1 (clockwise from right-top).
                let expected = [
                    [cx + hw, cy - hh], // right-top
                    [cx + hw, cy + hh], // right-bottom
                    [cx - hw, cy + hh], // left-bottom
                    [cx - hw, cy - hh], // left-top
                ]
                #expect(trace.vertices.count == 4)
                for index in 0 ..< 4 {
                    #expect(abs(trace.vertices[index][0] - expected[index][0]) < epsilon)
                    #expect(abs(trace.vertices[index][1] - expected[index][1]) < epsilon)
                }
                #expect(abs(trace.bounds.minX - (cx - hw)) < epsilon)
                #expect(abs(trace.bounds.maxX - (cx + hw)) < epsilon)
                #expect(abs(trace.bounds.minY - (cy - hh)) < epsilon)
                #expect(abs(trace.bounds.maxY - (cy + hh)) < epsilon)
                checked += 1
            }
        }
        #expect(checked == 9, "pinned grid: 3 centers x 3 sizes = 9 rectangles")
    }

    private func evaluateRectangle(_ json: String) throws -> LottieSourceGeometryTrace {
        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        guard case let .rectangle(rectangle) = try #require(animation.layers.first?.shapes?.first) else {
            Issue.record("expected rectangle shape")
            throw ExtractionFailure()
        }
        return LottieSourceGeometryEvaluator(animation: animation).evaluate(
            rectangle,
            at: 0,
            sourcePath: "rectangle",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0)])
        ).value
    }

    private func rectangleJSON(cx: Double, cy: Double, sx: Double, sy: Double) -> String {
        """
        {"v":"5.7.4","fr":30,"ip":0,"op":30,"w":300,"h":300,"layers":[{"ty":4,"ind":1,"ip":0,"op":30,"ks":{},"shapes":[{"ty":"rc","nm":"R","d":1,"p":{"a":0,"k":[\(cx),\(
            cy
        )]},"s":{"a":0,"k":[\(sx),\(sy)]},"r":{"a":0,"k":0}}]}]}
        """
    }
}
