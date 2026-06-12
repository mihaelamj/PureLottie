import Foundation
import LottieImport
import LottieModel
import PureLayer
import XCTest

final class ShapeSemanticOracleTests: XCTestCase {
    func testReferenceShapeScopeOracleMatchesImportedPureLayerSnapshots() throws {
        let cases: [OracleCase] = [
            OracleCase(
                name: "style after one geometry",
                items: [
                    .rect("Box", x: 10, y: 10, width: 10, height: 10),
                    .fill("Red", red: 1, green: 0, blue: 0),
                ]
            ),
            OracleCase(
                name: "style before geometry renders nothing",
                items: [
                    .fill("Red", red: 1, green: 0, blue: 0),
                    .rect("Box", x: 10, y: 10, width: 10, height: 10),
                ]
            ),
            OracleCase(
                name: "later style remains open across earlier geometry",
                items: [
                    .rect("Left", x: 10, y: 10, width: 10, height: 10),
                    .fill("Red", red: 1, green: 0, blue: 0),
                    .rect("Right", x: 30, y: 10, width: 10, height: 10),
                    .fill("Blue", red: 0, green: 0, blue: 1),
                ]
            ),
            OracleCase(
                name: "one geometry feeds fill and stroke",
                items: [
                    .rect("Box", x: 20, y: 20, width: 20, height: 10),
                    .fill("Red", red: 1, green: 0, blue: 0),
                    .stroke("Blue", red: 0, green: 0, blue: 1, width: 3),
                ]
            ),
            OracleCase(
                name: "hidden geometry does not feed open style",
                items: [
                    .rect("Hidden", x: 10, y: 10, width: 10, height: 10, hidden: true),
                    .rect("Visible", x: 30, y: 10, width: 10, height: 10),
                    .fill("Blue", red: 0, green: 0, blue: 1),
                ]
            ),
            OracleCase(
                name: "hidden style does not receive geometry",
                items: [
                    .rect("Box", x: 10, y: 10, width: 10, height: 10),
                    .fill("HiddenRed", red: 1, green: 0, blue: 0, hidden: true),
                ]
            ),
            OracleCase(
                name: "trim modifies open stroke",
                items: [
                    .rect("Box", x: 10, y: 10, width: 10, height: 10),
                    .trim("Half", start: 10, end: 60),
                    .stroke("Blue", red: 0, green: 0, blue: 1, width: 2),
                ]
            ),
            OracleCase(
                name: "parent style receives translated child geometry",
                items: [
                    .group(
                        "Moved",
                        items: [
                            .rect("Box", x: 10, y: 10, width: 10, height: 10),
                        ],
                        translateX: 20,
                        translateY: 0
                    ),
                    .fill("Red", red: 1, green: 0, blue: 0),
                ]
            ),
        ]

        for testCase in cases {
            let scene = try importScene(testCase.items)
            let actual = try importedSnapshots(in: scene.root)
            let expected = ReferenceShapeScopeOracle().snapshots(for: testCase.items)
            XCTAssertEqual(actual, expected, testCase.name)
        }
    }

