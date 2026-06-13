public final class LottieValidator {
    private var defaultValidations: [AnyValidation<LottieSourceDocument>]
    private var customValidations: [AnyValidation<LottieSourceDocument>]

    public init() {
        defaultValidations = BuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(defaultValidations: [AnyValidation<LottieSourceDocument>], customValidations: [AnyValidation<LottieSourceDocument>]) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieValidator {
        LottieValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieSourceDocument, some Validatable>) -> Self {
        customValidations.append(AnyValidation(validation))
        return self
    }

    @discardableResult
    public func validating(
        _ validation: KeyPath<BuiltinValidation.Type, Validation<LottieSourceDocument, some Validatable>>
    ) -> Self {
        validating(BuiltinValidation.self[keyPath: validation])
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    @discardableResult
    public func withoutValidating(
        _ validation: KeyPath<BuiltinValidation.Type, Validation<LottieSourceDocument, some Validatable>>
    ) -> Self {
        withoutValidating(BuiltinValidation.self[keyPath: validation].description)
    }

    public func validate(_ document: LottieSourceDocument) throws {
        let errors = collectErrors(in: document)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    public func collectErrors(in document: LottieSourceDocument) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(document, at: JSONPath(), in: document, errors: &errors)
        visit(document.source, at: JSONPath(), in: document, errors: &errors)
        return errors
    }

    private var activeValidations: [AnyValidation<LottieSourceDocument>] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in document: LottieSourceDocument,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: document))
        }

        guard let value = subject as? JSONValue else { return }
        switch value {
        case let .object(members, _):
            for member in members {
                visit(member.value, at: path.appending(.key(member.key)), in: document, errors: &errors)
            }
        case let .array(values, _):
            for index in values.indices {
                visit(values[index], at: path.appending(.index(index)), in: document, errors: &errors)
            }
        case .string, .number, .bool, .null:
            break
        }
    }
}

public extension LottieSourceDocument {
    @discardableResult
    func validate(using validator: LottieValidator = LottieValidator()) throws -> Self {
        try validator.validate(self)
        return self
    }
}

public enum BuiltinValidation {
    static var defaultValidations: [AnyValidation<LottieSourceDocument>] {
        [
            AnyValidation(objectKeysAreUnique),
            AnyValidation(rootIsObject),
            AnyValidation(rootRequiredFieldsExist),
            AnyValidation(rootFrameRateIsPositive),
            AnyValidation(rootFrameWindowIsValid),
            AnyValidation(rootFieldsAreKnownOrMetadata),
            AnyValidation(assetIDsAreUnique),
            AnyValidation(layerIndicesAreUnique),
            AnyValidation(layerParentReferencesResolve),
            AnyValidation(layerParentReferencesDoNotCycle),
            AnyValidation(precompositionReferencesDoNotCycle),
            AnyValidation(layerAssetReferencesResolve),
            AnyValidation(layerMatteReferencesResolve),
            AnyValidation(layerTypesAreModeledOrReported),
            AnyValidation(layerCompositingFieldsAreModeledOrReported),
            AnyValidation(layerMatteFieldsAreModeledOrReported),
            AnyValidation(layerSilentRiskFieldsAreModeledOrReported),
            AnyValidation(layerTimeFieldsAreModeled),
            AnyValidation(layerMaskFieldsAreModeledOrReported),
            AnyValidation(layerTransformFieldsAreModeledOrReported),
            AnyValidation(transformSilentRiskFieldsAreModeledOrReported),
            AnyValidation(assetRenderFieldsAreModeledOrReported),
            AnyValidation(shapeTypesAreModeledOrReported),
            AnyValidation(shapeGeometryFieldsAreModeledOrReported),
            AnyValidation(shapeStyleFieldsAreModeledOrReported),
            AnyValidation(shapeModifierFieldsAreModeledOrReported),
            AnyValidation(shapeTransformFieldsAreModeledOrReported),
            AnyValidation(strokeStyleFieldsAreModeledOrReported),
        ]
    }

