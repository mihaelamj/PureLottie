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
}
