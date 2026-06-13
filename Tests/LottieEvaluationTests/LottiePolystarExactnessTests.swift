import Foundation
import LottieEvaluation
import LottieModel
import Testing

/// Bounded-exhaustive polygon and star exactness (issue #139, epic #137).
///
/// Sibling to the ellipse exactness test. The geometry evaluator's polygon and
/// star vertices are checked against an INDEPENDENT closed form derived from the
/// documented bodymovin/AE math (docs/lottie-format/bodymovin-source-semantics.md):
/// vertex i sits at angle `-pi/2 + rotation + (2*pi/count)*i*dir`, radius `or`
/// (polygon) or alternating `or`/`ir` (star, count = floor(pt)*2), offset by
/// position. Direction is fixed to 1 (dir = +1) across the grid to keep the
/// closed form unambiguous. lottie-web is not consulted; the documented math is
/// the spec, computed twice and required to agree to FP epsilon.
///
/// Status: theorem (bounded to the enumerated grid, to floating-point epsilon).
@Suite("Lottie polygon and star geometry exactness")
struct LottiePolystarExactnessTests {
    private struct ExtractionFailure: Error {}
    private let epsilon = 1e-9

    @Test("polygon vertices equal the closed form over a pinned grid")
    func polygonVerticesMatchClosedForm() throws {
        let pts = [3.0, 4, 5, 8]
        let radii = [30.0, 60]
        let rotations = [0.0, 25]
        let position = [10.0, 15]
        var checked = 0
        for pt in pts {
            for outerRadius in radii {
                for rotation in rotations {
                    let json = polystarJSON(starType: 2, pt: pt, cx: position[0], cy: position[1], rotation: rotation, or: outerRadius, ir: 0)
                    let trace = try evaluatePolystar(json)
                    let count = Int(pt)
                    let expected = closedForm(count: count, position: position, rotationDeg: rotation) { _ in outerRadius }
                    #expect(trace.vertices.count == count)
                    assertVertices(trace.vertices, equal: expected)
                    checked += 1
                }
            }
        }
        #expect(checked == 16, "pinned grid: 4 points x 2 radii x 2 rotations = 16 polygons")
    }

    @Test("star vertices equal the alternating-radius closed form over a pinned grid")
    func starVerticesMatchClosedForm() throws {
        let pts = [5.0, 6]
        let rotations = [0.0, 40]
        let outerRadius = 50.0
        let innerRadius = 25.0
        let position = [0.0, 0]
        var checked = 0
        for pt in pts {
            for rotation in rotations {
                let json = polystarJSON(starType: 1, pt: pt, cx: position[0], cy: position[1], rotation: rotation, or: outerRadius, ir: innerRadius)
                let trace = try evaluatePolystar(json)
                let count = Int(pt) * 2
                let expected = closedForm(count: count, position: position, rotationDeg: rotation) { index in
                    index.isMultiple(of: 2) ? outerRadius : innerRadius
                }
                #expect(trace.vertices.count == count)
                assertVertices(trace.vertices, equal: expected)
                checked += 1
            }
        }
        #expect(checked == 4, "pinned grid: 2 points x 2 rotations = 4 stars")
    }

    // MARK: Independent closed form (documented math, dir = +1)

    private func closedForm(count: Int, position: [Double], rotationDeg: Double, radius: (Int) -> Double) -> [[Double]] {
        let step = (2 * Double.pi) / Double(count)
        return (0 ..< count).map { index in
            let angle = -Double.pi / 2 + rotationDeg * Double.pi / 180 + step * Double(index)
            return [position[0] + radius(index) * cos(angle), position[1] + radius(index) * sin(angle)]
        }
    }

    private func assertVertices(_ actual: [[Double]], equal expected: [[Double]]) {
        #expect(actual.count == expected.count)
        for index in expected.indices where index < actual.count {
            #expect(abs(actual[index][0] - expected[index][0]) < epsilon)
            #expect(abs(actual[index][1] - expected[index][1]) < epsilon)
        }
    }

    private func evaluatePolystar(_ json: String) throws -> LottieSourceGeometryTrace {
        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        guard case let .polystar(polystar) = try #require(animation.layers.first?.shapes?.first) else {
            Issue.record("expected polystar shape")
            throw ExtractionFailure()
        }
        return LottieSourceGeometryEvaluator(animation: animation).evaluate(
            polystar,
            at: 0,
            sourcePath: "polystar",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0)])
        ).value
    }

    private func polystarJSON(starType: Int, pt: Double, cx: Double, cy: Double, rotation: Double, or: Double, ir: Double) -> String {
        let irFields = starType == 1 ? ",\"ir\":{\"a\":0,\"k\":\(ir)},\"is\":{\"a\":0,\"k\":0}" : ""
        return """
        {"v":"5.7.4","fr":30,"ip":0,"op":30,"w":400,"h":400,"layers":[{"ty":4,"ind":1,"ip":0,"op":30,"ks":{},"shapes":[{"ty":"sr","nm":"S","sy":\(starType),"d":1,"pt":{"a":0,"k":\(
            pt
        )},"p":{"a":0,"k":[\(cx),\(cy)]},"r":{"a":0,"k":\(rotation)},"or":{"a":0,"k":\(or)},"os":{"a":0,"k":0}\(irFields)}]}]}
        """
    }
}
