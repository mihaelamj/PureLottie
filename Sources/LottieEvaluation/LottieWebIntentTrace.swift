import Foundation
import LottieModel

public struct LottieWebIntentTrace: Codable, Equatable, Sendable, Validatable {
    public var schema: Schema
    public var source: String
    public var renderer: String
    public var lottieWeb: LottieWeb
    public var width: Double
    public var height: Double
    public var scale: Double
    public var coordinateSemantics: [String]
    public var frames: [Frame]

    public struct Schema: Codable, Equatable, Sendable, Validatable {
        public var name: String
        public var version: Int
    }

    public struct LottieWeb: Codable, Equatable, Sendable, Validatable {
        public var package: String
        public var version: String
    }

    public struct Frame: Codable, Equatable, Sendable, Validatable {
        public var frame: Double
        public var currentFrame: Double
        public var renderedFrame: Double
        public var firstFrame: Double
        public var frameRate: Double
        public var stageBounds: Bounds
        public var svgBounds: Bounds
        public var svgViewBox: String
        public var layerCount: Int
        public var pathCount: Int
        public var maskCount: Int
        public var matteCount: Int
        public var precompositionCount: Int
        public var trimCount: Int
        public var layers: [Layer]
        public var paths: [Path]
        public var masks: [Mask]
        public var mattes: [Matte]
        public var precompositions: [Precomposition]
        public var trims: [Trim]
        public var diagnostics: [Diagnostic]
    }

    public struct Layer: Codable, Equatable, Sendable, Validatable {
        public var index: Int
        public var name: String
        public var type: Int
        public var ind: Int
        public var inPoint: Double
        public var outPoint: Double
        public var startTime: Double
        public var renderedFrame: Double
        public var opacity: Double
        public var matrix: [Double]
        public var layerElementBounds: Bounds?
    }

    public struct Path: Codable, Equatable, Sendable, Validatable {
        public var index: Int
        public var tag: String
        public var id: String?
        public var className: String
        public var visible: Bool
        public var d: String
        public var transform: String?
        public var pathLength: Double
        public var localBBox: Bounds
        public var clientBounds: Bounds
        public var ctm: AffineMatrix
        public var sampledLocalBounds: Bounds
        public var sampledCompositionBounds: Bounds
        public var sampledOutputBounds: Bounds
        public var strokeExpandedCompositionBounds: Bounds
        public var strokeExpandedOutputBounds: Bounds
        public var style: Style
        public var ancestors: [Ancestor]
    }

    public struct Bounds: Codable, Equatable, Sendable, Validatable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double
        public var width: Double
        public var height: Double
    }

    public struct AffineMatrix: Codable, Equatable, Sendable, Validatable {
        public var a: Double
        public var b: Double
        public var c: Double
        public var d: Double
        public var e: Double
        public var f: Double
    }

    public struct Style: Codable, Equatable, Sendable, Validatable {
        public var fill: String
        public var fillOpacity: Double
        public var fillRule: String
        public var opacity: Double
        public var stroke: String
        public var strokeOpacity: Double
        public var strokeWidth: Double
        public var strokeLinecap: String
        public var strokeLinejoin: String
        public var strokeMiterlimit: Double
        public var strokeDasharray: String
        public var strokeDashoffset: String
        public var display: String
        public var visibility: String
    }

    public struct Ancestor: Codable, Equatable, Sendable, Validatable {
        public var tag: String
        public var id: String?
        public var className: String
        public var transform: String?
        public var opacity: String?
        public var style: String?
    }

    public struct Mask: Codable, Equatable, Sendable, Validatable {
        public var renderElementIndex: Int
        public var layerInd: Int
        public var layerName: String
        public var maskIndex: Int
        public var name: String?
        public var mode: String
        public var inverted: Bool
        public var closed: Bool
        public var opacity: Double
        public var expansion: Double
        public var pathD: String
        public var localBBox: Bounds
        public var vertexCount: Int
    }

    public struct Matte: Codable, Equatable, Sendable, Validatable {
        public var targetRenderElementIndex: Int
        public var targetLayerInd: Int
        public var targetLayerName: String
        public var mode: Int
        public var explicitSourceLayerIndex: Int?
        public var sourceRenderElementIndex: Int?
        public var sourceLayerInd: Int?
        public var sourceLayerName: String?
        public var sourceLayerType: Int?
        public var sourceHidden: Bool
        public var sourceResolved: Bool
        public var sourceIsMarker: Bool
    }

    public struct Precomposition: Codable, Equatable, Sendable, Validatable {
        public var renderElementIndex: Int
        public var layerInd: Int
        public var layerName: String
        public var refId: String
        public var startTime: Double
        public var stretch: Double
        public var inPoint: Double
        public var outPoint: Double
        public var renderedFrame: Double
        public var timeRemapped: Bool
        public var timeRemapValue: Double?
        public var childLayerCount: Int
        public var builtChildElementCount: Int
    }

    public struct Trim: Codable, Equatable, Sendable, Validatable {
        public var renderElementIndex: Int
        public var layerInd: Int
        public var layerName: String
        public var trimIndex: Int
        public var startFraction: Double
        public var endFraction: Double
        public var offsetTurns: Double
        public var mode: Int
        public var shapeCount: Int
        public var animated: Bool
    }

    public struct Diagnostic: Codable, Equatable, Sendable, Validatable {
        public var feature: String
        public var reason: String
        public var renderElementIndex: Int?
        public var layerInd: Int?
    }
}

