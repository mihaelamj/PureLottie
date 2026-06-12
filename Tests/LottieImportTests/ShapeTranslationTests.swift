import Foundation
import LottieImport
import LottieModel
import PureLayer
import XCTest

final class ShapeTranslationTests: XCTestCase {
    func testLottieReverseStyleScopeLowersIntoPureLayerOrder() throws {
        let scene = try importScene("""
        {
          "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
          "layers": [{
            "ty": 4, "nm": "Shapes", "ind": 1, "ip": 0, "op": 30, "st": 0,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [
              { "ty": "rc", "nm": "Left", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "Red", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 },
              { "ty": "rc", "nm": "Right", "p": { "a": 0, "k": [30, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "Blue", "c": { "a": 0, "k": [0, 0, 1, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }],
          "assets": []
        }
        """)

        XCTAssertEqual(try shapeSnapshots(in: scene.root), [
            ShapeSnapshot(
                paint: .fill(red: 0, green: 0, blue: 1, alpha: 1),
                bounds: Bounds(minX: 5, minY: 5, maxX: 35, maxY: 15),
                strokeStart: 0,
                strokeEnd: 1
            ),
            ShapeSnapshot(
                paint: .fill(red: 1, green: 0, blue: 0, alpha: 1),
                bounds: Bounds(minX: 5, minY: 5, maxX: 15, maxY: 15),
                strokeStart: 0,
                strokeEnd: 1
            ),
        ])
    }

    func testOneGeometryFeedsEveryOpenStyle() throws {
        let scene = try importScene("""
        {
          "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
          "layers": [{
            "ty": 4, "nm": "Shapes", "ind": 1, "ip": 0, "op": 30, "st": 0,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [
              { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [20, 20] }, "s": { "a": 0, "k": [20, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "Red", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 },
              { "ty": "st", "nm": "Blue", "c": { "a": 0, "k": [0, 0, 1, 1] }, "o": { "a": 0, "k": 100 }, "w": { "a": 0, "k": 3 } }
            ]
          }],
          "assets": []
        }
        """)
        let bounds = Bounds(minX: 10, minY: 15, maxX: 30, maxY: 25)

        XCTAssertEqual(try shapeSnapshots(in: scene.root), [
            ShapeSnapshot(
                paint: .stroke(red: 0, green: 0, blue: 1, alpha: 1, width: 3),
                bounds: bounds,
                strokeStart: 0,
                strokeEnd: 1
            ),
            ShapeSnapshot(
                paint: .fill(red: 1, green: 0, blue: 0, alpha: 1),
                bounds: bounds,
                strokeStart: 0,
                strokeEnd: 1
            ),
        ])
    }

    func testGroupOpacityLowersToPureLayerContainer() throws {
        let scene = try importScene("""
        {
          "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
          "layers": [{
            "ty": 4, "nm": "Shapes", "ind": 1, "ip": 0, "op": 30, "st": 0,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [{
              "ty": "gr", "nm": "Half",
              "it": [
                { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
                { "ty": "fl", "nm": "Red", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 },
                { "ty": "tr", "a": { "a": 0, "k": [0, 0] }, "p": { "a": 0, "k": [0, 0] }, "s": { "a": 0, "k": [100, 100] }, "r": { "a": 0, "k": 0 }, "o": { "a": 0, "k": 50 } }
              ]
            }]
          }],
          "assets": []
        }
        """)

        let shapeLayer = try XCTUnwrap(allShapeLayers(in: scene.root).first)
        let opacityContainer = try XCTUnwrap(shapeLayer.superlayer)

        XCTAssertEqual(opacityContainer.opacity, 0.5, accuracy: 0.0001)
    }

    func testGroupTransformBakesIntoPureDrawPath() throws {
        let scene = try importScene("""
        {
          "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
          "layers": [{
            "ty": 4, "nm": "Shapes", "ind": 1, "ip": 0, "op": 30, "st": 0,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [{
              "ty": "gr", "nm": "Translated",
              "it": [
                { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
                { "ty": "fl", "nm": "Red", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 },
                { "ty": "tr", "a": { "a": 0, "k": [0, 0] }, "p": { "a": 0, "k": [20, 0] }, "s": { "a": 0, "k": [100, 100] }, "r": { "a": 0, "k": 0 }, "o": { "a": 0, "k": 100 } }
              ]
            }]
          }],
          "assets": []
        }
        """)

        let shapeLayer = try XCTUnwrap(allShapeLayers(in: scene.root).first)
        let box = try XCTUnwrap(shapeLayer.path?.boundingBox)

        XCTAssertEqual(box.minX, 25, accuracy: 0.0001)
        XCTAssertEqual(box.maxX, 35, accuracy: 0.0001)
    }

