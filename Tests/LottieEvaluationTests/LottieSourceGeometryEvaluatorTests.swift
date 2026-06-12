import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie source geometry evaluator")
struct LottieSourceGeometryEvaluatorTests {
    @Test("ellipse expands from noon with lottie-web round corner constant")
    func ellipseExpandsFromNoon() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              { "ty": "el", "nm": "Ellipse", "p": { "a": 0, "k": [10, 20] }, "s": { "a": 0, "k": [40, 20] } }
            ]
          }]
        }
        """)
        let ellipse = try requireEllipse(animation, shapeIndex: 0)

        let trace = LottieSourceGeometryEvaluator(animation: animation).evaluate(
            ellipse,
            at: 0,
            sourcePath: "root > layer 'Shapes' > ellipse 'Ellipse'",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0)])
        ).value

        #expect(trace.kind == .ellipse)
        #expect(trace.primitive == "el")
        #expect(trace.direction.effectiveValue == 1)
        #expect(trace.direction.defaulted)
        #expect(trace.vertices.count == 4)
        expectVector(trace.vertices[0], equals: [10, 10])
        expectVector(trace.vertices[1], equals: [30, 20])
        expectVector(trace.vertices[2], equals: [10, 30])
        expectVector(trace.vertices[3], equals: [-10, 20])
        expectVector(trace.outTangents[0], equals: [11.038, 0])
        #expect(trace.constants.first { $0.name == "roundCorner" }?.value == 0.5519)
        expectBounds(trace.bounds, minX: -10, minY: 10, maxX: 30, maxY: 30)
    }

    @Test("rectangle records lottie-web direction branch and radius clamp")
    func rectangleRecordsDirectionAndRadiusClamp() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              { "ty": "rc", "nm": "Square", "d": 1, "p": { "a": 0, "k": [50, 50] }, "s": { "a": 0, "k": [40, 20] }, "r": { "a": 0, "k": 0 } },
              { "ty": "rc", "nm": "Rounded", "p": { "a": 0, "k": [50, 50] }, "s": { "a": 0, "k": [40, 20] }, "r": { "a": 0, "k": 30 } }
            ]
          }]
        }
        """)
        let square = try requireRectangle(animation, shapeIndex: 0)
        let rounded = try requireRectangle(animation, shapeIndex: 1)
        let evaluator = LottieSourceGeometryEvaluator(animation: animation)

        let squareTrace = evaluator.evaluate(
            square,
            at: 0,
            sourcePath: "root > layer 'Shapes' > rectangle 'Square'",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0)])
        ).value
        let roundedTrace = evaluator.evaluate(
            rounded,
            at: 0,
            sourcePath: "root > layer 'Shapes' > rectangle 'Rounded'",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(1)])
        ).value

        #expect(squareTrace.direction.effectiveValue == 1)
        #expect(!squareTrace.direction.isReversed)
        expectVector(squareTrace.vertices[0], equals: [70, 40])
        expectVector(squareTrace.vertices[1], equals: [70, 60])
        expectVector(squareTrace.vertices[2], equals: [30, 60])
        expectVector(squareTrace.vertices[3], equals: [30, 40])

        #expect(roundedTrace.direction.effectiveValue == 3)
        #expect(roundedTrace.direction.isReversed)
        #expect(roundedTrace.direction.defaulted)
        #expect(roundedTrace.constants.first { $0.name == "radiusClamp" }?.value == 10)
        expectVector(roundedTrace.vertices[0], equals: [70, 50])
        expectVector(roundedTrace.vertices[1], equals: [60, 40])
        expectVector(roundedTrace.outTangents[0], equals: [0, 0])
        expectVector(roundedTrace.inTangents[1], equals: [0, 0])
    }

    @Test("raw Bezier path preserves authored vertices and records direction without reordering")
    func rawBezierPreservesAuthoredVertices() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              {
                "ty": "sh",
                "nm": "Open",
                "d": 3,
                "ks": {
                  "a": 0,
                  "k": {
                    "c": false,
                    "v": [[0, 0], [10, 0], [10, 10]],
                    "i": [[0, 0], [0, 0], [0, 0]],
                    "o": [[0, 0], [0, 0], [0, 0]]
                  }
                }
              }
            ]
          }]
        }
        """)
        let path = try requirePath(animation, shapeIndex: 0)

        let trace = LottieSourceGeometryEvaluator(animation: animation).evaluate(
            path,
            at: 0,
            sourcePath: "root > layer 'Shapes' > path 'Open'",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0)])
        ).value

        #expect(trace.kind == .path)
        #expect(!trace.isClosed)
        #expect(trace.direction.effectiveValue == 3)
        #expect(trace.direction.isReversed)
        #expect(!trace.direction.affectsContour)
        #expect(trace.vertices == [[0, 0], [10, 0], [10, 10]])
    }

    @Test("Bezier bounds use cubic extrema without treating off-curve controls as bounds")
    func bezierBoundsUseCubicExtremaWithoutOffCurveControls() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              {
                "ty": "sh",
                "nm": "Curve",
                "ks": {
                  "a": 0,
                  "k": {
                    "c": false,
                    "v": [[0, 0], [1, 0]],
                    "i": [[0, 0], [0, 10]],
                    "o": [[0, 10], [0, 0]]
                  }
                }
              }
            ]
          }]
        }
        """)
        let path = try requirePath(animation, shapeIndex: 0)

        let trace = LottieSourceGeometryEvaluator(animation: animation).evaluate(
            path,
            at: 0,
            sourcePath: "root > layer 'Shapes' > path 'Curve'",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0)])
        ).value

        expectVector(trace.absoluteOutTangents[0], equals: [0, 10])
        expectVector(trace.absoluteInTangents[1], equals: [1, 10])
        expectBounds(trace.bounds, minX: 0, minY: 0, maxX: 1, maxY: 7.5)
    }

    @Test("polygon and star expand with lottie-web rotation and point floor semantics")
    func polystarsExpandWithLottieWebSemantics() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              { "ty": "sr", "nm": "Polygon", "sy": 2, "d": 1, "pt": { "a": 0, "k": 4.9 }, "p": { "a": 0, "k": [0, 0] }, "r": { "a": 0, "k": 0 }, "or": { "a": 0, "k": 10 }, "os": { "a": 0, "k": 0 } },
              { "ty": "sr", "nm": "Star", "sy": 1, "d": 1, "pt": { "a": 0, "k": 5 }, "p": { "a": 0, "k": [0, 0] }, "r": { "a": 0, "k": 0 }, "or": { "a": 0, "k": 10 }, "os": { "a": 0, "k": 0 }, "ir": { "a": 0, "k": 5 }, "is": { "a": 0, "k": 0 } }
            ]
          }]
        }
        """)
        let polygon = try requirePolystar(animation, shapeIndex: 0)
        let star = try requirePolystar(animation, shapeIndex: 1)
        let evaluator = LottieSourceGeometryEvaluator(animation: animation)

        let polygonTrace = evaluator.evaluate(
            polygon,
            at: 0,
            sourcePath: "root > layer 'Shapes' > polystar 'Polygon'",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0)])
        ).value
        let starTrace = evaluator.evaluate(
            star,
            at: 0,
            sourcePath: "root > layer 'Shapes' > polystar 'Star'",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(1)])
        ).value

        #expect(polygonTrace.kind == .polygon)
        #expect(polygonTrace.vertices.count == 4)
        #expect(polygonTrace.constants.first { $0.name == "pointsFloor" }?.value == 4)
        expectVector(polygonTrace.vertices[0], equals: [0, -10])
        expectVector(polygonTrace.vertices[1], equals: [10, 0])
        expectVector(polygonTrace.vertices[2], equals: [0, 10])
        expectVector(polygonTrace.vertices[3], equals: [-10, 0])

        #expect(starTrace.kind == .star)
        #expect(starTrace.vertices.count == 10)
        expectVector(starTrace.vertices[0], equals: [0, -10])
        expectVector(starTrace.vertices[1], equals: [2.938926261462366, -4.045084971874737])
    }

    @Test("missing polystar point field reports only the missing source field")
    func missingPolystarPointFieldReportsOnlyMissingField() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              { "ty": "sr", "nm": "Polygon", "sy": 2, "p": { "a": 0, "k": [0, 0] }, "r": { "a": 0, "k": 0 }, "or": { "a": 0, "k": 10 }, "os": { "a": 0, "k": 0 } }
            ]
          }]
        }
        """)
        let polygon = try requirePolystar(animation, shapeIndex: 0)

        let diagnostics = LottieSourceGeometryEvaluator(animation: animation).evaluate(
            polygon,
            at: 0,
            sourcePath: "root > layer 'Shapes' > polystar 'Polygon'",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes"), .index(0)])
        ).diagnostics

        #expect(diagnostics.map(\.ruleID) == ["lottie.evaluation.geometry.required-field"])
        #expect(diagnostics.first?.codingPath.description == "$.layers[0].shapes[0].pt")
    }

    @Test("RenderIR carries expanded source geometry beside the compatibility payload")
    func renderIRCarriesSourceGeometry() throws {
        let animation = try decode("""
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
            "ks": {},
            "shapes": [
              { "ty": "sr", "nm": "Polygon", "sy": 2, "pt": { "a": 0, "k": 4 }, "p": { "a": 0, "k": [0, 0] }, "r": { "a": 0, "k": 0 }, "or": { "a": 0, "k": 10 }, "os": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "Fill", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }]
        }
        """)

        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 0)
        let shapeNode = try #require(frame.nodes.first)
        guard case let .shape(shape) = shapeNode.kind else {
            Issue.record("Expected a shape node.")
            return
        }
        let fragment = try #require(shape.draws.first?.fragments.first)

        #expect(fragment.sourceGeometry.kind == .polygon)
        #expect(fragment.sourceGeometry.primitive == "sr")
        expectVector(fragment.sourceGeometry.vertices[0], equals: [0, -10])
        guard case let .path(bezier) = fragment.geometry else {
            Issue.record("Expected polystar compatibility payload to be a path.")
            return
        }
        #expect(bezier.vertices == fragment.sourceGeometry.vertices)
    }

    @Test("RenderIR records one source path morph diagnostic for animated Bezier geometry")
    func renderIRDoesNotDuplicatePathMorphDiagnostics() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Shapes",
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {},
            "shapes": [
              {
                "ty": "sh",
                "nm": "Morph",
                "ks": { "k": [
                  { "t": 0, "s": [{ "i": [[0, 0]], "o": [[0, 0]], "v": [[0, 0]], "c": false }], "e": [{ "i": [[0, 0]], "o": [[0, 0]], "v": [[10, 10]], "c": false }] },
                  { "t": 10, "s": [{ "i": [[0, 0]], "o": [[0, 0]], "v": [[10, 10]], "c": false }] }
                ]}
              },
              { "ty": "fl", "nm": "Fill", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }]
        }
        """)

        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 5)
        let sourceMorphDiagnostics = frame.diagnostics.filter {
            $0.ruleID == "lottie.evaluation.path-morph.unsupported"
        }

        #expect(sourceMorphDiagnostics.count == 1)
    }

    @Test("RenderIR samples animated polystar source geometry without static-import gap")
    func renderIRSamplesAnimatedPolystarGeometry() throws {
        let animation = try decode("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 20,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Shapes",
            "ind": 1,
            "ip": 0,
            "op": 20,
            "ks": {},
            "shapes": [
              {
                "ty": "sr",
                "nm": "Moving Polygon",
                "sy": 2,
                "pt": { "a": 0, "k": 4 },
                "p": { "a": 1, "k": [
                  { "t": 0, "s": [0, 0], "e": [10, 0], "o": { "x": 0, "y": 0 }, "i": { "x": 1, "y": 1 } },
                  { "t": 10, "s": [10, 0] }
                ]},
                "r": { "a": 0, "k": 0 },
                "or": { "a": 0, "k": 10 },
                "os": { "a": 0, "k": 0 }
              },
              { "ty": "fl", "nm": "Fill", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }]
        }
        """)

        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 5)
        let shapeNode = try #require(frame.nodes.first)
        guard case let .shape(shape) = shapeNode.kind else {
            Issue.record("Expected a shape node.")
            return
        }
        let fragment = try #require(shape.draws.first?.fragments.first)

        expectVector(fragment.sourceGeometry.vertices[0], equals: [5, -10])
        #expect(frame.diagnostics.allSatisfy { $0.ruleID != "lottie.evaluation.shape.polystar.animated-geometry.unsupported" })
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }

    private func firstShape(_ animation: LottieAnimation, shapeIndex: Int) throws -> LottieShape {
        try #require(animation.layers.first?.shapes?[shapeIndex])
    }

    private func requireEllipse(_ animation: LottieAnimation, shapeIndex: Int) throws -> ShapeEllipse {
        guard case let .ellipse(ellipse) = try firstShape(animation, shapeIndex: shapeIndex) else {
            Issue.record("Expected ellipse shape.")
            throw TestFailure()
        }
        return ellipse
    }

    private func requireRectangle(_ animation: LottieAnimation, shapeIndex: Int) throws -> ShapeRectangle {
        guard case let .rectangle(rectangle) = try firstShape(animation, shapeIndex: shapeIndex) else {
            Issue.record("Expected rectangle shape.")
            throw TestFailure()
        }
        return rectangle
    }

    private func requirePath(_ animation: LottieAnimation, shapeIndex: Int) throws -> ShapePath {
        guard case let .path(path) = try firstShape(animation, shapeIndex: shapeIndex) else {
            Issue.record("Expected path shape.")
            throw TestFailure()
        }
        return path
    }

    private func requirePolystar(_ animation: LottieAnimation, shapeIndex: Int) throws -> ShapePolystar {
        guard case let .polystar(polystar) = try firstShape(animation, shapeIndex: shapeIndex) else {
            Issue.record("Expected polystar shape.")
            throw TestFailure()
        }
        return polystar
    }

    private func expectVector(_ actual: [Double], equals expected: [Double], tolerance: Double = 0.000001) {
        #expect(actual.count == expected.count)
        for index in expected.indices {
            #expect(abs(actual[index] - expected[index]) <= tolerance)
        }
    }

    private func expectBounds(
        _ actual: LottieSourceGeometryBounds,
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        tolerance: Double = 0.000001
    ) {
        #expect(abs(actual.minX - minX) <= tolerance)
        #expect(abs(actual.minY - minY) <= tolerance)
        #expect(abs(actual.maxX - maxX) <= tolerance)
        #expect(abs(actual.maxY - maxY) <= tolerance)
    }

    private struct TestFailure: Error {}
}
