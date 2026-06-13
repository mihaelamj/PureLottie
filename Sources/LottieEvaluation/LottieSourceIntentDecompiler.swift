//
//  LottieSourceIntentDecompiler.swift
//  PureLottie
//

import Foundation
import LottieModel

/// Reconstructed source-level intent produced from evaluated RenderIR frames.
///
/// This is a compiler evidence document, not a renderer output. It records the
/// source facts that survived evaluation and the explicit losses that prevent a
/// source -> compile -> decompile -> source-intent round trip from being exact.
public struct LottieDecompiledSourceIntent: Codable, Sendable, Equatable, Validatable {
    public var schema: LottieDecompiledSourceIntentSchema
    public var source: LottieDecompiledSourceIntentSource
    public var composition: LottieSourceIntentComposition
    public var frames: [LottieDecompiledSourceIntentFrame]
    public var losses: [LottieDecompiledSourceIntentLoss]
    public var roundTrip: LottieSourceIntentRoundTrip

    public init(
        schema: LottieDecompiledSourceIntentSchema = LottieDecompiledSourceIntentSchema(),
        source: LottieDecompiledSourceIntentSource,
        composition: LottieSourceIntentComposition,
        frames: [LottieDecompiledSourceIntentFrame],
        losses: [LottieDecompiledSourceIntentLoss] = [],
        roundTrip: LottieSourceIntentRoundTrip = .decompiledSourceIntent
    ) {
        self.schema = schema
        self.source = source
        self.composition = composition
        self.frames = frames
        self.losses = losses
        self.roundTrip = roundTrip
    }

    public var allLosses: [LottieDecompiledSourceIntentLoss] {
        losses + frames.flatMap(\.losses)
    }
}

public struct LottieDecompiledSourceIntentSchema: Codable, Sendable, Equatable, Validatable {
    public var name: String
    public var version: Int

    public init(name: String = "purelottie.decompiled-source-intent", version: Int = 1) {
        self.name = name
        self.version = version
    }
}

public struct LottieDecompiledSourceIntentSource: Codable, Sendable, Equatable, Validatable {
    public var identity: String
    public var path: String?
    public var frameCount: Int
    public var compilerPipeline: [String]

    public init(
        identity: String,
        path: String? = nil,
        frameCount: Int,
        compilerPipeline: [String] = ["parse", "validate", "evaluate-render-ir", "decompile-source-intent"]
    ) {
        self.identity = identity
        self.path = path
        self.frameCount = frameCount
        self.compilerPipeline = compilerPipeline
    }
}

public struct LottieDecompiledSourceIntentFrame: Codable, Sendable, Equatable, Validatable {
    public var sourceFrame: Double
    public var localTimeSeconds: Double?
    public var visibleLayers: [LottieSourceIntentLayer]
    public var losses: [LottieDecompiledSourceIntentLoss]

    public init(
        sourceFrame: Double,
        localTimeSeconds: Double?,
        visibleLayers: [LottieSourceIntentLayer],
        losses: [LottieDecompiledSourceIntentLoss] = []
    ) {
        self.sourceFrame = sourceFrame
        self.localTimeSeconds = localTimeSeconds
        self.visibleLayers = visibleLayers
        self.losses = losses
    }
}

public struct LottieDecompiledSourceIntentLoss: Codable, Sendable, Equatable, Validatable {
    public var kind: LottieDecompiledSourceIntentLossKind
    public var reconstructability: LottieDecompiledSourceIntentReconstructability
    public var phase: String
    public var classification: String
    public var modelPath: String
    public var sourcePath: String?
    public var jsonPath: String?
    public var sourceRange: String?
    public var ruleID: String?
    public var reason: String
    public var evidence: String?

    public init(
        kind: LottieDecompiledSourceIntentLossKind,
        reconstructability: LottieDecompiledSourceIntentReconstructability,
        phase: String,
        classification: String,
        modelPath: String,
        sourcePath: String? = nil,
        jsonPath: String? = nil,
        sourceRange: String? = nil,
        ruleID: String? = nil,
        reason: String,
        evidence: String? = nil
    ) {
        self.kind = kind
        self.reconstructability = reconstructability
        self.phase = phase
        self.classification = classification
        self.modelPath = modelPath
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.sourceRange = sourceRange
        self.ruleID = ruleID
        self.reason = reason
        self.evidence = evidence
    }
}

public enum LottieDecompiledSourceIntentLossKind: String, Codable, Sendable, Equatable {
    case diagnostic
    case missingSourceFact
    case approximation
    case unsupported
    case intentionallyDropped
}

public enum LottieDecompiledSourceIntentReconstructability: String, Codable, Sendable, Equatable {
    case exact
    case reconstructedWithLoss
    case notReconstructable
}

public extension LottieSourceIntentRoundTrip {
    static var decompiledSourceIntent: LottieSourceIntentRoundTrip {
        LottieSourceIntentRoundTrip(
            laws: [
                "source facts must retain sourcePath and jsonPath",
                "lossy or unsupported facts must produce path-bearing loss records",
                "frames remain Lottie source-frame numbers until importer conversion",
            ],
            normalForm: "RenderIR evaluated source intent",
            lossyFields: []
        )
    }
}

/// Converts backend-independent RenderIR frames back into source-level intent.
public struct LottieSourceIntentDecompiler: Sendable {
    public init() {}

