//
//  LottieTerminationCostTests.swift
//  PureLottie
//

import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie termination and cost bounds")
struct LottieTerminationCostTests {
    @Test("deep nesting precomposition DAG terminates successfully")
    func deepNestingPrecompositionDAGTerminatesSuccessfully() throws {
        // Construct a Lottie JSON string with 10 nested precompositions
        var assetsString = ""
        for i in 1 ... 9 {
            assetsString += """
            {
              "id": "comp_\(i)",
              "layers": [
                { "ty": 0, "refId": "comp_\(i + 1)", "ip": 0, "op": 100, "ks": {} }
              ]
            },
            """
        }
        assetsString += """
        {
          "id": "comp_10",
          "layers": [
            { "ty": 1, "ind": 1, "ip": 0, "op": 100, "sw": 100, "sh": 100, "sc": "#ffffff", "ks": {} }
          ]
        }
        """

        let json = """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 100,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 0, "refId": "comp_1", "ip": 0, "op": 100, "ks": {} }
          ],
          "assets": [
            \(assetsString)
          ]
        }
        """

        let document = try LottieSourceDocument.parse(json)
        try document.validate() // Ensure acyclic validation passes

        // Evaluate frame 0 and assert that it resolves successfully
        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        let evaluator = LottieRenderIRBuilder(animation: animation)
        let frame = evaluator.frame(at: 0)

        // The depth of precomp evaluation should be 10, nodes should be resolved
        #expect(frame.nodes.count > 0)
    }

    @Test("wide fan-out precomposition DAG terminates successfully")
    func wideFanOutPrecompositionDAGTerminatesSuccessfully() throws {
        // Construct a Lottie JSON string with 50 layers referencing the same precomp
        var layersString = ""
        for i in 1 ... 50 {
            layersString += """
            { "ty": 0, "ind": \(i), "refId": "comp_1", "ip": 0, "op": 100, "ks": {} },
            """
        }
        // Remove trailing comma
        if !layersString.isEmpty {
            layersString.removeLast()
        }

        let json = """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 100,
          "w": 64,
          "h": 64,
          "layers": [
            \(layersString)
          ],
          "assets": [
            {
              "id": "comp_1",
              "layers": [
                { "ty": 1, "ind": 1, "ip": 0, "op": 100, "sw": 100, "sh": 100, "sc": "#ffffff", "ks": {} }
              ]
            }
          ]
        }
        """

        let document = try LottieSourceDocument.parse(json)
        try document.validate()

        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        let evaluator = LottieRenderIRBuilder(animation: animation)
        let frame = evaluator.frame(at: 0)

        #expect(frame.nodes.count >= 50)
    }

    @Test("adversarial time remap with non-linear jumps terminates successfully")
    func adversarialTimeRemapWithNonLinearJumpsTerminatesSuccessfully() throws {
        // Construct a Lottie JSON string with a precomp layer carrying a 100-keyframe time-remap property
        var keyframesString = ""
        for i in 0 ... 99 {
            keyframesString += """
            { "t": \(i), "s": [\(Double(99 - i) / 30.0)] },
            """
        }
        keyframesString += """
        { "t": 100 }
        """

        let json = """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 100,
          "w": 64,
          "h": 64,
          "layers": [
            {
              "ty": 0,
              "refId": "comp_1",
              "ip": 0,
              "op": 100,
              "tm": {
                "a": 1,
                "k": [
                  \(keyframesString)
                ]
              },
              "ks": {}
            }
          ],
          "assets": [
            {
              "id": "comp_1",
              "layers": [
                { "ty": 1, "ind": 1, "ip": 0, "op": 100, "sw": 100, "sh": 100, "sc": "#ffffff", "ks": {} }
              ]
            }
          ]
        }
        """

        let document = try LottieSourceDocument.parse(json)
        try document.validate(using: LottieValidator.blank.validating(\.precompositionReferencesDoNotCycle))

        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        let evaluator = LottieRenderIRBuilder(animation: animation)

        // Evaluate at frame 50 and make sure it does not recurse infinitely
        let frame = evaluator.frame(at: 50.0)
        #expect(frame.nodes.count > 0)
    }
}
