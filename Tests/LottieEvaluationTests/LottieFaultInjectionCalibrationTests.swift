//
//  LottieFaultInjectionCalibrationTests.swift
//  PureLottie
//

import Foundation
import LottieEvaluation
@testable import LottieImport
import LottieModel
import Testing

@Suite("Lottie fault-injection calibration")
struct LottieFaultInjectionCalibrationTests {
    @Test("all faults in catalog are detected by corresponding checks")
    func faultsAreDetected() throws {
        // 1. offByOneKeyframeIndex (Trips: LottieOracleCorpusTests / matrix-translation comparison)
        try verifyFaultIsDetected(.offByOneKeyframeIndex) {
            let animation = try loadFixtureAnimation("eligible-shape-position.json")
            let oracle = try oracleTrace("eligible-shape-position.json")
            let builder = LottieRenderIRBuilder(animation: animation)
            let tolerances = try loadTolerances()
            let translationTolerance = try tolerances.threshold(id: "matrix.translation.css-pixel.absolute")

            let webFrame = try #require(oracle.frames.first { $0.frame == 5 })
            let webLayer = try #require(webFrame.layers.first)

            try LottieFaultInjector.inject(.offByOneKeyframeIndex) {
                let pureFrame = builder.frame(at: 5)
                let node = try #require(pureFrame.nodes.first)
                let diff = abs(webLayer.matrix[12] - node.transform.worldMatrix.values[12])
                #expect(diff > translationTolerance, "offByOneKeyframeIndex fault should trip the oracle translation tolerance")
            }
        }

        // 2. wrongMatrixMultiplicationOrder (Trips: LottieOracleCorpusTests / transform matrix composition)
        try verifyFaultIsDetected(.wrongMatrixMultiplicationOrder) {
            let animation = try loadFixtureAnimation("scale-rotation-anchor.json")
            let oracle = try oracleTrace("scale-rotation-anchor.json")
            let builder = LottieRenderIRBuilder(animation: animation)

            let webFrame = try #require(oracle.frames.first { $0.frame == 5 })
            let webLayer = try #require(webFrame.layers.first)

            try LottieFaultInjector.inject(.wrongMatrixMultiplicationOrder) {
                let pureFrame = builder.frame(at: 5)
                let node = try #require(pureFrame.nodes.first)

                let diff = zip(webLayer.matrix, node.transform.worldMatrix.values).map { abs($0.0 - $0.1) }.max() ?? 0
                #expect(diff > 0.001, "wrongMatrixMultiplicationOrder fault should trip the oracle matrix values")
            }
        }

        // 3. droppedTrimSegment (Trips: LottieSourceIntentRoundTripGate / trim-result-paths validation)
        try verifyFaultIsDetected(.droppedTrimSegment) {
            let animation = try loadFixtureAnimation("trim-rectangle-half.json")
            let source = LottieDecompiledSourceIntentSource(identity: "trim-rectangle-half", frameCount: 1)
            let selected = [LottieSourceIntentRoundTripSelection(frame: 0, rationale: "test")]

            LottieFaultInjector.inject(.droppedTrimSegment) {
                let gate = LottieSourceIntentTransformTimingRoundTripGate()
                let report = gate.report(animation: animation, source: source, selectedFrames: selected)
                #expect(throws: ValidationErrorCollection.self) {
                    try report.validate()
                }
            }
        }

        // 4. swappedMaskMode (Trips: LottieSourceIntentReversibilityCorpusGateTests / mask mode comparison)
        try verifyFaultIsDetected(.swappedMaskMode) {
            let animation = try loadFixtureAnimation("mask-add-rectangle.json")
            let source = LottieDecompiledSourceIntentSource(identity: "mask-add-rectangle", frameCount: 1)
            let selected = [LottieSourceIntentRoundTripSelection(frame: 0, rationale: "test")]

            LottieFaultInjector.inject(.swappedMaskMode) {
                let gate = LottieSourceIntentTransformTimingRoundTripGate()
                let report = gate.report(animation: animation, source: source, selectedFrames: selected)
                #expect(report.findingCount > 0, "swappedMaskMode fault should produce round-trip findings due to mask mode mismatch")
                let hasMaskModeFinding = report.frames.flatMap(\.layers).flatMap(\.findings).contains { finding in
                    finding.property.contains("mode") && finding.ruleID == "lottie.round-trip.feature.string"
                }
                #expect(hasMaskModeFinding, "Should have a mask mode mismatch finding")
            }
        }