    public func decompile(
        frames renderFrames: [LottieRenderFrame],
        source: LottieDecompiledSourceIntentSource
    ) -> LottieDecompiledSourceIntent {
        let first = renderFrames.first
        return LottieDecompiledSourceIntent(
            source: LottieDecompiledSourceIntentSource(
                identity: source.identity,
                path: source.path,
                frameCount: renderFrames.count,
                compilerPipeline: source.compilerPipeline
            ),
            composition: composition(from: first),
            frames: renderFrames.enumerated().map(decompiledFrame),
            losses: renderFrames.isEmpty ? [
                LottieDecompiledSourceIntentLoss(
                    kind: .missingSourceFact,
                    reconstructability: .notReconstructable,
                    phase: "decompile",
                    classification: "reported",
                    modelPath: "$.frames",
                    sourcePath: "root",
                    jsonPath: "$",
                    reason: "No RenderIR frames were supplied to the source-intent decompiler."
                ),
            ] : []
        )
    }

    public func decompile(
        frame renderFrame: LottieRenderFrame,
        source: LottieDecompiledSourceIntentSource
    ) -> LottieDecompiledSourceIntent {
        decompile(frames: [renderFrame], source: source)
    }

    private func composition(from frame: LottieRenderFrame?) -> LottieSourceIntentComposition {
        LottieSourceIntentComposition(
            name: nil,
            version: nil,
            width: frame?.width ?? 0,
            height: frame?.height ?? 0,
            inPoint: frame?.layerGraph.frameWindow.inPoint ?? 0,
            outPoint: frame?.layerGraph.frameWindow.outPoint ?? 0,
            frameRate: frame?.frameRate ?? 0,
            provenance: LottieSourceIntentProvenance(
                sourcePath: "root",
                jsonPath: "$",
                consumedFields: ["$.w", "$.h", "$.ip", "$.op", "$.fr", "$.layers"],
                preservedFields: ["$.w", "$.h", "$.ip", "$.op", "$.fr"]
            )
        )
    }

    private func decompiledFrame(offset: Int, frame: LottieRenderFrame) -> LottieDecompiledSourceIntentFrame {
        LottieDecompiledSourceIntentFrame(
            sourceFrame: frame.sourceFrame,
            localTimeSeconds: frame.frameRate > 0 ? frame.sourceFrame / frame.frameRate : nil,
            visibleLayers: frame.nodes.enumerated().map { nodeOffset, node in
                decompiledLayer(node, renderOrder: nodeOffset)
            },
            losses: frameLosses(frame, frameOffset: offset)
        )
    }

    private func frameLosses(
        _ frame: LottieRenderFrame,
        frameOffset: Int
    ) -> [LottieDecompiledSourceIntentLoss] {
        var losses = frame.diagnostics.enumerated().map { diagnosticOffset, diagnostic in
            loss(
                from: diagnostic,
                modelPath: "$.frames[\(frameOffset)].losses[\(diagnosticOffset)]"
            )
        }
        for nodeOffset in frame.nodes.indices {
            if let loss = nodeLoss(frame.nodes[nodeOffset], modelPath: "$.frames[\(frameOffset)].visibleLayers[\(nodeOffset)]") {
                losses.append(loss)
            }
        }
        return losses
    }

    private func decompiledLayer(_ node: LottieRenderNode, renderOrder: Int) -> LottieSourceIntentLayer {
        LottieSourceIntentLayer(
            id: node.id.description,
            name: node.layerName,
            index: node.layerIndex,
            type: layerType(from: node.kind),
            renderOrder: renderOrder,
            localFrame: node.localFrame,
            opacity: node.opacity,
            transform: transform(from: node.transform.local, source: node.source),
            geometry: geometry(in: node),
            styles: styles(in: node),
            masks: node.masks.map(mask),
            matte: node.matte.map { matte($0, source: node.source) },
            diagnostics: nodeDiagnostics(node),
            provenance: provenance(
                from: node.source,
                consumedFields: [node.source.jsonPath.description],
                preservedFields: [node.source.jsonPath.description]
            )
        )
    }

    private func layerType(from kind: LottieRenderNode.Kind) -> LottieSourceIntentLayerType {
        switch kind {
        case .precompositionBoundary:
            .precomposition
        case .solid:
            .solid
        case .imagePlaceholder:
            .image
        case .null:
            .null
        case .shape:
            .shape
        case .textPlaceholder:
            .text
        case .unsupportedLayer:
            .unsupported
        }
    }

    private func transform(
        from state: LottieTransformState,
        source: LottieRenderSource
    ) -> LottieSourceIntentTransform {
        LottieSourceIntentTransform(
            anchor: state.anchor,
            position: state.position,
            scale: state.scale,
            rotationZDegrees: state.rotationZDegrees,
            is3DLayer: state.is3DLayer,
            matrix: LottieSourceIntentMatrix(unchecked: state.matrix.values),
            matrixConvention: .lottieWebRowVector4x4,
            provenance: LottieSourceIntentProvenance(
                sourcePath: "\(source.sourcePath) > transform",
                jsonPath: source.jsonPath.appending(.key("ks")).description,
                consumedFields: state.trace.components.map(\.propertyPath),
                preservedFields: [source.jsonPath.appending(.key("ks")).description]
            )
        )
    }

