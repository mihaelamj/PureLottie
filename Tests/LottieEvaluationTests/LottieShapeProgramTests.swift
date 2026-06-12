import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie shape program")
struct LottieShapeProgramTests {
    @Test("reverse shape walk exposes inspectable style runs")
    func reverseWalkStyleRunsCanBeInspected() throws {
        let layer = try shapeLayer("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              { "ty": "rc", "nm": "Left", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "Red", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 },
              { "ty": "rc", "nm": "Right", "p": { "a": 0, "k": [30, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              { "ty": "fl", "nm": "Blue", "c": { "a": 0, "k": [0, 0, 1, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }]
        }
        """)

        let program = try program(for: layer)
        let runs = styleRuns(in: program.nodes)

        #expect(program.diagnostics.isEmpty)
        #expect(runs.map(\.sourcePath) == [
            "layer 'Shapes' > fill 'Blue'",
            "layer 'Shapes' > fill 'Red'",
        ])
        #expect(runs[0].fragments.map(\.sourcePath) == [
            "layer 'Shapes' > rectangle 'Right'",
            "layer 'Shapes' > rectangle 'Left'",
        ])
        #expect(runs[1].fragments.map(\.sourcePath) == [
            "layer 'Shapes' > rectangle 'Left'",
        ])
    }

    @Test("groups preserve boundaries transforms opacity and atomic compositing")
    func groupsPreserveScopeAndCompositing() throws {
        let layer = try shapeLayer("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              {
                "ty": "gr",
                "nm": "Half",
                "it": [
                  { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
                  { "ty": "fl", "nm": "LocalRed", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 },
                  { "ty": "tr", "nm": "Transform", "a": { "a": 0, "k": [0, 0] }, "p": { "a": 0, "k": [20, 0] }, "s": { "a": 0, "k": [100, 100] }, "r": { "a": 0, "k": 0 }, "o": { "a": 0, "k": 50 } }
                ]
              },
              { "ty": "fl", "nm": "ParentBlue", "c": { "a": 0, "k": [0, 0, 1, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 }
            ]
          }]
        }
        """)

        let program = try program(for: layer)
        let rootRuns = styleRuns(in: program.nodes)
        let group = try firstGroup(in: program.nodes)
        let groupRuns = styleRuns(in: group.nodes)

        #expect(program.diagnostics.isEmpty)
        #expect(rootRuns.first?.sourcePath == "layer 'Shapes' > fill 'ParentBlue'")
        #expect(rootRuns.first?.fragments.first?.transformStack.map(\.sourcePath) == [
            "layer 'Shapes' > group 'Half' > transform 'Transform'",
        ])
        #expect(group.sourcePath == "layer 'Shapes' > group 'Half'")
        #expect(group.compositing == .atomicTransparency)
        #expect(group.opacity?.initialValue == 50)
        #expect(group.transform?.position?.initialValue == [20, 0])
        #expect(groupRuns.first?.sourcePath == "layer 'Shapes' > group 'Half' > fill 'LocalRed'")
        #expect(groupRuns.first?.fragments.first?.transformStack.map(\.sourcePath) == [
            "layer 'Shapes' > group 'Half' > transform 'Transform'",
        ])
    }

    @Test("unsupported shape operations emit semantic diagnostics with JSON paths")
    func unsupportedShapeOperationsAreDiagnosed() throws {
        let layer = try shapeLayer("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              { "ty": "rp", "nm": "Repeater" },
              { "ty": "gf", "nm": "Gradient Fill" }
            ]
          }]
        }
        """)

        let program = try program(for: layer)

        #expect(program.nodes.isEmpty)
        #expect(program.diagnostics.map(\.ruleID) == [
            "lottie.evaluation.shape.unsupported-type",
            "lottie.evaluation.shape.unsupported-type",
        ])
        #expect(program.diagnostics.map(\.reason) == [
            "shape type 'gf'",
            "shape type 'rp'",
        ])
        #expect(program.diagnostics.map(\.classification) == [
            .reported,
            .reported,
        ])
        #expect(program.diagnostics.map(\.codingPath.description) == [
            "$.layers[0].shapes[1]",
            "$.layers[0].shapes[0]",
        ])
        #expect(program.diagnostics.map(\.evidence) == [
            "layer 'Shapes' > 'Gradient Fill'",
            "layer 'Shapes' > 'Repeater'",
        ])
    }

    @Test("stroke style metadata remains inspectable before backend lowering")
    func strokeStyleMetadataIsPreserved() throws {
        let layer = try shapeLayer("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 100,
          "h": 100,
          "layers": [{
            "ty": 4,
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [10, 10] }, "r": { "a": 0, "k": 0 } },
              {
                "ty": "st",
                "nm": "DashedRound",
                "c": { "a": 0, "k": [0, 0, 1, 1] },
                "o": { "a": 0, "k": 80 },
                "w": { "a": 0, "k": 3 },
                "lc": 2,
                "lj": 3,
                "ml": 4,
                "ml2": { "a": 0, "k": 6 },
                "bm": 2,
                "d": [
                  { "n": "d", "v": { "a": 0, "k": 4 } },
                  { "n": "g", "v": { "a": 0, "k": 2 } },
                  { "n": "o", "v": { "a": 0, "k": 1 } }
                ]
              }
            ]
          }]
        }
        """)

        let run = try #require(try styleRuns(in: program(for: layer).nodes).first)
        guard case let .stroke(stroke) = run.style else {
            Issue.record("Expected stroke style run.")
            return
        }

        #expect(stroke.lineCap == 2)
        #expect(stroke.lineJoin == 3)
        #expect(stroke.miterLimit == 4)
        #expect(stroke.secondaryMiterLimit?.initialValue == 6)
        #expect(stroke.blendMode == 2)
        #expect(stroke.dashPattern?.map(\.type) == ["d", "g", "o"])
        #expect(stroke.dashPattern?.map { $0.value?.initialValue ?? -1 } == [4, 2, 1])
        #expect(run.fragments.map(\.sourcePath) == ["layer 'Shapes' > rectangle 'Box'"])
    }

    private func shapeLayer(_ source: String) throws -> LottieLayer {
        let animation = try LottieAnimation.decode(from: Data(source.utf8))
        return try #require(animation.layers.first)
    }

    private func program(for layer: LottieLayer) throws -> LottieShapeProgram {
        try LottieShapeProgramBuilder().program(
            for: #require(layer.shapes),
            sourcePath: "layer 'Shapes'",
            jsonPath: JSONPath([.key("layers"), .index(0), .key("shapes")])
        )
    }

    private func styleRuns(in nodes: [LottieShapeProgram.Node]) -> [LottieShapeProgram.StyleRun] {
        nodes.compactMap { node in
            if case let .styleRun(run) = node { return run }
            return nil
        }
    }

    private func firstGroup(in nodes: [LottieShapeProgram.Node]) throws -> LottieShapeProgram.Group {
        for node in nodes {
            if case let .group(group) = node { return group }
        }
        return try #require(nil as LottieShapeProgram.Group?)
    }
}
