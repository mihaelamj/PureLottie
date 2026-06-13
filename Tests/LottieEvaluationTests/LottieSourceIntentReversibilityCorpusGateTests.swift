import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie source-intent reversibility corpus gate")
struct LottieSourceIntentReversibilityCorpusGateTests {
    @Test("curated corpus has deterministic source-intent reversibility snapshot")
    func curatedCorpusHasDeterministicSourceIntentReversibilitySnapshot() throws {
        let manifest = try loadManifest()
        var fixtures: [CorpusReversibilityGateReport.Fixture] = []

        for entry in manifest {
            let sourceURL = url(fromOracleRootPath: entry.lottie)
            let animation = try LottieAnimation.decode(from: Data(contentsOf: sourceURL))
            let webIntent = try LottieWebIntentTrace.decodeValidated(
                from: Data(contentsOf: url(fromOracleRootPath: entry.lottieWebIntent))
            )
            #expect(webIntent.frames.map(\.frame) == entry.frames.map(\.frame))

            let roundTrip = LottieSourceIntentTransformTimingRoundTripGate().report(
                animation: animation,
                source: LottieDecompiledSourceIntentSource(
                    identity: entry.id,
                    path: entry.lottie,
                    frameCount: entry.frames.count
                ),
                selectedFrames: entry.frames.map {
                    LottieSourceIntentRoundTripSelection(frame: $0.frame, rationale: $0.rationale)
                }
            )
            try roundTrip.validate()
            #expect(roundTrip.frames.map(\.sourceFrame) == entry.frames.map(\.frame))
            #expect(roundTrip.frames.map(\.rationale) == entry.frames.map(\.rationale))
            #expect(roundTrip.findingCount == 0, "\(entry.id) has unrecorded source-intent round-trip findings")
            if entry.semanticStatus == .diagnosed {
                #expect(roundTrip.lossCount > 0, "\(entry.id) is diagnosed but has no path-bearing loss records")
            }

            fixtures.append(CorpusReversibilityGateReport.Fixture(entry: entry, report: roundTrip))
        }

        let report = CorpusReversibilityGateReport(fixtures: fixtures)
        try assertSnapshot(
            report,
            manifestCount: manifest.count,
            selectedFrameCount: manifest.flatMap(\.frames).count
        )
    }

    @Test("corpus reversibility snapshot validation rejects missing frame rationales")
    func corpusReversibilitySnapshotValidationRejectsMissingFrameRationales() {
        let report = CorpusReversibilityGateReport(fixtures: [
            .init(
                id: "bad",
                semanticStatus: "modeled",
                lottie: "bad.json",
                lottieWebIntent: "bad.intent.json",
                coverage: ["rectangle"],
                selectedFrameCount: 1,
                excluded: false,
                status: "exact",
                frameCount: 1,
                findingCount: 0,
                lossCount: 0,
                reconstructedFactCount: 0,
                sourcePathCount: 0,
                frames: [
                    .init(
                        frame: 0,
                        rationale: "",
                        status: "exact",
                        localTimeSeconds: 0,
                        layerCount: 0,
                        findingCount: 0,
                        lossCount: 0,
                        reconstructedFactCount: 0,
                        sourcePaths: [],
                        layers: [],
                        losses: [],
                        findings: []
                    ),
                ]
            ),
        ])

        let errors = CorpusReversibilityGateReportValidator().collectErrors(in: report)
        #expect(errors.contains { $0.ruleID == "lottie.reversibility.frame.rationale" })
    }

