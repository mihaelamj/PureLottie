import Foundation
import LottieModel
import XCTest

/// Decode-strictness guards for keyframe easing and spatial tangents.
///
/// A keyframe's easing handles (`i`/`o`) and spatial tangents (`ti`/`to`)
/// control the interpolation curve. A malformed-but-present handle must surface
/// as a decode error, not be silently discarded: dropping it would substitute
/// linear timing for the authored curve and produce silently wrong animation
/// with no diagnostic. Absent handles remain a clean `nil`.
final class AnimatedValueDecodeTests: XCTestCase {
    private func decodeKeyframe(_ json: String) throws -> LottieKeyframe<[Double]> {
        try JSONDecoder().decode(LottieKeyframe<[Double]>.self, from: Data(json.utf8))
    }

    func testWellFormedEasingHandlesDecode() throws {
        let keyframe = try decodeKeyframe(#"{"t":0,"s":[0],"i":{"x":[0.5],"y":[0.5]},"o":{"x":[0.3],"y":[0.0]}}"#)
        XCTAssertEqual(keyframe.easeIn?.x, 0.5)
        XCTAssertEqual(keyframe.easeIn?.y, 0.5)
        XCTAssertEqual(keyframe.easeOut?.x, 0.3)
        XCTAssertEqual(keyframe.easeOut?.y, 0.0)
    }

    func testScalarEasingComponentsDecode() throws {
        // lottie-web also serializes handle components as scalars rather than arrays.
        let keyframe = try decodeKeyframe(#"{"t":0,"s":[0],"i":{"x":0.5,"y":0.5}}"#)
        XCTAssertEqual(keyframe.easeIn?.x, 0.5)
    }

    func testAbsentEasingAndTangentsAreNil() throws {
        let keyframe = try decodeKeyframe(#"{"t":0,"s":[0]}"#)
        XCTAssertNil(keyframe.easeIn)
        XCTAssertNil(keyframe.easeOut)
        XCTAssertNil(keyframe.spatialIn)
        XCTAssertNil(keyframe.spatialOut)
    }

    func testMalformedPresentEasingThrowsRatherThanSilentlyDropping() {
        // `i` is present but the wrong shape; it must throw, not become nil (linear).
        XCTAssertThrowsError(try decodeKeyframe(#"{"t":0,"s":[0],"i":"not-an-easing-handle"}"#))
        XCTAssertThrowsError(try decodeKeyframe(#"{"t":0,"s":[0],"o":42}"#))
    }

    func testMalformedSpatialTangentThrowsRatherThanSilentlyDropping() {
        XCTAssertThrowsError(try decodeKeyframe(#"{"t":0,"s":[0],"to":"not-an-array"}"#))
        XCTAssertThrowsError(try decodeKeyframe(#"{"t":0,"s":[0],"ti":{"x":1}}"#))
    }

    // MARK: Expression detection (`x`)

    func testPropertyExpressionIsDetected() throws {
        // An AfterEffects expression on `x` is not evaluated; it must be flagged so
        // the importer can report the gap instead of rendering the base value silently.
        let scalar = try JSONDecoder().decode(AnimatedDouble.self, from: Data(#"{"a":0,"k":50,"x":"$bm_rt = clamp(value, 0, 100);"}"#.utf8))
        XCTAssertTrue(scalar.hasExpression)
        XCTAssertEqual(scalar.initialValue, 50)

        let vector = try JSONDecoder().decode(AnimatedVector.self, from: Data(#"{"a":0,"k":[1,2],"x":"loopOut('cycle');"}"#.utf8))
        XCTAssertTrue(vector.hasExpression)
        XCTAssertEqual(vector.initialValue, [1, 2])
    }

    func testAbsentOrEmptyExpressionIsNotFlagged() throws {
        let noExpression = try JSONDecoder().decode(AnimatedDouble.self, from: Data(#"{"a":0,"k":50}"#.utf8))
        XCTAssertFalse(noExpression.hasExpression)

        let emptyExpression = try JSONDecoder().decode(AnimatedDouble.self, from: Data(#"{"a":0,"k":50,"x":""}"#.utf8))
        XCTAssertFalse(emptyExpression.hasExpression)
    }

    // MARK: Legacy item-level closed flag (`sh.closed`)

    private func decodePath(_ json: String) throws -> ShapePath {
        try JSONDecoder().decode(ShapePath.self, from: Data(json.utf8))
    }

    func testItemLevelClosedTrueFoldsIntoBezierWhenInnerFlagAbsent() throws {
        // Legacy bodymovin omits the bezier `c` and carries the closed flag at the
        // shape-item level. It must fold in so the closing segment is drawn.
        let path = try decodePath(#"{"ty":"sh","closed":true,"ks":{"a":0,"k":{"i":[[0,0]],"o":[[0,0]],"v":[[0,0]]}}}"#)
        XCTAssertEqual(path.shape.initialValue?.isClosed, true)
    }

    func testItemLevelClosedFalseFoldsIntoBezier() throws {
        let path = try decodePath(#"{"ty":"sh","closed":false,"ks":{"a":0,"k":{"i":[[0,0]],"o":[[0,0]],"v":[[0,0]]}}}"#)
        XCTAssertEqual(path.shape.initialValue?.isClosed, false)
    }

    func testInnerClosedFlagStillHonoredWithoutItemLevelFlag() throws {
        let path = try decodePath(#"{"ty":"sh","ks":{"a":0,"k":{"i":[[0,0]],"o":[[0,0]],"v":[[0,0]],"c":true}}}"#)
        XCTAssertEqual(path.shape.initialValue?.isClosed, true)
    }

    func testAbsentClosedFlagsDefaultToOpen() throws {
        let path = try decodePath(#"{"ty":"sh","ks":{"a":0,"k":{"i":[[0,0]],"o":[[0,0]],"v":[[0,0]]}}}"#)
        XCTAssertEqual(path.shape.initialValue?.isClosed, false)
    }

    func testRealGatinLegacyPathsDecodeAsClosed() throws {
        // gatin is a legacy export: all 36 paths carry item-level `closed` (30
        // true, 6 false) with no inner `c`. Before the fold-in fix every path
        // decoded open, dropping the closing segment and under-filling shapes.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/LottieCorpus/airbnb-lottie-web/demo/gatin/data.json")
        let animation = try LottieAnimation.decode(from: Data(contentsOf: url))
        var closedCount = 0
        var openCount = 0
        func walk(_ shapes: [LottieShape]) {
            for shape in shapes {
                switch shape {
                case let .group(group):
                    walk(group.items)
                case let .path(path):
                    if path.shape.initialValue?.isClosed == true { closedCount += 1 } else { openCount += 1 }
                default:
                    break
                }
            }
        }
        for layer in animation.layers {
            walk(layer.shapes ?? [])
        }
        XCTAssertEqual(closedCount, 30)
        XCTAssertEqual(openCount, 6)
    }
}
