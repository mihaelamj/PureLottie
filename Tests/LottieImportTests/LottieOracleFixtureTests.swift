import Foundation
import LottieEvaluation
import LottieImport
import LottieModel
import Testing

@Suite("Lottie oracle fixtures")
struct LottieOracleFixtureTests {
    @Test("selected oracle fixture is semantically eligible for frame comparison")
    func selectedOracleFixtureIsSemanticallyEligibleForFrameComparison() throws {
        let data = try Data(contentsOf: fixture("eligible-shape-position.json"))
        let document = try LottieSourceDocument.parse(data)
        do {
            try document.validate()
        } catch let collection as ValidationErrorCollection {
            let message = collection.values.map { String(describing: $0) }.joined(separator: "\n")
            Issue.record("Validation failed:\n\(message)")
            return
        }

        let animation = try document.decodeAnimation()
        #expect(animation.inPoint == 0)
        #expect(animation.outPoint == 10)
        #expect(animation.frameRate == 10)

        let scene = try LottieImporter().scene(from: data)
        #expect(scene.report.findings.isEmpty)

        let builder = LottieRenderIRBuilder(animation: animation)
        for frame in [0.0, 5.0, 9.0] {
            let renderFrame = builder.frame(at: frame)
            #expect(renderFrame.diagnostics.isEmpty)
            #expect(renderFrame.nodes.count == 1)
            let node = try #require(renderFrame.nodes.first)
            #expect(node.source.sourcePath == "root > layer 'Moving Box'")
            #expect(node.source.jsonPath.description == "$.layers[0]")
            #expect(node.trace.instruction == .emitRenderNode)
            #expect(node.trace.nodeID == node.id)
            #expect(node.opacity == 1)

            guard case let .shape(shape) = node.kind else {
                Issue.record("Expected a shape RenderIR node.")
                return
            }
            #expect(shape.draws.count == 1)
        }
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieOracle", isDirectory: true)
            .appendingPathComponent(name)
    }
}