    @Test("corpus reversibility snapshot validation rejects pathless losses")
    func corpusReversibilitySnapshotValidationRejectsPathlessLosses() {
        let report = CorpusReversibilityGateReport(fixtures: [
            .init(
                id: "bad-loss",
                semanticStatus: "modeled",
                lottie: "bad-loss.json",
                lottieWebIntent: "bad-loss.intent.json",
                coverage: ["stroke"],
                selectedFrameCount: 1,
                excluded: false,
                status: "recordedLoss",
                frameCount: 1,
                findingCount: 0,
                lossCount: 1,
                reconstructedFactCount: 0,
                sourcePathCount: 0,
                frames: [
                    .init(
                        frame: 0,
                        rationale: "Path-bearing loss validation fixture.",
                        status: "recordedLoss",
                        localTimeSeconds: 0,
                        layerCount: 0,
                        findingCount: 0,
                        lossCount: 1,
                        reconstructedFactCount: 0,
                        sourcePaths: [],
                        layers: [],
                        losses: [
                            CorpusReversibilityGateReport.Loss(
                                loss: LottieDecompiledSourceIntentLoss(
                                    kind: .unsupported,
                                    reconstructability: .notReconstructable,
                                    phase: "lowering",
                                    classification: "reported",
                                    modelPath: "$.fixtures[0].frames[0].losses[0]",
                                    sourcePath: "",
                                    jsonPath: "",
                                    ruleID: "",
                                    reason: ""
                                )
                            ),
                        ],
                        findings: []
                    ),
                ]
            ),
        ])

        let errors = CorpusReversibilityGateReportValidator().collectErrors(in: report)
        #expect(errors.contains { $0.ruleID == "lottie.reversibility.loss.rule-id" })
        #expect(errors.contains { $0.ruleID == "lottie.reversibility.loss.source-path" })
        #expect(errors.contains { $0.ruleID == "lottie.reversibility.loss.json-path" })
        #expect(errors.contains { $0.ruleID == "lottie.reversibility.loss.reason" })
    }

