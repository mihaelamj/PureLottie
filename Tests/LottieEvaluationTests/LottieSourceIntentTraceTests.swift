import Foundation
import LottieEvaluation
import Testing

@Suite("Lottie source-intent trace schema")
struct LottieSourceIntentTraceTests {
    @Test("golden source-intent trace decodes with required provenance")
    func goldenSourceIntentTraceDecodesWithRequiredProvenance() throws {
        let trace = try decodeGoldenTrace()

        #expect(trace.schema.name == "purelottie.source-intent-trace")
        #expect(trace.schema.version == 1)
        #expect(trace.source.identity == "shape-position")
        #expect(trace.composition.width == 64)
        #expect(trace.composition.height == 64)
        #expect(trace.composition.inPoint == 0)
        #expect(trace.composition.outPoint == 10)
        #expect(trace.composition.frameRate == 10)
        #expect(trace.composition.frameWindow == .ipInclusiveOpExclusive)
        #expect(trace.composition.provenance.jsonPath == "$")
        #expect(trace.composition.provenance.consumedFields.contains("$.layers"))

        let frame = try #require(trace.frames.first)
        #expect(frame.sourceFrame == 0)
        #expect(frame.localTimeSeconds == 0)

        let layer = try #require(frame.visibleLayers.first)
        #expect(layer.id == "render#1")
        #expect(layer.type == .shape)
        #expect(layer.renderOrder == 0)
        #expect(layer.localFrame == 0)
        #expect(layer.provenance.jsonPath == "$.layers[0]")
        #expect(layer.provenance.consumedFields.contains("$.layers[0].ks"))

        #expect(layer.transform.matrix.values.count == 16)
        #expect(layer.transform.matrixConvention == .lottieWebRowVector4x4)
        #expect(layer.transform.provenance.jsonPath == "$.layers[0].ks")

        let geometry = try #require(layer.geometry.first)
        #expect(geometry.kind == .rectangle)
        #expect(geometry.primitive == "rc")
        #expect(geometry.parameters["center"] == [32, 32])
        #expect(geometry.parameters["size"] == [24, 24])
        #expect(geometry.provenance.jsonPath == "$.layers[0].shapes[0]")

        let style = try #require(layer.styles.first)
        #expect(style.kind == .fill)
        #expect(style.color == [0.95, 0.15, 0.2, 1])
        #expect(style.provenance.jsonPath == "$.layers[0].shapes[1]")
    }

    @Test("trace represents unsupported render-affecting facts explicitly")
    func traceRepresentsUnsupportedRenderAffectingFactsExplicitly() throws {
        let trace = try decodeGoldenTrace()
        let layer = try #require(trace.frames.first?.visibleLayers.first)
        let diagnostic = try #require(layer.diagnostics.first)

        #expect(diagnostic.ruleID == "lottie.evaluation.transform.skew.unsupported")
        #expect(diagnostic.phase == .semantic)
        #expect(diagnostic.classification == .reported)
        #expect(diagnostic.provenance.jsonPath == "$.layers[0].ks.sk")
        #expect(diagnostic.provenance.unrepresentedFields == ["$.layers[0].ks.sk"])
        #expect(diagnostic.evidence?.contains("silently lowering") == true)
    }

    @Test("matrix decoding rejects non 4x4 arrays")
    func matrixDecodingRejectsNon4x4Arrays() throws {
        let data = Data(#"{ "matrix": [1, 0, 0] }"#.utf8)

        do {
            _ = try JSONDecoder().decode(MatrixBox.self, from: data)
            Issue.record("Expected matrix decoding to reject a non-4x4 array.")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.codingPath.map(\.stringValue) == ["matrix"])
            #expect(context.debugDescription.contains("16 values"))
        } catch {
            Issue.record("Expected a dataCorrupted decoding error, got \(error).")
        }
    }

    @Test("diagnostic decoding rejects unknown vocabularies")
    func diagnosticDecodingRejectsUnknownVocabularies() throws {
        let data = Data(
            """
            {
              "ruleID": "example",
              "severity": "warning",
              "phase": "paint",
              "classification": "reported",
              "reason": "Bad phase",
              "evidence": null,
              "provenance": {
                "sourcePath": "root",
                "jsonPath": "$",
                "sourceRange": null,
                "consumedFields": [],
                "preservedFields": [],
                "unrepresentedFields": []
              }
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LottieSourceIntentDiagnostic.self, from: data)
        }
    }

    @Test("golden trace model round trips through JSON coding")
    func goldenTraceModelRoundTripsThroughJSONCoding() throws {
        let trace = try decodeGoldenTrace()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let encoded = try encoder.encode(trace)
        let decoded = try JSONDecoder().decode(LottieSourceIntentTrace.self, from: encoded)

        #expect(decoded == trace)
        #expect(trace.roundTrip.lossyFields.isEmpty)
        #expect(trace.roundTrip.laws.count == 3)
    }

    private func decodeGoldenTrace() throws -> LottieSourceIntentTrace {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SourceIntentTrace", isDirectory: true)
            .appendingPathComponent("shape-position.frame-0.trace.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LottieSourceIntentTrace.self, from: data)
    }

    private struct MatrixBox: Decodable {
        var matrix: LottieSourceIntentMatrix
    }
}
