import Foundation
import XCTest

final class CorpusSemanticLedgerTests: XCTestCase {
    func testCorpusFieldsAreClassifiedInSemanticLedger() throws {
        let observed = try observedFields()
        let classified = semanticLedger.keys
        let unclassified = observed.subtracting(classified).sorted()

        XCTAssertTrue(unclassified.isEmpty, unclassified.map(\.description).joined(separator: "\n"))
    }

    private func observedFields() throws -> Set<ObservedField> {
        var fields = Set<ObservedField>()
        for file in try fixtureFiles() {
            guard let document = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else {
                continue
            }
            observe(document, scope: "root", fields: &fields)
            let rootLayers = document["layers"] as? [[String: Any]] ?? []
            observe(layers: rootLayers, fields: &fields)

            for asset in document["assets"] as? [[String: Any]] ?? [] {
                observe(asset, scope: "asset", fields: &fields)
                observe(layers: asset["layers"] as? [[String: Any]] ?? [], fields: &fields)
            }
        }
        return fields
    }

    private func observe(layers: [[String: Any]], fields: inout Set<ObservedField>) {
        for layer in layers {
            observe(layer, scope: "layer", fields: &fields)
            if let transform = layer["ks"] as? [String: Any] {
                observe(transform, scope: "layer.transform", fields: &fields)
            }
            for mask in layer["masksProperties"] as? [[String: Any]] ?? [] {
                observe(mask, scope: "mask", fields: &fields)
            }
            observe(shapes: layer["shapes"] as? [[String: Any]] ?? [], fields: &fields)
        }
    }

    private func observe(shapes: [[String: Any]], fields: inout Set<ObservedField>) {
        for shape in shapes {
            let type = shape["ty"] as? String ?? "?"
            observe(shape, scope: "shape.\(type)", fields: &fields)
            observe(shapes: shape["it"] as? [[String: Any]] ?? [], fields: &fields)
        }
    }

    private func observe(_ object: [String: Any], scope: String, fields: inout Set<ObservedField>) {
        for key in object.keys {
            fields.insert(ObservedField(scope: scope, key: key))
        }
    }

    private func fixtureFiles() throws -> [URL] {
        let root = fixtureRoot()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "json" else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
        .sorted { $0.path < $1.path }
    }

    private func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieCorpus", isDirectory: true)
    }
}

private struct ObservedField: Hashable, Comparable, CustomStringConvertible {
    var scope: String
    var key: String

    var description: String {
        "\(scope).\(key)"
    }

    static func < (lhs: ObservedField, rhs: ObservedField) -> Bool {
        lhs.description < rhs.description
    }
}

private enum SemanticDisposition {
    /// Decoded into `LottieModel` and translated by `LottieImport`.
    case translated
    /// Decoded into `LottieModel`; translation is intentionally decided later.
    case modeled
    /// Reported through `ImportReport` as unsupported or approximate.
    case reported
    /// Non-rendering metadata that can be ignored without changing pixels.
    case metadata
    /// Known rendering semantic not yet modeled/reported. These are the current
    /// silent-wrong risks to burn down.
    case knownGap
}

private let semanticLedger: [ObservedField: SemanticDisposition] = {
    var ledger: [ObservedField: SemanticDisposition] = [:]

    func add(_ scope: String, _ disposition: SemanticDisposition, _ keys: [String]) {
        for key in keys {
            ledger[ObservedField(scope: scope, key: key)] = disposition
        }
    }

    add("root", .translated, ["assets", "fr", "h", "ip", "layers", "op", "v", "w"])
    add("root", .metadata, ["chars", "comps", "ddd", "fonts", "markers", "meta", "metadata", "mn", "nm", "props", "tgs"])

    add("asset", .translated, ["h", "id", "layers", "nm", "w"])
    add("asset", .metadata, ["e", "fr", "p", "t", "u"])

    add("layer", .translated, ["h", "hd", "ind", "ip", "ks", "layers", "masksProperties", "nm", "op", "parent", "refId", "sc", "sh", "shapes", "st", "sw", "sr", "ty", "w"])
    add("layer", .reported, ["td", "tm", "tp", "tt"])
    add("layer", .metadata, ["bounds", "cl", "ct", "ddd", "hasMask", "hidden", "hix", "ln", "mn", "sy"])
    add("layer", .knownGap, ["ao", "bm", "ef", "t"])

    add("layer.transform", .translated, ["a", "o", "p", "r", "s"])
    add("layer.transform", .knownGap, ["or", "rx", "ry", "rz", "sa", "sk"])
    add("layer.transform", .metadata, ["hd", "nm", "ty"])

    add("mask", .translated, ["inv", "mode", "nm", "o", "pt"])
    add("mask", .metadata, ["cl", "x"])

    add("shape.el", .translated, ["hd", "nm", "p", "s", "ty"])
    add("shape.el", .metadata, ["closed", "d", "mn"])
    add("shape.el", .knownGap, ["bm"])

    add("shape.fl", .translated, ["c", "hd", "nm", "o", "r", "ty"])
    add("shape.fl", .metadata, ["fillEnabled", "ln", "mn"])
    add("shape.fl", .knownGap, ["bm"])

    add("shape.gr", .translated, ["hd", "it", "nm", "ty"])
    add("shape.gr", .metadata, ["cix", "cl", "ix", "mn", "np"])
    add("shape.gr", .knownGap, ["bm"])

    add("shape.rc", .translated, ["hd", "nm", "p", "r", "s", "ty"])
    add("shape.rc", .metadata, ["d", "mn"])
    add("shape.rc", .knownGap, ["bm"])

    add("shape.sh", .translated, ["hd", "ks", "nm", "ty"])
    add("shape.sh", .metadata, ["cl", "closed", "ind", "ix", "mn"])
    add("shape.sh", .knownGap, ["bm", "d"])

    add("shape.st", .translated, ["c", "hd", "nm", "o", "ty", "w"])
    add("shape.st", .metadata, ["fillEnabled", "mn"])
    add("shape.st", .knownGap, ["bm", "cl", "d", "lc", "lj", "ml", "ml2"])

    add("shape.tm", .translated, ["e", "hd", "m", "nm", "o", "s", "ty"])
    add("shape.tm", .metadata, ["ix", "mn"])

    add("shape.tr", .translated, ["a", "hd", "nm", "o", "p", "r", "s", "ty"])
    add("shape.tr", .knownGap, ["sa", "sk"])

    // Unsupported shape types are currently reported by type/name at import
    // time. Their interior fields are classified as reported because the whole
    // shape operation is not translated yet.
    for scope in ["shape.gf", "shape.gs", "shape.mm", "shape.rd", "shape.rp", "shape.sr"] {
        add(
            scope,
            .reported,
            [
                "a",
                "bm",
                "c",
                "closed",
                "d",
                "e",
                "g",
                "h",
                "hd",
                "ir",
                "is",
                "ix",
                "lc",
                "lj",
                "m",
                "ml",
                "ml2",
                "mm",
                "mn",
                "nm",
                "o",
                "or",
                "os",
                "p",
                "pt",
                "r",
                "s",
                "sy",
                "t",
                "tr",
                "ty",
                "w",
            ]
        )
    }

    return ledger
}()
