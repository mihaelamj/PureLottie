import Foundation

public enum LottieConformanceVerifier {
    public struct Error: Swift.Error, CustomStringConvertible {
        public let reason: String
        public init(_ reason: String) {
            self.reason = reason
        }

        public var description: String {
            reason
        }
    }

    /// JSON Model Structures
    struct OracleFixture: Decodable {
        let id: String
        let lottie: String
        let lottieWebIntent: String
        let semanticStatus: String
        let coverage: [String]
        let frames: [OracleFixtureFrame]
    }

    struct OracleFixtureFrame: Decodable {
        let frame: Double
        let rationale: String
    }

    struct ToleranceLedger: Decodable {
        let tolerances: [Tolerance]
    }

    struct Tolerance: Decodable {
        let id: String
        let threshold: Double
    }

    struct ReversibilityReport: Decodable {
        let fixtureCount: Int
        let selectedFrameCount: Int
        let findingCount: Int
        let exactFixtureCount: Int
        let fixtures: [ReversibilityFixture]
    }

    struct ReversibilityFixture: Decodable {
        let id: String
        let semanticStatus: String
        let status: String
        let frames: [ReversibilityFrame]
    }

    struct ReversibilityFrame: Decodable {
        let frame: Double
        let rationale: String
        let findingCount: Int
        let lossCount: Int
        let layers: [ReversibilityLayer]
    }

    struct ReversibilityLayer: Decodable {
        let id: String
        let name: String?
        let sourcePath: String
        let localFrame: Double
        let decompiledLocalFrame: Double?
        let opacity: Double
        let decompiledOpacity: Double?
        let position: [Double]
        let decompiledPosition: [Double]
        let scale: [Double]
        let decompiledScale: [Double]
        let rotationZDegrees: Double
        let decompiledRotationZDegrees: Double?
        let matrixTranslation: [Double]
        let decompiledMatrixTranslation: [Double]
        let geometryCount: Int
        let decompiledGeometryCount: Int
        let styleCount: Int
        let decompiledStyleCount: Int
        let trimTraceCount: Int
        let decompiledTrimTraceCount: Int
        let maskCount: Int
        let decompiledMaskCount: Int
        let hasMatte: Bool
        let decompiledHasMatte: Bool
    }

    struct WebIntentTrace: Decodable {
        let source: String
        let width: Double
        let height: Double
        let frames: [WebIntentFrame]
    }

    struct WebIntentFrame: Decodable {
        let frame: Double
        let layers: [WebIntentLayer]
        let precompositions: [WebIntentPrecomposition]
    }

    struct WebIntentLayer: Decodable {
        let name: String
        let opacity: Double
        let matrix: [Double]
    }

    struct WebIntentPrecomposition: Decodable {
        let layerName: String
        let renderedFrame: Double?
    }

    struct WitnessCorpus: Decodable {
        let entries: [WitnessEntry]
    }

    struct WitnessEntry: Decodable {
        let id: String
        let lottie: String
        let lottieWebIntent: String
        let frames: [WitnessFrame]
        let witness: WitnessDetail
    }

    struct WitnessFrame: Decodable {
        let frame: Double
        let rationale: String
    }

    struct WitnessDetail: Decodable {
        let status: String
        let evidence: [String]
        let reason: String
    }

    private static func hasDirectTranslationComparison(coverage: [String]) -> Bool {
        let coverageSet = Set(coverage)
        guard coverageSet.contains("animated-position") || coverageSet.contains("split-position") else {
            return false
        }
        let disjointWith = Set(["anchor", "rotation", "parent-transform", "precomp", "shape-transform", "time-remap"])
        return coverageSet.isDisjoint(with: disjointWith)
    }