    private func geometry(in node: LottieRenderNode) -> [LottieSourceIntentGeometry] {
        guard case let .shape(shape) = node.kind else { return [] }
        return shape.draws.enumerated().flatMap { drawOffset, draw in
            draw.fragments.enumerated().map { fragmentOffset, fragment in
                geometry(
                    from: fragment,
                    id: "\(node.id.description).geometry[\(drawOffset)].fragment[\(fragmentOffset)]"
                )
            }
        }
    }

    private func geometry(
        from fragment: LottieRenderGeometryFragment,
        id: String
    ) -> LottieSourceIntentGeometry {
        let (kind, primitive, parameters, path) = geometryPayload(from: fragment.geometry)
        return LottieSourceIntentGeometry(
            id: id,
            kind: kind,
            primitive: primitive,
            parameters: parameters,
            path: path,
            transformStack: fragment.transformStack.map(shapeTransform),
            modifiers: fragment.modifiers.map(modifier),
            provenance: provenance(
                from: fragment.source,
                consumedFields: [fragment.source.jsonPath.description],
                preservedFields: [fragment.source.jsonPath.description]
            )
        )
    }

    private func geometryPayload(
        from geometry: LottieRenderGeometry
    ) -> (
        LottieSourceIntentGeometryKind,
        String,
        [String: [Double]],
        LottieSourceIntentPath?
    ) {
        switch geometry {
        case let .path(bezier):
            (.path, "sh", [:], path(from: bezier))
        case let .rectangle(center, size, roundness):
            (
                .rectangle,
                "rc",
                ["center": center, "size": size, "roundness": [roundness]],
                nil
            )
        case let .ellipse(center, size):
            (.ellipse, "el", ["center": center, "size": size], nil)
        }
    }

    private func styles(in node: LottieRenderNode) -> [LottieSourceIntentStyle] {
        guard case let .shape(shape) = node.kind else { return [] }
        return shape.draws.enumerated().map { offset, draw in
            style(from: draw.style, id: "\(node.id.description).style[\(offset)]", source: draw.source)
        }
    }

    private func style(
        from style: LottieRenderShapeStyle,
        id: String,
        source: LottieRenderSource
    ) -> LottieSourceIntentStyle {
        switch style {
        case let .fill(fill):
            LottieSourceIntentStyle(
                id: id,
                kind: .fill,
                color: fill.color,
                opacity: fill.opacity,
                blendMode: fill.blendMode,
                provenance: provenance(from: source)
            )
        case let .stroke(stroke):
            LottieSourceIntentStyle(
                id: id,
                kind: .stroke,
                color: stroke.color,
                opacity: stroke.opacity,
                width: stroke.width,
                lineCap: stroke.lineCap,
                lineJoin: stroke.lineJoin,
                miterLimit: stroke.miterLimit,
                dashPattern: stroke.dashPattern.map { dash in
                    LottieSourceIntentStrokeDash(
                        name: dash.name,
                        type: dash.type,
                        value: dash.value,
                        isAnimated: dash.isAnimated
                    )
                },
                blendMode: stroke.blendMode,
                provenance: provenance(from: source)
            )
        }
    }

    private func shapeTransform(_ transform: LottieRenderShapeTransform) -> LottieSourceIntentTransform {
        LottieSourceIntentTransform(
            anchor: transform.anchor,
            position: transform.position,
            scale: transform.scale,
            rotationZDegrees: transform.rotationDegrees,
            is3DLayer: false,
            matrix: LottieSourceIntentMatrix(unchecked: shapeTransformMatrix(transform).values),
            matrixConvention: .lottieWebRowVector4x4,
            provenance: provenance(from: transform.source)
        )
    }

    private func shapeTransformMatrix(_ transform: LottieRenderShapeTransform) -> LottieTransformMatrix {
        let anchor = LottieTransformMatrix.translation(
            x: -transform.anchor.component(0, default: 0),
            y: -transform.anchor.component(1, default: 0),
            z: transform.anchor.component(2, default: 0)
        )
        let scale = LottieTransformMatrix.scale(
            x: transform.scale.component(0, default: 100) / 100,
            y: transform.scale.component(1, default: 100) / 100,
            z: transform.scale.component(2, default: 100) / 100
        )
        let rotation = LottieTransformMatrix.rotationZ(-transform.rotationDegrees * .pi / 180)
        let position = LottieTransformMatrix.translation(
            x: transform.position.component(0, default: 0),
            y: transform.position.component(1, default: 0),
            z: -transform.position.component(2, default: 0)
        )
        return anchor.concatenating(scale).concatenating(rotation).concatenating(position)
    }

    private func modifier(_ modifier: LottieRenderShapeModifier) -> LottieSourceIntentModifier {
        switch modifier {
        case let .trim(trim):
            LottieSourceIntentModifier(
                kind: .trim,
                trim: LottieSourceIntentTrim(
                    start: trim.start,
                    end: trim.end,
                    offset: trim.offset,
                    multiple: trim.multiple,
                    isAnimated: trim.isAnimated
                ),
                provenance: provenance(from: trim.source)
            )
        }
    }

    private func mask(_ mask: LottieRenderMask) -> LottieSourceIntentMask {
        LottieSourceIntentMask(
            name: mask.name,
            mode: mask.mode,
            inverted: mask.isInverted,
            opacity: mask.opacity,
            path: mask.path.map(path),
            provenance: provenance(from: mask.source)
        )
    }