    private func assertSnapshot(
        _ report: CorpusReversibilityGateReport,
        manifestCount: Int,
        selectedFrameCount: Int
    ) throws {
        let errors = CorpusReversibilityGateReportValidator().collectErrors(in: report)
        #expect(errors.isEmpty, "\(errors.map(\.description).joined(separator: "\n"))")
        #expect(report.schema.name == "purelottie.source-intent-reversibility-gate")
        #expect(report.schema.version == 1)
        #expect(report.fixtureCount == manifestCount)
        #expect(report.fixtureCount >= 31)
        #expect(report.selectedFrameCount == selectedFrameCount)
        #expect(report.excludedFixtureCount == 0)
        #expect(report.excludedFixtures.isEmpty)
        #expect(report.findingCount == 0)
        #expect(report.lossCount > 0)
        #expect(report.reconstructedFactCount > 0)
        #expect(report.sourcePathCount > 0)
        #expect(report.fixtures.allSatisfy { !$0.frames.isEmpty })
        #expect(report.fixtures.allSatisfy { fixture in
            fixture.frames.allSatisfy { !$0.rationale.isEmpty }
        })
        #expect(report.fixtures.contains { $0.status == "recordedLoss" })
        #expect(report.fixtures.contains { $0.status == "exact" })

        let encoded = try encoded(report)
        let snapshotURL = repositoryRoot()
            .appendingPathComponent("Tests/Fixtures/LottieOracle/reversibility-gate", isDirectory: true)
            .appendingPathComponent("report.json")
        if ProcessInfo.processInfo.environment["PURELOTTIE_UPDATE_REVERSIBILITY_GATE_REPORT"] == "1" {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoded.write(to: snapshotURL, options: .atomic)
            return
        }

        let expected = try Data(contentsOf: snapshotURL)
        let encodedString = String(data: encoded, encoding: .utf8)?.replacingOccurrences(of: "\r\n", with: "\n")
        let expectedString = String(data: expected, encoding: .utf8)?.replacingOccurrences(of: "\r\n", with: "\n")
        #expect(
            encodedString == expectedString,
            "Regenerate with PURELOTTIE_UPDATE_REVERSIBILITY_GATE_REPORT=1 swift test --filter LottieSourceIntentReversibilityCorpusGateTests"
        )
    }

    private func loadManifest() throws -> [CorpusFixtureManifestEntry] {
        try JSONDecoder().decode(
            [CorpusFixtureManifestEntry].self,
            from: Data(contentsOf: repositoryRoot().appendingPathComponent("Tools/LottieOracle/oracle-fixtures.json"))
        )
    }

    private func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func url(fromOracleRootPath path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: repositoryRoot().appendingPathComponent("Tools/LottieOracle", isDirectory: true))
            .standardizedFileURL
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct CorpusReversibilityGateReport: Codable, Equatable, Validatable {
    var schema = Schema()
    var fixtureCount: Int
    var selectedFrameCount: Int
    var excludedFixtureCount: Int
    var exactFixtureCount: Int
    var recordedLossFixtureCount: Int
    var mismatchFixtureCount: Int
    var findingCount: Int
    var lossCount: Int
    var reconstructedFactCount: Int
    var sourcePathCount: Int
    var excludedFixtures: [Exclusion]
    var fixtures: [Fixture]

    init(fixtures: [Fixture], excludedFixtures: [Exclusion] = []) {
        self.fixtures = fixtures.sorted { $0.id < $1.id }
        self.excludedFixtures = excludedFixtures.sorted()
        fixtureCount = self.fixtures.count
        selectedFrameCount = self.fixtures.flatMap(\.frames).count
        excludedFixtureCount = self.excludedFixtures.count
        exactFixtureCount = self.fixtures.filter { $0.status == "exact" }.count
        recordedLossFixtureCount = self.fixtures.filter { $0.status == "recordedLoss" }.count
        mismatchFixtureCount = self.fixtures.filter { $0.status == "mismatch" }.count
        findingCount = self.fixtures.map(\.findingCount).reduce(0, +)
        lossCount = self.fixtures.map(\.lossCount).reduce(0, +)
        reconstructedFactCount = self.fixtures.map(\.reconstructedFactCount).reduce(0, +)
        sourcePathCount = self.fixtures.map(\.sourcePathCount).reduce(0, +)
    }

    struct Schema: Codable, Equatable, Validatable {
        var name = "purelottie.source-intent-reversibility-gate"
        var version = 1
    }

    struct Exclusion: Codable, Equatable, Comparable, Validatable {
        var id: String
        var lottie: String
        var sourcePath: String
        var jsonPath: String
        var reason: String

        static func < (lhs: Exclusion, rhs: Exclusion) -> Bool {
            lhs.sortKey < rhs.sortKey
        }

        private var sortKey: String {
            "\(id)\n\(lottie)\n\(sourcePath)\n\(jsonPath)\n\(reason)"
        }
    }

    struct Fixture: Codable, Equatable, Validatable {
        var id: String
        var semanticStatus: String
        var lottie: String
        var lottieWebIntent: String
        var coverage: [String]
        var selectedFrameCount: Int
        var excluded: Bool
        var status: String
        var frameCount: Int
        var findingCount: Int
        var lossCount: Int
        var reconstructedFactCount: Int
        var sourcePathCount: Int
        var frames: [Frame]

        init(entry: CorpusFixtureManifestEntry, report: LottieSourceIntentRoundTripReport) {
            id = entry.id
            semanticStatus = entry.semanticStatus.rawValue
            lottie = entry.lottie
            lottieWebIntent = entry.lottieWebIntent
            coverage = entry.coverage.sorted()
            selectedFrameCount = entry.frames.count
            excluded = false
            frameCount = report.frames.count
            findingCount = report.findingCount
            lossCount = report.lossCount
            frames = report.frames.map(Frame.init(frame:))
            reconstructedFactCount = frames.map(\.reconstructedFactCount).reduce(0, +)
            sourcePathCount = Set(frames.flatMap(\.sourcePaths)).count
            status = Self.status(findingCount: findingCount, lossCount: lossCount)
        }

        init(
            id: String,
            semanticStatus: String,
            lottie: String,
            lottieWebIntent: String,
            coverage: [String],
            selectedFrameCount: Int,
            excluded: Bool,
            status: String,
            frameCount: Int,
            findingCount: Int,
            lossCount: Int,
            reconstructedFactCount: Int,
            sourcePathCount: Int,
            frames: [Frame]
        ) {
            self.id = id
            self.semanticStatus = semanticStatus
            self.lottie = lottie
            self.lottieWebIntent = lottieWebIntent
            self.coverage = coverage
            self.selectedFrameCount = selectedFrameCount
            self.excluded = excluded
            self.status = status
            self.frameCount = frameCount
            self.findingCount = findingCount
            self.lossCount = lossCount
            self.reconstructedFactCount = reconstructedFactCount
            self.sourcePathCount = sourcePathCount
            self.frames = frames
        }

        private static func status(findingCount: Int, lossCount: Int) -> String {
            if findingCount > 0 {
                return "mismatch"
            }
            return lossCount > 0 ? "recordedLoss" : "exact"
        }
    }

    struct Frame: Codable, Equatable, Validatable {
        var frame: Double
        var rationale: String
        var status: String
        var localTimeSeconds: Double?
        var layerCount: Int
        var findingCount: Int
        var lossCount: Int
        var reconstructedFactCount: Int
        var sourcePaths: [String]
        var layers: [Layer]
        var losses: [Loss]
        var findings: [Finding]

        init(frame: LottieSourceIntentRoundTripFrame) {
            self.frame = frame.sourceFrame
            rationale = frame.rationale
            status = Self.status(findingCount: frame.findingCount, lossCount: frame.lossCount)
            localTimeSeconds = frame.localTimeSeconds
            layerCount = frame.layerCount
            findingCount = frame.findingCount
            lossCount = frame.lossCount
            layers = frame.layers.map(Layer.init(layer:)).sorted()
            losses = frame.losses.map(Loss.init(loss:)).sorted()
            findings = (frame.findings + frame.layers.flatMap(\.findings)).map(Finding.init(finding:)).sorted()
            reconstructedFactCount = layers.map(\.reconstructedFactCount).reduce(0, +)
            sourcePaths = Array(Set(layers.map(\.sourcePath) + losses.map(\.sourcePath) + findings.map(\.sourcePath))).sorted()
        }

        init(
            frame: Double,
            rationale: String,
            status: String,
            localTimeSeconds: Double?,
            layerCount: Int,
            findingCount: Int,
            lossCount: Int,
            reconstructedFactCount: Int,
            sourcePaths: [String],
            layers: [Layer],
            losses: [Loss],
            findings: [Finding]
        ) {
            self.frame = frame
            self.rationale = rationale
            self.status = status
            self.localTimeSeconds = localTimeSeconds
            self.layerCount = layerCount
            self.findingCount = findingCount
            self.lossCount = lossCount
            self.reconstructedFactCount = reconstructedFactCount
            self.sourcePaths = sourcePaths
            self.layers = layers
            self.losses = losses
            self.findings = findings
        }

        private static func status(findingCount: Int, lossCount: Int) -> String {
            if findingCount > 0 {
                return "mismatch"
            }
            return lossCount > 0 ? "recordedLoss" : "exact"
        }
    }

    struct Layer: Codable, Equatable, Comparable, Validatable {
        var id: String
        var name: String?
        var sourcePath: String
        var jsonPath: String
        var timingMode: String?
        var localFrame: Double
        var decompiledLocalFrame: Double?
        var opacity: Double
        var decompiledOpacity: Double?
        var position: [Double]
        var decompiledPosition: [Double]
        var scale: [Double]
        var decompiledScale: [Double]
        var rotationZDegrees: Double
        var decompiledRotationZDegrees: Double?
        var matrixTranslation: [Double]
        var decompiledMatrixTranslation: [Double]
        var geometryCount: Int
        var decompiledGeometryCount: Int
        var styleCount: Int
        var decompiledStyleCount: Int
        var trimTraceCount: Int
        var decompiledTrimTraceCount: Int
        var maskCount: Int
        var decompiledMaskCount: Int
        var hasMatte: Bool
        var decompiledHasMatte: Bool
        var findingCount: Int
        var reconstructedFactCount: Int

        init(layer: LottieSourceIntentRoundTripLayer) {
            id = layer.id
            name = layer.name
            sourcePath = layer.sourcePath
            jsonPath = layer.jsonPath
            timingMode = layer.timingMode
            localFrame = layer.localFrame
            decompiledLocalFrame = layer.decompiledLocalFrame
            opacity = layer.opacity
            decompiledOpacity = layer.decompiledOpacity
            position = layer.position
            decompiledPosition = layer.decompiledPosition
            scale = layer.scale
            decompiledScale = layer.decompiledScale
            rotationZDegrees = layer.rotationZDegrees
            decompiledRotationZDegrees = layer.decompiledRotationZDegrees
            matrixTranslation = layer.matrixTranslation
            decompiledMatrixTranslation = layer.decompiledMatrixTranslation
            geometryCount = layer.geometryCount
            decompiledGeometryCount = layer.decompiledGeometryCount
            styleCount = layer.styleCount
            decompiledStyleCount = layer.decompiledStyleCount
            trimTraceCount = layer.trimTraceCount
            decompiledTrimTraceCount = layer.decompiledTrimTraceCount
            maskCount = layer.maskCount
            decompiledMaskCount = layer.decompiledMaskCount
            hasMatte = layer.hasMatte
            decompiledHasMatte = layer.decompiledHasMatte
            findingCount = layer.findings.count
            reconstructedFactCount = 8
                + geometryCount
                + decompiledGeometryCount
                + styleCount
                + decompiledStyleCount
                + trimTraceCount
                + decompiledTrimTraceCount
                + maskCount
                + decompiledMaskCount
                + (hasMatte ? 1 : 0)
                + (decompiledHasMatte ? 1 : 0)
        }

        static func < (lhs: Layer, rhs: Layer) -> Bool {
            lhs.sortKey < rhs.sortKey
        }

        private var sortKey: String {
            "\(sourcePath)\n\(jsonPath)\n\(id)"
        }
    }

    struct Loss: Codable, Equatable, Comparable, Validatable {
        var kind: String
        var reconstructability: String
        var phase: String
        var classification: String
        var modelPath: String
        var sourcePath: String
        var jsonPath: String
        var sourceRange: String?
        var ruleID: String
        var reason: String
        var evidence: String?

        init(loss: LottieDecompiledSourceIntentLoss) {
            kind = loss.kind.rawValue
            reconstructability = loss.reconstructability.rawValue
            phase = loss.phase
            classification = loss.classification
            modelPath = loss.modelPath
            sourcePath = loss.sourcePath ?? ""
            jsonPath = loss.jsonPath ?? ""
            sourceRange = loss.sourceRange
            ruleID = loss.ruleID ?? ""
            reason = loss.reason
            evidence = loss.evidence
        }

        static func < (lhs: Loss, rhs: Loss) -> Bool {
            lhs.sortKey < rhs.sortKey
        }

        private var sortKey: String {
            "\(sourcePath)\n\(jsonPath)\n\(modelPath)\n\(ruleID)\n\(reason)"
        }
    }

    struct Finding: Codable, Equatable, Comparable, Validatable {
        var ruleID: String
        var sourcePath: String
        var jsonPath: String
        var property: String
        var expected: String
        var actual: String
        var reason: String

        init(finding: LottieSourceIntentRoundTripFinding) {
            ruleID = finding.ruleID
            sourcePath = finding.sourcePath
            jsonPath = finding.jsonPath
            property = finding.property
            expected = finding.expected
            actual = finding.actual
            reason = finding.reason
        }

        static func < (lhs: Finding, rhs: Finding) -> Bool {
            lhs.sortKey < rhs.sortKey
        }

        private var sortKey: String {
            "\(sourcePath)\n\(jsonPath)\n\(property)\n\(ruleID)"
        }
    }
}

