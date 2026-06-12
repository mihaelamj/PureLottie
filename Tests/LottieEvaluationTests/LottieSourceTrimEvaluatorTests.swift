import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie source trim evaluator")
struct LottieSourceTrimEvaluatorTests {
    @Test("ellipse trim records the expected first quadrant by length")
    func ellipseTrimRecordsFirstQuadrantByLength() throws {
        let trace = try firstTrimTrace(for: """
        { "ty": "el", "nm": "Circle", "p": { "a": 0, "k": [0, 0] }, "s": { "a": 0, "k": [100, 100] } },
        { "ty": "tm", "nm": "Quarter", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 25 }, "o": { "a": 0, "k": 0 }, "m": 1 },
        \(stroke)
        """)

        let input = try #require(trace.inputPaths.first)
        let selected = try #require(trace.selectedSegments.first)
        let result = try #require(trace.resultPaths.first)

        #expect(trace.mode == .parallel)
        #expect(trace.normalization.normalizedStartFraction == 0)
        #expect(trace.normalization.normalizedEndFraction == 0.25)
        #expect(trace.selectedSegments.count == 1)
        #expect(input.totalLength > 313)
        #expect(input.totalLength < 315)
        #expect(abs(selected.endLength - input.totalLength * 0.25) < 0.01)
        #expect(selected.cubicSegments.map(\.cubicSegmentIndex) == [0])
        expectVector(result.vertices.first ?? [], equals: [0, -50])
        expectVector(result.vertices.last ?? [], equals: [50, 0])
        #expect(trace.approximations.contains { $0.name == "lottieWebDefaultCurveSegments" && $0.value == 150 })

        let encoded = try JSONEncoder().encode(trace)
        let decoded = try JSONDecoder().decode(LottieSourceTrimTrace.self, from: encoded)
        #expect(decoded == trace)
    }

    @Test("rectangle trim records perimeter length and segment ranges")
    func rectangleTrimRecordsPerimeterLengthAndRanges() throws {
        let trace = try firstTrimTrace(for: """
        { "ty": "rc", "nm": "Box", "d": 1, "p": { "a": 0, "k": [0, 0] }, "s": { "a": 0, "k": [100, 50] }, "r": { "a": 0, "k": 0 } },
        { "ty": "tm", "nm": "Half", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 50 }, "o": { "a": 0, "k": 0 }, "m": 1 },
        \(stroke)
        """)

        let input = try #require(trace.inputPaths.first)
        let selected = try #require(trace.selectedSegments.first)
        let result = try #require(trace.resultPaths.first)

        #expect(abs(input.totalLength - 300) < 0.0001)
        #expect(abs(selected.startLength) < 0.0001)
        #expect(abs(selected.endLength - 150) < 0.0001)
        #expect(selected.cubicSegments.map(\.cubicSegmentIndex) == [0, 1])
        expectVector(result.vertices.first ?? [], equals: [50, -25])
        expectVector(result.vertices.last ?? [], equals: [-50, 25])
    }

    @Test("arbitrary cubic trim records sampled length and resulting cubic")
    func arbitraryCubicTrimRecordsSampledLengthAndResultingCubic() throws {
        let trace = try firstTrimTrace(for: """
        {
          "ty": "sh",
          "nm": "Arch",
          "ks": {
            "a": 0,
            "k": {
              "c": false,
              "v": [[0, 0], [100, 0]],
              "i": [[0, 0], [0, 100]],
              "o": [[0, 100], [0, 0]]
            }
          }
        },
        { "ty": "tm", "nm": "Middle", "s": { "a": 0, "k": 25 }, "e": { "a": 0, "k": 75 }, "o": { "a": 0, "k": 0 }, "m": 1 },
        \(stroke)
        """)

        let input = try #require(trace.inputPaths.first)
        let selected = try #require(trace.selectedSegments.first)
        let result = try #require(trace.resultPaths.first)

        #expect(input.totalLength > 190)
        #expect(input.totalLength < 210)
        #expect(selected.cubicSegments.count == 1)
        #expect(abs(selected.startFraction - 0.25) < 0.0001)
        #expect(abs(selected.endFraction - 0.75) < 0.0001)
        #expect(result.vertices.count == 2)
        #expect((result.vertices.first?.first ?? 0) < 30)
        #expect((result.vertices.last?.first ?? 0) > 70)
        #expect((result.vertices.first?.last ?? 0) > 45)
        #expect((result.vertices.last?.last ?? 0) > 45)
        #expect(trace.approximations.contains { $0.name == "trimmedCubicRoundingDecimals" })
    }

