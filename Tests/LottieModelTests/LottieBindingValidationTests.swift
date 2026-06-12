import Foundation
import LottieModel
import Testing

@Suite("Lottie binding validation")
struct LottieBindingValidationTests {
    @Test("Track matte fields decode as source facts")
    func trackMatteFieldsDecodeAsSourceFacts() throws {
        let animation = try LottieAnimation.decode(from: Data("""
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

        #expect(animation.layers[0].trackMatteSource == 1)
        #expect(animation.layers[1].trackMatteType == 1)
        #expect(animation.layers[1].trackMatteParent == 1)
    }

    @Test("Duplicate asset ids and layer indices are source validation errors")
    func duplicateBindingSymbolsAreValidationErrors() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 3, "nm": "One", "ind": 1, "ip": 0, "op": 30, "ks": {} },
            { "ty": 3, "nm": "Two", "ind": 1, "ip": 0, "op": 30, "ks": {} }
          ],
          "assets": [
            { "id": "same", "layers": [] },
            { "id": "same", "layers": [] }
          ]
        }
        """)

        let errors = validationErrors(
            for: document,
            using: LottieValidator.blank
                .validating(\.assetIDsAreUnique)
                .validating(\.layerIndicesAreUnique)
        )

        #expect(errors.map(\.ruleID) == [
            "lottie.asset.id.duplicate",
            "lottie.layer.index.duplicate",
        ])
        #expect(errors[0].codingPath.description == "$.assets[1].id")
        #expect(errors[1].codingPath.description == "$.layers[1].ind")
        #expect(errors.allSatisfy { $0.range != nil })
    }

    @Test("Parent cycles are semantic validation errors")
    func parentCyclesAreValidationErrors() throws {
        let document = try LottieSourceDocument.parse("""
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

        let errors = validationErrors(
            for: document,
            using: LottieValidator.blank.validating(\.layerParentReferencesDoNotCycle)
        )

        #expect(errors.count == 2)
        #expect(errors.allSatisfy { $0.ruleID == "lottie.layer.parent.cycle" })
        #expect(errors.map(\.codingPath.description) == ["$.layers[0].parent", "$.layers[1].parent"])
        #expect(errors.allSatisfy { $0.range != nil })
    }

    @Test("Track matte references resolve before import")
    func trackMatteReferencesResolveBeforeImport() throws {
        let document = try LottieSourceDocument.parse("""
        {
          "v": "5.7.4",
          "fr": 30,
          "ip": 0,
          "op": 30,
          "w": 64,
          "h": 64,
          "layers": [
            { "ty": 4, "nm": "First target", "ind": 1, "tt": 1, "ip": 0, "op": 30, "ks": {}, "shapes": [] },
            { "ty": 4, "nm": "Second target", "ind": 2, "tt": 1, "tp": 99, "ip": 0, "op": 30, "ks": {}, "shapes": [] }
          ],
          "assets": []
        }
        """)

        let errors = validationErrors(
            for: document,
            using: LottieValidator.blank.validating(\.layerMatteReferencesResolve)
        )

        #expect(errors.map(\.ruleID) == [
            "lottie.layer.matte.missing",
            "lottie.layer.matte.missing",
        ])
        #expect(errors.map(\.codingPath.description) == ["$.layers[0].tt", "$.layers[1].tp"])
        #expect(errors.allSatisfy { $0.range != nil })
    }

    private func validationErrors(for document: LottieSourceDocument, using validator: LottieValidator) -> [ValidationError] {
        do {
            try document.validate(using: validator)
            Issue.record("Expected validation to fail.")
            return []
        } catch let collection as ValidationErrorCollection {
            return collection.values
        } catch {
            Issue.record("Expected ValidationErrorCollection, got \(error).")
            return []
        }
    }
}