private final class CorpusReversibilityGateReportValidator {
    private let validations = CorpusReversibilityGateBuiltinValidation.defaultValidations

    func collectErrors(in report: CorpusReversibilityGateReport) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(report, at: JSONPath(), in: report, errors: &errors)
        visit(report.schema, at: JSONPath([.key("schema")]), in: report, errors: &errors)
        for exclusionIndex in report.excludedFixtures.indices {
            visit(
                report.excludedFixtures[exclusionIndex],
                at: JSONPath([.key("excludedFixtures"), .index(exclusionIndex)]),
                in: report,
                errors: &errors
            )
        }
        for fixtureIndex in report.fixtures.indices {
            let fixture = report.fixtures[fixtureIndex]
            let fixturePath = JSONPath([.key("fixtures"), .index(fixtureIndex)])
            visit(fixture, at: fixturePath, in: report, errors: &errors)
            for frameIndex in fixture.frames.indices {
                let frame = fixture.frames[frameIndex]
                let framePath = fixturePath.appending(.key("frames")).appending(.index(frameIndex))
                visit(frame, at: framePath, in: report, errors: &errors)
                for layerIndex in frame.layers.indices {
                    visit(
                        frame.layers[layerIndex],
                        at: framePath.appending(.key("layers")).appending(.index(layerIndex)),
                        in: report,
                        errors: &errors
                    )
                }
                for lossIndex in frame.losses.indices {
                    visit(
                        frame.losses[lossIndex],
                        at: framePath.appending(.key("losses")).appending(.index(lossIndex)),
                        in: report,
                        errors: &errors
                    )
                }
                for findingIndex in frame.findings.indices {
                    visit(
                        frame.findings[findingIndex],
                        at: framePath.appending(.key("findings")).appending(.index(findingIndex)),
                        in: report,
                        errors: &errors
                    )
                }
            }
        }
        return errors
    }

    private func visit(
        _ subject: some Validatable,
        at path: JSONPath,
        in report: CorpusReversibilityGateReport,
        errors: inout [ValidationError]
    ) {
        for validation in validations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: report))
        }
    }
}