    @Test("offset trim records wrapped path ranges")
    func offsetTrimRecordsWrappedPathRanges() throws {
        let trace = try firstTrimTrace(for: """
        \(line(name: "Line", y: 0)),
        { "ty": "tm", "nm": "Wrapped", "s": { "a": 0, "k": 50 }, "e": { "a": 0, "k": 100 }, "o": { "a": 0, "k": 90 }, "m": 1 },
        \(stroke)
        """)

        #expect(trace.normalization.offsetTurns == 0.25)
        #expect(trace.normalization.normalizedStartFraction == 0.75)
        #expect(trace.normalization.normalizedEndFraction == 1.25)
        #expect(trace.selectedSegments.count == 2)
        #expect(trace.resultPaths.count == 2)
        expectVector(trace.resultPaths[0].vertices.first ?? [], equals: [75, 0])
        expectVector(trace.resultPaths[0].vertices.last ?? [], equals: [100, 0])
        expectVector(trace.resultPaths[1].vertices.first ?? [], equals: [0, 0])
        expectVector(trace.resultPaths[1].vertices.last ?? [], equals: [25, 0])
    }

    @Test("empty trim records no selected segments and empty result paths")
    func emptyTrimRecordsNoSegments() throws {
        let trace = try firstTrimTrace(for: """
        \(line(name: "Line", y: 0)),
        { "ty": "tm", "nm": "Empty", "s": { "a": 0, "k": 50 }, "e": { "a": 0, "k": 50 }, "o": { "a": 0, "k": 0 }, "m": 1 },
        \(stroke)
        """)

        #expect(trace.normalization.isEmpty)
        #expect(trace.selectedSegments.isEmpty)
        #expect(trace.resultPaths.count == 1)
        #expect(trace.resultPaths.first?.vertices.isEmpty == true)
    }

    @Test("full trim preserves the original path")
    func fullTrimPreservesOriginalPath() throws {
        let trace = try firstTrimTrace(for: """
        \(line(name: "Line", y: 0)),
        { "ty": "tm", "nm": "Full", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 100 }, "o": { "a": 0, "k": 0 }, "m": 1 },
        \(stroke)
        """)

        let selected = try #require(trace.selectedSegments.first)
        let result = try #require(trace.resultPaths.first)

        #expect(trace.normalization.isFull)
        #expect(abs(selected.startLength) < 0.0001)
        #expect(abs(selected.endLength - 100) < 0.0001)
        #expect(result.vertices == [[0, 0], [100, 0]])
        #expect(result.isClosed == false)
    }

    @Test("reversed authored start and end are swapped like lottie-web")
    func reversedAuthoredStartAndEndAreSwapped() throws {
        let trace = try firstTrimTrace(for: """
        \(line(name: "Line", y: 0)),
        { "ty": "tm", "nm": "Reversed", "s": { "a": 0, "k": 75 }, "e": { "a": 0, "k": 25 }, "o": { "a": 0, "k": 0 }, "m": 1 },
        \(stroke)
        """)

        let result = try #require(trace.resultPaths.first)

        #expect(trace.normalization.swappedStartEnd)
        #expect(trace.normalization.normalizedStartFraction == 0.25)
        #expect(trace.normalization.normalizedEndFraction == 0.75)
        expectVector(result.vertices.first ?? [], equals: [25, 0])
        expectVector(result.vertices.last ?? [], equals: [75, 0])
    }

