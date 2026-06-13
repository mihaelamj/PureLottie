//
//  LottieSourceIntentNormalizerTests.swift
//  PureLottie
//

import Foundation
import LottieEvaluation
import Testing

@Suite("Lottie source-intent normalizer and confluence")
struct LottieSourceIntentNormalizerTests {

    private func mockProvenance(name: String) -> LottieSourceIntentProvenance {
        LottieSourceIntentProvenance(
            sourcePath: "mock > \(name)",
            jsonPath: "$.mock.\(name)",
            consumedFields: ["$.mock.\(name)"]
        )
    }

    private func makeTransform(matrixValues: [Double], name: String) throws -> LottieSourceIntentTransform {
        let matrix = try LottieSourceIntentMatrix(values: matrixValues)
        return LottieSourceIntentTransform(
            anchor: [0, 0, 0],
            position: [matrixValues[12], matrixValues[13], matrixValues[14]],
            scale: [100, 100, 100],
            rotationZDegrees: 0,
            is3DLayer: false,
            matrix: matrix,
            matrixConvention: .lottieWebRowVector4x4,
            provenance: mockProvenance(name: name)
        )
    }

    private func makeTrim(start: Double, end: Double, offset: Double, name: String) -> LottieSourceIntentModifier {
        LottieSourceIntentModifier(
            kind: .trim,
            trim: LottieSourceIntentTrim(
                start: start,
                end: end,
                offset: offset,
                multiple: nil,
                isAnimated: false
            ),
            provenance: mockProvenance(name: name)
        )
    }

    @Test("identity transform removal removes identity matrix")
    func identityTransformRemovalRemovesIdentityMatrix() throws {
        let t1 = try makeTransform(matrixValues: [
            2, 0, 0, 0,
            0, 3, 0, 0,
            0, 0, 1, 0,
            10, 20, 0, 1
        ], name: "t1")
        
        let tIdentity = try makeTransform(matrixValues: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        ], name: "identity")

        let geom = LottieSourceIntentGeometry(
            id: "geom-1",
            kind: .path,
            primitive: "sh",
            transformStack: [t1, tIdentity],
            provenance: mockProvenance(name: "geom")
        )

        let normalizer = LottieSourceIntentNormalizer()
        var steps: [LottieSourceIntentRewriteStep] = []
        let result = normalizer.normalize(geom, strategy: .leftToRight, steps: &steps)

        #expect(result.transformStack.count == 1)
        #expect(result.transformStack[0].matrix.values == t1.matrix.values)
        #expect(steps.contains { $0.ruleName == "transform-identity" })
    }

    @Test("identity trim removal removes identity trim")
    func identityTrimRemovalRemovesIdentityTrim() {
        let m1 = makeTrim(start: 10, end: 90, offset: 0, name: "m1")
        let mIdentity = makeTrim(start: 0, end: 100, offset: 0, name: "identity")

        let geom = LottieSourceIntentGeometry(
            id: "geom-2",
            kind: .path,
            primitive: "sh",
            modifiers: [m1, mIdentity],
            provenance: mockProvenance(name: "geom")
        )

        let normalizer = LottieSourceIntentNormalizer()
        var steps: [LottieSourceIntentRewriteStep] = []
        let result = normalizer.normalize(geom, strategy: .leftToRight, steps: &steps)

        #expect(result.modifiers.count == 1)
        #expect(result.modifiers[0].trim?.start == 10)
        #expect(result.modifiers[0].trim?.end == 90)
        #expect(steps.contains { $0.ruleName == "trim-identity" })
    }

    @Test("confluence: left-to-right and right-to-left yield identical transform matrices")
    func confluenceLeftToRightAndRightToLeftYieldIdenticalTransformMatrices() throws {
        // T1: Scale + Translate
        let t1 = try makeTransform(matrixValues: [
            2, 0, 0, 0,
            0, 3, 0, 0,
            0, 0, 1, 0,
            10, 20, 0, 1
        ], name: "t1")

        // T2: Rotate + Translate
        let t2 = try makeTransform(matrixValues: [
            0, -1, 0, 0,
            1, 0, 0, 0,
            0, 0, 1, 0,
            5, -10, 0, 1
        ], name: "t2")

        // T3: Scale + Translate
        let t3 = try makeTransform(matrixValues: [
            1.5, 0, 0, 0,
            0, 2, 0, 0,
            0, 0, 1, 0,
            2, 4, 0, 1
        ], name: "t3")

        let geom = LottieSourceIntentGeometry(
            id: "geom-confluence",
            kind: .path,
            primitive: "sh",
            transformStack: [t1, t2, t3],
            provenance: mockProvenance(name: "geom")
        )

        let normalizer = LottieSourceIntentNormalizer()
        
        var ltrSteps: [LottieSourceIntentRewriteStep] = []
        let ltrResult = normalizer.normalize(geom, strategy: .leftToRight, steps: &ltrSteps)

        var rtlSteps: [LottieSourceIntentRewriteStep] = []
        let rtlResult = normalizer.normalize(geom, strategy: .rightToLeft, steps: &rtlSteps)

        // Verify the normal form is unique (confluence)
        #expect(ltrResult.transformStack.count == 1)
        #expect(rtlResult.transformStack.count == 1)
        
        // Assert bit-identical values for matrices
        #expect(ltrResult.transformStack[0].matrix.values == rtlResult.transformStack[0].matrix.values)
        
        // Ensure steps were taken
        #expect(ltrSteps.count == 2)
        #expect(rtlSteps.count == 2)
    }

    @Test("confluence: left-to-right and right-to-left yield identical composed trims")
    func confluenceLeftToRightAndRightToLeftYieldIdenticalComposedTrims() throws {
        let m1 = makeTrim(start: 10, end: 90, offset: 0, name: "m1")
        let m2 = makeTrim(start: 20, end: 80, offset: 0, name: "m2")
        let m3 = makeTrim(start: 30, end: 70, offset: 0, name: "m3")

        let geom = LottieSourceIntentGeometry(
            id: "geom-confluence-trim",
            kind: .path,
            primitive: "sh",
            modifiers: [m1, m2, m3],
            provenance: mockProvenance(name: "geom")
        )

        let normalizer = LottieSourceIntentNormalizer()
        
        var ltrSteps: [LottieSourceIntentRewriteStep] = []
        let ltrResult = normalizer.normalize(geom, strategy: .leftToRight, steps: &ltrSteps)

        var rtlSteps: [LottieSourceIntentRewriteStep] = []
        let rtlResult = normalizer.normalize(geom, strategy: .rightToLeft, steps: &rtlSteps)

        // Verify confluence
        #expect(ltrResult.modifiers.count == 1)
        #expect(rtlResult.modifiers.count == 1)

        let ltrTrim = try #require(ltrResult.modifiers[0].trim)
        let rtlTrim = try #require(rtlResult.modifiers[0].trim)

        // Assert bit-identical start and end
        #expect(ltrTrim.start == rtlTrim.start)
        #expect(ltrTrim.end == rtlTrim.end)
        #expect(ltrTrim.offset == rtlTrim.offset)
    }
}
