import Foundation
import LottieModel
import XCTest

/// Model-decode totality (issue #138, epic #137).
///
/// `LottieTotalityTests.testFuzzedInputs` fuzzes the parse + validate layer
/// (`LottieSourceDocument.parse` + `LottieValidator`). This covers the typed
/// Decodable layer underneath it: `LottieAnimation.decode` must reject malformed
/// or type-confused input with a thrown error (it strict-decodes; it must not
/// silently produce a model), and across a deterministic fuzz sample it must
/// throw or succeed, never trap. Reaching the end of the loop proves no input in
/// the sample traps (a trap, e.g. force-unwrap or fatalError, would abort the
/// test process); this samples robustness, it does not prove totality over all
/// inputs.
///
/// `FuzzPRNG` is the deterministic generator declared in `LottieTotalityTests`
/// (same test target).
final class LottieModelDecodeTotalityTests: XCTestCase {
    func testDecodeRejectsMalformedInput() {
        // Strict decode must THROW on each of these, not silently yield a model.
        let mustThrow = [
            "",
            "{",
            "[]",
            "null",
            "42",
            "\"string\"",
            "{\"v\":\"5.5.7\"}", // missing required fr/ip/op/w/h
            "{\"fr\":[],\"ip\":0,\"op\":1,\"w\":1,\"h\":1,\"layers\":[]}", // fr wrong type
            "{\"fr\":60,\"ip\":0,\"op\":1,\"w\":1,\"h\":1,\"layers\":\"no\"}", // layers wrong type
            "{\"fr\":60,\"ip\":0,\"op\":1,\"w\":1,\"h\":1}", // missing required layers
        ]
        for input in mustThrow {
            XCTAssertThrowsError(
                try LottieAnimation.decode(from: Data(input.utf8)),
                "strict decode should reject malformed input: \(input)"
            )
        }
    }

    func testDecodeIsTotalOnFuzzedBytes() {
        // Deterministic byte mutations of a well-formed seed. Decode must throw or
        // succeed for every input; completing the loop proves it never traps.
        var prng = FuzzPRNG(state: 1337)
        let seed = Array("{\"fr\":60,\"ip\":0,\"op\":60,\"w\":64,\"h\":64,\"layers\":[]}".utf8)
        for _ in 0 ..< 500 {
            var bytes = seed
            let edits = 1 + prng.next(upperBound: 8)
            for _ in 0 ..< edits where !bytes.isEmpty {
                bytes[prng.next(upperBound: bytes.count)] = UInt8(prng.next(upperBound: 256))
            }
            _ = try? LottieAnimation.decode(from: Data(bytes))
        }
        // Also feed raw random byte strings (often invalid UTF-8 / non-JSON).
        for _ in 0 ..< 500 {
            let length = prng.next(upperBound: 64)
            var bytes: [UInt8] = []
            for _ in 0 ..< length {
                bytes.append(UInt8(prng.next(upperBound: 256)))
            }
            _ = try? LottieAnimation.decode(from: Data(bytes))
        }
    }
}