    public static var objectKeysAreUnique: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "json.object.duplicate-key",
            description: "JSON object keys are unique",
            phase: .source,
            check: { context in
                guard let members = context.subject.objectMembers else { return [] }
                var firstByKey: [String: JSONObjectMember] = [:]
                var errors: [ValidationError] = []

                for member in members {
                    if let first = firstByKey[member.key] {
                        let path = context.codingPath.appending(.key(member.key))
                        errors.append(
                            ValidationError(
                                ruleID: "json.object.duplicate-key",
                                reason: "Duplicate JSON object key `\(member.key)` is not allowed.",
                                at: path,
                                range: member.keyRange,
                                phase: .source,
                                classification: .gap,
                                evidence: "Later value would overwrite an earlier value during JSONDecoder decoding."
                            )
                        )
                        errors.append(
                            ValidationError(
                                ruleID: "json.object.duplicate-key.first",
                                reason: "First declaration of JSON object key `\(member.key)` is here.",
                                at: path,
                                range: first.keyRange,
                                severity: .note,
                                phase: .source,
                                classification: .metadata
                            )
                        )
                    } else {
                        firstByKey[member.key] = member
                    }
                }

                return errors
            }
        )
    }

    public static var rootIsObject: Validation<LottieSourceDocument, LottieSourceDocument> {
        Validation(
            ruleID: "lottie.root.object",
            description: "Root Lottie document is a JSON object",
            phase: .source,
            check: { context in context.subject.source.objectMembers != nil }
        )
    }

    public static var rootRequiredFieldsExist: Validation<LottieSourceDocument, LottieSourceDocument> {
        Validation(
            ruleID: "lottie.root.required-fields",
            description: "Root Lottie document declares v, fr, ip, op, w, h, and layers",
            phase: .source,
            check: { context in
                guard let members = context.subject.source.objectMembers else { return [] }
                let keys = Set(members.map(\.key))
                return ["v", "fr", "ip", "op", "w", "h", "layers"].compactMap { key in
                    guard !keys.contains(key) else { return nil }
                    return ValidationError(
                        ruleID: "lottie.root.required-fields",
                        reason: "Root Lottie document is missing required field `\(key)`.",
                        at: JSONPath().appending(.key(key)),
                        range: context.subject.source.range,
                        phase: .source,
                        classification: .gap
                    )
                }
            }
        )
    }

    public static var rootFrameRateIsPositive: Validation<LottieSourceDocument, LottieSourceDocument> {
        Validation(
            ruleID: "lottie.root.frame-rate",
            description: "Root frame rate is greater than zero",
            phase: .semantic,
            check: { context in
                guard let frameRate = context.subject.source.member("fr"), let value = frameRate.numberValue, value <= 0 else {
                    return []
                }
                return [
                    ValidationError(
                        ruleID: "lottie.root.frame-rate",
                        reason: "Failed to satisfy: Root frame rate is greater than zero",
                        at: JSONPath([.key("fr")]),
                        range: frameRate.range,
                        phase: .semantic,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var rootFrameWindowIsValid: Validation<LottieSourceDocument, LottieSourceDocument> {
        Validation(
            ruleID: "lottie.root.frame-window",
            description: "Root out point is greater than in point and `op` remains exclusive",
            phase: .semantic,
            check: { context in
                guard let inPoint = context.subject.source.member("ip")?.numberValue,
                      let outPointValue = context.subject.source.member("op"),
                      let outPoint = outPointValue.numberValue,
                      outPoint <= inPoint
                else {
                    return []
                }
                return [
                    ValidationError(
                        ruleID: "lottie.root.frame-window",
                        reason: "Failed to satisfy: Root out point is greater than in point and `op` remains exclusive",
                        at: JSONPath([.key("op")]),
                        range: outPointValue.range,
                        phase: .semantic,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var rootFieldsAreKnownOrMetadata: Validation<LottieSourceDocument, LottieSourceDocument> {
        Validation(
            ruleID: "lottie.root.unknown-field",
            description: "Root fields are known or explicitly classified before rendering",
            phase: .source,
            check: { context in
                guard let members = context.subject.source.objectMembers else { return [] }
                let known = Set(["v", "ver", "fr", "ip", "op", "w", "h", "layers", "assets", "markers", "slots", "meta", "metadata", "nm", "mn", "ddd", "props", "chars", "fonts"])
                return members.compactMap { member in
                    guard !known.contains(member.key) else { return nil }
                    return ValidationError(
                        ruleID: "lottie.root.unknown-field",
                        reason: "Unknown root field `\(member.key)` must be classified before rendering.",
                        at: JSONPath([.key(member.key)]),
                        range: member.value.range,
                        phase: .source,
                        classification: .gap
                    )
                }
            }
        )
    }

    public static var layerParentReferencesResolve: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.parent.missing",
            description: "Layer parent indices resolve inside their composition",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isLayerPath(context.codingPath),
                      let parentValue = context.subject.member("parent"),
                      let parent = parentValue.numberValue
                else {
                    return []
                }
                let parentIndex = Int(parent)
                let siblingIndices = Set(layerSiblings(for: context.codingPath, in: context.document.source).compactMap { layer -> Int? in
                    guard let number = layer.member("ind")?.numberValue else { return nil }
                    return Int(number)
                })
                guard siblingIndices.contains(parentIndex) else {
                    return [
                        ValidationError(
                            ruleID: "lottie.layer.parent.missing",
                            reason: "Layer parent index `\(parentIndex)` does not resolve inside this composition.",
                            at: context.codingPath.appending(.key("parent")),
                            range: parentValue.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }
                return []
            }
        )
    }

    public static var assetIDsAreUnique: Validation<LottieSourceDocument, LottieSourceDocument> {
        Validation(
            ruleID: "lottie.asset.id.duplicate",
            description: "Asset ids are unique inside the document",
            phase: .semantic,
            check: { context in
                guard let assets = context.subject.source.member("assets")?.arrayValues else { return [] }
                var firstByID: [String: Int] = [:]
                var errors: [ValidationError] = []
                for (offset, asset) in assets.enumerated() {
                    guard let idValue = asset.member("id"), let id = idValue.stringValue else { continue }
                    if firstByID[id] != nil {
                        errors.append(
                            ValidationError(
                                ruleID: "lottie.asset.id.duplicate",
                                reason: "Asset id `\(id)` is declared more than once.",
                                at: JSONPath([.key("assets"), .index(offset), .key("id")]),
                                range: idValue.range,
                                phase: .semantic,
                                classification: .gap
                            )
                        )
                    } else {
                        firstByID[id] = offset
                    }
                }
                return errors
            }
        )
    }

    public static var layerIndicesAreUnique: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.index.duplicate",
            description: "Layer indices are unique inside each composition",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isLayerPath(context.codingPath),
                      let offset = layerOffset(for: context.codingPath),
                      let indexValue = context.subject.member("ind"),
                      let index = indexValue.numberValue
                else {
                    return []
                }
                let duplicateExistsBeforeLayer = layerSiblings(for: context.codingPath, in: context.document.source)
                    .prefix(offset)
                    .contains { sibling in sibling.member("ind")?.numberValue == index }
                guard duplicateExistsBeforeLayer else { return [] }
                return [
                    ValidationError(
                        ruleID: "lottie.layer.index.duplicate",
                        reason: "Layer index `\(Int(index))` is declared more than once inside this composition.",
                        at: context.codingPath.appending(.key("ind")),
                        range: indexValue.range,
                        phase: .semantic,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var layerParentReferencesDoNotCycle: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.parent.cycle",
            description: "Layer parent chains are acyclic inside each composition",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isLayerPath(context.codingPath),
                      let layerIndexValue = context.subject.member("ind"),
                      let layerIndex = layerIndexValue.numberValue,
                      let parentValue = context.subject.member("parent"),
                      let parent = parentValue.numberValue
                else {
                    return []
                }

                let byIndex = layerIndexTable(for: context.codingPath, in: context.document.source)
                var seen: Set<Int> = [Int(layerIndex)]
                var cursor: Int? = Int(parent)
                while let parentIndex = cursor {
                    guard seen.insert(parentIndex).inserted else {
                        return [
                            ValidationError(
                                ruleID: "lottie.layer.parent.cycle",
                                reason: "Layer parent chain cycles through index `\(parentIndex)`.",
                                at: context.codingPath.appending(.key("parent")),
                                range: parentValue.range,
                                phase: .semantic,
                                classification: .gap
                            ),
                        ]
                    }
                    cursor = byIndex[parentIndex]?.member("parent")?.numberValue.map(Int.init)
                }
                return []
            }
        )
    }

    public static var precompositionReferencesDoNotCycle: Validation<LottieSourceDocument, LottieSourceDocument> {
        Validation(
            ruleID: "lottie.asset.precomposition.cycle",
            description: "Precomposition asset references are acyclic",
            phase: .semantic,
            check: { context in
                var deps: [String: [(refId: String, path: JSONPath, range: SourceRange?)]] = [:]

                if let rootLayers = context.subject.source.member("layers")?.arrayValues {
                    var rootDeps: [(refId: String, path: JSONPath, range: SourceRange?)] = []
                    for (i, layer) in rootLayers.enumerated() {
                        if let ty = layer.member("ty")?.numberValue, Int(ty) == 0,
                           let refIdVal = layer.member("refId"),
                           let refId = refIdVal.stringValue
                        {
                            rootDeps.append((
                                refId: refId,
                                path: JSONPath([.key("layers"), .index(i), .key("refId")]),
                                range: refIdVal.range
                            ))
                        }
                    }
                    deps["root"] = rootDeps
                }

                if let assets = context.subject.source.member("assets")?.arrayValues {
                    for (offset, asset) in assets.enumerated() {
                        guard let id = asset.member("id")?.stringValue else { continue }
                        guard let layers = asset.member("layers")?.arrayValues else { continue }
                        var assetDeps: [(refId: String, path: JSONPath, range: SourceRange?)] = []
                        for (i, layer) in layers.enumerated() {
                            if let ty = layer.member("ty")?.numberValue, Int(ty) == 0,
                               let refIdVal = layer.member("refId"),
                               let refId = refIdVal.stringValue
                            {
                                assetDeps.append((
                                    refId: refId,
                                    path: JSONPath([.key("assets"), .index(offset), .key("layers"), .index(i), .key("refId")]),
                                    range: refIdVal.range
                                ))
                            }
                        }
                        deps[id] = assetDeps
                    }
                }

                var errors: [ValidationError] = []

                func canReach(from: String, target: String, visited: inout Set<String>) -> Bool {
                    if from == target { return true }
                    guard visited.insert(from).inserted else { return false }
                    guard let edges = deps[from] else { return false }
                    for edge in edges {
                        if canReach(from: edge.refId, target: target, visited: &visited) {
                            return true
                        }
                    }
                    return false
                }

                for (source, edges) in deps {
                    for edge in edges {
                        var visited: Set<String> = []
                        if canReach(from: edge.refId, target: source, visited: &visited) {
                            errors.append(ValidationError(
                                ruleID: "lottie.asset.precomposition.cycle",
                                reason: "Precomposition reference `\(edge.refId)` creates a cycle back to `\(source)`.",
                                at: edge.path,
                                range: edge.range,
                                phase: .semantic,
                                classification: .gap
                            ))
                        }
                    }
                }

                return errors
            }
        )
    }

    public static var layerAssetReferencesResolve: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.refId.missing",
            description: "Image and precomposition layer asset references resolve",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isLayerPath(context.codingPath),
                      let type = context.subject.member("ty")?.numberValue,
                      [0, 2].contains(Int(type))
                else {
                    return []
                }

                guard let reference = context.subject.member("refId") else {
                    return [
                        ValidationError(
                            ruleID: "lottie.layer.refId.required",
                            reason: "Referenced layer type requires `refId`.",
                            at: context.codingPath.appending(.key("refId")),
                            range: context.subject.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }

                guard let referenceID = reference.stringValue else {
                    return [
                        ValidationError(
                            ruleID: "lottie.layer.refId.type",
                            reason: "Layer `refId` must be a string.",
                            at: context.codingPath.appending(.key("refId")),
                            range: reference.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }

                let assetIDs = assetIDs(in: context.document.source)
                guard assetIDs.contains(referenceID) else {
                    return [
                        ValidationError(
                            ruleID: "lottie.layer.refId.missing",
                            reason: "Layer `refId` \(referenceID) does not resolve to an asset.",
                            at: context.codingPath.appending(.key("refId")),
                            range: reference.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }
                return []
            }
        )
    }

    public static var layerMatteReferencesResolve: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.matte.missing",
            description: "Track matte source layers resolve inside their composition",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isLayerPath(context.codingPath),
                      let matteValue = context.subject.member("tt")
                else {
                    return []
                }

                guard let matteMode = matteValue.numberValue else {
                    return [
                        ValidationError(
                            ruleID: "lottie.layer.matte.type",
                            reason: "Layer track matte mode `tt` must be a number.",
                            at: context.codingPath.appending(.key("tt")),
                            range: matteValue.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }
                guard Int(matteMode) != 0 else { return [] }

                if let explicitValue = context.subject.member("tp") {
                    guard let explicitIndex = explicitValue.numberValue else {
                        return [
                            ValidationError(
                                ruleID: "lottie.layer.matte.type",
                                reason: "Layer track matte parent `tp` must be a number.",
                                at: context.codingPath.appending(.key("tp")),
                                range: explicitValue.range,
                                phase: .semantic,
                                classification: .gap
                            ),
                        ]
                    }
                    let siblingIndices = Set(layerSiblings(for: context.codingPath, in: context.document.source).compactMap { layer -> Int? in
                        guard let number = layer.member("ind")?.numberValue else { return nil }
                        return Int(number)
                    })
                    guard siblingIndices.contains(Int(explicitIndex)) else {
                        return [
                            ValidationError(
                                ruleID: "lottie.layer.matte.missing",
                                reason: "Layer track matte parent `\(Int(explicitIndex))` does not resolve inside this composition.",
                                at: context.codingPath.appending(.key("tp")),
                                range: explicitValue.range,
                                phase: .semantic,
                                classification: .gap
                            ),
                        ]
                    }
                    return []
                }

                guard let offset = layerOffset(for: context.codingPath), offset > 0 else {
                    return [
                        ValidationError(
                            ruleID: "lottie.layer.matte.missing",
                            reason: "Layer track matte mode requires an implicit preceding source layer or explicit `tp`.",
                            at: context.codingPath.appending(.key("tt")),
                            range: matteValue.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }
                return []
            }
        )
    }

    public static var layerSilentRiskFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        objectFieldRule(
            ruleID: "lottie.layer.silent-risk-field",
            description: "Layer rendering fields are modeled or reported before rendering",
            phase: .semantic,
            fields: [
                "ao": "Auto-orient changes rotation from the position path tangent.",
                "ef": "Effects can change rendered pixels.",
                "t": "Text documents and text animators change rendered pixels.",
            ],
            when: { isLayerPath($0.codingPath) }
        )
    }

    public static var layerTypesAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.type-modeled",
            description: "Layer types are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil, isLayerPath(context.codingPath) else { return [] }
                guard let typeValue = context.subject.member("ty") else {
                    return [
                        ValidationError(
                            ruleID: "lottie.layer.type-modeled",
                            reason: "Layer must declare numeric type field `ty`.",
                            at: context.codingPath.appending(.key("ty")),
                            range: context.subject.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }
                guard let type = integralNumber(typeValue) else {
                    return [
                        ValidationError(
                            ruleID: "lottie.layer.type-modeled",
                            reason: "Layer type field `ty` must be an integer.",
                            at: context.codingPath.appending(.key("ty")),
                            range: typeValue.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }
                guard [0, 1, 3, 4].contains(type) else {
                    return [
                        ValidationError(
                            ruleID: "lottie.layer.type-modeled",
                            reason: "Layer type `\(type)` is not modeled by the validated importer.",
                            at: context.codingPath.appending(.key("ty")),
                            range: typeValue.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }
                return []
            }
        )
    }

    public static var layerCompositingFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.compositing-field",
            description: "Layer compositing fields are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil, isLayerPath(context.codingPath) else { return [] }
                guard let blendMode = context.subject.member("bm") else { return [] }
                guard integralNumber(blendMode) != nil else {
                    return [
                        integerFieldError(
                            ruleID: "lottie.layer.compositing-field",
                            field: "Layer blend mode `bm`",
                            key: "bm",
                            value: blendMode,
                            path: context.codingPath
                        ),
                    ]
                }
                return []
            }
        )
    }

    public static var layerMatteFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.matte-field",
            description: "Track matte fields are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil, isLayerPath(context.codingPath) else { return [] }
                var errors: [ValidationError] = []
                if let matteType = context.subject.member("tt") {
                    if let mode = integralNumber(matteType) {
                        if mode != 0 {
                            errors.append(ValidationError(
                                ruleID: "lottie.layer.matte-field",
                                reason: "Track matte mode `tt` changes compositing and is not lowered by the validated importer.",
                                at: context.codingPath.appending(.key("tt")),
                                range: matteType.range,
                                phase: .semantic,
                                classification: .gap
                            ))
                        }
                    } else {
                        errors.append(ValidationError(
                            ruleID: "lottie.layer.matte-field",
                            reason: "Track matte mode `tt` must be an integer.",
                            at: context.codingPath.appending(.key("tt")),
                            range: matteType.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                    }
                }
                if let matteSource = context.subject.member("td") {
                    if let marker = integralNumber(matteSource) {
                        if marker != 0 {
                            errors.append(ValidationError(
                                ruleID: "lottie.layer.matte-field",
                                reason: "Track matte source marker `td` changes compositing and is not lowered by the validated importer.",
                                at: context.codingPath.appending(.key("td")),
                                range: matteSource.range,
                                phase: .semantic,
                                classification: .gap
                            ))
                        }
                    } else {
                        errors.append(ValidationError(
                            ruleID: "lottie.layer.matte-field",
                            reason: "Track matte source marker `td` must be an integer.",
                            at: context.codingPath.appending(.key("td")),
                            range: matteSource.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                    }
                }
                return errors
            }
        )
    }

    public static var layerTimeFieldsAreModeled: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.time-locality",
            description: "Layer local-time fields are modeled before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil, isLayerPath(context.codingPath) else { return [] }
                var errors: [ValidationError] = []
                if let stretch = context.subject.member("sr") {
                    if let value = stretch.numberValue {
                        if value != 1 {
                            errors.append(
                                ValidationError(
                                    ruleID: "lottie.layer.time-locality",
                                    reason: "Non-default layer stretch `sr` must scale source time before rendering.",
                                    at: context.codingPath.appending(.key("sr")),
                                    range: stretch.range,
                                    phase: .semantic,
                                    classification: .gap
                                )
                            )
                        }
                    } else {
                        errors.append(numberFieldError(
                            ruleID: "lottie.layer.time-locality",
                            field: "Layer stretch `sr`",
                            key: "sr",
                            value: stretch,
                            path: context.codingPath
                        ))
                    }
                }
                if let startTime = context.subject.member("st") {
                    if let value = startTime.numberValue {
                        if value != 0 {
                            errors.append(
                                ValidationError(
                                    ruleID: "lottie.layer.time-locality",
                                    reason: "Non-zero layer start time `st` must offset source time before rendering.",
                                    at: context.codingPath.appending(.key("st")),
                                    range: startTime.range,
                                    phase: .semantic,
                                    classification: .gap
                                )
                            )
                        }
                    } else {
                        errors.append(numberFieldError(
                            ruleID: "lottie.layer.time-locality",
                            field: "Layer start time `st`",
                            key: "st",
                            value: startTime,
                            path: context.codingPath
                        ))
                    }
                }
                if let timeRemap = context.subject.member("tm") {
                    errors.append(
                        ValidationError(
                            ruleID: "lottie.layer.time-locality",
                            reason: "Layer time remap `tm` must remap source time before rendering.",
                            at: context.codingPath.appending(.key("tm")),
                            range: timeRemap.range,
                            phase: .semantic,
                            classification: .gap
                        )
                    )
                }
                return errors
            }
        )
    }

    public static var layerMaskFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.mask-field",
            description: "Layer mask fields are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                if context.subject.objectMembers != nil, isLayerPath(context.codingPath),
                   let masks = context.subject.member("masksProperties")
                {
                    guard let values = masks.arrayValues else {
                        return [
                            ValidationError(
                                ruleID: "lottie.layer.mask-field",
                                reason: "Layer masks field `masksProperties` must be an array.",
                                at: context.codingPath.appending(.key("masksProperties")),
                                range: masks.range,
                                phase: .semantic,
                                classification: .gap
                            ),
                        ]
                    }
                    guard values.count <= 1 else {
                        return [
                            ValidationError(
                                ruleID: "lottie.layer.mask-field",
                                reason: "Multiple masks require mask compositing that is not lowered by the validated importer.",
                                at: context.codingPath.appending(.key("masksProperties")),
                                range: masks.range,
                                phase: .semantic,
                                classification: .gap
                            ),
                        ]
                    }
                    return []
                }

                guard context.subject.objectMembers != nil, isMaskPath(context.codingPath) else { return [] }
                var errors: [ValidationError] = []
                if let modeValue = context.subject.member("mode") {
                    if let mode = modeValue.stringValue {
                        if !["a", "n"].contains(mode) {
                            errors.append(ValidationError(
                                ruleID: "lottie.layer.mask-field",
                                reason: "Mask mode `\(mode)` changes compositing and is not lowered by the validated importer.",
                                at: context.codingPath.appending(.key("mode")),
                                range: modeValue.range,
                                phase: .semantic,
                                classification: .gap
                            ))
                        }
                    } else {
                        errors.append(ValidationError(
                            ruleID: "lottie.layer.mask-field",
                            reason: "Mask mode field `mode` must be a string.",
                            at: context.codingPath.appending(.key("mode")),
                            range: modeValue.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                    }
                }
                if let inverted = context.subject.member("inv") {
                    if inverted.boolValue == true {
                        errors.append(ValidationError(
                            ruleID: "lottie.layer.mask-field",
                            reason: "Inverted masks require compositing that is not lowered by the validated importer.",
                            at: context.codingPath.appending(.key("inv")),
                            range: inverted.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                    } else if inverted.boolValue == nil {
                        errors.append(ValidationError(
                            ruleID: "lottie.layer.mask-field",
                            reason: "Mask inversion field `inv` must be a boolean.",
                            at: context.codingPath.appending(.key("inv")),
                            range: inverted.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                    }
                }
                for key in ["pt", "o"] where animatedPropertyIsAnimated(context.subject.member(key)) {
                    errors.append(ValidationError(
                        ruleID: "lottie.layer.mask-field",
                        reason: "Animated mask field `\(key)` is approximated by the importer.",
                        at: context.codingPath.appending(.key(key)),
                        range: context.subject.member(key)?.range,
                        phase: .semantic,
                        classification: .approximate
                    ))
                }
                return errors
            }
        )
    }

    public static var layerTransformFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.transform-field",
            description: "Layer transform mode fields are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isLayerPath(context.codingPath),
                      let mode = context.subject.member("ddd")
                else {
                    return []
                }
                guard let value = mode.numberValue else {
                    return [
                        numberFieldError(
                            ruleID: "lottie.layer.transform-field",
                            field: "Layer 3D mode `ddd`",
                            key: "ddd",
                            value: mode,
                            path: context.codingPath
                        ),
                    ]
                }
                guard value != 0 else { return [] }
                return [
                    ValidationError(
                        ruleID: "lottie.layer.transform-field",
                        reason: "Layer 3D mode `ddd` changes transform evaluation and is not lowered by the validated importer.",
                        at: context.codingPath.appending(.key("ddd")),
                        range: mode.range,
                        phase: .semantic,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var transformSilentRiskFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        objectFieldRule(
            ruleID: "lottie.transform.silent-risk-field",
            description: "Transform rendering fields are modeled or reported before rendering",
            phase: .semantic,
            fields: [
                "or": "3D orientation changes transform evaluation.",
                "rx": "3D x rotation changes transform evaluation.",
                "ry": "3D y rotation changes transform evaluation.",
                "rz": "3D z rotation changes transform evaluation.",
                "sa": "Skew axis changes transform evaluation.",
                "sk": "Skew amount changes transform evaluation.",
            ],
            when: { isLayerTransformPath($0.codingPath) || isShapeTransformPath($0.codingPath, subject: $0.subject) }
        )
    }

    public static var assetRenderFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        objectFieldRule(
            ruleID: "lottie.asset.render-field",
            description: "Asset render fields are modeled or reported before rendering",
            phase: .semantic,
            fields: [
                "e": "Embedded image asset flags change image resolution.",
                "p": "Image asset payloads change rendered pixels.",
                "t": "Image asset sequence metadata changes rendered pixels.",
                "u": "Image asset base paths change rendered pixels.",
            ],
            when: { isAssetPath($0.codingPath) }
        )
    }

    public static var shapeTypesAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.shape.type-modeled",
            description: "Shape item types are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isShapeItemPath(context.codingPath),
                      let typeValue = context.subject.member("ty")
                else {
                    return []
                }
                guard let type = typeValue.stringValue else {
                    return [
                        ValidationError(
                            ruleID: "lottie.shape.type-modeled",
                            reason: "Shape item type field `ty` must be a string.",
                            at: context.codingPath.appending(.key("ty")),
                            range: typeValue.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }
                let supported = Set(["el", "fl", "gr", "rc", "sh", "sr", "st", "tm", "tr"])
                guard !supported.contains(type) else { return [] }
                return [
                    ValidationError(
                        ruleID: "lottie.shape.type-modeled",
                        reason: "Shape item type `\(type)` is not modeled by the validated importer.",
                        at: context.codingPath.appending(.key("ty")),
                        range: typeValue.range,
                        phase: .semantic,
                        classification: .gap
                    ),
                ]
            }
        )
    }

    public static var shapeGeometryFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.shape.geometry-field",
            description: "Shape geometry fields are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isShapeItemPath(context.codingPath),
                      let type = context.subject.member("ty")?.stringValue,
                      ["el", "rc", "sh", "sr"].contains(type)
                else {
                    return []
                }
                var errors: [ValidationError] = []
                if let direction = context.subject.member("d") {
                    if let value = integralNumber(direction) {
                        if ![1, 2, 3].contains(value) {
                            errors.append(ValidationError(
                                ruleID: "lottie.shape.geometry-field",
                                reason: "Shape direction `d` must be 1, 2, or 3 before rendering.",
                                at: context.codingPath.appending(.key("d")),
                                range: direction.range,
                                phase: .semantic,
                                classification: .gap
                            ))
                        }
                    } else {
                        errors.append(ValidationError(
                            ruleID: "lottie.shape.geometry-field",
                            reason: "Shape direction field `d` must be an integer.",
                            at: context.codingPath.appending(.key("d")),
                            range: direction.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                    }
                }
                if type == "sr", let starType = context.subject.member("sy") {
                    if let value = integralNumber(starType) {
                        if value != 1, value != 2 {
                            errors.append(ValidationError(
                                ruleID: "lottie.shape.geometry-field",
                                reason: "Polystar `sy` must be 1 for star or 2 for polygon before rendering.",
                                at: context.codingPath.appending(.key("sy")),
                                range: starType.range,
                                phase: .semantic,
                                classification: .gap
                            ))
                        }
                    } else {
                        errors.append(integerFieldError(
                            ruleID: "lottie.shape.geometry-field",
                            field: "Polystar `sy`",
                            key: "sy",
                            value: starType,
                            path: context.codingPath
                        ))
                    }
                }
                return errors
            }
        )
    }

    public static var shapeStyleFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.shape.style-field",
            description: "Shape style fields are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isShapeItemPath(context.codingPath),
                      let type = context.subject.member("ty")?.stringValue
                else {
                    return []
                }
                var errors: [ValidationError] = []
                if ["el", "fl", "gr", "rc", "sh", "sr", "st"].contains(type),
                   let blendMode = context.subject.member("bm")
                {
                    if let mode = integralNumber(blendMode) {
                        if mode != 0 {
                            errors.append(ValidationError(
                                ruleID: "lottie.shape.style-field",
                                reason: "Shape blend mode `bm` changes compositing and is not lowered by the validated importer.",
                                at: context.codingPath.appending(.key("bm")),
                                range: blendMode.range,
                                phase: .semantic,
                                classification: .gap
                            ))
                        }
                    } else {
                        errors.append(integerFieldError(
                            ruleID: "lottie.shape.style-field",
                            field: "Shape blend mode `bm`",
                            key: "bm",
                            value: blendMode,
                            path: context.codingPath
                        ))
                    }
                }
                if type == "fl" {
                    appendAnimatedFieldErrors(["c", "o"], subject: context.subject, path: context.codingPath, label: "fill", ruleID: "lottie.shape.style-field", errors: &errors)
                }
                if type == "st" {
                    appendAnimatedFieldErrors(
                        ["c", "o", "w"],
                        subject: context.subject,
                        path: context.codingPath,
                        label: "stroke",
                        ruleID: "lottie.shape.style-field",
                        errors: &errors
                    )
                    appendUnsupportedStrokeStyleErrors(subject: context.subject, path: context.codingPath, errors: &errors)
                }
                return errors
            }
        )
    }

    public static var shapeModifierFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.shape.modifier-field",
            description: "Shape modifier fields are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isShapeItemPath(context.codingPath),
                      context.subject.member("ty")?.stringValue == "tm"
                else {
                    return []
                }
                var errors: [ValidationError] = []
                if let offset = context.subject.member("o"),
                   animatedPropertyIsAnimated(offset) || abs(scalarInitialValue(offset) ?? 0) > 0.0001
                {
                    errors.append(ValidationError(
                        ruleID: "lottie.shape.modifier-field",
                        reason: "Trim path offset `o` is not lowered by the validated importer.",
                        at: context.codingPath.appending(.key("o")),
                        range: offset.range,
                        phase: .semantic,
                        classification: .gap
                    ))
                }
                if let multiple = context.subject.member("m") {
                    if let mode = integralNumber(multiple) {
                        if mode == 2 {
                            errors.append(ValidationError(
                                ruleID: "lottie.shape.modifier-field",
                                reason: "Individual trim mode `m: 2` is approximated by the importer.",
                                at: context.codingPath.appending(.key("m")),
                                range: multiple.range,
                                phase: .semantic,
                                classification: .approximate
                            ))
                        } else if mode != 1 {
                            errors.append(ValidationError(
                                ruleID: "lottie.shape.modifier-field",
                                reason: "Trim path mode `m` must be 1 or 2.",
                                at: context.codingPath.appending(.key("m")),
                                range: multiple.range,
                                phase: .semantic,
                                classification: .gap
                            ))
                        }
                    } else {
                        errors.append(integerFieldError(
                            ruleID: "lottie.shape.modifier-field",
                            field: "Trim path mode `m`",
                            key: "m",
                            value: multiple,
                            path: context.codingPath
                        ))
                    }
                }
                return errors
            }
        )
    }

    public static var shapeTransformFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.shape.transform-field",
            description: "Shape transform fields are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil,
                      isShapeItemPath(context.codingPath),
                      context.subject.member("ty")?.stringValue == "tr"
                else {
                    return []
                }
                var errors: [ValidationError] = []
                appendAnimatedFieldErrors(
                    ["a", "p", "s", "r", "o"],
                    subject: context.subject,
                    path: context.codingPath,
                    label: "shape transform",
                    ruleID: "lottie.shape.transform-field",
                    errors: &errors
                )
                return errors
            }
        )
    }

    public static var strokeStyleFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.shape.stroke-style-field",
            description: "Stroke style fields are modeled or reported before rendering",
            phase: .semantic,
            check: { context in
                guard let dashPattern = context.subject.member("d") else { return [] }
                let dashPath = context.codingPath.appending(.key("d"))
                guard let entries = dashPattern.arrayValues else {
                    return [
                        ValidationError(
                            ruleID: "lottie.shape.stroke-style-field",
                            reason: "Stroke dash pattern `d` must be an array.",
                            at: dashPath,
                            range: dashPattern.range,
                            phase: .semantic,
                            classification: .gap
                        ),
                    ]
                }

                var errors: [ValidationError] = []
                let allowedTypes = Set(["d", "g", "o"])
                for (index, entry) in entries.enumerated() {
                    let entryPath = dashPath.appending(.index(index))
                    guard entry.objectMembers != nil else {
                        errors.append(ValidationError(
                            ruleID: "lottie.shape.stroke-style-field",
                            reason: "Stroke dash entry must be an object.",
                            at: entryPath,
                            range: entry.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                        continue
                    }

                    guard let typeValue = entry.member("n"), let type = typeValue.stringValue else {
                        errors.append(ValidationError(
                            ruleID: "lottie.shape.stroke-style-field",
                            reason: "Stroke dash entry must declare string field `n`.",
                            at: entryPath.appending(.key("n")),
                            range: entry.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                        continue
                    }
                    if !allowedTypes.contains(type) {
                        errors.append(ValidationError(
                            ruleID: "lottie.shape.stroke-style-field",
                            reason: "Stroke dash entry type `\(type)` must be one of d, g, or o.",
                            at: entryPath.appending(.key("n")),
                            range: typeValue.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                    }
                    if entry.member("v") == nil {
                        errors.append(ValidationError(
                            ruleID: "lottie.shape.stroke-style-field",
                            reason: "Stroke dash entry must declare value field `v`.",
                            at: entryPath.appending(.key("v")),
                            range: entry.range,
                            phase: .semantic,
                            classification: .gap
                        ))
                    }
                }
                return errors
            },
            when: { $0.subject.member("ty")?.stringValue == "st" }
        )
    }
}

private extension BuiltinValidation {
    static func objectFieldRule(
        ruleID: String,
        description: String,
        phase: ValidationPhase,
        fields: [String: String],
        when predicate: @escaping (ValidationContext<LottieSourceDocument, JSONValue>) -> Bool
    ) -> Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: ruleID,
            description: description,
            phase: phase,
            check: { context in
                guard context.subject.objectMembers != nil else { return [] }
                return fields.keys.sorted().compactMap { key in
                    guard let value = context.subject.member(key) else { return nil }
                    return ValidationError(
                        ruleID: ruleID,
                        reason: "\(fields[key] ?? "Field changes rendered pixels") Field `\(key)` must be modeled or reported before rendering.",
                        at: context.codingPath.appending(.key(key)),
                        range: value.range,
                        phase: phase,
                        classification: .gap
                    )
                }
            },
            when: predicate
        )
    }

    static func isLayerPath(_ path: JSONPath) -> Bool {
        guard case .index = path.components.last else { return false }
        let parent = Array(path.components.dropLast())
        guard parent.last == .key("layers") else { return false }
        if parent.count == 1 { return true }
        return parent.count >= 3 && parent[parent.count - 3] == .key("assets")
    }

    static func isLayerTransformPath(_ path: JSONPath) -> Bool {
        guard path.components.last == .key("ks") else { return false }
        return isLayerPath(JSONPath(Array(path.components.dropLast())))
    }

    static func isShapeTransformPath(_: JSONPath, subject: JSONValue) -> Bool {
        subject.member("ty")?.stringValue == "tr"
    }

    static func isAssetPath(_ path: JSONPath) -> Bool {
        guard case .index = path.components.last else { return false }
        let parent = Array(path.components.dropLast())
        return parent == [.key("assets")]
    }

    static func isMaskPath(_ path: JSONPath) -> Bool {
        guard case .index = path.components.last else { return false }
        let masksPath = JSONPath(Array(path.components.dropLast()))
        guard masksPath.components.last == .key("masksProperties") else { return false }
        let layerPath = JSONPath(Array(masksPath.components.dropLast()))
        return isLayerPath(layerPath)
    }

    static func isShapeItemPath(_ path: JSONPath) -> Bool {
        guard case .index = path.components.last else { return false }
        let parent = Array(path.components.dropLast())
        guard parent.last == .key("shapes") || parent.last == .key("it") else { return false }
        return parent.contains(.key("layers")) || parent.contains(.key("assets"))
    }

    static func animatedPropertyIsAnimated(_ value: JSONValue?) -> Bool {
        value?.member("a")?.numberValue == 1
    }

    static func integralNumber(_ value: JSONValue) -> Int? {
        guard let number = value.numberValue,
              number.rounded(.towardZero) == number,
              number >= Double(Int.min),
              number <= Double(Int.max)
        else {
            return nil
        }
        return Int(number)
    }

    static func scalarInitialValue(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        if let number = value.numberValue { return number }
        guard let key = value.member("k") else { return nil }
        if let number = key.numberValue { return number }
        return key.arrayValues?.first?.numberValue
    }

    static func appendAnimatedFieldErrors(
        _ fields: [String],
        subject: JSONValue,
        path: JSONPath,
        label: String,
        ruleID: String,
        errors: inout [ValidationError]
    ) {
        for key in fields where animatedPropertyIsAnimated(subject.member(key)) {
            let value = subject.member(key)
            errors.append(ValidationError(
                ruleID: ruleID,
                reason: "Animated \(label) field `\(key)` is not lowered by the validated importer.",
                at: path.appending(.key(key)),
                range: value?.range,
                phase: .semantic,
                classification: .gap
            ))
        }
    }

    static func appendUnsupportedStrokeStyleErrors(subject: JSONValue, path: JSONPath, errors: inout [ValidationError]) {
        if let lineCap = subject.member("lc") {
            if let value = integralNumber(lineCap) {
                if value != 1 {
                    errors.append(unsupportedStrokeStyleError("Stroke line cap `lc`", key: "lc", value: lineCap, path: path))
                }
            } else {
                errors.append(integerFieldError(ruleID: "lottie.shape.style-field", field: "Stroke line cap `lc`", key: "lc", value: lineCap, path: path))
            }
        }
        if let lineJoin = subject.member("lj") {
            if let value = integralNumber(lineJoin) {
                if value != 1 {
                    errors.append(unsupportedStrokeStyleError("Stroke line join `lj`", key: "lj", value: lineJoin, path: path))
                }
            } else {
                errors.append(integerFieldError(ruleID: "lottie.shape.style-field", field: "Stroke line join `lj`", key: "lj", value: lineJoin, path: path))
            }
        }
        if let miterLimit = subject.member("ml") {
            if let value = miterLimit.numberValue {
                if abs(value - 10) > 0.0001 {
                    errors.append(unsupportedStrokeStyleError("Stroke miter limit `ml`", key: "ml", value: miterLimit, path: path))
                }
            } else {
                errors.append(numberFieldError(ruleID: "lottie.shape.style-field", field: "Stroke miter limit `ml`", key: "ml", value: miterLimit, path: path))
            }
        }
        if let secondaryMiterLimit = subject.member("ml2") {
            errors.append(unsupportedStrokeStyleError("Secondary stroke miter limit `ml2`", key: "ml2", value: secondaryMiterLimit, path: path))
        }
        if let dashPattern = subject.member("d"), dashPattern.arrayValues?.isEmpty == false {
            errors.append(unsupportedStrokeStyleError("Stroke dash pattern `d`", key: "d", value: dashPattern, path: path))
        }
    }

    static func integerFieldError(ruleID: String, field: String, key: String, value: JSONValue, path: JSONPath) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "\(field) must be an integer.",
            at: path.appending(.key(key)),
            range: value.range,
            phase: .semantic,
            classification: .gap
        )
    }

    static func numberFieldError(ruleID: String, field: String, key: String, value: JSONValue, path: JSONPath) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "\(field) must be numeric.",
            at: path.appending(.key(key)),
            range: value.range,
            phase: .semantic,
            classification: .gap
        )
    }

    static func unsupportedStrokeStyleError(_ feature: String, key: String, value: JSONValue, path: JSONPath) -> ValidationError {
        ValidationError(
            ruleID: "lottie.shape.style-field",
            reason: "\(feature) is not lowered by the validated importer.",
            at: path.appending(.key(key)),
            range: value.range,
            phase: .semantic,
            classification: .gap
        )
    }

    static func layerSiblings(for layerPath: JSONPath, in source: JSONValue) -> [JSONValue] {
        let parentPath = JSONPath(Array(layerPath.components.dropLast()))
        return source.value(at: parentPath)?.arrayValues ?? []
    }

    static func layerOffset(for layerPath: JSONPath) -> Int? {
        guard case let .index(offset) = layerPath.components.last else { return nil }
        return offset
    }

    static func layerIndexTable(for layerPath: JSONPath, in source: JSONValue) -> [Int: JSONValue] {
        var result: [Int: JSONValue] = [:]
        for layer in layerSiblings(for: layerPath, in: source) {
            guard let number = layer.member("ind")?.numberValue else { continue }
            let index = Int(number)
            if result[index] == nil {
                result[index] = layer
            }
        }
        return result
    }

    static func assetIDs(in source: JSONValue) -> Set<String> {
        Set((source.member("assets")?.arrayValues ?? []).compactMap { asset in
            asset.member("id")?.stringValue
        })
    }
}