    @Test("parallel and sequential trim modes record different multi-path selections")
    func parallelAndSequentialModesRecordDifferentSelections() throws {
        let parallel = try firstTrimTrace(for: """
        \(line(name: "Line A", y: 0)),
        \(line(name: "Line B", y: 10)),
        { "ty": "tm", "nm": "Parallel", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 50 }, "o": { "a": 0, "k": 0 }, "m": 1 },
        \(stroke)
        """)
        let sequential = try firstTrimTrace(for: """
        \(line(name: "Line A", y: 0)),
        \(line(name: "Line B", y: 10)),
        { "ty": "tm", "nm": "Sequential", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 50 }, "o": { "a": 0, "k": 0 }, "m": 2 },
        \(stroke)
        """)

        #expect(parallel.mode == .parallel)
        #expect(sequential.mode == .sequential)
        #expect(parallel.selectedSegments.count == 2)
        #expect(parallel.selectedSegments.allSatisfy { abs($0.endLength - 50) < 0.0001 })
        #expect(sequential.totalLength == 200)
        #expect(sequential.selectedSegments.count == 1)
        #expect(sequential.selectedSegments.first?.pathIndex == 1)
        #expect(sequential.sequenceOrder.first?.contains("Line A") == true)
        #expect(abs((sequential.selectedSegments.first?.endLength ?? 0) - 100) < 0.0001)
    }

    @Test("invalid trim mode records a semantic diagnostic")
    func invalidTrimModeRecordsSemanticDiagnostic() throws {
        let frame = try renderFrame(for: """
        \(line(name: "Line", y: 0)),
        { "ty": "tm", "nm": "Invalid", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 100 }, "o": { "a": 0, "k": 0 }, "m": 7 },
        \(stroke)
        """)
        let trace = try firstTrimTrace(in: frame)

        #expect(trace.mode == .parallel)
        #expect(frame.diagnostics.contains { diagnostic in
            diagnostic.ruleID == "lottie.evaluation.trim.mode"
                && diagnostic.codingPath.description == "$.layers[0].shapes[1].m"
                && diagnostic.classification == .gap
        })
    }

    private func firstTrimTrace(for shapes: String) throws -> LottieSourceTrimTrace {
        try firstTrimTrace(in: renderFrame(for: shapes))
    }

    private func renderFrame(for shapes: String) throws -> LottieRenderFrame {
        let animation = try decodeAnimation(shapes: shapes)
        return LottieRenderIRBuilder(animation: animation).frame(at: 0)
    }

    private func firstTrimTrace(in frame: LottieRenderFrame) throws -> LottieSourceTrimTrace {
        let node = try #require(frame.nodes.first)
        guard case let .shape(shape) = node.kind else {
            Issue.record("Expected shape node.")
            throw TestFailure()
        }
        return try #require(shape.draws.first?.trimTraces.first)
    }

    private func decodeAnimation(shapes: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 200,
          "h": 200,
          "layers": [{
            "ty": 4,
            "nm": "Shapes",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              \(shapes)
            ]
          }]
        }
        """.utf8))
    }

    private func line(name: String, y: Double) -> String {
        """
        {
          "ty": "sh",
          "nm": "\(name)",
          "ks": {
            "a": 0,
            "k": {
              "c": false,
              "v": [[0, \(y)], [100, \(y)]],
              "i": [[0, 0], [0, 0]],
              "o": [[0, 0], [0, 0]]
            }
          }
        }
        """
    }

    private var stroke: String {
        """
        {
          "ty": "st",
          "nm": "Stroke",
          "c": { "a": 0, "k": [0, 0, 0, 1] },
          "o": { "a": 0, "k": 100 },
          "w": { "a": 0, "k": 2 }
        }
        """
    }

    private func expectVector(_ actual: [Double], equals expected: [Double], tolerance: Double = 0.0011) {
        #expect(actual.count == expected.count)
        for index in expected.indices {
            #expect(abs(actual[index] - expected[index]) <= tolerance)
        }
    }

    private struct TestFailure: Error {}
}
