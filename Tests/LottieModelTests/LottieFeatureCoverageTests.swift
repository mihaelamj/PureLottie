import Foundation
@testable import LottieModel
import Testing

/// Coverage meta-test (issue #138, epic #137).
///
/// What this test proves, and what it does NOT (stated honestly so the claim is
/// not overread):
///
///  - PROVES (key-set drift guard): every property key the pinned official schema
///    defines has a disposition in `LottieFeatureCoverage.registry`, and the
///    registry claims no key the schema does not define. The key list is NOT
///    hand-typed here; it is read from `Fixtures/lottie-spec-keys.txt`, which is
///    machine-extracted from lottie/lottie-spec @4b55957 by
///    docs/lottie-format/verify-coverage.sh. So a schema key added upstream and
///    left unclassified fails this test. Status: theorem (bounded to @4b55957).
///
///  - DOES NOT YET PROVE: that a key marked `.modeled` is actually decoded into a
///    typed home (a `.modeled` key the model silently drops would still pass this
///    test), nor that a `.reported` key actually reaches the ImportReport. Backing
///    each disposition with a decode/report check that bites is the remaining work
///    of #138 and must land before #138 closes. Until then this is a key-set
///    guard, not a completeness proof.
@Suite("Lottie feature coverage")
struct LottieFeatureCoverageTests {
    /// The authoritative key set, machine-extracted from the pinned schema (not
    /// retyped). Read from the committed fixture so the oracle is the schema's
    /// own output, not a hand-copy.
    static func schemaKeys() throws -> Set<String> {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/lottie-spec-keys.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let keys = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return Set(keys)
    }

    @Test("every schema key has a coverage disposition (nothing left unsaid)")
    func everySchemaKeyIsCovered() throws {
        let registered = Set(LottieFeatureCoverage.registry.keys)
        let uncovered = try Self.schemaKeys().subtracting(registered)
        #expect(uncovered.isEmpty, "schema keys with no disposition: \(uncovered.sorted())")
    }

    @Test("the registry claims no key the schema does not define (no fabrication)")
    func registryClaimsOnlySchemaKeys() throws {
        let registered = Set(LottieFeatureCoverage.registry.keys)
        let extra = try registered.subtracting(Self.schemaKeys())
        #expect(extra.isEmpty, "registry keys absent from the schema: \(extra.sorted())")
    }

    @Test("the pinned schema snapshot has the expected key count")
    func pinnedKeyCount() throws {
        #expect(try Self.schemaKeys().count == 70)
    }

    /// The JSON keys the model actually decodes, extracted from the `CodingKeys`
    /// enums in the LottieModel sources. Handles `case a = "x"` (raw value) and
    /// comma-separated bare cases (`case x, y`, where the key equals the case
    /// name). The model is Decodable-only with private CodingKeys, so this reads
    /// source: a key with no CodingKey is not decoded. Extra (non-key) identifiers
    /// only enlarge this set, so they cannot make a genuinely-undecoded `.modeled`
    /// key pass the subset check below.
    static func decodedCodingKeys() throws -> Set<String> {
        let modelDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/LottieModel")
        let files = try FileManager.default
            .contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var keys: Set<String> = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            var inBlock = false
            for rawLine in text.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.contains("enum CodingKeys") { inBlock = true
                    continue
                }
                if inBlock, line == "}" { inBlock = false
                    continue
                }
                guard inBlock, line.hasPrefix("case ") else { continue }
                for token in line.dropFirst("case ".count).split(separator: ",") {
                    let trimmed = token.trimmingCharacters(in: .whitespaces)
                    if let eq = trimmed.range(of: "=") {
                        let raw = trimmed[eq.upperBound...]
                            .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                        if !raw.isEmpty { keys.insert(raw) }
                    } else if !trimmed.isEmpty {
                        keys.insert(trimmed)
                    }
                }
            }
        }
        return keys
    }

    @Test("every .modeled key is actually decoded by a CodingKey (no modeled lie)")
    func modeledKeysAreDecoded() throws {
        let decoded = try Self.decodedCodingKeys()
        let modeled = LottieFeatureCoverage.registry
            .filter { $0.value == .modeled }
            .map(\.key)
        let undecoded = Set(modeled).subtracting(decoded)
        #expect(undecoded.isEmpty, ".modeled keys with no CodingKey (silently dropped): \(undecoded.sorted())")
    }
}
