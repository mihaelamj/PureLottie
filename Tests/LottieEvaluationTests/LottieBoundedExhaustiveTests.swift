//
//  LottieBoundedExhaustiveTests.swift
//  PureLottie
//

import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Lottie bounded-exhaustive evaluation and round-trip")
struct LottieBoundedExhaustiveTests {
    struct BoundedLottieGenerator {
        let maxWeight: Int

        func generateDocuments() -> [[String: Any]] {
            var documents: [[String: Any]] = []

            // Partition weight between assets and layers
            for aw in 0 ... maxWeight {
                let assetsLists = generateAssets(budget: aw)
                for assets in assetsLists {
                    let assetIds = assets.compactMap { $0["id"] as? String }
                    let lw = maxWeight - aw
                    let layerLists = generateLayerLists(budget: lw, assetIds: assetIds)
                    for layers in layerLists {
                        let doc: [String: Any] = [
                            "v": "5.7.4",
                            "fr": 30.0,
                            "ip": 0.0,
                            "op": 10.0,
                            "w": 64.0,
                            "h": 64.0,
                            "layers": layers,
                            "assets": assets,
                        ]
                        documents.append(doc)

                        // Also inject variants that are specifically invalid to check validator:

                        // Variant 1: Negative frame rate
                        var docNegFr = doc
                        docNegFr["fr"] = -30.0
                        documents.append(docNegFr)

                        // Variant 2: Invalid frame window
                        var docBadWindow = doc
                        docBadWindow["ip"] = 20.0
                        docBadWindow["op"] = 10.0
                        documents.append(docBadWindow)

                        // Variant 3: Layer index conflict or parenting cycle
                        if layers.count >= 2 {
                            var cyclicLayers = layers
                            cyclicLayers[0]["parent"] = cyclicLayers[1]["ind"]
                            cyclicLayers[1]["parent"] = cyclicLayers[0]["ind"]
                            var docCycle = doc
                            docCycle["layers"] = cyclicLayers
                            documents.append(docCycle)
                        }

                        // Variant 4: Missing field
                        var docMissingField = doc
                        docMissingField.removeValue(forKey: "fr")
                        documents.append(docMissingField)
                    }
                }
            }
            return documents
        }

        private func generateTransforms(budget: Int) -> [[String: Any]] {
            var results: [[String: Any]] = [[:]]
            if budget >= 1 {
                results.append([
                    "p": ["a": 0, "k": [10.0, 20.0, 0.0]],
                    "s": ["a": 0, "k": [100.0, 100.0, 100.0]],
                    "r": ["a": 0, "k": 0.0],
                ])
            }
            if budget >= 2 {
                // Animated transform
                results.append([
                    "p": [
                        "a": 1,
                        "k": [
                            ["t": 0.0, "s": [10.0, 20.0, 0.0]],
                            ["t": 10.0],
                        ],
                    ],
                ])
                // 3D/ddd transform
                results.append([
                    "ddd": 1,
                    "p": ["a": 0, "k": [10.0, 20.0, 0.0]],
                ])
            }
            return results
        }

        private func generateShapes(budget: Int) -> [[String: Any]] {
            var results: [[String: Any]] = []
            if budget >= 1 {
                // Rect
                results.append(["ty": "rc", "nm": "Rect", "d": 1, "p": ["a": 0, "k": [0.0, 0.0]], "s": ["a": 0, "k": [50.0, 50.0]]])
                // Ellipse
                results.append(["ty": "el", "nm": "Ellipse", "d": 1, "p": ["a": 0, "k": [0.0, 0.0]], "s": ["a": 0, "k": [50.0, 50.0]]])
                // Path
                results.append(["ty": "sh", "nm": "Path", "ks": ["a": 0, "k": ["i": [[0.0, 0.0]], "o": [[0.0, 0.0]], "v": [[10.0, 10.0]], "c": true]]])
                // Fill
                results.append(["ty": "fl", "nm": "Fill", "c": ["a": 0, "k": [1.0, 0.0, 0.0, 1.0]], "o": ["a": 0, "k": 100.0]])
                // Stroke
                results.append(["ty": "st", "nm": "Stroke", "c": ["a": 0, "k": [0.0, 1.0, 0.0, 1.0]], "o": ["a": 0, "k": 100.0], "w": ["a": 0, "k": 2.0]])
                // Shape Transform
                results.append(["ty": "tr", "nm": "Transform", "p": ["a": 0, "k": [0.0, 0.0]]])
            }
            if budget >= 2 {
                // Group (empty)
                results.append(["ty": "gr", "nm": "Group", "it": [] as [Any]])
                // Sub-shapes combinations inside Group
                if budget >= 3 {
                    for w in 1 ... (budget - 2) {
                        let subShapes = generateShapes(budget: w)
                        for sub in subShapes {
                            results.append(["ty": "gr", "nm": "Group", "it": [sub]])
                        }
                    }
                }
            }
            return results
        }