public final class LottieWebIntentTraceValidator {
    private var defaultValidations: [LottieWebIntentAnyValidation]
    private var customValidations: [LottieWebIntentAnyValidation]

    public init() {
        defaultValidations = LottieWebIntentBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [LottieWebIntentAnyValidation],
        customValidations: [LottieWebIntentAnyValidation]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieWebIntentTraceValidator {
        LottieWebIntentTraceValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieWebIntentTrace, some Validatable>) -> Self {
        customValidations.append(LottieWebIntentAnyValidation(validation))
        return self
    }

    @discardableResult
    public func validating(
        _ validation: KeyPath<LottieWebIntentBuiltinValidation.Type, Validation<LottieWebIntentTrace, some Validatable>>
    ) -> Self {
        validating(LottieWebIntentBuiltinValidation.self[keyPath: validation])
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
        _ validation: KeyPath<LottieWebIntentBuiltinValidation.Type, Validation<LottieWebIntentTrace, some Validatable>>
    ) -> Self {
        withoutValidating(LottieWebIntentBuiltinValidation.self[keyPath: validation].description)
    }

    public func validate(_ trace: LottieWebIntentTrace) throws {
        let errors = collectErrors(in: trace)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    public func collectErrors(in trace: LottieWebIntentTrace) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(trace, at: JSONPath(), in: trace, errors: &errors)
        visit(trace.schema, at: JSONPath([.key("schema")]), in: trace, errors: &errors)
        visit(trace.lottieWeb, at: JSONPath([.key("lottieWeb")]), in: trace, errors: &errors)
        for frameIndex in trace.frames.indices {
            let frame = trace.frames[frameIndex]
            let framePath = JSONPath([.key("frames"), .index(frameIndex)])
            visit(frame, at: framePath, in: trace, errors: &errors)
            visit(frame.stageBounds, at: framePath.appending(.key("stageBounds")), in: trace, errors: &errors)
            visit(frame.svgBounds, at: framePath.appending(.key("svgBounds")), in: trace, errors: &errors)
            for layerIndex in frame.layers.indices {
                let layer = frame.layers[layerIndex]
                let layerPath = framePath
                    .appending(.key("layers"))
                    .appending(.index(layerIndex))
                visit(layer, at: layerPath, in: trace, errors: &errors)
                if let bounds = layer.layerElementBounds {
                    visit(bounds, at: layerPath.appending(.key("layerElementBounds")), in: trace, errors: &errors)
                }
            }
            for pathIndex in frame.paths.indices {
                let path = frame.paths[pathIndex]
                let pathPath = framePath
                    .appending(.key("paths"))
                    .appending(.index(pathIndex))
                visit(path, at: pathPath, in: trace, errors: &errors)
                visit(path.localBBox, at: pathPath.appending(.key("localBBox")), in: trace, errors: &errors)
                visit(path.clientBounds, at: pathPath.appending(.key("clientBounds")), in: trace, errors: &errors)
                visit(path.ctm, at: pathPath.appending(.key("ctm")), in: trace, errors: &errors)
                visit(path.sampledLocalBounds, at: pathPath.appending(.key("sampledLocalBounds")), in: trace, errors: &errors)
                visit(
                    path.sampledCompositionBounds,
                    at: pathPath.appending(.key("sampledCompositionBounds")),
                    in: trace,
                    errors: &errors
                )
                visit(path.sampledOutputBounds, at: pathPath.appending(.key("sampledOutputBounds")), in: trace, errors: &errors)
                visit(
                    path.strokeExpandedCompositionBounds,
                    at: pathPath.appending(.key("strokeExpandedCompositionBounds")),
                    in: trace,
                    errors: &errors
                )
                visit(
                    path.strokeExpandedOutputBounds,
                    at: pathPath.appending(.key("strokeExpandedOutputBounds")),
                    in: trace,
                    errors: &errors
                )
                visit(path.style, at: pathPath.appending(.key("style")), in: trace, errors: &errors)
                for ancestorIndex in path.ancestors.indices {
                    visit(
                        path.ancestors[ancestorIndex],
                        at: pathPath
                            .appending(.key("ancestors"))
                            .appending(.index(ancestorIndex)),
                        in: trace,
                        errors: &errors
                    )
                }
            }
            for maskIndex in frame.masks.indices {
                let maskPath = framePath
                    .appending(.key("masks"))
                    .appending(.index(maskIndex))
                visit(frame.masks[maskIndex], at: maskPath, in: trace, errors: &errors)
                visit(frame.masks[maskIndex].localBBox, at: maskPath.appending(.key("localBBox")), in: trace, errors: &errors)
            }
            for matteIndex in frame.mattes.indices {
                visit(
                    frame.mattes[matteIndex],
                    at: framePath
                        .appending(.key("mattes"))
                        .appending(.index(matteIndex)),
                    in: trace,
                    errors: &errors
                )
            }
            for precompositionIndex in frame.precompositions.indices {
                visit(
                    frame.precompositions[precompositionIndex],
                    at: framePath
                        .appending(.key("precompositions"))
                        .appending(.index(precompositionIndex)),
                    in: trace,
                    errors: &errors
                )
            }
            for trimIndex in frame.trims.indices {
                visit(
                    frame.trims[trimIndex],
                    at: framePath
                        .appending(.key("trims"))
                        .appending(.index(trimIndex)),
                    in: trace,
                    errors: &errors
                )
            }
            for diagnosticIndex in frame.diagnostics.indices {
                visit(
                    frame.diagnostics[diagnosticIndex],
                    at: framePath
                        .appending(.key("diagnostics"))
                        .appending(.index(diagnosticIndex)),
                    in: trace,
                    errors: &errors
                )
            }
        }
        return errors
    }

    private var activeValidations: [LottieWebIntentAnyValidation] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in trace: LottieWebIntentTrace,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: trace))
        }
    }
}

