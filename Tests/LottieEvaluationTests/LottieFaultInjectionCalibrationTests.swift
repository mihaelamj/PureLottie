//
//  LottieFaultInjectionCalibrationTests.swift
//  PureLottie
//

import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie fault-injection calibration")
struct LottieFaultInjectionCalibrationTests {
    @Test("all faults in catalog are detected by corresponding checks")
    func faultsAreDetected() throws {
        // 1. offByOneKeyframeIndex
        try verifyFaultIsDetected(.offByOneKeyframeIndex) {
            let animation = try decode("""
            {
              "v": "5.7.4", "fr": 30, "ip": 0, "op": 20, "w": 64, "h": 64,
              "layers": [{
                "ty": 4, "ind": 1, "ip": 0, "op": 20, "ks": {
                  "o": { "k": [
                    { "t": 0, "s": [0], "e": [20] },
                    { "t": 10, "s": [20], "e": [100] },
                    { "t": 20, "s": [100] }
                  ]}
                },
                "shapes": []
              }]
            }
            """)
            let opacity = try #require(animation.layers.first?.transform?.opacity)
            let evaluator = LottieFrameEvaluator(animation: animation)
            let normalVal = evaluator.evaluate(opacity, at: 5).value

            LottieFaultInjector.inject(.offByOneKeyframeIndex) {
                let faultVal = evaluator.evaluate(opacity, at: 5).value
                #expect(normalVal != faultVal, "offByOneKeyframeIndex should change evaluated keyframe progress value")
            }
        }

        // 2. wrongMatrixMultiplicationOrder
        verifyFaultIsDetected(.wrongMatrixMultiplicationOrder) {
            let m1 = LottieTransformMatrix.translation(x: 10, y: 0, z: 0)
            let m2 = LottieTransformMatrix.scale(x: 2, y: 1, z: 1)
            let normal = m1.concatenating(m2)

            LottieFaultInjector.inject(.wrongMatrixMultiplicationOrder) {
                let fault = m1.concatenating(m2)
                #expect(normal != fault, "wrongMatrixMultiplicationOrder should result in different concatenated matrix")
            }
        }

        // 3. droppedTrimSegment
        try verifyFaultIsDetected(.droppedTrimSegment) {
            let shapes = """
            { "ty": "el", "nm": "Circle", "p": { "a": 0, "k": [0, 0] }, "s": { "a": 0, "k": [100, 100] } },
            { "ty": "tm", "nm": "Quarter", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 25 }, "o": { "a": 0, "k": 0 }, "m": 1 },
            { "ty": "st", "nm": "Stroke", "c": { "a": 0, "k": [0, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "w": { "a": 0, "k": 2 } }
            """
            let animation = try decode("""
            {
              "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 200, "h": 200,
              "layers": [{ "ty": 4, "nm": "Shapes", "ind": 1, "ip": 0, "op": 30, "ks": {}, "shapes": [ \(shapes) ] }]
            }
            """)
            let frame = LottieRenderIRBuilder(animation: animation).frame(at: 0)
            let node = try #require(frame.nodes.first)
            guard case let .shape(shape) = node.kind else {
                Issue.record("Expected shape node")
                throw TestFailure()
            }
            let trace = try #require(shape.draws.first?.trimTraces.first)
            #expect(trace.resultPaths.count == 1, "Normally should have 1 trimmed result path")

            try LottieFaultInjector.inject(.droppedTrimSegment) {
                let faultFrame = LottieRenderIRBuilder(animation: animation).frame(at: 0)
                let faultNode = try #require(faultFrame.nodes.first)
                guard case let .shape(faultShape) = faultNode.kind else {
                    Issue.record("Expected shape node")
                    return
                }
                let faultTrace = try #require(faultShape.draws.first?.trimTraces.first)
                #expect(faultTrace.resultPaths.count == 0, "droppedTrimSegment should result in 0 result paths")
            }
        }

        // 4. swappedMaskMode
        try verifyFaultIsDetected(.swappedMaskMode) {
            let animation = try decode("""
            {
              "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
              "layers": [{
                "ty": 4, "ind": 1, "ip": 0, "op": 30, "ks": {},
                "masksProperties": [{
                  "mode": "a",
                  "pt": { "a": 0, "k": { "c": true, "v": [[0,0], [10,10]], "i": [[0,0], [0,0]], "o": [[0,0], [0,0]] } }
                }],
                "shapes": []
              }]
            }
            """)
            let renderFrame = LottieRenderIRBuilder(animation: animation).frame(at: 0)
            let decompiler = LottieSourceIntentDecompiler()
            let normalIntent = decompiler.decompile(
                frame: renderFrame,
                source: LottieDecompiledSourceIntentSource(identity: "mask-test", frameCount: 1)
            )
            let normalMask = try #require(normalIntent.frames.first?.visibleLayers.first?.masks.first)
            #expect(normalMask.mode == "a")

            try LottieFaultInjector.inject(.swappedMaskMode) {
                let faultIntent = decompiler.decompile(
                    frame: renderFrame,
                    source: LottieDecompiledSourceIntentSource(identity: "mask-test", frameCount: 1)
                )
                let faultMask = try #require(faultIntent.frames.first?.visibleLayers.first?.masks.first)
                #expect(faultMask.mode == "s", "swappedMaskMode should swap 'a' to 's'")
            }
        }

        // 5. roundedAwayPrecision
        verifyFaultIsDetected(.roundedAwayPrecision) {
            let valNormal = LottieMath.sin(0.12345)

            LottieFaultInjector.inject(.roundedAwayPrecision) {
                let valFault = LottieMath.sin(0.12345)
                #expect(valFault == 0.12, "roundedAwayPrecision should round sin output to 2 decimal places")
                #expect(abs(valNormal - valFault) > 0.001)
            }
        }

        // 6. reversedBezierDirection
        try verifyFaultIsDetected(.reversedBezierDirection) {
            let animation = try decode("""
            {
              "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100,
              "layers": [{
                "ty": 4, "ind": 1, "ip": 0, "op": 30, "ks": {},
                "shapes": [{
                  "ty": "sh", "nm": "Path",
                  "ks": {
                    "a": 0,
                    "k": {
                      "c": false,
                      "v": [[10, 20], [30, 40]],
                      "i": [[1, 2], [3, 4]],
                      "o": [[5, 6], [7, 8]]
                    }
                  }
                }]
              }]
            }
            """)
            let pathShape = try requirePath(animation, shapeIndex: 0)
            let evaluator = LottieSourceGeometryEvaluator(animation: animation)
            let normalTrace = evaluator.evaluate(
                pathShape, at: 0,
                sourcePath: "root > path",
                jsonPath: JSONPath()
            ).value

            #expect(normalTrace.vertices.first == [10, 20])

            LottieFaultInjector.inject(.reversedBezierDirection) {
                let faultTrace = evaluator.evaluate(
                    pathShape, at: 0,
                    sourcePath: "root > path",
                    jsonPath: JSONPath()
                ).value
                #expect(faultTrace.vertices.first == [30, 40], "reversedBezierDirection should reverse path vertex order")
            }
        }

        // 7. skippedPrecompTimeRemap
        try verifyFaultIsDetected(.skippedPrecompTimeRemap) {
            let animation = try decode("""
            {
              "v": "5.7.4", "nm": "Root", "fr": 10, "ip": 0, "op": 40, "w": 100, "h": 100,
              "layers": [{
                "ty": 0, "nm": "Remapped Precomp", "ind": 1, "refId": "compA", "ip": 0, "op": 40, "st": 0,
                "tm": { "a": 0, "k": 1.5 }, "ks": {}
              }],
              "assets": [{
                "id": "compA", "w": 50, "h": 40,
                "layers": [
                  { "ty": 1, "nm": "Child Solid", "ind": 1, "ip": 0, "op": 40, "st": 0, "ks": {}, "sc": "#ff0000", "sw": 10, "sh": 10 }
                ]
              }]
            }
            """)

            let builder = LottieRenderIRBuilder(animation: animation)
            let normalFrame = builder.frame(at: 10.0)
            let normalPrecomp = normalFrame.layerGraph.records.first { $0.name == "Remapped Precomp" }
            #expect(normalPrecomp?.timing.mode == .timeRemapSeconds)
            #expect(normalPrecomp?.timing.localFrame == 15.0) // 1.5s * 10fps = 15 frames

            LottieFaultInjector.inject(.skippedPrecompTimeRemap) {
                let faultFrame = builder.frame(at: 10.0)
                let faultPrecomp = faultFrame.layerGraph.records.first { $0.name == "Remapped Precomp" }
                #expect(faultPrecomp?.timing.mode != .timeRemapSeconds, "skippedPrecompTimeRemap should fall back to stretch timing mode")
            }
        }
    }

    private func verifyFaultIsDetected(_: LottieFault, block: () throws -> Void) rethrows {
        try block()
    }

    private func verifyFaultIsDetected(_: LottieFault, block: () -> Void) {
        block()
    }

    private func decode(_ source: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(source.utf8))
    }

    private func requirePath(_ animation: LottieAnimation, shapeIndex: Int) throws -> ShapePath {
        guard let shape = animation.layers.first?.shapes?[shapeIndex],
              case let .path(path) = shape
        else {
            Issue.record("Expected path shape.")
            throw TestFailure()
        }
        return path
    }

    private struct TestFailure: Error {}
}