private enum CorpusReversibilityGateBuiltinValidation {
    fileprivate static var defaultValidations: [CorpusReversibilityGateAnyValidation] {
        [
            CorpusReversibilityGateAnyValidation(schemaNameAndVersionAreSupported),
            CorpusReversibilityGateAnyValidation(reportAggregatesMatchFixtures),
            CorpusReversibilityGateAnyValidation(fixturesAreComplete),
            CorpusReversibilityGateAnyValidation(framesAreExplainedUniqueAndAggregated),
            CorpusReversibilityGateAnyValidation(layersArePathBearing),
            CorpusReversibilityGateAnyValidation(lossesArePathBearing),
            CorpusReversibilityGateAnyValidation(findingsArePathBearing),
            CorpusReversibilityGateAnyValidation(exclusionsArePathBearing),
        ]
    }

    static var schemaNameAndVersionAreSupported:
        Validation<CorpusReversibilityGateReport, CorpusReversibilityGateReport.Schema>
    {
        Validation(
            ruleID: "lottie.reversibility.schema.supported",
            description: "Corpus reversibility snapshot schema name is purelottie.source-intent-reversibility-gate and version is 1",
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.name != "purelottie.source-intent-reversibility-gate" {
                errors.append(error("lottie.reversibility.schema.name", at: context.codingPath.appending(.key("name"))))
            }
            if context.subject.version != 1 {
                errors.append(error("lottie.reversibility.schema.version", at: context.codingPath.appending(.key("version"))))
            }
            return errors
        }
    }