    private func importScene(_ items: [OracleShapeItem]) throws -> LottieScene {
        let document: [String: Any] = [
            "v": "5.7.4",
            "fr": 30,
            "ip": 0,
            "op": 30,
            "w": 100,
            "h": 100,
            "assets": [],
            "layers": [[
                "ty": 4,
                "nm": "Shapes",
                "ind": 1,
                "ip": 0,
                "op": 30,
                "st": 0,
                "ks": [
                    "a": ["a": 0, "k": [0, 0]],
                    "p": ["a": 0, "k": [0, 0]],
                    "s": ["a": 0, "k": [100, 100]],
                    "r": ["a": 0, "k": 0],
                    "o": ["a": 0, "k": 100],
                ],
                "shapes": items.map(\.json),
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: document)
        let animation = try LottieAnimation.decode(from: data)
        return LottieImporter().scene(from: animation)
    }

    private func importedSnapshots(in layer: Layer) throws -> [OracleShapeSnapshot] {
        try allShapeLayers(in: layer).map { shapeLayer in
            let box = try XCTUnwrap(shapeLayer.path?.boundingBox)
            let paint: OraclePaint
            if let fill = shapeLayer.fillColor {
                paint = .fill(red: fill.red, green: fill.green, blue: fill.blue, alpha: fill.alpha)
            } else if let stroke = shapeLayer.strokeColor {
                paint = .stroke(red: stroke.red, green: stroke.green, blue: stroke.blue, alpha: stroke.alpha, width: shapeLayer.lineWidth)
            } else {
                XCTFail("Expected fill or stroke paint")
                paint = .fill(red: 0, green: 0, blue: 0, alpha: 0)
            }
            return OracleShapeSnapshot(
                paint: paint,
                bounds: OracleBounds(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY),
                strokeStart: shapeLayer.strokeStart,
                strokeEnd: shapeLayer.strokeEnd
            )
        }
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
}

private struct OracleCase {
    var name: String
    var items: [OracleShapeItem]
}

private enum OracleShapeItem {
    case rect(String, x: Double, y: Double, width: Double, height: Double, hidden: Bool = false)
    case fill(String, red: Double, green: Double, blue: Double, hidden: Bool = false)
    case stroke(String, red: Double, green: Double, blue: Double, width: Double, hidden: Bool = false)
    case trim(String, start: Double, end: Double, hidden: Bool = false)
    case group(String, items: [OracleShapeItem], translateX: Double = 0, translateY: Double = 0, hidden: Bool = false)

    var json: [String: Any] {
        switch self {
        case let .rect(name, x, y, width, height, hidden):
            return [
                "ty": "rc",
                "nm": name,
                "hd": hidden,
                "p": ["a": 0, "k": [x, y]],
                "s": ["a": 0, "k": [width, height]],
                "r": ["a": 0, "k": 0],
            ]
        case let .fill(name, red, green, blue, hidden):
            return [
                "ty": "fl",
                "nm": name,
                "hd": hidden,
                "c": ["a": 0, "k": [red, green, blue, 1]],
                "o": ["a": 0, "k": 100],
                "r": 1,
            ]
        case let .stroke(name, red, green, blue, width, hidden):
            return [
                "ty": "st",
                "nm": name,
                "hd": hidden,
                "c": ["a": 0, "k": [red, green, blue, 1]],
                "o": ["a": 0, "k": 100],
                "w": ["a": 0, "k": width],
            ]
        case let .trim(name, start, end, hidden):
            return [
                "ty": "tm",
                "nm": name,
                "hd": hidden,
                "s": ["a": 0, "k": start],
                "e": ["a": 0, "k": end],
                "o": ["a": 0, "k": 0],
                "m": 1,
            ]
        case let .group(name, items, translateX, translateY, hidden):
            var childItems = items.map(\.json)
            childItems.append([
                "ty": "tr",
                "nm": "Transform",
                "a": ["a": 0, "k": [0, 0]],
                "p": ["a": 0, "k": [translateX, translateY]],
                "s": ["a": 0, "k": [100, 100]],
                "r": ["a": 0, "k": 0],
                "o": ["a": 0, "k": 100],
            ])
            return [
                "ty": "gr",
                "nm": name,
                "hd": hidden,
                "it": childItems,
            ]
        }
    }

    var isHidden: Bool {
        switch self {
        case let .rect(_, _, _, _, _, hidden): hidden
        case let .fill(_, _, _, _, hidden): hidden
        case let .stroke(_, _, _, _, _, hidden): hidden
        case let .trim(_, _, _, hidden): hidden
        case let .group(_, _, _, _, hidden): hidden
        }
    }
}

private struct ReferenceShapeScopeOracle {
    func snapshots(for items: [OracleShapeItem]) -> [OracleShapeSnapshot] {
        nodes(
            for: items,
            inheritedStyles: [],
            inheritedTransform: .identity,
            inheritedTrim: nil
        )
        .flatMap(\.snapshots)
    }

    private func nodes(
        for items: [OracleShapeItem],
        inheritedStyles: [OracleStyleAccumulator],
        inheritedTransform: OracleTransform,
        inheritedTrim: OracleTrim?
    ) -> [OracleNode] {
        var result: [OracleNode] = []
        var activeStyles = inheritedStyles
        let activeTransform = inheritedTransform
        var activeTrim = inheritedTrim

        for item in items.reversed() where !item.isHidden {
            switch item {
            case let .rect(_, x, y, width, height, _):
                let bounds = OracleBounds(
                    minX: x - width / 2,
                    minY: y - height / 2,
                    maxX: x + width / 2,
                    maxY: y + height / 2
                )
                let transformed = bounds.applying(activeTransform)
                for style in activeStyles {
                    style.append(transformed, trim: activeTrim)
                }
            case let .fill(_, red, green, blue, _):
                let style = OracleStyleAccumulator(
                    paint: .fill(red: red, green: green, blue: blue, alpha: 1)
                )
                activeStyles.append(style)
                result.append(.style(style))
            case let .stroke(_, red, green, blue, width, _):
                let style = OracleStyleAccumulator(
                    paint: .stroke(red: red, green: green, blue: blue, alpha: 1, width: width)
                )
                activeStyles.append(style)
                result.append(.style(style))
            case let .trim(_, start, end, _):
                activeTrim = OracleTrim(start: start / 100, end: end / 100)
            case let .group(_, childItems, translateX, translateY, _):
                let childNodes = nodes(
                    for: childItems,
                    inheritedStyles: activeStyles,
                    inheritedTransform: OracleTransform(
                        translateX: activeTransform.translateX + translateX,
                        translateY: activeTransform.translateY + translateY
                    ),
                    inheritedTrim: activeTrim
                )
                result.append(.group(childNodes))
            }
        }

        return result
    }
}

private enum OracleNode {
    case style(OracleStyleAccumulator)
    case group([OracleNode])

    var snapshots: [OracleShapeSnapshot] {
        switch self {
        case let .style(style):
            style.snapshots()
        case let .group(nodes):
            nodes.flatMap(\.snapshots)
        }
    }
}

private final class OracleStyleAccumulator {
    private struct Run {
        var bounds: OracleBounds
        var trim: OracleTrim?
    }

    let paint: OraclePaint
    private var runs: [Run] = []

    init(paint: OraclePaint) {
        self.paint = paint
    }

    func append(_ bounds: OracleBounds, trim: OracleTrim?) {
        guard bounds.isValid else { return }
        if let last = runs.last, last.trim == trim {
            runs[runs.count - 1] = Run(bounds: last.bounds.union(bounds), trim: trim)
        } else {
            runs.append(Run(bounds: bounds, trim: trim))
        }
    }

    func snapshots() -> [OracleShapeSnapshot] {
        runs.map { run in
            let trim = paint.isStroke ? run.trim : nil
            return OracleShapeSnapshot(
                paint: paint,
                bounds: run.bounds,
                strokeStart: trim?.start ?? 0,
                strokeEnd: trim?.end ?? 1
            )
        }
    }
}

private struct OracleShapeSnapshot: Equatable {
    var paint: OraclePaint
    var bounds: OracleBounds
    var strokeStart: Double
    var strokeEnd: Double
}

private enum OraclePaint: Equatable {
    case fill(red: Double, green: Double, blue: Double, alpha: Double)
    case stroke(red: Double, green: Double, blue: Double, alpha: Double, width: Double)

    var isStroke: Bool {
        if case .stroke = self {
            return true
        }
        return false
    }
}

private struct OracleBounds: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var isValid: Bool {
        minX <= maxX && minY <= maxY
    }

    func applying(_ transform: OracleTransform) -> OracleBounds {
        OracleBounds(
            minX: minX + transform.translateX,
            minY: minY + transform.translateY,
            maxX: maxX + transform.translateX,
            maxY: maxY + transform.translateY
        )
    }

    func union(_ other: OracleBounds) -> OracleBounds {
        OracleBounds(
            minX: min(minX, other.minX),
            minY: min(minY, other.minY),
            maxX: max(maxX, other.maxX),
            maxY: max(maxY, other.maxY)
        )
    }
}

private struct OracleTransform {
    static let identity = OracleTransform(translateX: 0, translateY: 0)

    var translateX: Double
    var translateY: Double
}

private struct OracleTrim: Equatable {
    var start: Double
    var end: Double
}
