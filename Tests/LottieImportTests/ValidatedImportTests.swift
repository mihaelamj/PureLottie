import Foundation
import LottieImport
import LottieModel
import PureLayer
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

    func testImporterSamplesVectorEasingPerComponent() throws {
        let scene = try LottieImporter().scene(from: Data("""
        {
          "v": "5.7.4",
          "fr": 10,
          "ip": 0,
          "op": 10,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Moving",
            "ind": 1,
            "ip": 0,
            "op": 10,
            "st": 0,
            "ks": {
              "p": { "a": 1, "k": [
                {
                  "t": 0,
                  "s": [0, 0],
                  "e": [100, 100],
                  "o": { "x": [0, 0.333], "y": [0, 0] },
                  "i": { "x": [1, 0.667], "y": [1, 1] }
                },
                { "t": 10, "s": [100, 100] }
              ]},
              "o": { "a": 0, "k": 100 }
            },
            "shapes": []
          }],
          "assets": []
        }
        """.utf8))

        let layer = try XCTUnwrap(scene.root.sublayers.first)
        let x = try XCTUnwrap(layer.animation(forKey: "lottie.position.x") as? KeyframeAnimation)
        let y = try XCTUnwrap(layer.animation(forKey: "lottie.position.y") as? KeyframeAnimation)

        XCTAssertEqual(x.values, [0, 100])
        XCTAssertEqual(y.values.count, 9)
        XCTAssertEqual(y.keyTimes?[2], 0.25)
        XCTAssertEqual(y.values[2], 15.635546873187725, accuracy: 0.00001)
    }

    func testImporterDoesNotReportCollinearSpatialTangents() throws {
        let scene = try LottieImporter().scene(from: Data("""
        {
          "v": "5.7.4",
          "fr": 10,
          "ip": 0,
          "op": 10,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Moving",
            "ind": 1,
            "ip": 0,
            "op": 10,
            "st": 0,
            "ks": {
              "p": { "a": 1, "k": [
                { "t": 0, "s": [0, 0], "e": [100, 0], "to": [50, 0], "ti": [-50, 0] },
                { "t": 10, "s": [100, 0] }
              ]},
              "o": { "a": 0, "k": 100 }
            },
            "shapes": []
          }],
          "assets": []
        }
        """.utf8))

        XCTAssertTrue(scene.report.isClean)
    }

    func testImporterReportsCurvedSpatialTangents() throws {
        let scene = try LottieImporter().scene(from: Data("""
        {
          "v": "5.7.4",
          "fr": 10,
          "ip": 0,
          "op": 10,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Moving",
            "ind": 1,
            "ip": 0,
            "op": 10,
            "st": 0,
            "ks": {
              "p": { "a": 1, "k": [
                { "t": 0, "s": [0, 0], "e": [100, 0], "to": [50, 50], "ti": [-50, -50] },
                { "t": 10, "s": [100, 0] }
              ]},
              "o": { "a": 0, "k": 100 }
            },
            "shapes": []
          }],
          "assets": []
        }
        """.utf8))

        XCTAssertEqual(scene.report.findings.first?.feature, "spatial position curve (linearized)")
        XCTAssertEqual(scene.report.findings.first?.disposition, .approximated)
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
            "tt": 1,
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
            XCTAssertEqual(collection.values[0].codingPath.description, "$.layers[0].tt")
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
