import Foundation
import LottieImport
import LottieModel
import Testing

@Suite("Lottie binding import")
struct LottieBindingImportTests {
    @Test("Raw model import reports duplicate layer indices and missing parents")
    func rawImportReportsDuplicateIndicesAndMissingParents() throws {
        let scene = try importRaw("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 3, "nm": "One", "ind": 1, "ip": 0, "op": 30, "ks": {} },
            { "ty": 3, "nm": "Two", "ind": 1, "ip": 0, "op": 30, "ks": {} },
            { "ty": 3, "nm": "Child", "ind": 3, "parent": 99, "ip": 0, "op": 30, "ks": {} }
          ],
          "assets": []
        }
        """)

        let features = scene.report.findings.map(\.feature)
        #expect(features.contains("duplicate layer index 1"))
        #expect(features.contains("missing parent layer 99"))
    }

    @Test("Raw model import reports parent cycles")
    func rawImportReportsParentCycles() throws {
        let scene = try importRaw("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 3, "nm": "One", "ind": 1, "parent": 2, "ip": 0, "op": 30, "ks": {} },
            { "ty": 3, "nm": "Two", "ind": 2, "parent": 1, "ip": 0, "op": 30, "ks": {} }
          ],
          "assets": []
        }
        """)

        let cycleFindings = scene.report.findings.filter { $0.feature.hasPrefix("parent cycle") }
        #expect(cycleFindings.count == 2)
        #expect(cycleFindings.allSatisfy { $0.sourcePath?.hasSuffix(".parent") == true })
    }

    @Test("Hidden parent layers still bind as transform ancestors")
    func hiddenParentLayersStillBindAsTransformAncestors() throws {
        let scene = try importRaw("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 3, "nm": "Hidden parent", "ind": 1, "hd": true, "ip": 0, "op": 30, "ks": { "p": { "a": 0, "k": [10, 10] } } },
            { "ty": 3, "nm": "Child", "ind": 2, "parent": 1, "ip": 0, "op": 30, "ks": {} }
          ],
          "assets": []
        }
        """)

        #expect(scene.report.isClean)
        #expect(scene.root.sublayers.count == 1)
        #expect(scene.root.sublayers.first?.sublayers.count == 1)
    }

    @Test("Validated data import rejects unsupported mattes with source ranges")
    func dataImportRejectsUnsupportedMattesWithSourceRanges() throws {
        do {
            _ = try LottieImporter().scene(from: Data("""
            {
              "v": "5.7.4",
              "fr": 30,
              "ip": 0,
              "op": 30,
              "w": 64,
              "h": 64,
              "layers": [
                { "ty": 4, "nm": "Matte", "ind": 1, "td": 1, "ip": 0, "op": 30, "ks": {}, "shapes": [] },
                { "ty": 4, "nm": "Target", "ind": 2, "tt": 1, "tp": 1, "ip": 0, "op": 30, "ks": {}, "shapes": [] }
              ],
              "assets": []
            }
            """.utf8))
            Issue.record("Expected validated import to reject track mattes.")
        } catch let collection as ValidationErrorCollection {
            #expect(collection.values.contains { $0.ruleID == "lottie.layer.matte-field" && $0.codingPath.description == "$.layers[1].tt" && $0.range != nil })
            #expect(collection.values.contains { $0.ruleID == "lottie.layer.matte-field" && $0.codingPath.description == "$.layers[0].td" && $0.range != nil })
        }
    }

    @Test("Track matte mode zero is not reported as unsupported")
    func trackMatteModeZeroIsNotReportedAsUnsupported() throws {
        let scene = try LottieImporter().scene(from: Data("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 4, "nm": "Shape", "ind": 1, "tt": 0, "ip": 0, "op": 30, "ks": {}, "shapes": [] }
          ],
          "assets": []
        }
        """.utf8))

        #expect(scene.report.findings.isEmpty)
    }

    @Test("Precomposition layer indices bind in their own namespace")
    func precompositionLayerIndicesBindInTheirOwnNamespace() throws {
        let scene = try importRaw("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 0, "nm": "Use comp", "ind": 1, "refId": "comp_1", "w": 64, "h": 64, "ip": 0, "op": 30, "ks": {} }
          ],
          "assets": [
            {
              "id": "comp_1",
              "w": 64,
              "h": 64,
              "layers": [
                { "ty": 3, "nm": "Local one", "ind": 1, "ip": 0, "op": 30, "ks": {} }
              ]
            }
          ]
        }
        """)

        #expect(scene.report.isClean)
    }

    private func importRaw(_ json: String) throws -> LottieScene {
        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        return LottieImporter().scene(from: animation)
    }
}
