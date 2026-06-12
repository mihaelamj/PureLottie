import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("lottie-web numeric intent oracle")
struct LottieWebIntentOracleTests {
    @Test("committed lottie-web intent trace matches PureLottie source facts")
    func committedLottieWebIntentTraceMatchesPureLottieSourceFacts() throws {
        let animation = try LottieAnimation.decode(from: Data(contentsOf: fixture("eligible-shape-position.json")))
        let oracle = try JSONDecoder().decode(
            LottieWebIntentTrace.self,
            from: Data(contentsOf: fixture("lottie-web-intent/eligible-shape-position.json"))
        )

        #expect(oracle.schema.name == "purelottie.lottie-web-intent")
        #expect(oracle.schema.version == 1)
        #expect(oracle.lottieWeb.version == "5.13.0")
        #expect(oracle.renderer == "svg")
        #expect(oracle.frames.map(\.frame) == [0, 5, 9])

        let builder = LottieRenderIRBuilder(animation: animation)
        for webFrame in oracle.frames {
            let pureFrame = builder.frame(at: webFrame.frame)
            let node = try #require(pureFrame.nodes.first)
            let webLayer = try #require(webFrame.layers.first)
            let webPath = try #require(webFrame.paths.first)
            let webLayerBounds = try #require(webLayer.layerElementBounds)

            #expect(webFrame.layerCount == 1)
            #expect(webFrame.pathCount == 1)
            #expect(webLayer.name == "Moving Box")
            #expect(webLayer.type == 4)
            #expect(webLayer.ind == 1)
            #expect(webLayer.inPoint == 0)
            #expect(webLayer.outPoint == 10)
            #expect(webLayer.renderedFrame == webFrame.frame)

            expectClose(webLayer.opacity, node.opacity)
            expectClose(webLayer.matrix[12], node.transform.worldMatrix.values[12])
            expectClose(webLayer.matrix[13], node.transform.worldMatrix.values[13])

            guard case let .shape(shape) = node.kind else {
                Issue.record("Expected a shape RenderIR node.")
                return
            }
            let draw = try #require(shape.draws.first)
            let fragment = try #require(draw.fragments.first)
            let bounds = fragment.sourceGeometry.bounds

            expectClose(webPath.localBBox.minX, bounds.minX)
            expectClose(webPath.localBBox.minY, bounds.minY)
            expectClose(webPath.localBBox.maxX, bounds.maxX)
            expectClose(webPath.localBBox.maxY, bounds.maxY)
            expectClose(webPath.pathLength, 96)
            #expect(webPath.d.contains("M44,20"))
            #expect(webPath.style.fill == "rgb(25, 102, 255)")
            #expect(webPath.style.stroke == "none")

            guard case let .fill(fill) = draw.style else {
                Issue.record("Expected a fill style.")
                return
            }
            #expect(fill.color.prefix(3).map { Int(floor($0 * 255)) } == [25, 102, 255])
            expectClose(fill.opacity, webPath.style.fillOpacity)

            expectClose(webLayerBounds.minX, bounds.minX + node.transform.worldMatrix.values[12], tolerance: 0.000_01)
            expectClose(webLayerBounds.minY, bounds.minY + node.transform.worldMatrix.values[13])
            expectClose(webLayerBounds.maxX, bounds.maxX + node.transform.worldMatrix.values[12], tolerance: 0.000_01)
            expectClose(webLayerBounds.maxY, bounds.maxY + node.transform.worldMatrix.values[13])
        }
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieOracle", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 0.000_001) {
        #expect(abs(actual - expected) <= tolerance)
    }
}

private struct LottieWebIntentTrace: Decodable {
    var schema: Schema
    var renderer: String
    var lottieWeb: LottieWeb
    var frames: [Frame]

    struct Schema: Decodable {
        var name: String
        var version: Int
    }

    struct LottieWeb: Decodable {
        var version: String
    }

    struct Frame: Decodable {
        var frame: Double
        var layerCount: Int
        var pathCount: Int
        var layers: [Layer]
        var paths: [Path]
    }

    struct Layer: Decodable {
        var name: String
        var type: Int
        var ind: Int
        var inPoint: Double
        var outPoint: Double
        var renderedFrame: Double
        var opacity: Double
        var matrix: [Double]
        var layerElementBounds: Bounds?
    }

    struct Path: Decodable {
        var d: String
        var pathLength: Double
        var localBBox: Bounds
        var style: Style
    }

    struct Style: Decodable {
        var fill: String
        var fillOpacity: Double
        var stroke: String
    }

    struct Bounds: Decodable {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
    }
}