    static var reportAggregatesMatchFixtures:
        Validation<CorpusReversibilityGateReport, CorpusReversibilityGateReport>
    {
        Validation(
            ruleID: "lottie.reversibility.report.aggregates",
            description: "Corpus reversibility snapshot aggregate counts match fixtures and exclusions"
        ) { context in
            let report = context.subject
            var errors: [ValidationError] = []
            let expectedExact = report.fixtures.filter { $0.status == "exact" }.count
            let expectedRecordedLoss = report.fixtures.filter { $0.status == "recordedLoss" }.count
            let expectedMismatch = report.fixtures.filter { $0.status == "mismatch" }.count
            let aggregateChecks: [(String, Int, Int, String)] = [
                ("fixtureCount", report.fixtureCount, report.fixtures.count, "lottie.reversibility.fixture-count"),
                ("selectedFrameCount", report.selectedFrameCount, report.fixtures.flatMap(\.frames).count, "lottie.reversibility.selected-frame-count"),
                ("excludedFixtureCount", report.excludedFixtureCount, report.excludedFixtures.count, "lottie.reversibility.excluded-fixture-count"),
                ("exactFixtureCount", report.exactFixtureCount, expectedExact, "lottie.reversibility.exact-fixture-count"),
                ("recordedLossFixtureCount", report.recordedLossFixtureCount, expectedRecordedLoss, "lottie.reversibility.recorded-loss-fixture-count"),
                ("mismatchFixtureCount", report.mismatchFixtureCount, expectedMismatch, "lottie.reversibility.mismatch-fixture-count"),
                ("findingCount", report.findingCount, report.fixtures.map(\.findingCount).reduce(0, +), "lottie.reversibility.finding-count"),
                ("lossCount", report.lossCount, report.fixtures.map(\.lossCount).reduce(0, +), "lottie.reversibility.loss-count"),
                (
                    "reconstructedFactCount",
                    report.reconstructedFactCount,
                    report.fixtures.map(\.reconstructedFactCount).reduce(0, +),
                    "lottie.reversibility.fact-count"
                ),
                ("sourcePathCount", report.sourcePathCount, report.fixtures.map(\.sourcePathCount).reduce(0, +), "lottie.reversibility.source-path-count"),
            ]

            for check in aggregateChecks where check.1 != check.2 {
                errors.append(error(check.3, at: context.codingPath.appending(.key(check.0))))
            }
            return errors
        }
    }

