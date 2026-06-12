import Foundation
import LottieModel
import XCTest

final class CorpusSemanticLedgerTests: XCTestCase {
    func testCorpusFieldsAreClassifiedInSemanticLedger() throws {
        let report = try ledgerReport()

        XCTAssertTrue(report.unclassifiedFields.isEmpty, report.diagnosticDescription)
    }

    func testCorpusLedgerReportsCountsAndEligibility() throws {
        let report = try ledgerReport()

        XCTAssertEqual(report.fixtureCount, 857, report.diagnosticDescription)
        XCTAssertEqual(report.uniquePayloadCount, 675, report.diagnosticDescription)
        XCTAssertEqual(report.eligibility.totalFixtures, report.fixtureCount)
        XCTAssertGreaterThan(report.featureCounts[.lowered, default: 0], 0)
        XCTAssertGreaterThan(report.featureCounts[.approximated, default: 0], 0)
        XCTAssertGreaterThan(report.featureCounts[.reported, default: 0], 0)
        XCTAssertGreaterThan(report.featureCounts[.metadata, default: 0], 0)
        XCTAssertGreaterThan(report.featureCounts[.gap, default: 0], 0)
        XCTAssertFalse(report.eligibility.fixtureReasons.isEmpty)
        XCTAssertTrue(report.diagnosticDescription.contains("Total fixtures: 857"))
        XCTAssertTrue(report.diagnosticDescription.contains("Unique payloads: 675"))
        XCTAssertTrue(report.diagnosticDescription.contains("Unclassified fields: 0"))
        XCTAssertTrue(report.diagnosticDescription.contains("Visual eligibility:"))
    }

    func testCorpusSourceProvenanceIsPinned() throws {
        let report = try ledgerReport()
        let actual = Dictionary(uniqueKeysWithValues: report.sources.map { ($0.directory, $0.fixtureCount) })

        for source in corpusSources {
            XCTAssertEqual(actual[source.directory], source.expectedFiles, source.directory)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fixtureRoot().appendingPathComponent(source.licensePath).path),
                source.licensePath
            )
        }
    }

    func testSemanticLedgerAndConformanceMatrixUseSameStatusVocabulary() throws {
        let statuses = try conformanceMatrixStatuses()
        let allowedStatuses = Set(["lowered", "approx", "reported", "gap", "modeled"])
        XCTAssertTrue(statuses.subtracting(allowedStatuses).isEmpty, statuses.sorted().joined(separator: "\n"))

        let ledgerStatuses = Set(semanticLedger.values.compactMap(\.conformanceStatus))
        XCTAssertTrue(
            ledgerStatuses.isSubset(of: statuses),
            "Ledger statuses missing from conformance matrix: \(ledgerStatuses.subtracting(statuses).sorted())"
        )
    }

    func testConformanceMatrixStatusParserAcceptsCRLFLineEndings() {
        let matrix = """
        area,original_semantics,corpus_evidence,purelottie_model,purelottie_import,target,status,required_validation
        Timing,"Frames, not seconds.",1,Model,Import,Layer,lowered,"Unit test."
        Transform,"Target has, comma.",1,Model,Import,"Layer, Path",approx,"Matrix test."
        """
        let windowsMatrix = matrix.replacingOccurrences(of: "\n", with: "\r\n")

        XCTAssertEqual(conformanceMatrixStatuses(from: windowsMatrix), Set(["lowered", "approx"]))
    }

    private func ledgerReport() throws -> CorpusLedgerReport {
        try Self.cachedReport.get()
    }

    private static let cachedReport: Result<CorpusLedgerReport, Error> = Result {
        try CorpusLedgerReport.build(fixtureRoot: fixtureRoot())
    }

    private static func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieCorpus", isDirectory: true)
    }

    private func fixtureRoot() -> URL {
        Self.fixtureRoot()
    }

    private func conformanceMatrixStatuses() throws -> Set<String> {
        let matrix = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/lottie-format/conformance-matrix.csv")
        let contents = try String(contentsOf: matrix, encoding: .utf8)

        return conformanceMatrixStatuses(from: contents)
    }

    private func conformanceMatrixStatuses(from contents: String) -> Set<String> {
        let rows = contents
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .dropFirst()
        return Set(rows.compactMap { row in
            let columns = csvColumns(row)
            guard columns.count > 6 else { return nil }
            return columns[6].trimmingCharacters(in: .whitespacesAndNewlines)
        })
    }
}

