import LottieModel
import XCTest

final class LottieValidationTests: XCTestCase {
    func testDefaultValidatorAcceptsSourceWithModeledSubsetOnly() throws {
        let data = Data("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": []
          }],
          "assets": []
        }
        """.utf8)

        XCTAssertNoThrow(try LottieAnimation.decodeValidated(from: data))
    }

    func testDuplicateKeysAreRejectedBeforeJSONDecoderCanOverwriteThem() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 30,
          "fr": 60,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": []
        }
        """)

        do {
            try document.validate(using: LottieValidator.blank.validating(\.objectKeysAreUnique))
            XCTFail("Expected duplicate-key validation to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertEqual(collection.values.map(\.ruleID), [
                "json.object.duplicate-key",
                "json.object.duplicate-key.first",
            ])
            XCTAssertEqual(collection.values[0].codingPath.description, "$.fr")
            XCTAssertEqual(collection.values[0].range?.start.line, 4)
            XCTAssertEqual(collection.values[1].severity, .note)
        }
    }

    func testRootTimingValidationUsesPositiveDescriptions() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 0,
          "ip": 20,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": []
        }
        """)

        do {
            try document.validate(using: LottieValidator.blank.validating(\.rootFrameRateIsPositive).validating(\.rootFrameWindowIsValid))
            XCTFail("Expected timing validation to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertEqual(collection.values.map(\.ruleID), [
                "lottie.root.frame-rate",
                "lottie.root.frame-window",
            ])
            XCTAssertEqual(
                String(describing: collection.values[1]),
                "Failed to satisfy: Root out point is greater than in point and `op` remains exclusive at path: $.op"
            )
        }
    }

    func testSilentRiskFieldsDroppedByModelAreValidationErrorsWithSourceRanges() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ao": 1,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 },
              "sk": { "a": 0, "k": 20 }
            },
            "shapes": [{
              "ty": "st",
              "nm": "Dashed stroke",
              "c": { "a": 0, "k": [1, 0, 0, 1] },
              "o": { "a": 0, "k": 100 },
              "w": { "a": 0, "k": 2 },
              "lc": 2,
              "d": []
            }]
          }],
          "assets": []
        }
        """)

        do {
            try document.validate()
            XCTFail("Expected default validation to throw on silent-risk fields.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertTrue(collection.values.contains { $0.ruleID == "lottie.layer.silent-risk-field" && $0.codingPath.description == "$.layers[0].ao" })
            XCTAssertTrue(collection.values.contains { $0.ruleID == "lottie.transform.silent-risk-field" && $0.codingPath.description == "$.layers[0].ks.sk" })
            XCTAssertTrue(collection.values.allSatisfy { $0.range != nil })
        }
    }

    func testModeledStrokeStyleFieldsPassSourceValidation() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [{
              "ty": "st",
              "nm": "Dashed stroke",
              "c": { "a": 0, "k": [1, 0, 0, 1] },
              "o": { "a": 0, "k": 100 },
              "w": { "a": 0, "k": 2 },
              "lc": 2,
              "lj": 3,
              "ml": 4,
              "ml2": { "a": 0, "k": 4 },
              "bm": 2,
              "d": [{ "n": "d", "v": { "a": 0, "k": 3 } }]
            }]
          }],
          "assets": []
        }
        """)

        try document.validate(using: LottieValidator.blank.validating(\.strokeStyleFieldsAreModeledOrReported))
        let animation = try document.decodeAnimation()
        guard case let .stroke(stroke) = animation.layers[0].shapes?[0] else {
            XCTFail("Expected stroke shape.")
            return
        }
        XCTAssertEqual(stroke.lineCap, 2)
        XCTAssertEqual(stroke.lineJoin, 3)
        XCTAssertEqual(stroke.miterLimit, 4)
        XCTAssertEqual(stroke.secondaryMiterLimit?.initialValue, 4)
        XCTAssertEqual(stroke.blendMode, 2)
        XCTAssertEqual(stroke.dashPattern?.first?.type, "d")
    }

    func testMalformedStrokeDashEntriesFailSourceValidation() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [{
              "ty": "st",
              "nm": "Bad dash stroke",
              "c": { "a": 0, "k": [1, 0, 0, 1] },
              "o": { "a": 0, "k": 100 },
              "w": { "a": 0, "k": 2 },
              "d": [{ "n": "bad" }, 2]
            }]
          }],
          "assets": []
        }
        """)

        do {
            try document.validate(using: LottieValidator.blank.validating(\.strokeStyleFieldsAreModeledOrReported))
            XCTFail("Expected malformed dash entries to fail validation.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertEqual(collection.values.map(\.reason), [
                "Stroke dash entry type `bad` must be one of d, g, or o.",
                "Stroke dash entry must declare value field `v`.",
                "Stroke dash entry must be an object.",
            ])
            XCTAssertEqual(collection.values.map(\.codingPath.description), [
                "$.layers[0].shapes[0].d[0].n",
                "$.layers[0].shapes[0].d[0].v",
                "$.layers[0].shapes[0].d[1]",
            ])
        }
    }

    func testLayerReferencesAreResolvedBeforeImport() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            {
              "ty": 4,
              "ind": 1,
              "parent": 99,
              "ip": 0,
              "op": 30,
              "ks": {},
              "shapes": []
            },
            {
              "ty": 0,
              "ind": 2,
              "refId": "missing",
              "ip": 0,
              "op": 30,
              "ks": {}
            }
          ],
          "assets": []
        }
        """)

        do {
            try document.validate(using: LottieValidator.blank.validating(\.layerParentReferencesResolve).validating(\.layerAssetReferencesResolve))
            XCTFail("Expected reference validation to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertEqual(collection.values.map(\.ruleID), [
                "lottie.layer.parent.missing",
                "lottie.layer.refId.missing",
            ])
            XCTAssertEqual(collection.values[0].codingPath.description, "$.layers[0].parent")
            XCTAssertEqual(collection.values[1].codingPath.description, "$.layers[1].refId")
        }
    }

    func testWithoutValidatingRemovesDefaultRulesByDescription() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{ "ty": 4, "ind": 1, "ip": 0, "op": 30, "ao": 1, "ks": {}, "shapes": [] }],
          "assets": []
        }
        """)

        XCTAssertThrowsError(try document.validate())

        let validator = LottieValidator()
            .withoutValidating(\.layerSilentRiskFieldsAreModeledOrReported)

        try document.validate(using: validator)
        XCTAssertFalse(validator.validationDescriptions.contains(BuiltinValidation.layerSilentRiskFieldsAreModeledOrReported.description))
    }

    func testValidatedDecodeRejectsInvalidSourceBeforeRawModelDecode() throws {
        let data = Data("""
        {
          "v": "5.7.4",
          "fr": 30,
          "fr": 60,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [],
          "assets": []
        }
        """.utf8)

        XCTAssertNoThrow(try LottieAnimation.decode(from: data))
        XCTAssertThrowsError(try LottieAnimation.decodeValidated(from: data))
    }
}