    static var fixturesAreComplete:
        Validation<CorpusReversibilityGateReport, CorpusReversibilityGateReport.Fixture>
    {
        Validation(
            ruleID: "lottie.reversibility.fixture.complete",
            description: "Corpus reversibility fixture records are identified unique complete and internally aggregated"
        ) { context in
            let fixture = context.subject
            var errors: [ValidationError] = []
            if isBlank(fixture.id) {
                errors.append(error("lottie.reversibility.fixture.id", at: context.codingPath.appending(.key("id"))))
            }
            if context.document.fixtures.filter({ $0.id == fixture.id }).count > 1 {
                errors.append(error("lottie.reversibility.fixture.duplicate", at: context.codingPath.appending(.key("id"))))
            }
            if isBlank(fixture.lottie) {
                errors.append(error("lottie.reversibility.fixture.lottie", at: context.codingPath.appending(.key("lottie"))))
            }
            if isBlank(fixture.lottieWebIntent) {
                errors.append(error("lottie.reversibility.fixture.intent", at: context.codingPath.appending(.key("lottieWebIntent"))))
            }
            if !["exact", "recordedLoss", "mismatch"].contains(fixture.status) {
                errors.append(error("lottie.reversibility.fixture.status", at: context.codingPath.appending(.key("status"))))
            }
            let aggregateChecks: [(String, Int, Int, String)] = [
                ("selectedFrameCount", fixture.selectedFrameCount, fixture.frames.count, "lottie.reversibility.fixture.selected-frame-count"),
                ("frameCount", fixture.frameCount, fixture.frames.count, "lottie.reversibility.fixture.frame-count"),
                ("findingCount", fixture.findingCount, fixture.frames.map(\.findingCount).reduce(0, +), "lottie.reversibility.fixture.finding-count"),
                ("lossCount", fixture.lossCount, fixture.frames.map(\.lossCount).reduce(0, +), "lottie.reversibility.fixture.loss-count"),
                (
                    "reconstructedFactCount",
                    fixture.reconstructedFactCount,
                    fixture.frames.map(\.reconstructedFactCount).reduce(0, +),
                    "lottie.reversibility.fixture.fact-count"
                ),
                ("sourcePathCount", fixture.sourcePathCount, Set(fixture.frames.flatMap(\.sourcePaths)).count, "lottie.reversibility.fixture.source-path-count"),
            ]
            for check in aggregateChecks where check.1 != check.2 {
                errors.append(error(check.3, at: context.codingPath.appending(.key(check.0))))
            }
            if Set(fixture.frames.map(\.frame)).count != fixture.frames.count {
                errors.append(error("lottie.reversibility.fixture.duplicate-frame", at: context.codingPath.appending(.key("frames"))))
            }
            return errors
        }
    }

    static var framesAreExplainedUniqueAndAggregated:
        Validation<CorpusReversibilityGateReport, CorpusReversibilityGateReport.Frame>
    {
        Validation(
            ruleID: "lottie.reversibility.frame.explained",
            description: "Corpus reversibility frame records are unique explained path-bearing and internally aggregated"
        ) { context in
            let frame = context.subject
            var errors: [ValidationError] = []
            if isBlank(frame.rationale) {
                errors.append(error("lottie.reversibility.frame.rationale", at: context.codingPath.appending(.key("rationale"))))
            }
            if frame.layerCount != frame.layers.count {
                errors.append(error("lottie.reversibility.frame.layer-count", at: context.codingPath.appending(.key("layerCount"))))
            }
            if frame.findingCount != frame.findings.count {
                errors.append(error("lottie.reversibility.frame.finding-count", at: context.codingPath.appending(.key("findingCount"))))
            }
            if frame.lossCount != frame.losses.count {
                errors.append(error("lottie.reversibility.frame.loss-count", at: context.codingPath.appending(.key("lossCount"))))
            }
            if frame.reconstructedFactCount != frame.layers.map(\.reconstructedFactCount).reduce(0, +) {
                errors.append(error("lottie.reversibility.frame.fact-count", at: context.codingPath.appending(.key("reconstructedFactCount"))))
            }
            return errors
        }
    }

    static var layersArePathBearing:
        Validation<CorpusReversibilityGateReport, CorpusReversibilityGateReport.Layer>
    {
        Validation(
            ruleID: "lottie.reversibility.layer.path-bearing",
            description: "Corpus reversibility layer facts contain source and JSON paths"
        ) { context in
            var errors: [ValidationError] = []
            if isBlank(context.subject.sourcePath) {
                errors.append(error("lottie.reversibility.layer.source-path", at: context.codingPath.appending(.key("sourcePath"))))
            }
            if isBlank(context.subject.jsonPath) {
                errors.append(error("lottie.reversibility.layer.json-path", at: context.codingPath.appending(.key("jsonPath"))))
            }
            return errors
        }
    }

