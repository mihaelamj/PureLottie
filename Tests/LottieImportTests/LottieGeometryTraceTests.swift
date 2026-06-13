import Foundation
import LottieEvaluation
import LottieImport
import LottieModel
import PureLayer
import Testing

@Suite("Lottie geometry trace")
struct LottieGeometryTraceTests {
    @Test("trace exposes unscaled render surface offsets numerically")
    func traceExposesUnscaledRenderSurfaceOffsetsNumerically() throws {
        let data = try Data(contentsOf: fixture("eligible-shape-position.json"))
        let animation = try LottieAnimation.decode(from: data)
        let scene = try LottieImporter().scene(from: data)

        let trace = LottieGeometryTraceBuilder().trace(
            animation: animation,
            renderRoot: scene.root,
            sourceFrames: [0],
            scale: 2
        )

        let comparison = try #require(trace.frames.first?.comparisons.first)
        #expect(comparison.expectedCompositionBounds.minX == 20)
        #expect(comparison.expectedCompositionBounds.minY == 20)
        #expect(comparison.expectedCompositionBounds.maxX == 44)
        #expect(comparison.expectedCompositionBounds.maxY == 44)
        #expect(comparison.expectedOutputBounds.minX == 40)
        #expect(comparison.expectedOutputBounds.minY == 40)
        #expect(comparison.expectedOutputBounds.maxX == 88)
        #expect(comparison.expectedOutputBounds.maxY == 88)
        #expect(comparison.actualPureLayerBounds?.minX == 20)
        #expect(comparison.actualPureLayerBounds?.minY == 20)
        #expect(comparison.deltaToExpectedOutputBounds?.minX == -20)
        #expect(comparison.deltaToExpectedOutputBounds?.minY == -20)
        #expect(comparison.matchesExpectedOutputBounds == false)
    }

    @Test("scaled render surface matches expected output coordinates")
    func scaledRenderSurfaceMatchesExpectedOutputCoordinates() throws {
        let data = try Data(contentsOf: fixture("eligible-shape-position.json"))
        let animation = try LottieAnimation.decode(from: data)

        let trace = LottieGeometryTraceBuilder().trace(
            animation: animation,
            sourceFrames: [0, 9],
            scale: 2
        ) { sourceFrame, _ in
            let frame = LottieRenderIRBuilder(animation: animation).frame(at: sourceFrame)
            let tree = LottieRenderIRLowerer().lower(frame)
            return LottieRenderSurface.root(tree.root, width: animation.width, height: animation.height, scale: 2)
        }

        let first = try #require(trace.frames.first?.comparisons.first)
        #expect(first.actualPureLayerBounds?.minX == 40)
        #expect(first.actualPureLayerBounds?.minY == 40)
        #expect(first.actualPureLayerBounds?.maxX == 88)
        #expect(first.actualPureLayerBounds?.maxY == 88)
        #expect(first.deltaToExpectedOutputBounds?.minX == 0)
        #expect(first.deltaToExpectedOutputBounds?.minY == 0)
        #expect(first.matchesExpectedOutputBounds)

        let last = try #require(trace.frames.last?.comparisons.first)
        #expect(last.expectedCompositionBounds.minX == 28)
        #expect(last.expectedCompositionBounds.maxX == 52)
        #expect(last.expectedOutputBounds.minX == 56)
        #expect(last.expectedOutputBounds.maxX == 104)
        #expect(last.actualPureLayerBounds?.minX == 56)
        #expect(last.actualPureLayerBounds?.maxX == 104)
        #expect(last.matchesExpectedOutputBounds)
    }

    @Test("scaled importer scene preserves animated position")
    func scaledImporterScenePreservesAnimatedPosition() throws {
        let data = try Data(contentsOf: fixture("eligible-shape-position.json"))
        let scene = try LottieImporter().scene(from: data)
        let root = LottieRenderSurface.root(for: scene, scale: 2)
        let movingLayer = try #require(root.sublayers.first)

        let x = try #require(movingLayer.animation(forKey: "lottie.position.x") as? KeyframeAnimation)
        #expect(x.keyPath == "transform.translation.x")
        #expect(x.values.last == 16)
        #expect(movingLayer.presentation(at: 0).position.x == 0)
        #expect(movingLayer.presentation(at: 0.9).transform.m41 == 16)

        let trace = try LottieGeometryTraceBuilder().trace(
            animation: LottieAnimation.decode(from: data),
            renderRoot: root,
            sourceFrames: [0, 9],
            scale: 2
        )
        let last = try #require(trace.frames.last?.comparisons.first)
        #expect(last.actualPureLayerBounds?.minX == 56)
        #expect(last.actualPureLayerBounds?.maxX == 104)
        #expect(last.matchesExpectedOutputBounds)
    }

    @Test("trace compares trimmed stroke bounds")
    func traceComparesTrimmedStrokeBounds() throws {
        let data = Data(trimmedStrokeFixture.utf8)
        let animation = try LottieAnimation.decode(from: data)

        let trace = LottieGeometryTraceBuilder().trace(
            animation: animation,
            sourceFrames: [12],
            scale: 2
        ) { sourceFrame, _ in
            let frame = LottieRenderIRBuilder(animation: animation).frame(at: sourceFrame)
            let tree = LottieRenderIRLowerer().lower(frame)
            return LottieRenderSurface.root(tree.root, width: animation.width, height: animation.height, scale: 2)
        }

        let comparisons = try #require(trace.frames.first?.comparisons)
        let allComparisonsMatch = comparisons.allSatisfy(\.matchesExpectedOutputBounds)
        #expect(comparisons.count == 1)
        #expect(allComparisonsMatch, "\(comparisons)")
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieOracle", isDirectory: true)
            .appendingPathComponent(name)
    }

    private var trimmedStrokeFixture: String {
        """
        {
          "v": "5.7.4",
          "fr": 12,
          "ip": 0,
          "op": 24,
          "w": 160,
          "h": 120,
          "layers": [{
            "ty": 4,
            "nm": "Trimmed Ring",
            "ind": 1,
            "ip": 0,
            "op": 24,
            "st": 0,
            "ks": {
              "p": { "a": 0, "k": [80, 60, 0] },
              "a": { "a": 0, "k": [0, 0, 0] },
              "s": { "a": 0, "k": [100, 100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [
              {
                "ty": "el",
                "nm": "Ring Path",
                "p": { "a": 0, "k": [0, 0] },
                "s": { "a": 0, "k": [80, 80] }
              },
              {
                "ty": "st",
                "nm": "Purple Stroke",
                "c": { "a": 0, "k": [0.55, 0.2, 0.95, 1] },
                "o": { "a": 0, "k": 100 },
                "w": { "a": 0, "k": 8 }
              },
              {
                "ty": "tm",
                "nm": "Reveal",
                "s": { "a": 0, "k": 0 },
                "e": { "a": 1, "k": [
                  { "t": 0, "s": [0] },
                  { "t": 24, "s": [100] }
                ]},
                "o": { "a": 0, "k": 0 },
                "m": 1
              }
            ]
          }],
          "assets": []
        }
        """
    }
}
