import Foundation
import LottieEvaluation
import LottieImport
import LottieModel
import PureLayer
import Testing

@Suite("Lottie APNG export")
struct LottieAPNGExportTests {
    @Test("validated Lottie imports export through PureLayer as animated PNG")
    func validatedLottieImportsExportThroughPureLayerAsAnimatedPNG() throws {
        let data = try Data(contentsOf: fixture("eligible-shape-position.json"))
        let animation = try LottieAnimation.decode(from: data)
        let intent = try LottieWebIntentTrace.decodeValidated(
            from: Data(contentsOf: fixture("lottie-web-intent/eligible-shape-position.json"))
        )
        let tolerances = try loadTolerances()
        let sourceFrame = LottieRenderIRBuilder(animation: animation).frame(at: 5)
        try assertSourceIntentIsMeasured(sourceFrame, intent: intent, tolerances: tolerances)

        let scene = try LottieImporter().scene(from: data)
        #expect(scene.report.isClean)

        let apng = try MovieExporter().animatedPNG(
            of: scene.root,
            size: PixelSize(width: 128, height: 128),
            from: 0,
            to: 1,
            fps: 12
        )

        #expect(Array(apng.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        let chunkTypes = chunkTypes(apng)
        #expect(chunkTypes.contains("acTL"))
        #expect(chunkTypes.contains("fdAT"))
        #expect(chunkTypes.filter { $0 == "fcTL" }.count == 13)
        #expect(animationControlFrameCount(apng) == 13)
    }

    private func assertSourceIntentIsMeasured(
        _ frame: LottieRenderFrame,
        intent: LottieWebIntentTrace,
        tolerances: LottieOracleToleranceLedger
    ) throws {
        #expect(frame.diagnostics.isEmpty)
        let node = frame.nodes.first
        #expect(node != nil)
        guard let node else { return }
        let webFrame = intent.frames.first { $0.frame == frame.sourceFrame }
        #expect(webFrame != nil)
        guard let webFrame, let webLayer = webFrame.layers.first(where: { $0.name == node.layerName }) else {
            return
        }

        #expect(webLayer.matrix.indices.contains(13))
        let translationTolerance = try tolerances.threshold(id: "matrix.translation.css-pixel.absolute")
        expectClose(webLayer.matrix[12], node.transform.worldMatrix.values[12], tolerance: translationTolerance)
        expectClose(webLayer.matrix[13], node.transform.worldMatrix.values[13], tolerance: translationTolerance)

        guard case let .shape(shape) = node.kind,
              let draw = shape.draws.first,
              let fragment = draw.fragments.first
        else {
            Issue.record("Expected APNG fixture to expose measured shape geometry before export.")
            return
        }

        #expect(fragment.sourceGeometry.bezier.vertices.isEmpty == false)
        let boundsTolerance = try tolerances.threshold(id: "bounds.css-pixel.absolute")
        expectClose(fragment.sourceGeometry.bounds.minX, 20, tolerance: boundsTolerance)
        expectClose(fragment.sourceGeometry.bounds.minY, 20, tolerance: boundsTolerance)
        expectClose(fragment.sourceGeometry.bounds.maxX, 44, tolerance: boundsTolerance)
        expectClose(fragment.sourceGeometry.bounds.maxY, 44, tolerance: boundsTolerance)
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieOracle", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func loadTolerances() throws -> LottieOracleToleranceLedger {
        try LottieOracleToleranceLedger.decodeValidated(
            from: Data(contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Tools/LottieOracle/oracle-tolerances.json"))
        )
    }

    private func chunkTypes(_ bytes: [UInt8]) -> [String] {
        var types: [String] = []
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(readUInt32(bytes, at: offset))
            guard offset + 12 + length <= bytes.count else { break }
            let typeBytes = bytes[(offset + 4) ..< (offset + 8)]
            if let type = String(bytes: typeBytes, encoding: .ascii) {
                types.append(type)
            }
            offset += 12 + length
        }
        return types
    }

    private func animationControlFrameCount(_ bytes: [UInt8]) -> Int? {
        var offset = 8
        while offset + 20 <= bytes.count {
            let length = Int(readUInt32(bytes, at: offset))
            guard offset + 12 + length <= bytes.count else { break }
            let typeBytes = bytes[(offset + 4) ..< (offset + 8)]
            guard String(bytes: typeBytes, encoding: .ascii) == "acTL" else {
                offset += 12 + length
                continue
            }
            guard length >= 4 else { return nil }
            return Int(readUInt32(bytes, at: offset + 8))
        }
        return nil
    }

    private func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 |
            UInt32(bytes[offset + 1]) << 16 |
            UInt32(bytes[offset + 2]) << 8 |
            UInt32(bytes[offset + 3])
    }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double) {
        #expect(abs(actual - expected) <= tolerance)
    }
}
