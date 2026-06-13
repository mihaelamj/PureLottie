//
//  LottieDeterminismTests.swift
//  PureLottie
//

import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie determinism check")
struct LottieDeterminismTests {
    @Test("sin and cos bitwise determinism")
    func sinAndCosBitwiseDeterminism() {
        let testInputs: [Double] = [
            0.0,
            LottieMath.pi / 2,
            LottieMath.pi / 4,
            1.0,
            -2.5,
            100.0,
        ]

        // Print or verify bit patterns to ensure they are stable.
        for input in testInputs {
            let s = LottieMath.sin(input)
            let c = LottieMath.cos(input)

            // Verify that they are close to the system's sin/cos
            // to ensure correctness (C1 rule).
            #expect(abs(s - Foundation.sin(input)) < 1e-14)
            #expect(abs(c - Foundation.cos(input)) < 1e-14)
        }

        // Hardcoded expected bit patterns for strict cross-platform identity check.
        let testCases: [(input: Double, expectedSinPattern: UInt64, expectedCosPattern: UInt64)] = [
            (0.0, 0, 4_607_182_418_800_017_408), // sin(0)=0, cos(0)=1.0
            (LottieMath.pi / 2, 4_607_182_418_800_017_408, 9_223_372_036_854_775_808), // sin(pi/2)=1.0, cos(pi/2)=-0.0
            (LottieMath.pi / 4, 4_604_544_271_217_802_188, 4_604_544_271_217_802_188), // sin(pi/4)=cos(pi/4)
            (1.0, 4_605_754_516_372_524_270, 4_603_041_830_072_026_762),
            (-2.5, 13_826_937_814_250_408_623, 13_828_763_316_576_947_071),
            (100.0, 13_826_108_192_625_282_458, 4_605_942_297_449_095_154),
        ]

        for testCase in testCases {
            let s = LottieMath.sin(testCase.input)
            let c = LottieMath.cos(testCase.input)
            #expect(s.bitPattern == testCase.expectedSinPattern, "sin(\(testCase.input)) bit pattern mismatch: got \(s.bitPattern), expected \(testCase.expectedSinPattern)")
            #expect(c.bitPattern == testCase.expectedCosPattern, "cos(\(testCase.input)) bit pattern mismatch: got \(c.bitPattern), expected \(testCase.expectedCosPattern)")
        }
    }

    @Test("rotation matrix bitwise determinism")
    func rotationMatrixBitwiseDeterminism() {
        let matrix = LottieTransformMatrix.rotationZ(1.0)
        let expectedValues: [UInt64] = [
            4_603_041_830_072_026_762, 13_829_126_553_227_300_078, 0, 0,
            4_605_754_516_372_524_270, 4_603_041_830_072_026_762, 0, 0,
            0, 0, 4_607_182_418_800_017_408, 0,
            0, 0, 0, 4_607_182_418_800_017_408,
        ]

        #expect(matrix.values.count == 16)
        for i in 0 ..< 16 {
            #expect(matrix.values[i].bitPattern == expectedValues[i], "matrix.values[\(i)] bit pattern mismatch: got \(matrix.values[i].bitPattern), expected \(expectedValues[i])")
        }
    }
}
