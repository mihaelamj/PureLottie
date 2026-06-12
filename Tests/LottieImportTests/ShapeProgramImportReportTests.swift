import Foundation
import LottieImport
import LottieModel
import Testing

@Suite("Shape program import report")
struct ShapeProgramImportReportTests {
    @Test("backend-only shape style gaps are reported during PureLayer lowering")
    func backendOnlyShapeStyleGapsAreReported() throws {
        let animation = try LottieAnimation.decode(from: Data("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "nm": "Shapes",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "st": 0,
            "ks": {
              "a": { "a": 0, "k": [0, 0] },
              "p": { "a": 0, "k": [0, 0] },
              "s": { "a": 0, "k": [100, 100] },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            },
            "shapes": [
              { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              {
                "ty": "st",
                "nm": "FancyStroke",
                "c": { "a": 0, "k": [0, 0, 1, 1] },
                "o": { "a": 0, "k": 100 },
                "w": { "a": 0, "k": 2 },
                "lc": 2,
                "lj": 3,
                "ml": 4,
                "ml2": { "a": 0, "k": 6 },
                "bm": 2,
                "d": [{ "n": "d", "v": { "a": 0, "k": 4 } }]
              },
              { "ty": "fl", "nm": "BlendFill", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1, "bm": 1 },
              { "ty": "rp", "nm": "Repeater" }
            ]
          }],
          "assets": []
        }
        """.utf8))

        let scene = LottieImporter().scene(from: animation)

        #expect(scene.report.findings.map(\.feature) == [
            "shape type 'rp'",
            "fill blend mode",
            "stroke blend mode",
            "stroke line cap",
            "stroke line join",
            "stroke miter limit",
            "secondary stroke miter limit",
            "stroke dash pattern",
        ])
        #expect(scene.report.findings.allSatisfy { !$0.path.isEmpty })
    }
}
