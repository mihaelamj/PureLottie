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
            AnyValidation(layerParentReferencesResolve),
            AnyValidation(layerAssetReferencesResolve),
            AnyValidation(layerSilentRiskFieldsAreModeledOrReported),
            AnyValidation(layerTimeFieldsAreModeled),
            AnyValidation(transformSilentRiskFieldsAreModeledOrReported),
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

    public static var layerSilentRiskFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        objectFieldRule(
            ruleID: "lottie.layer.silent-risk-field",
            description: "Layer rendering fields are modeled or reported before rendering",
            phase: .semantic,
            fields: [
                "ao": "Auto-orient changes rotation from the position path tangent.",
                "bm": "Blend mode changes layer compositing.",
                "ef": "Effects can change rendered pixels.",
                "t": "Text documents and text animators change rendered pixels.",
                "td": "Track matte target/source edges change compositing.",
                "tp": "Track matte parent index changes compositing.",
                "tt": "Track matte mode changes compositing.",
            ],
            when: { isLayerPath($0.codingPath) }
        )
    }

    public static var layerTimeFieldsAreModeled: Validation<LottieSourceDocument, JSONValue> {
        Validation(
            ruleID: "lottie.layer.time-locality",
            description: "Non-default layer stretch and start time are modeled before rendering",
            phase: .semantic,
            check: { context in
                guard context.subject.objectMembers != nil, isLayerPath(context.codingPath) else { return [] }
                var errors: [ValidationError] = []
                if let stretch = context.subject.member("sr"), stretch.numberValue != nil, stretch.numberValue != 1 {
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
                if let startTime = context.subject.member("st"), startTime.numberValue != nil, startTime.numberValue != 0 {
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
                return errors
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

    public static var strokeStyleFieldsAreModeledOrReported: Validation<LottieSourceDocument, JSONValue> {
        objectFieldRule(
            ruleID: "lottie.shape.stroke-style-field",
            description: "Stroke style fields are modeled or reported before rendering",
            phase: .semantic,
            fields: [
                "bm": "Shape blend mode changes compositing.",
                "d": "Stroke dash pattern changes stroke pixels.",
                "lc": "Line cap changes stroke endpoints.",
                "lj": "Line join changes stroke corners.",
                "ml": "Miter limit changes stroke joins.",
                "ml2": "Secondary miter metadata must be classified before rendering.",
            ],
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

    static func layerSiblings(for layerPath: JSONPath, in source: JSONValue) -> [JSONValue] {
        let parentPath = JSONPath(Array(layerPath.components.dropLast()))
        return source.value(at: parentPath)?.arrayValues ?? []
    }

    static func assetIDs(in source: JSONValue) -> Set<String> {
        Set((source.member("assets")?.arrayValues ?? []).compactMap { asset in
            asset.member("id")?.stringValue
        })
    }
}
