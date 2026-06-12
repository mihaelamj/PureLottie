import Foundation
import LottieImport
import LottieModel
import Testing

@Suite("Time remap import reporting")
struct TimeRemapImportReportTests {
    @Test("Raw decoded time remap is reported by the importer until lowering consumes evaluator semantics")
    func rawTimeRemapIsReportedByImporter() throws {
        let animation = try LottieAnimation.decode(from: Data("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 0,
            "nm": "Remapped precomp",
            "ind": 1,
            "refId": "precomp",
            "ip": 0,
            "op": 30,
            "st": 0,
            "tm": { "k": 1 },
            "ks": {}
          }],
          "assets": [{ "id": "precomp", "layers": [] }]
        }
        """.utf8))
        let scene = LottieImporter().scene(from: animation)

        #expect(scene.report.findings.map(\.feature) == ["time remap"])
        #expect(scene.report.findings.first?.path == "root > layer 'Remapped precomp'")
        #expect(scene.report.findings.first?.disposition == .skipped)
    }

    @Test("Validated data import rejects time remap before lowering")
    func validatedDataImportRejectsTimeRemapBeforeLowering() throws {
        do {
            _ = try LottieImporter().scene(from: Data("""
            {
              "v": "5.7.4",
              "fr": 30,
              "ip": 0,
              "op": 30,
              "w": 64,
              "h": 64,
              "layers": [{
                "ty": 0,
                "nm": "Remapped precomp",
                "ind": 1,
                "refId": "precomp",
                "ip": 0,
                "op": 30,
                "st": 0,
                "tm": { "k": 1 },
                "ks": {}
              }],
              "assets": [{ "id": "precomp", "layers": [] }]
            }
            """.utf8))
            Issue.record("Expected validated import to reject time remap.")
        } catch let collection as ValidationErrorCollection {
            #expect(collection.values.map(\.ruleID) == ["lottie.layer.time-locality"])
            #expect(collection.values.first?.codingPath.description == "$.layers[0].tm")
            #expect(collection.values.first?.range != nil)
        }
    }
}