    public static func verify(
        manifestURL: URL,
        tolerancesURL: URL,
        reversibilityURL: URL,
        witnessCorpusURL: URL,
        lottieWebIntentDir: URL,
        witnessLottieWebIntentDir: URL
    ) throws {
        let decoder = JSONDecoder()

        // 1. Load tolerances
        let tolerancesData = try Data(contentsOf: tolerancesURL)
        let toleranceLedger = try decoder.decode(ToleranceLedger.self, from: tolerancesData)
        let tolerances = Dictionary(uniqueKeysWithValues: toleranceLedger.tolerances.map { ($0.id, $0.threshold) })

        guard let opacityTolerance = tolerances["opacity.unit-interval.absolute"],
              let translationTolerance = tolerances["matrix.translation.css-pixel.absolute"],
              let frameTolerance = tolerances["frame.source-frame.absolute"]
        else {
            throw Error("Missing expected tolerances in tolerances ledger.")
        }

        // 2. Load manifest
        let manifestData = try Data(contentsOf: manifestURL)
        let fixtures = try decoder.decode([OracleFixture].self, from: manifestData)

        // 3. Load reversibility report
        let reversibilityData = try Data(contentsOf: reversibilityURL)
        let reversibilityReport = try decoder.decode(ReversibilityReport.self, from: reversibilityData)

        // 4. Verify counts & structure
        if reversibilityReport.fixtureCount != fixtures.count {
            throw Error("Mismatch in fixture count: manifest has \(fixtures.count), reversibility report has \(reversibilityReport.fixtureCount)")
        }
        let selectedFrameCount = fixtures.flatMap(\.frames).count
        if reversibilityReport.selectedFrameCount != selectedFrameCount {
            throw Error("Mismatch in selected frame count: manifest has \(selectedFrameCount), reversibility report has \(reversibilityReport.selectedFrameCount)")
        }

        // 5. Verify each fixture
        for fixture in fixtures {
            guard let revFixture = reversibilityReport.fixtures.first(where: { $0.id == fixture.id }) else {
                throw Error("Fixture \(fixture.id) not found in reversibility report")
            }

            if revFixture.semanticStatus != fixture.semanticStatus {
                throw Error("Fixture \(fixture.id) semantic status mismatch: manifest says \(fixture.semanticStatus), reversibility report says \(revFixture.semanticStatus)")
            }

            // A. Check round-trip laws
            if revFixture.status == "exact" {
                for revFrame in revFixture.frames {
                    if revFrame.findingCount > 0 {
                        throw Error("Fixture \(fixture.id) is marked exact but has \(revFrame.findingCount) findings in frame \(revFrame.frame)")
                    }
                    for revLayer in revFrame.layers {
                        if let decompOpacity = revLayer.decompiledOpacity {
                            if abs(decompOpacity - revLayer.opacity) > 1e-15 {
                                throw Error(
                                    "Fixture \(fixture.id) layer \(revLayer.sourcePath) opacity round-trip error: original \(revLayer.opacity), decompiled \(decompOpacity)"
                                )
                            }
                        }
                        if revLayer.decompiledPosition != revLayer.position {
                            throw Error(
                                "Fixture \(fixture.id) layer \(revLayer.sourcePath) position round-trip mismatch: original \(revLayer.position), decompiled \(revLayer.decompiledPosition)"
                            )
                        }
                        if revLayer.decompiledScale != revLayer.scale {
                            throw Error(
                                "Fixture \(fixture.id) layer \(revLayer.sourcePath) scale round-trip mismatch: original \(revLayer.scale), decompiled \(revLayer.decompiledScale)"
                            )
                        }
                        if let decompRot = revLayer.decompiledRotationZDegrees {
                            if abs(decompRot - revLayer.rotationZDegrees) > 1e-12 {
                                throw Error(
                                    "Fixture \(fixture.id) layer \(revLayer.sourcePath) rotation round-trip error: original \(revLayer.rotationZDegrees), decompiled \(decompRot)"
                                )
                            }
                        }
                        if revLayer.decompiledMatrixTranslation != revLayer.matrixTranslation {
                            throw Error(
                                "Fixture \(fixture.id) layer \(revLayer.sourcePath) matrixTranslation round-trip mismatch: original \(revLayer.matrixTranslation), decompiled \(revLayer.decompiledMatrixTranslation)"
                            )
                        }
                        if revLayer.decompiledHasMatte != revLayer.hasMatte {
                            throw Error(
                                "Fixture \(fixture.id) layer \(revLayer.sourcePath) hasMatte round-trip mismatch: original \(revLayer.hasMatte), decompiled \(revLayer.decompiledHasMatte)"
                            )
                        }
                        if revLayer.decompiledGeometryCount != revLayer.geometryCount {
                            throw Error("Fixture \(fixture.id) layer \(revLayer.sourcePath) geometryCount round-trip mismatch")
                        }
                        if revLayer.decompiledStyleCount != revLayer.styleCount {
                            throw Error("Fixture \(fixture.id) layer \(revLayer.sourcePath) styleCount round-trip mismatch")
                        }
                        if revLayer.decompiledTrimTraceCount != revLayer.trimTraceCount {
                            throw Error("Fixture \(fixture.id) layer \(revLayer.sourcePath) trimTraceCount round-trip mismatch")
                        }
                        if revLayer.decompiledMaskCount != revLayer.maskCount {
                            throw Error("Fixture \(fixture.id) layer \(revLayer.sourcePath) maskCount round-trip mismatch")
                        }
                    }
                }
            }

            // B. Recompute comparison against reference trace (numeric oracle check)
            let traceFilename = URL(fileURLWithPath: fixture.lottieWebIntent).lastPathComponent
            let traceURL = lottieWebIntentDir.appendingPathComponent(traceFilename)
            let traceData = try Data(contentsOf: traceURL)
            let trace = try decoder.decode(WebIntentTrace.self, from: traceData)

            for frameObj in fixture.frames {
                guard let webFrame = trace.frames.first(where: { $0.frame == frameObj.frame }) else {
                    throw Error("Frame \(frameObj.frame) not found in reference trace for \(fixture.id)")
                }
                guard let revFrame = revFixture.frames.first(where: { $0.frame == frameObj.frame }) else {
                    throw Error("Frame \(frameObj.frame) not found in reversibility report for \(fixture.id)")
                }

                // Check layer features
                for webLayer in webFrame.layers {
                    guard let revLayer = revFrame.layers.first(where: { $0.name == webLayer.name }) else {
                        // lottie-web might have non-participating layers or layers with zero bounds
                        continue
                    }

                    // Check opacity
                    let opacityDelta = abs(webLayer.opacity - revLayer.opacity)
                    if opacityDelta > opacityTolerance {
                        throw Error("Fixture \(fixture.id) frame \(webFrame.frame) layer \(webLayer.name) opacity delta \(opacityDelta) exceeds tolerance \(opacityTolerance)")
                    }

                    // Check translation (if applicable)
                    if hasDirectTranslationComparison(coverage: fixture.coverage) {
                        guard webLayer.matrix.count >= 16, revLayer.matrixTranslation.count >= 2 else {
                            throw Error("Fixture \(fixture.id) missing translation matrix components")
                        }
                        let dx = abs(webLayer.matrix[12] - revLayer.matrixTranslation[0])
                        let dy = abs(webLayer.matrix[13] - revLayer.matrixTranslation[1])
                        if dx > translationTolerance {
                            throw Error("Fixture \(fixture.id) frame \(webFrame.frame) layer \(webLayer.name) translation.x delta \(dx) exceeds tolerance \(translationTolerance)")
                        }
                        if dy > translationTolerance {
                            throw Error("Fixture \(fixture.id) frame \(webFrame.frame) layer \(webLayer.name) translation.y delta \(dy) exceeds tolerance \(translationTolerance)")
                        }
                    }
                }

                // Check precompositions
                for webPrecomp in webFrame.precompositions {
                    guard let renderedFrame = webPrecomp.renderedFrame else {
                        continue
                    }
                    guard let revLayer = revFrame.layers.first(where: { $0.name == webPrecomp.layerName }) else {
                        throw Error("Precomp layer \(webPrecomp.layerName) not found in reversibility report for \(fixture.id)")
                    }

                    let frameDelta = abs(renderedFrame - revLayer.localFrame)
                    if frameDelta > frameTolerance {
                        throw Error(
                            "Fixture \(fixture.id) frame \(webFrame.frame) precomp layer \(webPrecomp.layerName) localFrame delta \(frameDelta) exceeds tolerance \(frameTolerance) (expected \(renderedFrame), actual \(revLayer.localFrame))"
                        )
                    }
                }
            }
        }

        // 6. Verify witness corpus
        let witnessCorpusData = try Data(contentsOf: witnessCorpusURL)
        let witnessCorpus = try decoder.decode(WitnessCorpus.self, from: witnessCorpusData)

        for entry in witnessCorpus.entries {
            let traceFilename = URL(fileURLWithPath: entry.lottieWebIntent).lastPathComponent
            let traceURL = witnessLottieWebIntentDir.appendingPathComponent(traceFilename)
            guard FileManager.default.fileExists(atPath: traceURL.path) else {
                throw Error("Witness trace file not found: \(traceURL.path)")
            }
            let traceData = try Data(contentsOf: traceURL)
            let trace = try decoder.decode(WebIntentTrace.self, from: traceData)

            if trace.frames.map(\.frame) != entry.frames.map(\.frame) {
                throw Error("Witness \(entry.id) frame list mismatch between manifest and trace file")
            }
            if entry.witness.status != "witnessed" {
                throw Error("Witness \(entry.id) status must be 'witnessed'")
            }
            if entry.witness.evidence.isEmpty {
                throw Error("Witness \(entry.id) evidence must be non-empty")
            }
        }
    }
}