    private func matte(
        _ matte: LottieRenderMatte,
        source: LottieRenderSource
    ) -> LottieSourceIntentMatte {
        LottieSourceIntentMatte(
            mode: matte.mode,
            sourceLayerIndex: matte.sourceLayerIndex,
            sourcePath: matte.sourcePath,
            explicitSource: matte.isExplicitSource,
            provenance: LottieSourceIntentProvenance(
                sourcePath: "\(source.sourcePath) > matte",
                jsonPath: source.jsonPath.appending(.key("tt")).description,
                consumedFields: [
                    source.jsonPath.appending(.key("tt")).description,
                    source.jsonPath.appending(.key("tp")).description,
                ],
                preservedFields: [source.jsonPath.appending(.key("tt")).description]
            )
        )
    }

    private func path(from bezier: LottieBezier) -> LottieSourceIntentPath {
        LottieSourceIntentPath(
            closed: bezier.isClosed,
            vertices: bezier.vertices,
            inTangents: bezier.inTangents,
            outTangents: bezier.outTangents
        )
    }

    private func nodeDiagnostics(_ node: LottieRenderNode) -> [LottieSourceIntentDiagnostic] {
        if case let .unsupportedLayer(rawType) = node.kind {
            return [
                LottieSourceIntentDiagnostic(
                    ruleID: "lottie.decompile.layer.unsupported-type",
                    severity: .warning,
                    phase: .semantic,
                    classification: .reported,
                    reason: "Unsupported Lottie layer type \(rawType) was preserved as an unsupported source-intent layer.",
                    evidence: node.explanation,
                    provenance: LottieSourceIntentProvenance(
                        sourcePath: node.source.sourcePath,
                        jsonPath: node.source.jsonPath.appending(.key("ty")).description,
                        unrepresentedFields: [node.source.jsonPath.appending(.key("ty")).description]
                    )
                ),
            ]
        }
        return []
    }

    private func nodeLoss(
        _ node: LottieRenderNode,
        modelPath: String
    ) -> LottieDecompiledSourceIntentLoss? {
        guard case let .unsupportedLayer(rawType) = node.kind else { return nil }
        return LottieDecompiledSourceIntentLoss(
            kind: .unsupported,
            reconstructability: .notReconstructable,
            phase: "decompile",
            classification: "gap",
            modelPath: modelPath,
            sourcePath: node.source.sourcePath,
            jsonPath: node.source.jsonPath.appending(.key("ty")).description,
            ruleID: "lottie.decompile.layer.unsupported-type",
            reason: "Unsupported Lottie layer type \(rawType) was preserved as an unsupported source-intent layer.",
            evidence: node.explanation
        )
    }

    private func loss(
        from diagnostic: ValidationError,
        modelPath: String
    ) -> LottieDecompiledSourceIntentLoss {
        LottieDecompiledSourceIntentLoss(
            kind: lossKind(from: diagnostic.classification),
            reconstructability: reconstructability(from: diagnostic.classification),
            phase: diagnostic.phase.rawValue,
            classification: diagnostic.classification.rawValue,
            modelPath: modelPath,
            sourcePath: diagnostic.evidence ?? diagnostic.codingPath.description,
            jsonPath: diagnostic.codingPath.description,
            sourceRange: diagnostic.range?.description,
            ruleID: diagnostic.ruleID,
            reason: diagnostic.reason,
            evidence: diagnostic.evidence
        )
    }

    private func lossKind(from classification: FeatureClassification) -> LottieDecompiledSourceIntentLossKind {
        switch classification {
        case .exact, .metadata:
            .diagnostic
        case .approximate:
            .approximation
        case .reported:
            .diagnostic
        case .gap:
            .unsupported
        }
    }

    private func reconstructability(from classification: FeatureClassification) -> LottieDecompiledSourceIntentReconstructability {
        switch classification {
        case .exact, .metadata:
            .exact
        case .approximate:
            .reconstructedWithLoss
        case .reported, .gap:
            .notReconstructable
        }
    }

    private func provenance(
        from source: LottieRenderSource,
        consumedFields: [String]? = nil,
        preservedFields: [String]? = nil
    ) -> LottieSourceIntentProvenance {
        LottieSourceIntentProvenance(
            sourcePath: source.sourcePath,
            jsonPath: source.jsonPath.description,
            sourceRange: source.sourceRange?.description,
            consumedFields: consumedFields ?? [source.jsonPath.description],
            preservedFields: preservedFields ?? [source.jsonPath.description]
        )
    }
}

public final class LottieDecompiledSourceIntentValidator {
    private var defaultValidations: [LottieDecompiledSourceIntentAnyValidation]
    private var customValidations: [LottieDecompiledSourceIntentAnyValidation]

