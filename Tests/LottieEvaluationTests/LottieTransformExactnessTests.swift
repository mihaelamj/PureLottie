import Foundation
import LottieEvaluation
import LottieModel
import Testing

/// Bounded-exhaustive transform-matrix exactness (issue #139, epic #137).
///
/// Completes the numeric self-oracle's geometry/transform exactness. The layer
/// transform matrix is checked by its OBSERVABLE action on points against an
/// INDEPENDENT closed form derived from the documented bodymovin/AE order and
/// signs (docs/lottie-format/bodymovin-source-semantics.md): row-vector
/// translate(-anchor) . scale . rotateZ(-r) . translate(position), i.e. for a
/// point P:
///   q = (P - anchor); q = q .* (scale/100);
///   q = rotate(q, theta = -r_degrees) ; result = q + position.
/// Skew is fixed to 0 to keep the closed form unambiguous. lottie-web is not
/// consulted; the documented math is the spec, computed two ways, required to
/// agree to FP epsilon.
///
/// Status: theorem (bounded to the enumerated grid, to floating-point epsilon).
@Suite("Lottie transform matrix exactness")
struct LottieTransformExactnessTests {
    private let epsilon = 1e-9

    @Test("matrix action on points equals the closed form over a pinned grid")
    func transformMatrixMatchesClosedForm() throws {
        let anchors = [[0.0, 0, 0], [10, 20, 0]]
        let positions = [[0.0, 0, 0], [100, 50, 0]]
        let scales = [[100.0, 100, 100], [200, 50, 100]]
        let rotations = [0.0, 90, 45]
        let probes = [[0.0, 0, 0], [10, 20, 0], [-5, 7, 0], [30, 30, 0]]
        var checked = 0

        for anchor in anchors {
            for position in positions {
                for scale in scales {
                    for rotation in rotations {
                        let animation = try decode(transformJSON(anchor: anchor, position: position, scale: scale, rotation: rotation))
                        let layer = try #require(animation.layers.first)
                        let matrix = LottieTransformEvaluator(animation: animation).localTransform(
                            for: layer,
                            at: 0,
                            path: JSONPath([.key("layers"), .index(0)])
                        ).value.matrix

                        for probe in probes {
                            let actual = matrix.applying(to: probe)
                            let expected = closedForm(probe, anchor: anchor, position: position, scale: scale, rotationDeg: rotation)
                            #expect(abs(actual[0] - expected[0]) < epsilon, "x at \(probe) for r=\(rotation): \(actual) vs \(expected)")
                            #expect(abs(actual[1] - expected[1]) < epsilon, "y at \(probe) for r=\(rotation): \(actual) vs \(expected)")
                            checked += 1
                        }
                    }
                }
            }
        }
        #expect(checked == 96, "pinned grid: 2 anchors x 2 positions x 2 scales x 3 rotations x 4 probes = 96 checks")
    }

    private func closedForm(_ point: [Double], anchor: [Double], position: [Double], scale: [Double], rotationDeg: Double) -> [Double] {
        var qx = point[0] - anchor[0]
        var qy = point[1] - anchor[1]
        qx *= scale[0] / 100
        qy *= scale[1] / 100
        // Row-vector rotation (point * M, lottie-web convention), operand theta = -r.
        let theta = -rotationDeg * Double.pi / 180
        let rx = qx * cos(theta) + qy * sin(theta)
        let ry = -qx * sin(theta) + qy * cos(theta)
        return [rx + position[0], ry + position[1], 0]
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }

    private func transformJSON(anchor: [Double], position: [Double], scale: [Double], rotation: Double) -> String {
        """
        {"v":"5.7.4","fr":30,"ip":0,"op":20,"w":300,"h":300,"layers":[{"ty":4,"ind":1,"ip":0,"op":20,"ks":{"a":{"a":0,"k":[\(anchor[
            0
        ]),\(anchor[
            1
        ]),\(anchor[
            2
        ])]},"p":{"a":0,"k":[\(position[0]),\(position[1]),\(position[2])]},"s":{"a":0,"k":[\(scale[0]),\(scale[1]),\(scale[2])]},"r":{"a":0,"k":\(rotation)}},"shapes":[]}]}
        """
    }
}
