//
//  LottieMath.swift
//  PureLottie
//

/// Deterministic, bit-stable floating point math operations.
///
/// This provides platform-independent implementations of transcendental functions
/// like sin and cos using argument reduction to [-pi/4, pi/4] and Taylor series.
/// This guarantees bit-identical results across macOS, Linux, Windows, and WASM.
public enum LottieMath {
    public static let pi = 3.14159265358979323846
    public static let halfPi = 1.57079632679489661923
    public static let twoPi = 6.28318530717958647692

    /// A bit-identical implementation of sin(x) using argument reduction to [-pi/4, pi/4]
    /// and Taylor series. This is 100% deterministic across all platforms.
    public static func sin(_ x: Double) -> Double {
        let reduced = reduceAngle(x)
        switch reduced.quadrant {
        case 0:
            return sinTaylor(reduced.remainder)
        case 1:
            return cosTaylor(reduced.remainder)
        case -1:
            return -cosTaylor(reduced.remainder)
        default: // 2 or -2
            return -sinTaylor(reduced.remainder)
        }
    }

    /// A bit-identical implementation of cos(x) using argument reduction to [-pi/4, pi/4]
    /// and Taylor series. This is 100% deterministic across all platforms.
    public static func cos(_ x: Double) -> Double {
        let reduced = reduceAngle(x)
        switch reduced.quadrant {
        case 0:
            return cosTaylor(reduced.remainder)
        case 1:
            return -sinTaylor(reduced.remainder)
        case -1:
            return sinTaylor(reduced.remainder)
        default: // 2 or -2
            return -cosTaylor(reduced.remainder)
        }
    }

    private struct ReducedAngle {
        let quadrant: Int // -2, -1, 0, 1, 2
        let remainder: Double // in [-pi/4, pi/4]
    }

    private static func reduceAngle(_ x: Double) -> ReducedAngle {
        // First reduce x modulo 2*pi
        var y = x.truncatingRemainder(dividingBy: twoPi)
        if y > pi {
            y -= twoPi
        } else if y < -pi {
            y += twoPi
        }

        // Now find closest multiple of pi/2
        let m = Int((y / halfPi).rounded(.toNearestOrAwayFromZero))
        let remainder = y - Double(m) * halfPi
        return ReducedAngle(quadrant: m, remainder: remainder)
    }

    private static func sinTaylor(_ x: Double) -> Double {
        let x2 = x * x
        var term = x
        var sum = x
        let coeffs: [Double] = [
            -1.0 / 6.0,
            1.0 / 120.0,
            -1.0 / 5040.0,
            1.0 / 362_880.0,
            -1.0 / 39_916_800.0,
            1.0 / 6_227_020_800.0,
            -1.0 / 1_307_674_368_000.0,
        ]
        for coeff in coeffs {
            term *= x2
            sum += term * coeff
        }
        return sum
    }

    private static func cosTaylor(_ x: Double) -> Double {
        let x2 = x * x
        var term = 1.0
        var sum = 1.0
        let coeffs: [Double] = [
            -1.0 / 2.0,
            1.0 / 24.0,
            -1.0 / 720.0,
            1.0 / 40320.0,
            -1.0 / 3_628_800.0,
            1.0 / 479_001_600.0,
            -1.0 / 87_178_291_200.0,
            1.0 / 20_922_789_888_000.0,
        ]
        for coeff in coeffs {
            term *= x2
            sum += term * coeff
        }
        return sum
    }
}