    public init() {
        defaultValidations = LottieDecompiledSourceIntentBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [LottieDecompiledSourceIntentAnyValidation],
        customValidations: [LottieDecompiledSourceIntentAnyValidation]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieDecompiledSourceIntentValidator {
        LottieDecompiledSourceIntentValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieDecompiledSourceIntent, some Validatable>) -> Self {
        customValidations.append(LottieDecompiledSourceIntentAnyValidation(validation))
        return self
    }

    @discardableResult
    public func validating(
        _ validation: KeyPath<LottieDecompiledSourceIntentBuiltinValidation.Type, Validation<LottieDecompiledSourceIntent, some Validatable>>
    ) -> Self {
        validating(LottieDecompiledSourceIntentBuiltinValidation.self[keyPath: validation])
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    public func validate(_ intent: LottieDecompiledSourceIntent) throws {
        let errors = collectErrors(in: intent)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    public func collectErrors(in intent: LottieDecompiledSourceIntent) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(intent, at: JSONPath(), in: intent, errors: &errors)
        visit(intent.schema, at: JSONPath([.key("schema")]), in: intent, errors: &errors)
        visit(intent.source, at: JSONPath([.key("source")]), in: intent, errors: &errors)
        visit(intent.composition, at: JSONPath([.key("composition")]), in: intent, errors: &errors)
        for frameIndex in intent.frames.indices {
            let framePath = JSONPath([.key("frames"), .index(frameIndex)])
            let frame = intent.frames[frameIndex]
            visit(frame, at: framePath, in: intent, errors: &errors)
            for layerIndex in frame.visibleLayers.indices {
                visit(
                    frame.visibleLayers[layerIndex],
                    at: framePath.appending(.key("visibleLayers")).appending(.index(layerIndex)),
                    in: intent,
                    errors: &errors
                )
            }
            for lossIndex in frame.losses.indices {
                visit(
                    frame.losses[lossIndex],
                    at: framePath.appending(.key("losses")).appending(.index(lossIndex)),
                    in: intent,
                    errors: &errors
                )
            }
        }
        for lossIndex in intent.losses.indices {
            visit(intent.losses[lossIndex], at: JSONPath([.key("losses"), .index(lossIndex)]), in: intent, errors: &errors)
        }
        return errors
    }

    private var activeValidations: [LottieDecompiledSourceIntentAnyValidation] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in intent: LottieDecompiledSourceIntent,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: intent))
        }
    }
}

public extension LottieDecompiledSourceIntent {
    @discardableResult
    func validate(
        using validator: LottieDecompiledSourceIntentValidator = LottieDecompiledSourceIntentValidator()
    ) throws -> Self {
        try validator.validate(self)
        return self
    }

    static func decodeValidated(
        from data: Data,
        using validator: LottieDecompiledSourceIntentValidator = LottieDecompiledSourceIntentValidator()
    ) throws -> LottieDecompiledSourceIntent {
        do {
            return try JSONDecoder().decode(LottieDecompiledSourceIntent.self, from: data)
                .validate(using: validator)
        } catch let errors as ValidationErrorCollection {
            throw errors
        } catch let error as DecodingError {
            throw ValidationErrorCollection([validationError(from: error)])
        }
    }

    private static func validationError(from error: DecodingError) -> ValidationError {
        switch error {
        case let .keyNotFound(key, context):
            return ValidationError(
                ruleID: "lottie.decompile.decode.key-not-found",
                reason: "Failed to satisfy: Decompiled source intent decodes as the typed schema",
                at: jsonPath(from: context.codingPath).appending(codingComponent(from: key)),
                phase: .parse,
                classification: .gap,
                evidence: context.debugDescription
            )
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            return decodingError(context: context)
        @unknown default:
            return ValidationError(
                ruleID: "lottie.decompile.decode.unknown",
                reason: "Failed to satisfy: Decompiled source intent decodes as the typed schema",
                at: JSONPath(),
                phase: .parse,
                classification: .gap
            )
        }
    }

    private static func decodingError(context: DecodingError.Context) -> ValidationError {
        ValidationError(
            ruleID: "lottie.decompile.decode",
            reason: "Failed to satisfy: Decompiled source intent decodes as the typed schema",
            at: jsonPath(from: context.codingPath),
            phase: .parse,
            classification: .gap,
            evidence: context.debugDescription
        )
    }

    private static func jsonPath(from codingPath: [any CodingKey]) -> JSONPath {
        JSONPath(codingPath.map(codingComponent(from:)))
    }

    private static func codingComponent(from key: any CodingKey) -> JSONPath.Component {
        if let index = key.intValue {
            return .index(index)
        }
        return .key(key.stringValue)
    }
}

public enum LottieDecompiledSourceIntentBuiltinValidation {
    fileprivate static var defaultValidations: [LottieDecompiledSourceIntentAnyValidation] {
        [
            LottieDecompiledSourceIntentAnyValidation(schemaNameAndVersionAreSupported),
            LottieDecompiledSourceIntentAnyValidation(sourceIdentityIsPresent),
            LottieDecompiledSourceIntentAnyValidation(compositionFactsAreFinite),
            LottieDecompiledSourceIntentAnyValidation(framesArePresentAndUnique),
            LottieDecompiledSourceIntentAnyValidation(frameFactsAreFinite),
            LottieDecompiledSourceIntentAnyValidation(layerFactsAreFinite),
            LottieDecompiledSourceIntentAnyValidation(provenanceIsSourceAddressableOrLost),
            LottieDecompiledSourceIntentAnyValidation(lossRecordsArePathBearing),
        ]
    }

    public static var schemaNameAndVersionAreSupported:
        Validation<LottieDecompiledSourceIntent, LottieDecompiledSourceIntentSchema>
    {
        Validation(
            ruleID: "lottie.decompile.schema.supported",
            description: "Decompiled source-intent schema name is purelottie.decompiled-source-intent and version is 1",
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.name != "purelottie.decompiled-source-intent" {
                errors.append(error(
                    ruleID: "lottie.decompile.schema.name",
                    description: "Decompiled source-intent schema name is purelottie.decompiled-source-intent and version is 1",
                    path: context.codingPath.appending(.key("name"))
                ))
            }
            if context.subject.version != 1 {
                errors.append(error(
                    ruleID: "lottie.decompile.schema.version",
                    description: "Decompiled source-intent schema name is purelottie.decompiled-source-intent and version is 1",
                    path: context.codingPath.appending(.key("version"))
                ))
            }
            return errors
        }
    }