    static var lossesArePathBearing:
        Validation<CorpusReversibilityGateReport, CorpusReversibilityGateReport.Loss>
    {
        Validation(
            ruleID: "lottie.reversibility.loss.path-bearing",
            description: "Corpus reversibility loss records contain rule id source/json paths and reason"
        ) { context in
            var errors: [ValidationError] = []
            if isBlank(context.subject.ruleID) {
                errors.append(error("lottie.reversibility.loss.rule-id", at: context.codingPath.appending(.key("ruleID"))))
            }
            if isBlank(context.subject.sourcePath) {
                errors.append(error("lottie.reversibility.loss.source-path", at: context.codingPath.appending(.key("sourcePath"))))
            }
            if isBlank(context.subject.jsonPath) {
                errors.append(error("lottie.reversibility.loss.json-path", at: context.codingPath.appending(.key("jsonPath"))))
            }
            if isBlank(context.subject.reason) {
                errors.append(error("lottie.reversibility.loss.reason", at: context.codingPath.appending(.key("reason"))))
            }
            return errors
        }
    }

    static var findingsArePathBearing:
        Validation<CorpusReversibilityGateReport, CorpusReversibilityGateReport.Finding>
    {
        Validation(
            ruleID: "lottie.reversibility.finding.path-bearing",
            description: "Corpus reversibility findings contain rule id source/json paths and reason"
        ) { context in
            var errors: [ValidationError] = []
            if isBlank(context.subject.ruleID) {
                errors.append(error("lottie.reversibility.finding.rule-id", at: context.codingPath.appending(.key("ruleID"))))
            }
            if isBlank(context.subject.sourcePath) {
                errors.append(error("lottie.reversibility.finding.source-path", at: context.codingPath.appending(.key("sourcePath"))))
            }
            if isBlank(context.subject.jsonPath) {
                errors.append(error("lottie.reversibility.finding.json-path", at: context.codingPath.appending(.key("jsonPath"))))
            }
            if isBlank(context.subject.reason) {
                errors.append(error("lottie.reversibility.finding.reason", at: context.codingPath.appending(.key("reason"))))
            }
            return errors
        }
    }

    static var exclusionsArePathBearing:
        Validation<CorpusReversibilityGateReport, CorpusReversibilityGateReport.Exclusion>
    {
        Validation(
            ruleID: "lottie.reversibility.exclusion.path-bearing",
            description: "Corpus reversibility fixture exclusions contain id source/json paths and reason"
        ) { context in
            var errors: [ValidationError] = []
            if isBlank(context.subject.id) {
                errors.append(error("lottie.reversibility.exclusion.id", at: context.codingPath.appending(.key("id"))))
            }
            if isBlank(context.subject.sourcePath) {
                errors.append(error("lottie.reversibility.exclusion.source-path", at: context.codingPath.appending(.key("sourcePath"))))
            }
            if isBlank(context.subject.jsonPath) {
                errors.append(error("lottie.reversibility.exclusion.json-path", at: context.codingPath.appending(.key("jsonPath"))))
            }
            if isBlank(context.subject.reason) {
                errors.append(error("lottie.reversibility.exclusion.reason", at: context.codingPath.appending(.key("reason"))))
            }
            return errors
        }
    }

    private static func error(_ ruleID: String, at path: JSONPath) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "Failed to satisfy: Corpus reversibility snapshot is deterministic path-bearing and fully explained",
            at: path,
            phase: .semantic,
            classification: .gap
        )
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct CorpusReversibilityGateAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, CorpusReversibilityGateReport) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<CorpusReversibilityGateReport, Subject>) {
        ruleID = validation.ruleID
        description = validation.description
        applyClosure = { subject, path, document in
            guard let subject = subject as? Subject else { return [] }
            return validation.apply(to: subject, at: path, in: document)
        }
    }

    func apply(
        to subject: some Validatable,
        at path: JSONPath,
        in document: CorpusReversibilityGateReport
    ) -> [ValidationError] {
        applyClosure(subject, path, document)
    }
}

private struct CorpusFixtureManifestEntry: Decodable {
    var id: String
    var coverage: [String]
    var semanticStatus: SemanticStatus
    var lottie: String
    var lottieWebIntent: String
    var frames: [Frame]

    struct Frame: Decodable {
        var frame: Double
        var rationale: String
    }

    enum SemanticStatus: String, Decodable {
        case modeled
        case diagnosed
    }
}