        private func generateShapeLists(budget: Int) -> [[[String: Any]]] {
            if budget <= 0 { return [[]] }
            var results: [[[String: Any]]] = [[]]
            for w in 1 ... budget {
                let items = generateShapes(budget: w)
                let tails = generateShapeLists(budget: budget - w)
                for item in items {
                    for tail in tails {
                        results.append([item] + tail)
                    }
                }
            }
            return results
        }

        private func generateLayers(budget: Int, assetIds: [String]) -> [[String: Any]] {
            var results: [[String: Any]] = []
            guard budget >= 2 else { return results }

            // Solid layer
            for tw in 0 ... (budget - 2) {
                let transforms = generateTransforms(budget: tw)
                for tf in transforms {
                    results.append([
                        "ty": 1,
                        "nm": "Solid",
                        "ind": 1,
                        "ip": 0.0,
                        "op": 10.0,
                        "st": 0.0,
                        "sr": 1.0,
                        "sw": 64.0,
                        "sh": 64.0,
                        "sc": "#ff0000",
                        "ks": tf,
                    ])
                }
            }

            // Null layer
            for tw in 0 ... (budget - 2) {
                let transforms = generateTransforms(budget: tw)
                for tf in transforms {
                    results.append([
                        "ty": 3,
                        "nm": "Null",
                        "ind": 1,
                        "ip": 0.0,
                        "op": 10.0,
                        "st": 0.0,
                        "ks": tf,
                    ])
                }
            }

            // Shape layer
            for tw in 0 ... (budget - 2) {
                let transforms = generateTransforms(budget: tw)
                for sw in 0 ... (budget - 2 - tw) {
                    let shapeLists = generateShapeLists(budget: sw)
                    for sl in shapeLists {
                        for tf in transforms {
                            results.append([
                                "ty": 4,
                                "nm": "Shape",
                                "ind": 1,
                                "ip": 0.0,
                                "op": 10.0,
                                "ks": tf,
                                "shapes": sl,
                            ])
                        }
                    }
                }
            }

            // Precomp layer
            for refId in assetIds {
                for tw in 0 ... (budget - 2) {
                    let transforms = generateTransforms(budget: tw)
                    for tf in transforms {
                        results.append([
                            "ty": 0,
                            "nm": "Precomp",
                            "ind": 1,
                            "refId": refId,
                            "ip": 0.0,
                            "op": 10.0,
                            "ks": tf,
                        ])
                    }
                }
            }

            // Track Matte layer (unsupported, validation will reject)
            results.append([
                "ty": 1,
                "nm": "Matte Target",
                "ind": 1,
                "ip": 0.0,
                "op": 10.0,
                "tt": 1,
                "tp": 2,
                "ks": [:],
            ])

            // Mask layer (unsupported, validation will reject)
            results.append([
                "ty": 1,
                "nm": "Masked Layer",
                "ind": 1,
                "ip": 0.0,
                "op": 10.0,
                "masksProperties": [
                    [
                        "mode": "a",
                        "pt": ["a": 0, "k": ["i": [[0.0, 0.0]], "o": [[0.0, 0.0]], "v": [[10.0, 10.0]], "c": true]],
                    ],
                ],
                "ks": [:],
            ])

            // Unsupported layer type (validation will reject)
            results.append([
                "ty": 99,
                "nm": "Unsupported Layer",
            ])

            return results
        }