private struct CorpusLedgerReport {
    var fixtureCount: Int
    var uniquePayloadCount: Int
    var observedFields: Set<ObservedField>
    var fieldOccurrences: [ObservedField: Int]
    var unclassifiedFields: [ObservedField]
    var featureCounts: [SemanticDisposition: Int]
    var featureOccurrences: [SemanticDisposition: Int]
    var eligibility: EligibilitySummary
    var sources: [SourceSummary]

    static func build(fixtureRoot: URL) throws -> CorpusLedgerReport {
        let files = try fixtureFiles(fixtureRoot: fixtureRoot)
        var payloads = Set<Data>()
        var observedFields = Set<ObservedField>()
        var fieldOccurrences: [ObservedField: Int] = [:]
        var fixtures: [FixtureSummary] = []

        for file in files {
            let data = try Data(contentsOf: file)
            payloads.insert(data)
            let document = try LottieSourceDocument.parse(data).source

            var fixtureFields = Set<ObservedField>()
            var eligibilityFields = Set<ObservedField>()
            observe(
                document,
                scope: "root",
                observed: &observedFields,
                occurrences: &fieldOccurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
            let rootLayers = document.member("layers")?.arrayValues ?? []
            observe(
                layers: rootLayers,
                observed: &observedFields,
                occurrences: &fieldOccurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )

            for asset in document.member("assets")?.arrayValues ?? [] {
                observe(
                    asset,
                    scope: "asset",
                    observed: &observedFields,
                    occurrences: &fieldOccurrences,
                    fixtureFields: &fixtureFields,
                    eligibilityFields: &eligibilityFields
                )
                observe(
                    layers: asset.member("layers")?.arrayValues ?? [],
                    observed: &observedFields,
                    occurrences: &fieldOccurrences,
                    fixtureFields: &fixtureFields,
                    eligibilityFields: &eligibilityFields
                )
            }

            fixtures.append(FixtureSummary(path: file.path, fields: fixtureFields, eligibilityFields: eligibilityFields))
        }

        let unclassified = observedFields.subtracting(semanticLedger.keys).sorted()
        let featureCounts = Dictionary(grouping: observedFields.compactMap { semanticLedger[$0] }, by: { $0 })
            .mapValues(\.count)
        var featureOccurrences: [SemanticDisposition: Int] = [:]
        for (field, count) in fieldOccurrences {
            guard let disposition = semanticLedger[field] else { continue }
            featureOccurrences[disposition, default: 0] += count
        }

        return CorpusLedgerReport(
            fixtureCount: files.count,
            uniquePayloadCount: payloads.count,
            observedFields: observedFields,
            fieldOccurrences: fieldOccurrences,
            unclassifiedFields: unclassified,
            featureCounts: featureCounts,
            featureOccurrences: featureOccurrences,
            eligibility: EligibilitySummary(fixtures: fixtures),
            sources: sourceSummaries(fixtureRoot: fixtureRoot)
        )
    }

    var diagnosticDescription: String {
        var lines = [
            "Total fixtures: \(fixtureCount)",
            "Unique payloads: \(uniquePayloadCount)",
            "Observed unique fields: \(observedFields.count)",
            "Feature counts:",
        ]
        for disposition in SemanticDisposition.allCases {
            lines.append("  \(disposition.rawValue): \(featureCounts[disposition, default: 0]) unique, \(featureOccurrences[disposition, default: 0]) occurrences")
        }
        lines.append("Visual eligibility: \(eligibility.eligibleFixtures) eligible, \(eligibility.ineligibleFixtures) ineligible")
        for reason in eligibility.reasonCounts.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(reason.key): \(reason.value)")
        }
        if !eligibility.fixtureReasons.isEmpty {
            lines.append("Ineligible fixture examples:")
            for fixture in eligibility.fixtureReasons.prefix(10) {
                lines.append("  \(fixture.key)")
                lines.append(contentsOf: fixture.value.prefix(5).map { "    \($0)" })
            }
        }
        lines.append("Source provenance:")
        for source in sources {
            lines.append("  \(source.directory): \(source.fixtureCount) files, \(source.licensePath)")
        }
        lines.append("Unclassified fields: \(unclassifiedFields.count)")
        if !unclassifiedFields.isEmpty {
            lines.append(contentsOf: unclassifiedFields.map { "  \($0.description)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func fixtureFiles(fixtureRoot: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: fixtureRoot,
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

    private static func observe(
        layers: [JSONValue],
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        for layer in layers {
            observe(layer, scope: "layer", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            if let transform = layer.member("ks") {
                observe(transform, scope: "layer.transform", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
                observeTransformProperties(transform, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            }
            if let timeRemap = layer.member("tm") {
                observeAnimatable(timeRemap, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            }
            for mask in layer.member("masksProperties")?.arrayValues ?? [] {
                observe(mask, scope: "mask", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
                observeAnimatableProperties(
                    in: mask,
                    keys: ["o", "pt"],
                    observed: &observed,
                    occurrences: &occurrences,
                    fixtureFields: &fixtureFields,
                    eligibilityFields: &eligibilityFields
                )
            }
            observe(
                shapes: layer.member("shapes")?.arrayValues ?? [],
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
        }
    }

    private static func observe(
        shapes: [JSONValue],
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        for shape in shapes {
            let type = shape.member("ty")?.stringValue ?? "?"
            observe(shape, scope: "shape.\(type)", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            observeShapeProperties(shape, type: type, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            observe(
                shapes: shape.member("it")?.arrayValues ?? [],
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
        }
    }

    private static func observe(
        _ object: JSONValue,
        scope: String,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        for member in object.objectMembers ?? [] {
            register(
                ObservedField(scope: scope, key: member.key),
                value: member.value,
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
        }
    }

    private static func observeTransformProperties(
        _ transform: JSONValue,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        if let position = transform.member("p") {
            observePosition(position, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        }
        observeAnimatableProperties(
            in: transform,
            keys: ["a", "o", "or", "r", "rx", "ry", "rz", "s", "sa", "sk"],
            observed: &observed,
            occurrences: &occurrences,
            fixtureFields: &fixtureFields,
            eligibilityFields: &eligibilityFields
        )
    }

    private static func observeShapeProperties(
        _ shape: JSONValue,
        type: String,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        switch type {
        case "el":
            observeAnimatableProperties(
                in: shape,
                keys: ["p", "s"],
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
        case "fl":
            observeAnimatableProperties(
                in: shape,
                keys: ["c", "o"],
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
        case "rc":
            observeAnimatableProperties(
                in: shape,
                keys: ["p", "r", "s"],
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
        case "sh":
            observeAnimatableProperties(
                in: shape,
                keys: ["ks"],
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
        case "st":
            observeAnimatableProperties(
                in: shape,
                keys: ["c", "ml2", "o", "w"],
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
            observeStrokeDash(shape.member("d"), observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        case "tm":
            observeAnimatableProperties(
                in: shape,
                keys: ["e", "o", "s"],
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
        case "tr":
            observeAnimatableProperties(
                in: shape,
                keys: ["a", "o", "p", "r", "s", "sa", "sk"],
                observed: &observed,
                occurrences: &occurrences,
                fixtureFields: &fixtureFields,
                eligibilityFields: &eligibilityFields
            )
        default:
            observeAnimatableMembers(in: shape, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            observeStrokeDash(shape.member("d"), observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        }
    }

    private static func observeAnimatableProperties(
        in object: JSONValue,
        keys: [String],
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        for key in keys {
            guard let value = object.member(key) else { continue }
            observeAnimatable(value, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        }
    }

    private static func observeAnimatableMembers(
        in object: JSONValue,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        for member in object.objectMembers ?? [] where isAnimatable(member.value) {
            observeAnimatable(member.value, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        }
    }

    private static func observePosition(
        _ value: JSONValue,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        guard isSplitPosition(value) else {
            observeAnimatable(value, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            return
        }

        observe(value, scope: "position", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        observeAnimatableProperties(
            in: value,
            keys: ["x", "y", "z"],
            observed: &observed,
            occurrences: &occurrences,
            fixtureFields: &fixtureFields,
            eligibilityFields: &eligibilityFields
        )
    }

    private static func observeAnimatable(
        _ value: JSONValue,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        guard isAnimatable(value) else { return }

        observe(value, scope: "animatable", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        if let keyframes = value.member("k")?.arrayValues, keyframes.contains(where: { $0.objectMembers != nil }) {
            for keyframe in keyframes {
                observeKeyframe(keyframe, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            }
        } else if let fixedValue = value.member("k") {
            observeBezierPayload(fixedValue, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        }
    }

    private static func observeKeyframe(
        _ keyframe: JSONValue,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        guard keyframe.objectMembers != nil else { return }
        observe(keyframe, scope: "keyframe", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        for easingKey in ["i", "o"] {
            if let easing = keyframe.member(easingKey) {
                observe(easing, scope: "easing", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            }
        }
        for valueKey in ["e", "s"] {
            if let payload = keyframe.member(valueKey) {
                observeBezierPayload(payload, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            }
        }
    }

    private static func observeBezierPayload(
        _ value: JSONValue,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        if isBezier(value) {
            observe(value, scope: "bezier", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            return
        }

        for child in value.arrayValues ?? [] {
            observeBezierPayload(child, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
        }
    }

    private static func observeStrokeDash(
        _ value: JSONValue?,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        for dash in value?.arrayValues ?? [] {
            observe(dash, scope: "stroke.dash", observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            if let dashValue = dash.member("v") {
                observeAnimatable(dashValue, observed: &observed, occurrences: &occurrences, fixtureFields: &fixtureFields, eligibilityFields: &eligibilityFields)
            }
        }
    }

    private static func register(
        _ field: ObservedField,
        value: JSONValue,
        observed: inout Set<ObservedField>,
        occurrences: inout [ObservedField: Int],
        fixtureFields: inout Set<ObservedField>,
        eligibilityFields: inout Set<ObservedField>
    ) {
        observed.insert(field)
        occurrences[field, default: 0] += 1
        fixtureFields.insert(field)
        if isVisualBlocker(field, value: value) {
            eligibilityFields.insert(field)
        }
    }

    private static func isVisualBlocker(_ field: ObservedField, value: JSONValue) -> Bool {
        guard let disposition = semanticLedger[field], !disposition.isVisuallyEligible else {
            return false
        }

        switch field.description {
        case "layer.ao", "layer.ddd", "layer.bm",
             "shape.el.bm", "shape.fl.bm", "shape.gr.bm", "shape.rc.bm", "shape.sh.bm",
             "shape.st.bm":
            return value.numberValue != 0
        case "layer.sr":
            return value.numberValue != 1
        case "layer.transform.or":
            return hasVectorEffect(value)
        case "layer.transform.rx", "layer.transform.ry", "layer.transform.rz", "layer.transform.sa",
             "layer.transform.sk", "shape.tr.sa", "shape.tr.sk":
            return hasScalarEffect(value)
        case "mask.inv":
            return value.boolValue == true
        case "shape.st.d":
            return hasDashPatternEffect(value)
        case "shape.st.lc", "shape.st.lj":
            return value.numberValue != 1
        case "shape.st.ml":
            return value.numberValue != 10
        case "shape.st.ml2", "stroke.dash.v":
            return hasScalarEffect(value)
        case "shape.tm.s":
            return hasScalarEffect(value)
        case "shape.tm.e":
            return hasScalarEffect(value, identity: 100)
        case "shape.tm.o":
            return hasScalarEffect(value)
        case "shape.tm.m":
            return value.numberValue == 2
        case "keyframe.e":
            return false
        case "stroke.dash.n":
            return false
        default:
            return true
        }
    }

    private static func hasScalarEffect(_ value: JSONValue, identity: Double = 0) -> Bool {
        if let number = value.numberValue {
            return number != identity
        }
        guard let object = value.objectMembers else { return false }
        if object.contains(where: { $0.key == "x" }) { return true }
        if let keyframes = value.member("k")?.arrayValues, keyframes.contains(where: { $0.objectMembers != nil }) {
            return true
        }
        return hasNumericEffect(value.member("k"), identity: identity)
    }

    private static func hasVectorEffect(_ value: JSONValue) -> Bool {
        if let values = value.arrayValues {
            return values.contains { ($0.numberValue ?? 0) != 0 }
        }
        guard let object = value.objectMembers else { return false }
        if object.contains(where: { $0.key == "x" }) { return true }
        return hasNumericEffect(value.member("k"))
    }

    private static func hasNumericEffect(_ value: JSONValue?, identity: Double = 0) -> Bool {
        guard let value else { return false }
        if let number = value.numberValue {
            return number != identity
        }
        if let array = value.arrayValues {
            return array.contains { hasNumericEffect($0, identity: identity) }
        }
        if let object = value.objectMembers {
            return object.contains { hasNumericEffect($0.value, identity: identity) }
        }
        return false
    }

    private static func hasDashPatternEffect(_ value: JSONValue) -> Bool {
        for dash in value.arrayValues ?? [] {
            guard let dashValue = dash.member("v"), hasScalarEffect(dashValue) else { continue }
            return true
        }
        return false
    }

    private static func isSplitPosition(_ value: JSONValue) -> Bool {
        value.member("s")?.boolValue == true && (value.member("x")?.objectMembers != nil || value.member("y")?.objectMembers != nil)
    }

    private static func isAnimatable(_ value: JSONValue) -> Bool {
        value.objectMembers != nil && value.member("k") != nil
    }

    private static func isBezier(_ value: JSONValue) -> Bool {
        value.member("v") != nil && (value.member("i") != nil || value.member("o") != nil || value.member("c") != nil)
    }
}

private struct FixtureSummary {
    var path: String
    var fields: Set<ObservedField>
    var eligibilityFields: Set<ObservedField>
}

private struct EligibilitySummary {
    var totalFixtures: Int
    var eligibleFixtures: Int
    var ineligibleFixtures: Int
    var reasonCounts: [String: Int]
    var fixtureReasons: [(key: String, value: [String])]

    init(fixtures: [FixtureSummary]) {
        totalFixtures = fixtures.count
        var eligible = 0
        var reasons: [String: Int] = [:]
        var reasonByFixture: [String: [String]] = [:]

        for fixture in fixtures {
            let fixtureReasons = Self.reasons(for: fixture)
            if fixtureReasons.isEmpty {
                eligible += 1
            } else {
                reasonByFixture[fixture.path] = fixtureReasons.sorted()
                for reason in fixtureReasons {
                    reasons[reason, default: 0] += 1
                }
            }
        }

        eligibleFixtures = eligible
        ineligibleFixtures = fixtures.count - eligible
        reasonCounts = reasons
        fixtureReasons = reasonByFixture.sorted { $0.key < $1.key }
    }

    private static func reasons(for fixture: FixtureSummary) -> Set<String> {
        Set(fixture.eligibilityFields.compactMap { field in
            guard let disposition = semanticLedger[field], !disposition.isVisuallyEligible else {
                return nil
            }
            return "\(disposition.rawValue): \(field.description)"
        })
    }
}

private struct SourceSummary {
    var directory: String
    var fixtureCount: Int
    var licensePath: String
}

private struct CorpusSource {
    var directory: String
    var expectedFiles: Int
    var licensePath: String
}

private let corpusSources = [
    CorpusSource(directory: "LottieFiles-lottie-react", expectedFiles: 1, licensePath: "_licenses/LottieFiles-lottie-react-LICENSE"),
    CorpusSource(directory: "Samsung-rlottie", expectedFiles: 105, licensePath: "_licenses/Samsung-rlottie-COPYING"),
    CorpusSource(directory: "TelegramMessenger-rlottie", expectedFiles: 97, licensePath: "_licenses/TelegramMessenger-rlottie-COPYING"),
    CorpusSource(directory: "airbnb-lottie-android", expectedFiles: 451, licensePath: "_licenses/airbnb-lottie-android-LICENSE"),
    CorpusSource(directory: "airbnb-lottie-ios", expectedFiles: 186, licensePath: "_licenses/airbnb-lottie-ios-LICENSE"),
    CorpusSource(directory: "airbnb-lottie-web", expectedFiles: 17, licensePath: "_licenses/airbnb-lottie-web-LICENSE.md"),
]

private func sourceSummaries(fixtureRoot: URL) -> [SourceSummary] {
    corpusSources.map { source in
        let directory = fixtureRoot.appendingPathComponent(source.directory, isDirectory: true)
        let count = (FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" }
            .count) ?? 0
        return SourceSummary(directory: source.directory, fixtureCount: count, licensePath: source.licensePath)
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

private enum SemanticDisposition: String, CaseIterable {
    /// Decoded and lowered into the backend without a known semantic loss.
    case lowered
    /// Decoded/lowered with a documented semantic approximation.
    case approximated
    /// Decoded or detected and reported before silent rendering.
    case reported
    /// Non-rendering metadata that can be ignored without changing pixels.
    case metadata
    /// Known rendering semantic not yet modeled or reported.
    case gap

    var isVisuallyEligible: Bool {
        switch self {
        case .lowered, .metadata:
            true
        case .approximated, .reported, .gap:
            false
        }
    }

    var conformanceStatus: String? {
        switch self {
        case .lowered:
            "lowered"
        case .approximated:
            "approx"
        case .reported:
            "reported"
        case .gap:
            "gap"
        case .metadata:
            nil
        }
    }
}

private let semanticLedger: [ObservedField: SemanticDisposition] = {
    var ledger: [ObservedField: SemanticDisposition] = [:]

    func add(_ scope: String, _ disposition: SemanticDisposition, _ keys: [String]) {
        for key in keys {
            ledger[ObservedField(scope: scope, key: key)] = disposition
        }
    }

    add("root", .lowered, ["assets", "fr", "h", "ip", "layers", "op", "v", "w"])
    add("root", .metadata, ["chars", "comps", "ddd", "fonts", "markers", "meta", "metadata", "mn", "nm", "props", "tgs"])

    add("asset", .lowered, ["h", "id", "layers", "nm", "w"])
    add("asset", .metadata, ["e", "fr", "p", "t", "u"])

    add("layer", .lowered, ["h", "hd", "ind", "ip", "ks", "layers", "nm", "op", "refId", "sc", "sh", "shapes", "st", "sw", "ty", "w"])
    add("layer", .approximated, ["masksProperties", "parent", "sr"])
    add("layer", .reported, ["ao", "ddd", "td", "tm", "tp", "tt"])
    add("layer", .metadata, ["bounds", "cl", "ct", "hasMask", "hidden", "hix", "ln", "mn", "sy"])
    add("layer", .gap, ["bm", "ef", "t"])

    add("layer.transform", .lowered, ["a", "o", "p", "r", "s"])
    add("layer.transform", .reported, ["or", "rx", "ry", "rz", "sa", "sk"])
    add("layer.transform", .metadata, ["hd", "nm", "ty"])

    add("mask", .approximated, ["inv", "mode", "o", "pt"])
    add("mask", .metadata, ["cl", "nm", "x"])

    add("position", .lowered, ["s", "x", "y", "z"])

    add("animatable", .lowered, ["a", "k"])
    add("animatable", .metadata, ["ix", "l", "sid"])
    add("animatable", .reported, ["p"])
    add("animatable", .gap, ["x"])

    add("keyframe", .approximated, ["e", "h", "i", "o", "s", "t", "ti", "to"])
    add("keyframe", .gap, ["__fnct"])
    add("keyframe", .metadata, ["n"])

    add("easing", .approximated, ["x", "y"])

    add("bezier", .lowered, ["c", "i", "o", "v"])

    add("stroke.dash", .reported, ["n", "v"])
    add("stroke.dash", .metadata, ["nm"])

    add("shape.el", .lowered, ["hd", "nm", "p", "s", "ty"])
    add("shape.el", .metadata, ["closed", "d", "mn"])
    add("shape.el", .gap, ["bm"])

    add("shape.fl", .lowered, ["c", "hd", "nm", "o", "r", "ty"])
    add("shape.fl", .metadata, ["fillEnabled", "ln", "mn"])
    add("shape.fl", .reported, ["bm"])

    add("shape.gr", .lowered, ["hd", "it", "nm", "ty"])
    add("shape.gr", .metadata, ["cix", "cl", "ix", "mn", "np"])
    add("shape.gr", .gap, ["bm"])

    add("shape.rc", .lowered, ["hd", "nm", "p", "r", "s", "ty"])
    add("shape.rc", .metadata, ["d", "mn"])
    add("shape.rc", .gap, ["bm"])

    add("shape.sh", .lowered, ["hd", "ks", "nm", "ty"])
    add("shape.sh", .metadata, ["cl", "closed", "ind", "ix", "mn"])
    add("shape.sh", .gap, ["bm", "d"])

    add("shape.st", .lowered, ["c", "hd", "nm", "o", "ty", "w"])
    add("shape.st", .reported, ["bm", "d", "lc", "lj", "ml", "ml2"])
    add("shape.st", .metadata, ["cl", "fillEnabled", "mn"])

    add("shape.tm", .approximated, ["e", "m", "o", "s"])
    add("shape.tm", .metadata, ["hd", "ix", "mn", "nm", "ty"])

    add("shape.tr", .lowered, ["a", "hd", "nm", "o", "p", "r", "s", "ty"])
    add("shape.tr", .gap, ["sa", "sk"])

    // Unsupported shape types are currently reported by type/name at import
    // time. Their interior fields are classified as reported because the whole
    // shape operation is not lowered yet.
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

private func csvColumns(_ line: String) -> [String] {
    var columns: [String] = []
    var current = ""
    var isQuoted = false
    var iterator = line.makeIterator()

    while let character = iterator.next() {
        if character == "\"" {
            if isQuoted, let next = iterator.next() {
                if next == "\"" {
                    current.append("\"")
                } else {
                    isQuoted = false
                    if next == "," {
                        columns.append(current)
                        current = ""
                    } else {
                        current.append(next)
                    }
                }
            } else {
                isQuoted.toggle()
            }
        } else if character == ",", !isQuoted {
            columns.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }

    columns.append(current)
    return columns
}