    public static var sourceIdentityIsPresent:
        Validation<LottieDecompiledSourceIntent, LottieDecompiledSourceIntentSource>
    {
        Validation(
            ruleID: "lottie.decompile.source.identity",
            description: "Decompiled source-intent source identity and compiler pipeline are present"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error(
                    ruleID: "lottie.decompile.source.identity.present",
                    description: "Decompiled source-intent source identity and compiler pipeline are present",
                    path: context.codingPath.appending(.key("identity"))
                ))
            }
            if context.subject.frameCount < 0 {
                errors.append(error(
                    ruleID: "lottie.decompile.source.frame-count",
                    description: "Decompiled source-intent source identity and compiler pipeline are present",
                    path: context.codingPath.appending(.key("frameCount"))
                ))
            }
            if context.subject.compilerPipeline.isEmpty {
                errors.append(error(
                    ruleID: "lottie.decompile.source.pipeline",
                    description: "Decompiled source-intent source identity and compiler pipeline are present",
                    path: context.codingPath.appending(.key("compilerPipeline"))
                ))
            }
            return errors
        }
    }

    public static var compositionFactsAreFinite:
        Validation<LottieDecompiledSourceIntent, LottieSourceIntentComposition>
    {
        Validation(
            ruleID: "lottie.decompile.composition.finite",
            description: "Decompiled composition dimensions and timing facts are finite and positive where required"
        ) { context in
            var errors = numericErrors(
                [
                    ("width", context.subject.width),
                    ("height", context.subject.height),
                    ("inPoint", context.subject.inPoint),
                    ("outPoint", context.subject.outPoint),
                    ("frameRate", context.subject.frameRate),
                ],
                at: context.codingPath,
                ruleID: "lottie.decompile.composition.number",
                description: "Decompiled composition dimensions and timing facts are finite and positive where required"
            ) { $0.isFinite }
            if context.subject.width <= 0 {
                errors.append(error(
                    ruleID: "lottie.decompile.composition.width",
                    description: "Decompiled composition dimensions and timing facts are finite and positive where required",
                    path: context.codingPath.appending(.key("width"))
                ))
            }
            if context.subject.height <= 0 {
                errors.append(error(
                    ruleID: "lottie.decompile.composition.height",
                    description: "Decompiled composition dimensions and timing facts are finite and positive where required",
                    path: context.codingPath.appending(.key("height"))
                ))
            }
            if context.subject.frameRate <= 0 {
                errors.append(error(
                    ruleID: "lottie.decompile.composition.frame-rate",
                    description: "Decompiled composition dimensions and timing facts are finite and positive where required",
                    path: context.codingPath.appending(.key("frameRate"))
                ))
            }
            if context.subject.inPoint > context.subject.outPoint {
                errors.append(error(
                    ruleID: "lottie.decompile.composition.frame-window",
                    description: "Decompiled composition dimensions and timing facts are finite and positive where required",
                    path: context.codingPath.appending(.key("outPoint"))
                ))
            }
            return errors
        }
    }

    public static var framesArePresentAndUnique:
        Validation<LottieDecompiledSourceIntent, LottieDecompiledSourceIntent>
    {
        Validation(
            ruleID: "lottie.decompile.frames.unique",
            description: "Decompiled source intent contains at least one unique source frame"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.frames.isEmpty {
                errors.append(error(
                    ruleID: "lottie.decompile.frames.present",
                    description: "Decompiled source intent contains at least one unique source frame",
                    path: context.codingPath.appending(.key("frames"))
                ))
            }
            var seen: Set<Double> = []
            for frameIndex in context.subject.frames.indices {
                let frame = context.subject.frames[frameIndex].sourceFrame
                if seen.contains(frame) {
                    errors.append(error(
                        ruleID: "lottie.decompile.frames.duplicate",
                        description: "Decompiled source intent contains at least one unique source frame",
                        path: context.codingPath
                            .appending(.key("frames"))
                            .appending(.index(frameIndex))
                            .appending(.key("sourceFrame"))
                    ))
                }
                seen.insert(frame)
            }
            return errors
        }
    }

    public static var frameFactsAreFinite:
        Validation<LottieDecompiledSourceIntent, LottieDecompiledSourceIntentFrame>
    {
        Validation(
            ruleID: "lottie.decompile.frame.finite",
            description: "Decompiled frame records contain finite source-frame and local-time facts"
        ) { context in
            var values = [("sourceFrame", context.subject.sourceFrame)]
            if let localTimeSeconds = context.subject.localTimeSeconds {
                values.append(("localTimeSeconds", localTimeSeconds))
            }
            return numericErrors(
                values,
                at: context.codingPath,
                ruleID: "lottie.decompile.frame.number",
                description: "Decompiled frame records contain finite source-frame and local-time facts"
            ) { $0.isFinite }
        }
    }

    public static var layerFactsAreFinite:
        Validation<LottieDecompiledSourceIntent, LottieSourceIntentLayer>
    {
        Validation(
            ruleID: "lottie.decompile.layer.facts",
            description: "Decompiled layer records contain stable identity finite timing opacity and transform facts"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error(
                    ruleID: "lottie.decompile.layer.id",
                    description: "Decompiled layer records contain stable identity finite timing opacity and transform facts",
                    path: context.codingPath.appending(.key("id"))
                ))
            }
            if context.subject.renderOrder < 0 {
                errors.append(error(
                    ruleID: "lottie.decompile.layer.render-order",
                    description: "Decompiled layer records contain stable identity finite timing opacity and transform facts",
                    path: context.codingPath.appending(.key("renderOrder"))
                ))
            }
            errors.append(contentsOf: numericErrors(
                [
                    ("localFrame", context.subject.localFrame),
                    ("opacity", context.subject.opacity),
                    ("rotationZDegrees", context.subject.transform.rotationZDegrees),
                ],
                at: context.codingPath,
                ruleID: "lottie.decompile.layer.number",
                description: "Decompiled layer records contain stable identity finite timing opacity and transform facts"
            ) { $0.isFinite })
            if !(0 ... 1).contains(context.subject.opacity) {
                errors.append(error(
                    ruleID: "lottie.decompile.layer.opacity",
                    description: "Decompiled layer records contain stable identity finite timing opacity and transform facts",
                    path: context.codingPath.appending(.key("opacity"))
                ))
            }
            errors.append(contentsOf: vectorErrors(
                [
                    ("anchor", context.subject.transform.anchor),
                    ("position", context.subject.transform.position),
                    ("scale", context.subject.transform.scale),
                    ("matrix", context.subject.transform.matrix.values),
                ],
                at: context.codingPath.appending(.key("transform")),
                ruleID: "lottie.decompile.layer.transform",
                description: "Decompiled layer records contain stable identity finite timing opacity and transform facts"
            ))
            if context.subject.transform.matrix.values.count != 16 {
                errors.append(error(
                    ruleID: "lottie.decompile.layer.matrix.count",
                    description: "Decompiled layer records contain stable identity finite timing opacity and transform facts",
                    path: context.codingPath.appending(.key("transform")).appending(.key("matrix"))
                ))
            }
            return errors
        }
    }

    public static var provenanceIsSourceAddressableOrLost:
        Validation<LottieDecompiledSourceIntent, LottieDecompiledSourceIntent>
    {
        Validation(
            ruleID: "lottie.decompile.provenance.addressable-or-lost",
            description: "Every decompiled fact has sourcePath and jsonPath or an explicit loss record at the same model path"
        ) { context in
            var errors: [ValidationError] = []
            let lossPaths = Set(context.subject.allLosses.map(\.modelPath))
            for record in provenanceRecords(in: context.subject) {
                let missingSource = record.provenance.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let missingJSON = record.provenance.jsonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                guard missingSource || missingJSON else { continue }
                guard !lossPaths.contains(record.modelPath) else { continue }
                errors.append(error(
                    ruleID: missingSource ? "lottie.decompile.provenance.source-path" : "lottie.decompile.provenance.json-path",
                    description: "Every decompiled fact has sourcePath and jsonPath or an explicit loss record at the same model path",
                    path: record.path,
                    classification: .gap
                ))
            }
            return errors
        }
    }

    public static var lossRecordsArePathBearing:
        Validation<LottieDecompiledSourceIntent, LottieDecompiledSourceIntentLoss>
    {
        Validation(
            ruleID: "lottie.decompile.loss.path-bearing",
            description: "Loss records contain model path source/json evidence and a reason"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error(
                    ruleID: "lottie.decompile.loss.model-path",
                    description: "Loss records contain model path source/json evidence and a reason",
                    path: context.codingPath.appending(.key("modelPath"))
                ))
            }
            let hasSourceEvidence = context.subject.sourcePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || context.subject.jsonPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            if !hasSourceEvidence {
                errors.append(error(
                    ruleID: "lottie.decompile.loss.source-evidence",
                    description: "Loss records contain model path source/json evidence and a reason",
                    path: context.codingPath,
                    classification: .gap
                ))
            }
            if context.subject.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error(
                    ruleID: "lottie.decompile.loss.reason",
                    description: "Loss records contain model path source/json evidence and a reason",
                    path: context.codingPath.appending(.key("reason"))
                ))
            }
            return errors
        }
    }

    private struct ProvenanceRecord {
        var provenance: LottieSourceIntentProvenance
        var modelPath: String
        var path: JSONPath
    }

    private static func provenanceRecords(in intent: LottieDecompiledSourceIntent) -> [ProvenanceRecord] {
        var records: [ProvenanceRecord] = [
            ProvenanceRecord(
                provenance: intent.composition.provenance,
                modelPath: "$.composition.provenance",
                path: JSONPath([.key("composition"), .key("provenance")])
            ),
        ]

        for frameIndex in intent.frames.indices {
            let frame = intent.frames[frameIndex]
            let framePath = JSONPath([.key("frames"), .index(frameIndex), .key("visibleLayers")])
            for layerIndex in frame.visibleLayers.indices {
                let layer = frame.visibleLayers[layerIndex]
                let layerPath = framePath.appending(.index(layerIndex))
                appendLayerProvenance(layer, at: layerPath, modelPath: "$.frames[\(frameIndex)].visibleLayers[\(layerIndex)]", to: &records)
            }
        }
        return records
    }

    private static func appendLayerProvenance(
        _ layer: LottieSourceIntentLayer,
        at layerPath: JSONPath,
        modelPath: String,
        to records: inout [ProvenanceRecord]
    ) {
        records.append(ProvenanceRecord(
            provenance: layer.provenance,
            modelPath: "\(modelPath).provenance",
            path: layerPath.appending(.key("provenance"))
        ))
        records.append(ProvenanceRecord(
            provenance: layer.transform.provenance,
            modelPath: "\(modelPath).transform.provenance",
            path: layerPath.appending(.key("transform")).appending(.key("provenance"))
        ))
        for geometryIndex in layer.geometry.indices {
            let geometry = layer.geometry[geometryIndex]
            let geometryPath = layerPath.appending(.key("geometry")).appending(.index(geometryIndex))
            let geometryModelPath = "\(modelPath).geometry[\(geometryIndex)]"
            records.append(ProvenanceRecord(
                provenance: geometry.provenance,
                modelPath: "\(geometryModelPath).provenance",
                path: geometryPath.appending(.key("provenance"))
            ))
            for transformIndex in geometry.transformStack.indices {
                records.append(ProvenanceRecord(
                    provenance: geometry.transformStack[transformIndex].provenance,
                    modelPath: "\(geometryModelPath).transformStack[\(transformIndex)].provenance",
                    path: geometryPath
                        .appending(.key("transformStack"))
                        .appending(.index(transformIndex))
                        .appending(.key("provenance"))
                ))
            }
            for modifierIndex in geometry.modifiers.indices {
                records.append(ProvenanceRecord(
                    provenance: geometry.modifiers[modifierIndex].provenance,
                    modelPath: "\(geometryModelPath).modifiers[\(modifierIndex)].provenance",
                    path: geometryPath
                        .appending(.key("modifiers"))
                        .appending(.index(modifierIndex))
                        .appending(.key("provenance"))
                ))
            }
        }
        for styleIndex in layer.styles.indices {
            records.append(ProvenanceRecord(
                provenance: layer.styles[styleIndex].provenance,
                modelPath: "\(modelPath).styles[\(styleIndex)].provenance",
                path: layerPath
                    .appending(.key("styles"))
                    .appending(.index(styleIndex))
                    .appending(.key("provenance"))
            ))
        }
        for maskIndex in layer.masks.indices {
            records.append(ProvenanceRecord(
                provenance: layer.masks[maskIndex].provenance,
                modelPath: "\(modelPath).masks[\(maskIndex)].provenance",
                path: layerPath
                    .appending(.key("masks"))
                    .appending(.index(maskIndex))
                    .appending(.key("provenance"))
            ))
        }
        if let matte = layer.matte {
            records.append(ProvenanceRecord(
                provenance: matte.provenance,
                modelPath: "\(modelPath).matte.provenance",
                path: layerPath.appending(.key("matte")).appending(.key("provenance"))
            ))
        }
        for diagnosticIndex in layer.diagnostics.indices {
            records.append(ProvenanceRecord(
                provenance: layer.diagnostics[diagnosticIndex].provenance,
                modelPath: "\(modelPath).diagnostics[\(diagnosticIndex)].provenance",
                path: layerPath
                    .appending(.key("diagnostics"))
                    .appending(.index(diagnosticIndex))
                    .appending(.key("provenance"))
            ))
        }
    }

    private static func numericErrors(
        _ values: [(String, Double)],
        at path: JSONPath,
        ruleID: String,
        description: String,
        predicate: (Double) -> Bool
    ) -> [ValidationError] {
        values.compactMap { name, value in
            predicate(value)
                ? nil
                : error(
                    ruleID: ruleID,
                    description: description,
                    path: path.appending(.key(name))
                )
        }
    }

    private static func vectorErrors(
        _ values: [(String, [Double])],
        at path: JSONPath,
        ruleID: String,
        description: String
    ) -> [ValidationError] {
        values.flatMap { name, vector in
            vector.indices.compactMap { index in
                vector[index].isFinite
                    ? nil
                    : error(
                        ruleID: ruleID,
                        description: description,
                        path: path.appending(.key(name)).appending(.index(index))
                    )
            }
        }
    }

    private static func error(
        ruleID: String,
        description: String,
        path: JSONPath,
        classification: FeatureClassification = .reported
    ) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "Failed to satisfy: \(description)",
            at: path,
            phase: .semantic,
            classification: classification
        )
    }
}

private struct LottieDecompiledSourceIntentAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, LottieDecompiledSourceIntent) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<LottieDecompiledSourceIntent, Subject>) {
        ruleID = validation.ruleID
        description = validation.description
        applyClosure = { subject, path, document in
            guard let subject = subject as? Subject else { return [] }
            return validation.apply(to: subject, at: path, in: document)
        }
    }

    func apply(
        to subject: any Validatable,
        at path: JSONPath,
        in document: LottieDecompiledSourceIntent
    ) -> [ValidationError] {
        applyClosure(subject, path, document)
    }
}

extension LottieSourceIntentComposition: Validatable {}
extension LottieSourceIntentLayer: Validatable {}
extension LottieSourceIntentProvenance: Validatable {}

private extension LottieSourceIntentMatrix {
    init(unchecked values: [Double]) {
        precondition(values.count == 16, "Decompiler matrices must preserve exactly sixteen values.")
        self.values = values
    }
}

private extension [Double] {
    func component(_ index: Int, default defaultValue: Double) -> Double {
        indices.contains(index) ? self[index] : defaultValue
    }
}