        // 5. roundedAwayPrecision (Trips: LottieWebIntentOracleTests / path bounds & length)
        try verifyFaultIsDetected(.roundedAwayPrecision) {
            let animation = try loadFixtureAnimation("scale-rotation-anchor.json")
            let oracle = try oracleTrace("scale-rotation-anchor.json")
            let builder = LottieRenderIRBuilder(animation: animation)

            let webFrame = try #require(oracle.frames.first { $0.frame == 5 })
            let webLayer = try #require(webFrame.layers.first)

            try LottieFaultInjector.inject(.roundedAwayPrecision) {
                let pureFrame = builder.frame(at: 5)
                let node = try #require(pureFrame.nodes.first)

                let diff = zip(webLayer.matrix, node.transform.worldMatrix.values).map { abs($0.0 - $0.1) }.max() ?? 0
                #expect(diff > 0.001, "roundedAwayPrecision fault should trip the oracle matrix values due to sin/cos precision loss")
            }
        }

        // 6. reversedBezierDirection (Trips: LottieLoweringSourceIntentGateTests / shape geometry)
        try verifyFaultIsDetected(.reversedBezierDirection) {
            let animation = try loadFixtureAnimation("raw-bezier-triangle.json")
            let builder = LottieRenderIRBuilder(animation: animation)

            let normalFrame = builder.frame(at: 0)
            let normalNode = try #require(normalFrame.nodes.first)
            guard case let .shape(normalShape) = normalNode.kind else {
                Issue.record("Expected shape node")
                throw TestFailure()
            }
            let normalDraw = try #require(normalShape.draws.first)
            let normalFragment = try #require(normalDraw.fragments.first)
            let normalVertices = normalFragment.sourceGeometry.vertices

            try LottieFaultInjector.inject(.reversedBezierDirection) {
                let faultFrame = builder.frame(at: 0)
                let faultNode = try #require(faultFrame.nodes.first)
                guard case let .shape(faultShape) = faultNode.kind else {
                    Issue.record("Expected shape")
                    return
                }
                let faultDraw = try #require(faultShape.draws.first)
                let faultFragment = try #require(faultDraw.fragments.first)
                let faultVertices = faultFragment.sourceGeometry.vertices

                #expect(normalVertices != faultVertices, "reversedBezierDirection fault should change shape vertices, causing lowering gate failure")
            }
        }

        // 7. skippedPrecompTimeRemap (Trips: LottieLoweringSourceIntentGateTests / precomp timing)
        try verifyFaultIsDetected(.skippedPrecompTimeRemap) {
            let animation = try loadFixtureAnimation("time-remap-precomp-diagnosed.json")
            let oracle = try oracleTrace("time-remap-precomp-diagnosed.json")
            let builder = LottieRenderIRBuilder(animation: animation)

            let webFrame = try #require(oracle.frames.first { $0.frame == 0 })
            let webPrecomp = try #require(webFrame.precompositions.first)
            let expectedFrame = try #require(webPrecomp.renderedFrame)

            try LottieFaultInjector.inject(.skippedPrecompTimeRemap) {
                let pureFrame = builder.frame(at: 0)
                let boundary = try #require(pureFrame.nodes.first { node in
                    if case .precompositionBoundary = node.kind { return true }
                    return false
                })
                #expect(boundary.localFrame != expectedFrame, "skippedPrecompTimeRemap fault should deviate precomp localFrame from expectedFrame, tripping precomp timing gate")
            }
        }
    }

    private func verifyFaultIsDetected(_: LottieFault, block: () throws -> Void) rethrows {
        try block()
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

    private func oracleTrace(_ name: String) throws -> LottieWebIntentTrace {
        try LottieWebIntentTrace.decodeValidated(
            from: Data(contentsOf: fixture("lottie-web-intent/\(name)"))
        )
    }

    private func loadFixtureAnimation(_ name: String) throws -> LottieAnimation {
        try LottieAnimation.decode(from: Data(contentsOf: fixture(name)))
    }

    private struct TestFailure: Error {}
}