public extension LottieWebIntentTrace {
    static func decodeValidated(
        from data: Data,
        using validator: LottieWebIntentTraceValidator = LottieWebIntentTraceValidator()
    ) throws -> LottieWebIntentTrace {
        do {
            return try JSONDecoder().decode(LottieWebIntentTrace.self, from: data)
                .validate(using: validator)
        } catch let errors as ValidationErrorCollection {
            throw errors
        } catch let error as DecodingError {
            throw ValidationErrorCollection([Self.validationError(from: error)])
        }
    }

    @discardableResult
    func validate(using validator: LottieWebIntentTraceValidator = LottieWebIntentTraceValidator()) throws -> Self {
        try validator.validate(self)
        return self
    }

    private static func validationError(from error: DecodingError) -> ValidationError {
        switch error {
        case let .keyNotFound(key, context):
            return ValidationError(
                ruleID: "lottie-web-intent.decode.key-not-found",
                reason: "Failed to satisfy: Lottie-web intent trace decodes as the typed schema",
                at: jsonPath(from: context.codingPath).appending(codingComponent(from: key)),
                phase: .parse,
                classification: .gap,
                evidence: context.debugDescription
            )
        case let .typeMismatch(_, context):
            return decodingError(context: context)
        case let .valueNotFound(_, context):
            return decodingError(context: context)
        case let .dataCorrupted(context):
            return decodingError(context: context)
        @unknown default:
            return ValidationError(
                ruleID: "lottie-web-intent.decode.unknown",
                reason: "Failed to satisfy: Lottie-web intent trace decodes as the typed schema",
                at: JSONPath(),
                phase: .parse,
                classification: .gap
            )
        }
    }

