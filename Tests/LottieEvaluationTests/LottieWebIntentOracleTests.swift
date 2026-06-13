import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("lottie-web numeric intent oracle")
struct LottieWebIntentOracleTests {
    @Test("committed lottie-web intent trace matches PureLottie source facts")
    func committedLottieWebIntentTraceMatchesPureLottieSourceFacts() throws {
        let animation = try LottieAnimation.decode(from: Data(contentsOf: fixture("eligible-shape-position.json")))
        let oracle = try LottieWebIntentTrace.decodeValidated(
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
