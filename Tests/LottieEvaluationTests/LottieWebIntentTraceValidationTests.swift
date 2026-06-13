import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("lottie-web intent trace validation")
struct LottieWebIntentTraceValidationTests {
    @Test("committed lottie-web intent traces decode through shared model")
    func committedLottieWebIntentTracesDecodeThroughSharedModel() throws {
        let intentDirectory = repositoryRoot()
            .appendingPathComponent("Tests/Fixtures/LottieOracle/lottie-web-intent", isDirectory: true)
        let traces = try FileManager.default.contentsOfDirectory(
            at: intentDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        #expect(traces.count >= 30)

        for traceURL in traces {
            let trace = try LottieWebIntentTrace.decodeValidated(from: Data(contentsOf: traceURL))
            #expect(trace.schema.name == "purelottie.lottie-web-intent", "\(traceURL.lastPathComponent)")
            #expect(trace.lottieWeb.version == "5.13.0", "\(traceURL.lastPathComponent)")
            #expect(trace.frames.isEmpty == false, "\(traceURL.lastPathComponent)")
        }
    }

    @Test("invalid lottie-web intent trace reports exact JSON paths")
    func invalidLottieWebIntentTraceReportsExactJSONPaths() throws {
        var trace = try LottieWebIntentTrace.decodeValidated(from: eligibleIntentData())
        trace.schema.version = 2
        trace.frames[0].pathCount = 99
        trace.frames[0].layers[0].matrix = [1, 0]
        trace.frames[0].paths[0].d = ""
        trace.frames[0].paths[0].style.fill = ""

        let errors = LottieWebIntentTraceValidator().collectErrors(in: trace)
        let paths = Set(errors.map(\.codingPath.description))

        #expect(paths.contains("$.schema.version"))
        #expect(paths.contains("$.frames[0].pathCount"))
        #expect(paths.contains("$.frames[0].layers[0].matrix"))
        #expect(paths.contains("$.frames[0].paths[0].d"))
        #expect(paths.contains("$.frames[0].paths[0].style.fill"))
    }

    @Test("missing lottie-web intent keys decode as validation errors with paths")
    func missingLottieWebIntentKeysDecodeAsValidationErrorsWithPaths() throws {
        let source = #"{"schema":{"name":"purelottie.lottie-web-intent","version":1}}"#

        do {
            _ = try LottieWebIntentTrace.decodeValidated(from: Data(source.utf8))
            Issue.record("Expected missing source key to fail decode validation.")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.first?.codingPath.description == "$.source")
            #expect(errors.values.first?.phase == .parse)
        } catch {
            Issue.record("Expected ValidationErrorCollection, got \(error).")
        }
    }

    @Test("default lottie-web intent validator is composable and removable")
    func defaultLottieWebIntentValidatorIsComposableAndRemovable() throws {
        var trace = try LottieWebIntentTrace.decodeValidated(from: eligibleIntentData())
        trace.schema.version = 2

        let strictErrors = LottieWebIntentTraceValidator().collectErrors(in: trace)
        #expect(strictErrors.contains { $0.codingPath.description == "$.schema.version" })

        let relaxedErrors = LottieWebIntentTraceValidator()
            .withoutValidating(\.schemaNameAndVersionAreSupported)
            .collectErrors(in: trace)
        #expect(relaxedErrors.contains { $0.codingPath.description == "$.schema.version" } == false)

        let custom = Validation<LottieWebIntentTrace, LottieWebIntentTrace>(
            ruleID: "test.trace.source-suffix",
            description: "Trace source path ends with .lottie.json",
            phase: .source
        ) { context in
            context.subject.source.hasSuffix(".lottie.json")
        }
        let customErrors = LottieWebIntentTraceValidator.blank
            .validating(custom)
            .collectErrors(in: trace)
        #expect(customErrors.map(\.codingPath.description) == ["$"])
    }

    private func eligibleIntentData() throws -> Data {
        try Data(contentsOf: repositoryRoot()
            .appendingPathComponent(
                "Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json"
            ))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
