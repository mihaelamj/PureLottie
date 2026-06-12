import LottieModel
import Testing

@Suite("Render feature validation")
struct RenderFeatureValidationTests {
    @Test("Unsupported layer types are rejected with source paths")
    func unsupportedLayerTypesAreRejectedWithSourcePaths() throws {
        let errors = try validationErrors(for: """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 2, "nm": "Image", "ind": 1, "refId": "image_0", "ip": 0, "op": 30, "ks": {} },
            { "ty": 5, "nm": "Text", "ind": 2, "ip": 0, "op": 30, "ks": {} },
            { "ty": 99, "nm": "Unknown", "ind": 3, "ip": 0, "op": 30, "ks": {} }
          ],
          "assets": [{ "id": "image_0" }]
        }
        """)

        expect(errors, contains: "lottie.layer.type-modeled", at: "$.layers[0].ty")
        expect(errors, contains: "lottie.layer.type-modeled", at: "$.layers[1].ty")
        expect(errors, contains: "lottie.layer.type-modeled", at: "$.layers[2].ty")
        #expect(errors.filter { $0.ruleID == "lottie.layer.type-modeled" }.allSatisfy { $0.range != nil })
    }

    @Test("Matte and time-remap fields are rejected before import")
    func matteAndTimeRemapFieldsAreRejectedBeforeImport() throws {
        let errors = try validationErrors(for: """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 4, "nm": "Matte", "ind": 1, "td": 1, "ip": 0, "op": 30, "ks": {}, "shapes": [] },
            { "ty": 4, "nm": "Target", "ind": 2, "tt": 1, "tp": 1, "ip": 0, "op": 30, "ks": {}, "shapes": [] },
            { "ty": 0, "nm": "Remapped", "ind": 3, "refId": "precomp", "tm": { "k": 1 }, "ip": 0, "op": 30, "ks": {} }
          ],
          "assets": [{ "id": "precomp", "layers": [] }]
        }
        """)

        expect(errors, contains: "lottie.layer.matte-field", at: "$.layers[0].td")
        expect(errors, contains: "lottie.layer.matte-field", at: "$.layers[1].tt")
        expect(errors, contains: "lottie.layer.time-locality", at: "$.layers[2].tm")
    }

    @Test("Unsupported mask fields are rejected with exact mask paths")
    func unsupportedMaskFieldsAreRejectedWithExactMaskPaths() throws {
        let errors = try validationErrors(for: """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Masked",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "masksProperties": [
              { "mode": "s", "inv": true, "pt": { "a": 1, "k": [] }, "o": { "a": 1, "k": [] } },
              { "mode": "a", "pt": { "a": 0, "k": {} } }
            ],
            "shapes": []
          }],
          "assets": []
        }
        """)

        expect(errors, contains: "lottie.layer.mask-field", at: "$.layers[0].masksProperties")
        expect(errors, contains: "lottie.layer.mask-field", at: "$.layers[0].masksProperties[0].mode")
        expect(errors, contains: "lottie.layer.mask-field", at: "$.layers[0].masksProperties[0].inv")
        expect(errors, contains: "lottie.layer.mask-field", at: "$.layers[0].masksProperties[0].pt", classification: .approximate)
        expect(errors, contains: "lottie.layer.mask-field", at: "$.layers[0].masksProperties[0].o", classification: .approximate)
    }

    @Test("3D layer mode is rejected before transform lowering")
    func layer3DModeIsRejectedBeforeTransformLowering() throws {
        let errors = try validationErrors(for: """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 4, "nm": "3D", "ind": 1, "ddd": 1, "ip": 0, "op": 30, "ks": {}, "shapes": [] },
            { "ty": 4, "nm": "Bad 3D", "ind": 2, "ddd": "yes", "ip": 0, "op": 30, "ks": {}, "shapes": [] }
          ],
          "assets": []
        }
        """)

        expect(errors, contains: "lottie.layer.transform-field", at: "$.layers[0].ddd")
        expect(errors, contains: "lottie.layer.transform-field", at: "$.layers[1].ddd")
    }

    @Test("Shape geometry style modifier and transform gaps carry source paths")
    func shapeFeatureGapsCarrySourcePaths() throws {
        let errors = try validationErrors(for: """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Shapes",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              { "ty": "sr", "nm": "Star", "sy": 3 },
              { "ty": "sh", "nm": "Directed path", "d": 4, "ks": { "a": 0, "k": {} } },
              { "ty": "st", "nm": "Stroke", "c": { "a": 1, "k": [] }, "o": { "a": 0, "k": 100 }, "w": { "a": 1, "k": [] }, "lc": 2, "lj": 3, "ml": 4, "ml2": { "a": 0, "k": 4 }, "bm": 1, "d": [{ "n": "d", "v": { "a": 0, "k": 2 } }] },
              { "ty": "tm", "nm": "Offset trim", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 100 }, "o": { "a": 0, "k": 15 }, "m": 2 },
              { "ty": "tr", "nm": "Animated transform", "p": { "a": 1, "k": [] } }
            ]
          }],
          "assets": []
        }
        """)

        expect(errors, contains: "lottie.shape.geometry-field", at: "$.layers[0].shapes[0].sy")
        expect(errors, contains: "lottie.shape.geometry-field", at: "$.layers[0].shapes[1].d")
        expect(errors, contains: "lottie.shape.style-field", at: "$.layers[0].shapes[2].bm")
        expect(errors, contains: "lottie.shape.style-field", at: "$.layers[0].shapes[2].c")
        expect(errors, contains: "lottie.shape.style-field", at: "$.layers[0].shapes[2].w")
        expect(errors, contains: "lottie.shape.style-field", at: "$.layers[0].shapes[2].lc")
        expect(errors, contains: "lottie.shape.style-field", at: "$.layers[0].shapes[2].d")
        expect(errors, contains: "lottie.shape.modifier-field", at: "$.layers[0].shapes[3].o")
        expect(errors, contains: "lottie.shape.modifier-field", at: "$.layers[0].shapes[3].m", classification: .approximate)
        expect(errors, contains: "lottie.shape.transform-field", at: "$.layers[0].shapes[4].p")
    }

