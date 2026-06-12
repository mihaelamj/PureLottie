import Foundation
import LottieImport
import LottieModel
import XCTest

final class ValidatedImportTests: XCTestCase {
    func testDataImportValidatesDecodesAndImports() throws {
        let scene = try LottieImporter().scene(from: Data("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Shapes",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "st": 0,
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
        """.utf8))

        XCTAssertEqual(scene.width, 64)
        XCTAssertEqual(scene.height, 64)
        XCTAssertEqual(scene.frameRate, 30)
        XCTAssertTrue(scene.report.isClean)
    }

    func testDataImportThrowsValidationErrorsBeforeImporterReport() throws {
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
            "nm": "Matte target",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ao": 1,
            "ks": {},
            "shapes": []
          }],
          "assets": []
        }
        """.utf8)

        do {
            _ = try LottieImporter().scene(from: data)
            XCTFail("Expected source validation to throw before import.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertEqual(collection.values.map(\.ruleID), ["lottie.layer.silent-risk-field"])
            XCTAssertEqual(collection.values[0].codingPath.description, "$.layers[0].ao")
        }
    }

    func testImportReportStillCapturesLoweringFindingsAfterValidationSucceeds() throws {
        let scene = try LottieImporter().scene(from: Data("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "nm": "Shapes",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "st": 0,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [
              { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "tm", "nm": "Half", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 50 }, "o": { "a": 0, "k": 0 }, "m": 1 },
              { "ty": "fl", "nm": "Red", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }],
          "assets": []
        }
        """.utf8))

        XCTAssertEqual(scene.report.findings.first?.feature, "trimmed fill path")
        XCTAssertEqual(scene.report.findings.first?.disposition, .skipped)
    }
}