    private static func decodingError(context: DecodingError.Context) -> ValidationError {
        ValidationError(
            ruleID: "lottie-web-intent.decode",
            reason: "Failed to satisfy: Lottie-web intent trace decodes as the typed schema",
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

public enum LottieWebIntentBuiltinValidation {
    fileprivate static var defaultValidations: [LottieWebIntentAnyValidation] {
        [
            LottieWebIntentAnyValidation(schemaNameAndVersionAreSupported),
            LottieWebIntentAnyValidation(traceIdentityIsPresent),
            LottieWebIntentAnyValidation(traceDimensionsArePositive),
            LottieWebIntentAnyValidation(coordinateSemanticsAreRecorded),
            LottieWebIntentAnyValidation(framesArePresentAndUnique),
            LottieWebIntentAnyValidation(lottieWebPackageIsPinned),
            LottieWebIntentAnyValidation(framesHaveValidCounts),
            LottieWebIntentAnyValidation(framesHavePositiveFrameRate),
            LottieWebIntentAnyValidation(layersHaveValidOpacityAndWindow),
            LottieWebIntentAnyValidation(layerMatricesAreValid4x4Payloads),
            LottieWebIntentAnyValidation(pathsHaveGeometryAndStyleFacts),
            LottieWebIntentAnyValidation(masksHavePathAndOpacityFacts),
            LottieWebIntentAnyValidation(mattesHaveSourceTargetFacts),
            LottieWebIntentAnyValidation(precompositionsHaveLocalFrameFacts),
            LottieWebIntentAnyValidation(trimsHaveNormalizedFractionFacts),
            LottieWebIntentAnyValidation(diagnosticsHaveReasons),
            LottieWebIntentAnyValidation(boundsContainFiniteOrderedValues),
            LottieWebIntentAnyValidation(affineMatricesContainFiniteValues),
            LottieWebIntentAnyValidation(stylesContainVisiblePaintFacts),
            LottieWebIntentAnyValidation(ancestorsContainElementTags),
        ]
    }

    public static var schemaNameAndVersionAreSupported: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Schema> {
        Validation(
            ruleID: "lottie-web-intent.schema.supported",
            description: "Lottie-web intent schema name is purelottie.lottie-web-intent and version is 1",
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.name != "purelottie.lottie-web-intent" {
                errors.append(error(
                    ruleID: "lottie-web-intent.schema.name",
                    description: "Lottie-web intent schema name is purelottie.lottie-web-intent and version is 1",
                    path: context.codingPath.appending(.key("name"))
                ))
            }
            if context.subject.version != 1 {
                errors.append(error(
                    ruleID: "lottie-web-intent.schema.version",
                    description: "Lottie-web intent schema name is purelottie.lottie-web-intent and version is 1",
                    path: context.codingPath.appending(.key("version"))
                ))
            }
            return errors
        }
    }

    public static var traceIdentityIsPresent: Validation<LottieWebIntentTrace, LottieWebIntentTrace> {
        Validation(
            ruleID: "lottie-web-intent.trace.identity",
            description: "Lottie-web intent trace records source path and svg renderer"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error(
                    ruleID: "lottie-web-intent.source.present",
                    description: "Lottie-web intent trace records source path and svg renderer",
                    path: context.codingPath.appending(.key("source"))
                ))
            }
            if context.subject.renderer != "svg" {
                errors.append(error(
                    ruleID: "lottie-web-intent.renderer.svg",
                    description: "Lottie-web intent trace records source path and svg renderer",
                    path: context.codingPath.appending(.key("renderer"))
                ))
            }
            return errors
        }
    }

    public static var traceDimensionsArePositive: Validation<LottieWebIntentTrace, LottieWebIntentTrace> {
        Validation(
            ruleID: "lottie-web-intent.trace.dimensions",
            description: "Lottie-web intent trace dimensions and scale are positive finite numbers"
        ) { context in
            numericErrors(
                [
                    ("width", context.subject.width),
                    ("height", context.subject.height),
                    ("scale", context.subject.scale),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.trace.dimension",
                description: "Lottie-web intent trace dimensions and scale are positive finite numbers"
            ) { $0.isFinite && $0 > 0 }
        }
    }

    public static var coordinateSemanticsAreRecorded: Validation<LottieWebIntentTrace, LottieWebIntentTrace> {
        Validation(
            ruleID: "lottie-web-intent.trace.coordinate-semantics",
            description: "Lottie-web intent trace records coordinate semantics"
        ) { context in
            context.subject.coordinateSemantics.isEmpty
                ? [
                    error(
                        ruleID: "lottie-web-intent.coordinate-semantics.present",
                        description: "Lottie-web intent trace records coordinate semantics",
                        path: context.codingPath.appending(.key("coordinateSemantics"))
                    ),
                ]
                : []
        }
    }

    public static var framesArePresentAndUnique: Validation<LottieWebIntentTrace, LottieWebIntentTrace> {
        Validation(
            ruleID: "lottie-web-intent.frames.unique",
            description: "Lottie-web intent trace contains at least one unique source frame"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.frames.isEmpty {
                errors.append(error(
                    ruleID: "lottie-web-intent.frames.present",
                    description: "Lottie-web intent trace contains at least one unique source frame",
                    path: context.codingPath.appending(.key("frames"))
                ))
            }
            var seen: Set<Double> = []
            for index in context.subject.frames.indices {
                let frame = context.subject.frames[index].frame
                if seen.contains(frame) {
                    errors.append(error(
                        ruleID: "lottie-web-intent.frames.duplicate",
                        description: "Lottie-web intent trace contains at least one unique source frame",
                        path: context.codingPath
                            .appending(.key("frames"))
                            .appending(.index(index))
                            .appending(.key("frame"))
                    ))
                }
                seen.insert(frame)
            }
            return errors
        }
    }

    public static var lottieWebPackageIsPinned: Validation<LottieWebIntentTrace, LottieWebIntentTrace.LottieWeb> {
        Validation(
            ruleID: "lottie-web-intent.engine.pinned",
            description: "Lottie-web intent trace was extracted with npm:lottie-web@5.13.0"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.package != "npm:lottie-web@5.13.0" {
                errors.append(error(
                    ruleID: "lottie-web-intent.engine.package",
                    description: "Lottie-web intent trace was extracted with npm:lottie-web@5.13.0",
                    path: context.codingPath.appending(.key("package"))
                ))
            }
            if context.subject.version != "5.13.0" {
                errors.append(error(
                    ruleID: "lottie-web-intent.engine.version",
                    description: "Lottie-web intent trace was extracted with npm:lottie-web@5.13.0",
                    path: context.codingPath.appending(.key("version"))
                ))
            }
            return errors
        }
    }

    public static var framesHaveValidCounts: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Frame> {
        Validation(
            ruleID: "lottie-web-intent.frame.counts",
            description: "Lottie-web intent frame counts match decoded feature arrays"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.layerCount != context.subject.layers.count {
                errors.append(error(
                    ruleID: "lottie-web-intent.frame.layer-count",
                    description: "Lottie-web intent frame counts match decoded feature arrays",
                    path: context.codingPath.appending(.key("layerCount"))
                ))
            }
            if context.subject.pathCount != context.subject.paths.count {
                errors.append(error(
                    ruleID: "lottie-web-intent.frame.path-count",
                    description: "Lottie-web intent frame counts match decoded feature arrays",
                    path: context.codingPath.appending(.key("pathCount"))
                ))
            }
            if context.subject.maskCount != context.subject.masks.count {
                errors.append(error(
                    ruleID: "lottie-web-intent.frame.mask-count",
                    description: "Lottie-web intent frame counts match decoded feature arrays",
                    path: context.codingPath.appending(.key("maskCount"))
                ))
            }
            if context.subject.matteCount != context.subject.mattes.count {
                errors.append(error(
                    ruleID: "lottie-web-intent.frame.matte-count",
                    description: "Lottie-web intent frame counts match decoded feature arrays",
                    path: context.codingPath.appending(.key("matteCount"))
                ))
            }
            if context.subject.precompositionCount != context.subject.precompositions.count {
                errors.append(error(
                    ruleID: "lottie-web-intent.frame.precomposition-count",
                    description: "Lottie-web intent frame counts match decoded feature arrays",
                    path: context.codingPath.appending(.key("precompositionCount"))
                ))
            }
            if context.subject.trimCount != context.subject.trims.count {
                errors.append(error(
                    ruleID: "lottie-web-intent.frame.trim-count",
                    description: "Lottie-web intent frame counts match decoded feature arrays",
                    path: context.codingPath.appending(.key("trimCount"))
                ))
            }
            return errors
        }
    }

    public static var framesHavePositiveFrameRate: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Frame> {
        Validation(
            ruleID: "lottie-web-intent.frame.rate",
            description: "Lottie-web intent frame records contain finite frames and positive frame rates"
        ) { context in
            numericErrors(
                [
                    ("frame", context.subject.frame),
                    ("currentFrame", context.subject.currentFrame),
                    ("renderedFrame", context.subject.renderedFrame),
                    ("firstFrame", context.subject.firstFrame),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.frame.number",
                description: "Lottie-web intent frame records contain finite frames and positive frame rates"
            ) { $0.isFinite }
                + numericErrors(
                    [("frameRate", context.subject.frameRate)],
                    at: context.codingPath,
                    ruleID: "lottie-web-intent.frame.frame-rate",
                    description: "Lottie-web intent frame records contain finite frames and positive frame rates"
                ) { $0.isFinite && $0 > 0 }
        }
    }

    public static var layersHaveValidOpacityAndWindow: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Layer> {
        Validation(
            ruleID: "lottie-web-intent.layer.window-opacity",
            description: "Lottie-web intent layer records contain finite opacity and a valid frame window"
        ) { context in
            var errors = numericErrors(
                [
                    ("inPoint", context.subject.inPoint),
                    ("outPoint", context.subject.outPoint),
                    ("startTime", context.subject.startTime),
                    ("renderedFrame", context.subject.renderedFrame),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.layer.frame-number",
                description: "Lottie-web intent layer records contain finite opacity and a valid frame window"
            ) { $0.isFinite }
            errors.append(contentsOf: numericErrors(
                [("opacity", context.subject.opacity)],
                at: context.codingPath,
                ruleID: "lottie-web-intent.layer.opacity",
                description: "Lottie-web intent layer records contain finite opacity and a valid frame window"
            ) { $0.isFinite && (0 ... 1).contains($0) })
            if context.subject.inPoint > context.subject.outPoint {
                errors.append(error(
                    ruleID: "lottie-web-intent.layer.frame-window",
                    description: "Lottie-web intent layer records contain finite opacity and a valid frame window",
                    path: context.codingPath.appending(.key("outPoint"))
                ))
            }
            return errors
        }
    }

    public static var layerMatricesAreValid4x4Payloads: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Layer> {
        Validation(
            ruleID: "lottie-web-intent.layer.matrix",
            description: "Lottie-web intent layer matrices contain exactly sixteen finite numbers"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.matrix.count != 16 {
                errors.append(error(
                    ruleID: "lottie-web-intent.layer.matrix.count",
                    description: "Lottie-web intent layer matrices contain exactly sixteen finite numbers",
                    path: context.codingPath.appending(.key("matrix"))
                ))
            }
            for index in context.subject.matrix.indices where !context.subject.matrix[index].isFinite {
                errors.append(error(
                    ruleID: "lottie-web-intent.layer.matrix.finite",
                    description: "Lottie-web intent layer matrices contain exactly sixteen finite numbers",
                    path: context.codingPath
                        .appending(.key("matrix"))
                        .appending(.index(index))
                ))
            }
            return errors
        }
    }

    public static var pathsHaveGeometryAndStyleFacts: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Path> {
        Validation(
            ruleID: "lottie-web-intent.path.geometry-style",
            description: "Lottie-web intent path records contain SVG geometry and style facts"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error(
                    ruleID: "lottie-web-intent.path.tag",
                    description: "Lottie-web intent path records contain SVG geometry and style facts",
                    path: context.codingPath.appending(.key("tag"))
                ))
            }
            if context.subject.d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !context.subject.hasZeroGeometry
            {
                errors.append(error(
                    ruleID: "lottie-web-intent.path.empty-d-zero-geometry",
                    description: "Lottie-web intent path records contain SVG geometry and style facts",
                    path: context.codingPath.appending(.key("d"))
                ))
            }
            if !context.subject.pathLength.isFinite || context.subject.pathLength < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.path.length",
                    description: "Lottie-web intent path records contain SVG geometry and style facts",
                    path: context.codingPath.appending(.key("pathLength"))
                ))
            }
            return errors
        }
    }

    public static var masksHavePathAndOpacityFacts: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Mask> {
        Validation(
            ruleID: "lottie-web-intent.mask.facts",
            description: "Lottie-web intent mask records contain path mode opacity and layer-local geometry facts"
        ) { context in
            var errors = stringErrors(
                [
                    ("layerName", context.subject.layerName),
                    ("mode", context.subject.mode),
                    ("pathD", context.subject.pathD),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.mask.string",
                description: "Lottie-web intent mask records contain path mode opacity and layer-local geometry facts"
            )
            errors.append(contentsOf: numericErrors(
                [
                    ("opacity", context.subject.opacity),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.mask.opacity",
                description: "Lottie-web intent mask records contain path mode opacity and layer-local geometry facts"
            ) { $0.isFinite && (0 ... 1).contains($0) })
            errors.append(contentsOf: numericErrors(
                [
                    ("expansion", context.subject.expansion),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.mask.expansion",
                description: "Lottie-web intent mask records contain path mode opacity and layer-local geometry facts"
            ) { $0.isFinite })
            if context.subject.renderElementIndex < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.mask.render-element-index",
                    description: "Lottie-web intent mask records contain path mode opacity and layer-local geometry facts",
                    path: context.codingPath.appending(.key("renderElementIndex"))
                ))
            }
            if context.subject.layerInd < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.mask.layer-ind",
                    description: "Lottie-web intent mask records contain path mode opacity and layer-local geometry facts",
                    path: context.codingPath.appending(.key("layerInd"))
                ))
            }
            if context.subject.maskIndex < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.mask.index",
                    description: "Lottie-web intent mask records contain path mode opacity and layer-local geometry facts",
                    path: context.codingPath.appending(.key("maskIndex"))
                ))
            }
            if context.subject.vertexCount <= 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.mask.vertex-count",
                    description: "Lottie-web intent mask records contain path mode opacity and layer-local geometry facts",
                    path: context.codingPath.appending(.key("vertexCount"))
                ))
            }
            return errors
        }
    }

    public static var mattesHaveSourceTargetFacts: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Matte> {
        Validation(
            ruleID: "lottie-web-intent.matte.facts",
            description: "Lottie-web intent matte records contain source target layer and mode facts"
        ) { context in
            var errors = stringErrors(
                [
                    ("targetLayerName", context.subject.targetLayerName),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.matte.target-name",
                description: "Lottie-web intent matte records contain source target layer and mode facts"
            )
            if context.subject.targetRenderElementIndex < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.matte.target-render-index",
                    description: "Lottie-web intent matte records contain source target layer and mode facts",
                    path: context.codingPath.appending(.key("targetRenderElementIndex"))
                ))
            }
            if context.subject.targetLayerInd < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.matte.target-layer-ind",
                    description: "Lottie-web intent matte records contain source target layer and mode facts",
                    path: context.codingPath.appending(.key("targetLayerInd"))
                ))
            }
            if context.subject.mode <= 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.matte.mode",
                    description: "Lottie-web intent matte records contain source target layer and mode facts",
                    path: context.codingPath.appending(.key("mode"))
                ))
            }
            if context.subject.sourceResolved {
                if context.subject.sourceRenderElementIndex == nil {
                    errors.append(error(
                        ruleID: "lottie-web-intent.matte.source-render-index",
                        description: "Lottie-web intent matte records contain source target layer and mode facts",
                        path: context.codingPath.appending(.key("sourceRenderElementIndex"))
                    ))
                }
                if context.subject.sourceLayerInd == nil {
                    errors.append(error(
                        ruleID: "lottie-web-intent.matte.source-layer-ind",
                        description: "Lottie-web intent matte records contain source target layer and mode facts",
                        path: context.codingPath.appending(.key("sourceLayerInd"))
                    ))
                }
                if context.subject.sourceLayerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    errors.append(error(
                        ruleID: "lottie-web-intent.matte.source-layer-name",
                        description: "Lottie-web intent matte records contain source target layer and mode facts",
                        path: context.codingPath.appending(.key("sourceLayerName"))
                    ))
                }
            }
            return errors
        }
    }

    public static var precompositionsHaveLocalFrameFacts:
        Validation<LottieWebIntentTrace, LottieWebIntentTrace.Precomposition>
    {
        Validation(
            ruleID: "lottie-web-intent.precomposition.facts",
            description: "Lottie-web intent precomposition records contain local rendered frame and child layer facts"
        ) { context in
            var errors = stringErrors(
                [
                    ("layerName", context.subject.layerName),
                    ("refId", context.subject.refId),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.precomposition.string",
                description: "Lottie-web intent precomposition records contain local rendered frame and child layer facts"
            )
            errors.append(contentsOf: numericErrors(
                [
                    ("startTime", context.subject.startTime),
                    ("stretch", context.subject.stretch),
                    ("inPoint", context.subject.inPoint),
                    ("outPoint", context.subject.outPoint),
                    ("renderedFrame", context.subject.renderedFrame),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.precomposition.number",
                description: "Lottie-web intent precomposition records contain local rendered frame and child layer facts"
            ) { $0.isFinite })
            if context.subject.renderElementIndex < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.precomposition.render-index",
                    description: "Lottie-web intent precomposition records contain local rendered frame and child layer facts",
                    path: context.codingPath.appending(.key("renderElementIndex"))
                ))
            }
            if context.subject.layerInd < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.precomposition.layer-ind",
                    description: "Lottie-web intent precomposition records contain local rendered frame and child layer facts",
                    path: context.codingPath.appending(.key("layerInd"))
                ))
            }
            if context.subject.childLayerCount < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.precomposition.child-count",
                    description: "Lottie-web intent precomposition records contain local rendered frame and child layer facts",
                    path: context.codingPath.appending(.key("childLayerCount"))
                ))
            }
            if context.subject.builtChildElementCount < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.precomposition.built-child-count",
                    description: "Lottie-web intent precomposition records contain local rendered frame and child layer facts",
                    path: context.codingPath.appending(.key("builtChildElementCount"))
                ))
            }
            return errors
        }
    }

    public static var trimsHaveNormalizedFractionFacts: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Trim> {
        Validation(
            ruleID: "lottie-web-intent.trim.facts",
            description: "Lottie-web intent trim records contain normalized start end offset and mode facts"
        ) { context in
            var errors = stringErrors(
                [
                    ("layerName", context.subject.layerName),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.trim.layer-name",
                description: "Lottie-web intent trim records contain normalized start end offset and mode facts"
            )
            errors.append(contentsOf: numericErrors(
                [
                    ("startFraction", context.subject.startFraction),
                    ("endFraction", context.subject.endFraction),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.trim.fraction",
                description: "Lottie-web intent trim records contain normalized start end offset and mode facts"
            ) { $0.isFinite && (0 ... 1).contains($0) })
            errors.append(contentsOf: numericErrors(
                [
                    ("offsetTurns", context.subject.offsetTurns),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.trim.offset",
                description: "Lottie-web intent trim records contain normalized start end offset and mode facts"
            ) { $0.isFinite })
            if context.subject.renderElementIndex < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.trim.render-element-index",
                    description: "Lottie-web intent trim records contain normalized start end offset and mode facts",
                    path: context.codingPath.appending(.key("renderElementIndex"))
                ))
            }
            if context.subject.layerInd < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.trim.layer-ind",
                    description: "Lottie-web intent trim records contain normalized start end offset and mode facts",
                    path: context.codingPath.appending(.key("layerInd"))
                ))
            }
            if context.subject.trimIndex < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.trim.index",
                    description: "Lottie-web intent trim records contain normalized start end offset and mode facts",
                    path: context.codingPath.appending(.key("trimIndex"))
                ))
            }
            if context.subject.mode <= 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.trim.mode",
                    description: "Lottie-web intent trim records contain normalized start end offset and mode facts",
                    path: context.codingPath.appending(.key("mode"))
                ))
            }
            if context.subject.shapeCount <= 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.trim.shape-count",
                    description: "Lottie-web intent trim records contain normalized start end offset and mode facts",
                    path: context.codingPath.appending(.key("shapeCount"))
                ))
            }
            return errors
        }
    }

    public static var diagnosticsHaveReasons: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Diagnostic> {
        Validation(
            ruleID: "lottie-web-intent.diagnostic.reason",
            description: "Lottie-web intent diagnostics contain feature names and reasons"
        ) { context in
            stringErrors(
                [
                    ("feature", context.subject.feature),
                    ("reason", context.subject.reason),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.diagnostic.string",
                description: "Lottie-web intent diagnostics contain feature names and reasons"
            )
        }
    }

    public static var boundsContainFiniteOrderedValues: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Bounds> {
        Validation(
            ruleID: "lottie-web-intent.bounds.finite-ordered",
            description: "Lottie-web intent bounds contain finite ordered values and non-negative size"
        ) { context in
            var errors = numericErrors(
                [
                    ("minX", context.subject.minX),
                    ("minY", context.subject.minY),
                    ("maxX", context.subject.maxX),
                    ("maxY", context.subject.maxY),
                    ("width", context.subject.width),
                    ("height", context.subject.height),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.bounds.finite",
                description: "Lottie-web intent bounds contain finite ordered values and non-negative size"
            ) { $0.isFinite }
            if context.subject.minX > context.subject.maxX {
                errors.append(error(
                    ruleID: "lottie-web-intent.bounds.x-order",
                    description: "Lottie-web intent bounds contain finite ordered values and non-negative size",
                    path: context.codingPath.appending(.key("maxX"))
                ))
            }
            if context.subject.minY > context.subject.maxY {
                errors.append(error(
                    ruleID: "lottie-web-intent.bounds.y-order",
                    description: "Lottie-web intent bounds contain finite ordered values and non-negative size",
                    path: context.codingPath.appending(.key("maxY"))
                ))
            }
            if context.subject.width < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.bounds.width",
                    description: "Lottie-web intent bounds contain finite ordered values and non-negative size",
                    path: context.codingPath.appending(.key("width"))
                ))
            }
            if context.subject.height < 0 {
                errors.append(error(
                    ruleID: "lottie-web-intent.bounds.height",
                    description: "Lottie-web intent bounds contain finite ordered values and non-negative size",
                    path: context.codingPath.appending(.key("height"))
                ))
            }
            return errors
        }
    }

    public static var affineMatricesContainFiniteValues: Validation<LottieWebIntentTrace, LottieWebIntentTrace.AffineMatrix> {
        Validation(
            ruleID: "lottie-web-intent.affine.finite",
            description: "Lottie-web intent affine matrices contain finite values"
        ) { context in
            numericErrors(
                [
                    ("a", context.subject.a),
                    ("b", context.subject.b),
                    ("c", context.subject.c),
                    ("d", context.subject.d),
                    ("e", context.subject.e),
                    ("f", context.subject.f),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.affine.value",
                description: "Lottie-web intent affine matrices contain finite values"
            ) { $0.isFinite }
        }
    }

    public static var stylesContainVisiblePaintFacts: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Style> {
        Validation(
            ruleID: "lottie-web-intent.style.paint",
            description: "Lottie-web intent style records contain visible paint facts"
        ) { context in
            stringErrors(
                [
                    ("fill", context.subject.fill),
                    ("fillRule", context.subject.fillRule),
                    ("stroke", context.subject.stroke),
                    ("strokeLinecap", context.subject.strokeLinecap),
                    ("strokeLinejoin", context.subject.strokeLinejoin),
                    ("strokeDasharray", context.subject.strokeDasharray),
                    ("strokeDashoffset", context.subject.strokeDashoffset),
                    ("display", context.subject.display),
                    ("visibility", context.subject.visibility),
                ],
                at: context.codingPath,
                ruleID: "lottie-web-intent.style.string",
                description: "Lottie-web intent style records contain visible paint facts"
            )
                + numericErrors(
                    [
                        ("fillOpacity", context.subject.fillOpacity),
                        ("opacity", context.subject.opacity),
                        ("strokeOpacity", context.subject.strokeOpacity),
                    ],
                    at: context.codingPath,
                    ruleID: "lottie-web-intent.style.opacity",
                    description: "Lottie-web intent style records contain visible paint facts"
                ) { $0.isFinite && (0 ... 1).contains($0) }
                + numericErrors(
                    [
                        ("strokeWidth", context.subject.strokeWidth),
                        ("strokeMiterlimit", context.subject.strokeMiterlimit),
                    ],
                    at: context.codingPath,
                    ruleID: "lottie-web-intent.style.stroke-number",
                    description: "Lottie-web intent style records contain visible paint facts"
                ) { $0.isFinite && $0 >= 0 }
        }
    }

    public static var ancestorsContainElementTags: Validation<LottieWebIntentTrace, LottieWebIntentTrace.Ancestor> {
        Validation(
            ruleID: "lottie-web-intent.ancestor.tag",
            description: "Lottie-web intent ancestor records contain SVG element tags"
        ) { context in
            context.subject.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [
                    error(
                        ruleID: "lottie-web-intent.ancestor.tag.present",
                        description: "Lottie-web intent ancestor records contain SVG element tags",
                        path: context.codingPath.appending(.key("tag"))
                    ),
                ]
                : []
        }
    }

    private static func numericErrors(
        _ fields: [(String, Double)],
        at path: JSONPath,
        ruleID: String,
        description: String,
        isValid: (Double) -> Bool
    ) -> [ValidationError] {
        fields.compactMap { field, value in
            isValid(value)
                ? nil
                : error(
                    ruleID: ruleID,
                    description: description,
                    path: path.appending(.key(field))
                )
        }
    }

    private static func stringErrors(
        _ fields: [(String, String)],
        at path: JSONPath,
        ruleID: String,
        description: String
    ) -> [ValidationError] {
        fields.compactMap { field, value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? error(
                    ruleID: ruleID,
                    description: description,
                    path: path.appending(.key(field))
                )
                : nil
        }
    }

    private static func error(ruleID: String, description: String, path: JSONPath) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "Failed to satisfy: \(description)",
            at: path,
            phase: .source,
            classification: .reported
        )
    }
}

private extension LottieWebIntentTrace.Path {
    var hasZeroGeometry: Bool {
        pathLength == 0
            && localBBox.isZero
            && clientBounds.isZero
            && sampledLocalBounds.isZero
            && sampledCompositionBounds.isZero
            && sampledOutputBounds.isZero
            && strokeExpandedCompositionBounds.isZero
            && strokeExpandedOutputBounds.isZero
    }
}

private extension LottieWebIntentTrace.Bounds {
    var isZero: Bool {
        minX == 0 && minY == 0 && maxX == 0 && maxY == 0 && width == 0 && height == 0
    }
}

private struct LottieWebIntentAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, LottieWebIntentTrace) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<LottieWebIntentTrace, Subject>) {
        ruleID = validation.ruleID
        description = validation.description
        applyClosure = { input, path, document in
            guard let subject = input as? Subject else { return [] }
            return validation.apply(to: subject, at: path, in: document)
        }
    }

    func apply(to subject: any Validatable, at codingPath: JSONPath, in document: LottieWebIntentTrace) -> [ValidationError] {
        applyClosure(subject, codingPath, document)
    }
}