    @Test("Fractional render enum values are rejected without truncation")
    func fractionalRenderEnumValuesAreRejectedWithoutTruncation() throws {
        let errors = try validationErrors(for: """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4.5,
            "nm": "Fractional",
            "ind": 1,
            "tt": 0.5,
            "td": 0.5,
            "sr": "fast",
            "st": "late",
            "ip": 0,
            "op": 30,
            "ks": {},
            "shapes": [
              { "ty": "sh", "nm": "Path", "d": 1.5, "ks": { "a": 0, "k": {} } },
              { "ty": "st", "nm": "Stroke", "c": { "a": 0, "k": [0, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "w": { "a": 0, "k": 2 }, "bm": 0.5, "lc": 1.5, "lj": "round", "ml": "wide" },
              { "ty": "tm", "nm": "Trim", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 100 }, "m": 2.5 }
            ]
          }],
          "assets": []
        }
        """)

        expect(errors, contains: "lottie.layer.type-modeled", at: "$.layers[0].ty")
        expect(errors, contains: "lottie.layer.matte-field", at: "$.layers[0].tt")
        expect(errors, contains: "lottie.layer.matte-field", at: "$.layers[0].td")
        expect(errors, contains: "lottie.layer.time-locality", at: "$.layers[0].sr")
        expect(errors, contains: "lottie.layer.time-locality", at: "$.layers[0].st")
        expect(errors, contains: "lottie.shape.geometry-field", at: "$.layers[0].shapes[0].d")
        expect(errors, contains: "lottie.shape.style-field", at: "$.layers[0].shapes[1].bm")
        expect(errors, contains: "lottie.shape.style-field", at: "$.layers[0].shapes[1].lc")
        expect(errors, contains: "lottie.shape.style-field", at: "$.layers[0].shapes[1].lj")
        expect(errors, contains: "lottie.shape.style-field", at: "$.layers[0].shapes[1].ml")
        expect(errors, contains: "lottie.shape.modifier-field", at: "$.layers[0].shapes[2].m")
    }

    @Test("Image asset payload fields are rejected with asset paths")
    func imageAssetPayloadFieldsAreRejectedWithAssetPaths() throws {
        let errors = try validationErrors(for: """
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [],
          "assets": [{ "id": "image_0", "w": 10, "h": 10, "u": "images/", "p": "dot.png", "e": 0, "t": "seq" }]
        }
        """)

        expect(errors, contains: "lottie.asset.render-field", at: "$.assets[0].e")
        expect(errors, contains: "lottie.asset.render-field", at: "$.assets[0].p")
        expect(errors, contains: "lottie.asset.render-field", at: "$.assets[0].t")
        expect(errors, contains: "lottie.asset.render-field", at: "$.assets[0].u")
    }

    @Test("Modeled render subset validates cleanly")
    func modeledRenderSubsetValidatesCleanly() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [{
            "ty": 4,
            "nm": "Modeled",
            "ind": 1,
            "ip": 0,
            "op": 30,
            "ks": {},
            "masksProperties": [{ "mode": "a", "inv": false, "pt": { "a": 0, "k": {} }, "o": { "a": 0, "k": 100 } }],
            "shapes": [
              { "ty": "rc", "nm": "Box", "p": { "a": 0, "k": [10, 10] }, "s": { "a": 0, "k": [20, 20] }, "r": { "a": 0, "k": 0 } },
              { "ty": "tm", "nm": "Identity trim", "s": { "a": 0, "k": 0 }, "e": { "a": 0, "k": 100 }, "o": { "a": 0, "k": 0 }, "m": 1 },
              { "ty": "fl", "nm": "Fill", "c": { "a": 0, "k": [1, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "r": 1 },
              { "ty": "st", "nm": "Stroke", "c": { "a": 0, "k": [0, 0, 0, 1] }, "o": { "a": 0, "k": 100 }, "w": { "a": 0, "k": 2 }, "lc": 1, "lj": 1, "ml": 10, "d": [] }
            ]
          }],
          "assets": [{ "id": "precomp", "layers": [] }]
        }
        """)

        try document.validate()
    }
}

private func validationErrors(for source: String) throws -> [ValidationError] {
    let document = try LottieSourceDocument.parse(source)
    do {
        try document.validate()
        Issue.record("Expected validation to fail.")
        return []
    } catch let collection as ValidationErrorCollection {
        return collection.values
    } catch {
        Issue.record("Expected ValidationErrorCollection, got \(error).")
        return []
    }
}

private func expect(
    _ errors: [ValidationError],
    contains ruleID: String,
    at path: String,
    classification: FeatureClassification? = nil
) {
    #expect(errors.contains { error in
        error.ruleID == ruleID
            && error.codingPath.description == path
            && (classification == nil || error.classification == classification)
    })
}