    func testParentStyleReceivesTransformedChildGeometry() throws {
        let scene = try importScene("""
        {
          "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
          "layers": [{
            "ty": 4, "nm": "Shapes", "ind": 1, "ip": 0, "op": 30, "st": 0,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [
              {
                "ty": "gr", "nm": "Moved",
                "it": [
                  { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
                  { "ty": "tr", "a": { "a": 0, "k": [0, 0] }, "p": { "a": 0, "k": [20, 0] }, "s": { "a": 0, "k": [100, 100] }, "r": { "a": 0, "k": 0 }, "o": { "a": 0, "k": 100 } }
                ]
              },
              { "ty": "fl", "nm": "ParentRed", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }],
          "assets": []
        }
        """)

        XCTAssertEqual(try shapeSnapshots(in: scene.root), [
            ShapeSnapshot(
                paint: .fill(red: 1, green: 0, blue: 0, alpha: 1),
                bounds: Bounds(minX: 25, minY: 5, maxX: 35, maxY: 15),
                strokeStart: 0,
                strokeEnd: 1
            ),
        ])
    }

    func testHiddenShapeItemsDoNotContributeDrawLayers() throws {
        let scene = try importScene("""
        {
          "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
          "layers": [{
            "ty": 4, "nm": "Shapes", "ind": 1, "ip": 0, "op": 30, "st": 0,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [
              { "ty": "rc", "nm": "Hidden", "hd": true, "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "HiddenFill", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 },
              { "ty": "rc", "nm": "Visible", "p": { "a": 0, "k": [30, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "VisibleFill", "c": { "a": 0, "k": [0, 0, 1, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }],
          "assets": []
        }
        """)

        let shapeLayers = allShapeLayers(in: scene.root)

        XCTAssertEqual(shapeLayers.count, 1)
        XCTAssertEqual(shapeLayers[0].fillColor?.blue, 1)
    }

    func testTrimmedFillIsReportedInsteadOfPretendingPureLayerCanTrimIt() throws {
        let scene = try importScene("""
        {
          "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
          "layers": [{
            "ty": 4, "nm": "Shapes", "ind": 1, "ip": 0, "op": 30, "st": 0,
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
        """)

        XCTAssertEqual(allShapeLayers(in: scene.root).count, 1)
        XCTAssertEqual(scene.report.findings.first?.feature, "trimmed fill path")
    }

    func testScalarKeyframeStartValuesDecodeForAnimatedOpacity() throws {
        let scene = try importScene("""
        {
          "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
          "layers": [{
            "ty": 4, "nm": "Shapes", "ind": 1, "ip": 0, "op": 30, "st": 0,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [
              { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "Fading", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 1, "k": [{ "t": 0, "s": 0, "h": 1 }, { "t": 10, "s": 100 }] }, "r": 1 }
            ]
          }],
          "assets": []
        }
        """)

        XCTAssertEqual(allShapeLayers(in: scene.root).count, 1)
        XCTAssertEqual(scene.report.findings.first?.feature, "animated fill opacity")
    }

    private func importScene(_ json: String) throws -> LottieScene {
        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        return LottieImporter().scene(from: animation)
    }

    private func allShapeLayers(in layer: Layer) -> [ShapeLayer] {
        var result: [ShapeLayer] = []
        if let shape = layer as? ShapeLayer {
            result.append(shape)
        }
        for sublayer in layer.sublayers {
            result.append(contentsOf: allShapeLayers(in: sublayer))
        }
        return result
    }

    private func shapeSnapshots(in layer: Layer) throws -> [ShapeSnapshot] {
        try allShapeLayers(in: layer).map { shapeLayer in
            let box = try XCTUnwrap(shapeLayer.path?.boundingBox)
            let paint: ShapePaint
            if let fill = shapeLayer.fillColor {
                paint = .fill(red: fill.red, green: fill.green, blue: fill.blue, alpha: fill.alpha)
            } else if let stroke = shapeLayer.strokeColor {
                paint = .stroke(red: stroke.red, green: stroke.green, blue: stroke.blue, alpha: stroke.alpha, width: shapeLayer.lineWidth)
            } else {
                XCTFail("Expected fill or stroke paint")
                paint = .fill(red: 0, green: 0, blue: 0, alpha: 0)
            }
            return ShapeSnapshot(
                paint: paint,
                bounds: Bounds(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY),
                strokeStart: shapeLayer.strokeStart,
                strokeEnd: shapeLayer.strokeEnd
            )
        }
    }

    private struct ShapeSnapshot: Equatable {
        var paint: ShapePaint
        var bounds: Bounds
        var strokeStart: Double
        var strokeEnd: Double
    }

    private enum ShapePaint: Equatable {
        case fill(red: Double, green: Double, blue: Double, alpha: Double)
        case stroke(red: Double, green: Double, blue: Double, alpha: Double, width: Double)
    }

    private struct Bounds: Equatable {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
    }
}