        private func generateLayerLists(budget: Int, assetIds: [String]) -> [[[String: Any]]] {
            if budget < 2 { return [[]] }
            var results: [[[String: Any]]] = [[]]
            for w in 2 ... budget {
                let layers = generateLayers(budget: w, assetIds: assetIds)
                let tails = generateLayerLists(budget: budget - w, assetIds: assetIds)
                for layer in layers {
                    for tail in tails {
                        // 1. Acyclically and correctly parented
                        var normalLayer = layer
                        normalLayer["ind"] = tail.count + 1
                        results.append([normalLayer] + tail)

                        // 2. Cyclic/duplicate variant
                        var dupLayer = layer
                        dupLayer["ind"] = 1
                        var newTail = tail
                        if !newTail.isEmpty {
                            newTail[0]["ind"] = 1
                        }
                        results.append([dupLayer] + newTail)
                    }
                }
            }
            return results
        }

        private func generateAssets(budget: Int) -> [[[String: Any]]] {
            var results: [[[String: Any]]] = [[]]
            guard budget >= 2 else { return results }
            for lw in 0 ... (budget - 2) {
                let layerLists = generateLayerLists(budget: lw, assetIds: [])
                for layers in layerLists {
                    results.append([[
                        "id": "compA",
                        "w": 64.0,
                        "h": 64.0,
                        "layers": layers,
                    ]])
                }
            }
            return results
        }
    }

    @Test("totality and round-trip up to N")
    func totalityAndRoundTripUpToN() throws {
        // We set N = 4 to guarantee a quick and fast combinatorial generation
        // that still covers all recursive components and evaluates correctness.
        let generator = BoundedLottieGenerator(maxWeight: 4)
        let documents = generator.generateDocuments()

        #expect(documents.count >= 1000, "Should generate at least 1,000 documents to cover a rich combination space")

        var passedCount = 0
        var rejectedCount = 0

        for (index, doc) in documents.enumerated() {
            let data = try JSONSerialization.data(withJSONObject: doc, options: [])
            let jsonString = try #require(String(data: data, encoding: .utf8))

            do {
                let document = try LottieSourceDocument.parse(jsonString)
                let validator = LottieValidator()

                var passedValidation = false
                do {
                    try document.validate(using: validator)
                    passedValidation = true
                } catch {
                    rejectedCount += 1
                }

                if passedValidation {
                    do {
                        // If it passes validation, import and round-trip must succeed without throwing or crashing
                        let animation = try document.decodeAnimation()

                        // We run round-trip on frame 0 and 5
                        let roundTripGate = LottieSourceIntentTransformTimingRoundTripGate()
                        let report = roundTripGate.report(
                            animation: animation,
                            source: LottieDecompiledSourceIntentSource(identity: "exhaustive-\(index)", frameCount: 0),
                            selectedFrames: [
                                LottieSourceIntentRoundTripSelection(frame: 0.0, rationale: "Exhaustive testing frame 0.0"),
                                LottieSourceIntentRoundTripSelection(frame: 5.0, rationale: "Exhaustive testing frame 5.0"),
                            ]
                        )

                        try report.validate()
                        passedCount += 1
                    } catch {
                        Issue.record("Document passed validation but failed compilation/round-trip: \(error). Document: \(jsonString)")
                    }
                }
            } catch {
                // Parsing error is expected/success under "rejected or reported"
                rejectedCount += 1
            }
        }

        // Assert that we have a significant portion of both passed and rejected cases
        #expect(passedCount > 0, "At least some generated documents should pass validation")
        #expect(rejectedCount > 0, "At least some generated documents should be rejected")

        // Print count for docs/lottie-format/bounded-exhaustive-round-trip.md reference
        print("Bounded-Exhaustive count for N=4: \(documents.count) generated, \(passedCount) passed, \(rejectedCount) rejected")
    }
}
