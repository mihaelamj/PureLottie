import Foundation
import LottieImport
import Testing

@Suite("Time remap import reporting")
struct TimeRemapImportReportTests {
    @Test("decoded time remap is reported by the importer until lowering consumes evaluator semantics")
    func timeRemapIsReportedAfterValidation() throws {
        let scene = try LottieImporter().scene(from: Data("""
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

        #expect(scene.report.findings.map(\.feature) == ["time remap"])
        #expect(scene.report.findings.first?.path == "root > layer 'Remapped precomp'")
        #expect(scene.report.findings.first?.disposition == .skipped)
    }
}
