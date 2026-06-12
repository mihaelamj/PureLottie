//
//  LottieSourceIntentTrace.swift
//  PureLottie
//

/// Durable, JSON-codable record of what a Lottie source document means at one
/// or more source frames before any PureLayer lowering.
public struct LottieSourceIntentTrace: Codable, Sendable, Equatable {
    /// Schema identifier. Bump when a reader must change to preserve meaning.
    public var schema: LottieSourceIntentSchema
    /// Identity of the source bytes that produced this trace.
    public var source: LottieSourceIntentSource
    /// Root composition facts copied from the Lottie document.
    public var composition: LottieSourceIntentComposition
    /// Evaluated frame records in source-frame units.
    public var frames: [LottieSourceIntentFrame]
    /// Trace-level diagnostics that are not tied to a single frame.
    public var diagnostics: [LottieSourceIntentDiagnostic]
    /// Round-trip contract carried with every trace fixture.
    public var roundTrip: LottieSourceIntentRoundTrip

    public init(
        schema: LottieSourceIntentSchema,
        source: LottieSourceIntentSource,
        composition: LottieSourceIntentComposition,
        frames: [LottieSourceIntentFrame],
        diagnostics: [LottieSourceIntentDiagnostic] = [],
        roundTrip: LottieSourceIntentRoundTrip
    ) {
        self.schema = schema
        self.source = source
        self.composition = composition
        self.frames = frames
        self.diagnostics = diagnostics
        self.roundTrip = roundTrip
    }
}

public struct LottieSourceIntentSchema: Codable, Sendable, Equatable {
    public var name: String
    public var version: Int

    public init(name: String = "purelottie.source-intent-trace", version: Int = 1) {
        self.name = name
        self.version = version
    }
}

public struct LottieSourceIntentSource: Codable, Sendable, Equatable {
    public var identity: String
    public var path: String?
    public var revision: String?
    public var sha256: String?
    public var byteCount: Int?

    public init(
        identity: String,
        path: String? = nil,
        revision: String? = nil,
        sha256: String? = nil,
        byteCount: Int? = nil
    ) {
        self.identity = identity
        self.path = path
        self.revision = revision
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public struct LottieSourceIntentComposition: Codable, Sendable, Equatable {
    public var name: String?
    public var version: String?
    public var width: Double
    public var height: Double
    public var inPoint: Double
    public var outPoint: Double
    public var frameRate: Double
    public var frameWindow: LottieSourceIntentFrameWindow
    public var provenance: LottieSourceIntentProvenance

    public init(
        name: String?,
        version: String?,
        width: Double,
        height: Double,
        inPoint: Double,
        outPoint: Double,
        frameRate: Double,
        frameWindow: LottieSourceIntentFrameWindow = .ipInclusiveOpExclusive,
        provenance: LottieSourceIntentProvenance
    ) {
        self.name = name
        self.version = version
        self.width = width
        self.height = height
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.frameRate = frameRate
        self.frameWindow = frameWindow
        self.provenance = provenance
    }
}

public enum LottieSourceIntentFrameWindow: String, Codable, Sendable, Equatable {
    case ipInclusiveOpExclusive
}

public struct LottieSourceIntentFrame: Codable, Sendable, Equatable {
    public var sourceFrame: Double
    public var localTimeSeconds: Double?
    public var visibleLayers: [LottieSourceIntentLayer]
    public var diagnostics: [LottieSourceIntentDiagnostic]

    public init(
        sourceFrame: Double,
        localTimeSeconds: Double? = nil,
        visibleLayers: [LottieSourceIntentLayer],
        diagnostics: [LottieSourceIntentDiagnostic] = []
    ) {
        self.sourceFrame = sourceFrame
        self.localTimeSeconds = localTimeSeconds
        self.visibleLayers = visibleLayers
        self.diagnostics = diagnostics
    }
}

public struct LottieSourceIntentLayer: Codable, Sendable, Equatable {
    public var id: String
    public var name: String?
    public var index: Int?
    public var type: LottieSourceIntentLayerType
    public var renderOrder: Int
    public var localFrame: Double
    public var opacity: Double
    public var transform: LottieSourceIntentTransform
    public var geometry: [LottieSourceIntentGeometry]
    public var styles: [LottieSourceIntentStyle]
    public var masks: [LottieSourceIntentMask]
    public var matte: LottieSourceIntentMatte?
    public var diagnostics: [LottieSourceIntentDiagnostic]
    public var provenance: LottieSourceIntentProvenance

    public init(
        id: String,
        name: String?,
        index: Int?,
        type: LottieSourceIntentLayerType,
        renderOrder: Int,
        localFrame: Double,
        opacity: Double,
        transform: LottieSourceIntentTransform,
        geometry: [LottieSourceIntentGeometry] = [],
        styles: [LottieSourceIntentStyle] = [],
        masks: [LottieSourceIntentMask] = [],
        matte: LottieSourceIntentMatte? = nil,
        diagnostics: [LottieSourceIntentDiagnostic] = [],
        provenance: LottieSourceIntentProvenance
    ) {
        self.id = id
        self.name = name
        self.index = index
        self.type = type
        self.renderOrder = renderOrder
        self.localFrame = localFrame
        self.opacity = opacity
        self.transform = transform
        self.geometry = geometry
        self.styles = styles
        self.masks = masks
        self.matte = matte
        self.diagnostics = diagnostics
        self.provenance = provenance
    }
}

public enum LottieSourceIntentLayerType: String, Codable, Sendable, Equatable {
    case precomposition
    case solid
    case image
    case null
    case shape
    case text
    case unsupported
}

public struct LottieSourceIntentTransform: Codable, Sendable, Equatable {
    public var anchor: [Double]
    public var position: [Double]
    public var scale: [Double]
    public var rotationZDegrees: Double
    public var is3DLayer: Bool
    public var matrix: LottieSourceIntentMatrix
    public var matrixConvention: LottieSourceIntentMatrixConvention
    public var provenance: LottieSourceIntentProvenance

    public init(
        anchor: [Double],
        position: [Double],
        scale: [Double],
        rotationZDegrees: Double,
        is3DLayer: Bool,
        matrix: LottieSourceIntentMatrix,
        matrixConvention: LottieSourceIntentMatrixConvention,
        provenance: LottieSourceIntentProvenance
    ) {
        self.anchor = anchor
        self.position = position
        self.scale = scale
        self.rotationZDegrees = rotationZDegrees
        self.is3DLayer = is3DLayer
        self.matrix = matrix
        self.matrixConvention = matrixConvention
        self.provenance = provenance
    }
}

public struct LottieSourceIntentMatrix: Codable, Sendable, Equatable {
    public var values: [Double]

    public init(values: [Double]) throws {
        guard values.count == 16 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "A source-intent transform matrix must contain exactly 16 values."
                )
            )
        }
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let values = try container.decode([Double].self)
        guard values.count == 16 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A source-intent transform matrix must contain exactly 16 values."
            )
        }
        self.values = values
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

public struct LottieSourceIntentMatrixConvention: Codable, Sendable, Equatable {
    public var storageOrder: String
    public var vectorConvention: String
    public var concatenationOrder: String
    public var pointApplication: String

    public init(
        storageOrder: String,
        vectorConvention: String,
        concatenationOrder: String,
        pointApplication: String
    ) {
        self.storageOrder = storageOrder
        self.vectorConvention = vectorConvention
        self.concatenationOrder = concatenationOrder
        self.pointApplication = pointApplication
    }

    public static var lottieWebRowVector4x4: LottieSourceIntentMatrixConvention {
        LottieSourceIntentMatrixConvention(
            storageOrder: "row-major-4x4",
            vectorConvention: "row-vector",
            concatenationOrder: "left-to-right",
            pointApplication: "x'=x*m0+y*m4+z*m8+m12; y'=x*m1+y*m5+z*m9+m13"
        )
    }
}

public struct LottieSourceIntentGeometry: Codable, Sendable, Equatable {
    public var id: String
    public var kind: LottieSourceIntentGeometryKind
    public var primitive: String
    public var parameters: [String: [Double]]
    public var path: LottieSourceIntentPath?
    public var transformStack: [LottieSourceIntentTransform]
    public var modifiers: [LottieSourceIntentModifier]
    public var provenance: LottieSourceIntentProvenance

    public init(
        id: String,
        kind: LottieSourceIntentGeometryKind,
        primitive: String,
        parameters: [String: [Double]] = [:],
        path: LottieSourceIntentPath? = nil,
        transformStack: [LottieSourceIntentTransform] = [],
        modifiers: [LottieSourceIntentModifier] = [],
        provenance: LottieSourceIntentProvenance
    ) {
        self.id = id
        self.kind = kind
        self.primitive = primitive
        self.parameters = parameters
        self.path = path
        self.transformStack = transformStack
        self.modifiers = modifiers
        self.provenance = provenance
    }
}

public enum LottieSourceIntentGeometryKind: String, Codable, Sendable, Equatable {
    case path
    case rectangle
    case ellipse
    case unsupported
}

public struct LottieSourceIntentPath: Codable, Sendable, Equatable {
    public var closed: Bool
    public var vertices: [[Double]]
    public var inTangents: [[Double]]
    public var outTangents: [[Double]]

    public init(
        closed: Bool,
        vertices: [[Double]],
        inTangents: [[Double]],
        outTangents: [[Double]]
    ) {
        self.closed = closed
        self.vertices = vertices
        self.inTangents = inTangents
        self.outTangents = outTangents
    }
}

public struct LottieSourceIntentModifier: Codable, Sendable, Equatable {
    public var kind: LottieSourceIntentModifierKind
    public var trim: LottieSourceIntentTrim?
    public var provenance: LottieSourceIntentProvenance

    public init(
        kind: LottieSourceIntentModifierKind,
        trim: LottieSourceIntentTrim? = nil,
        provenance: LottieSourceIntentProvenance
    ) {
        self.kind = kind
        self.trim = trim
        self.provenance = provenance
    }
}

public enum LottieSourceIntentModifierKind: String, Codable, Sendable, Equatable {
    case trim
    case unsupported
}

public struct LottieSourceIntentTrim: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var offset: Double
    public var multiple: Int?
    public var isAnimated: Bool

    public init(start: Double, end: Double, offset: Double, multiple: Int?, isAnimated: Bool) {
        self.start = start
        self.end = end
        self.offset = offset
        self.multiple = multiple
        self.isAnimated = isAnimated
    }
}

public struct LottieSourceIntentStyle: Codable, Sendable, Equatable {
    public var id: String
    public var kind: LottieSourceIntentStyleKind
    public var color: [Double]?
    public var opacity: Double?
    public var width: Double?
    public var lineCap: Int?
    public var lineJoin: Int?
    public var miterLimit: Double?
    public var dashPattern: [LottieSourceIntentStrokeDash]
    public var blendMode: Int?
    public var provenance: LottieSourceIntentProvenance

    public init(
        id: String,
        kind: LottieSourceIntentStyleKind,
        color: [Double]? = nil,
        opacity: Double? = nil,
        width: Double? = nil,
        lineCap: Int? = nil,
        lineJoin: Int? = nil,
        miterLimit: Double? = nil,
        dashPattern: [LottieSourceIntentStrokeDash] = [],
        blendMode: Int? = nil,
        provenance: LottieSourceIntentProvenance
    ) {
        self.id = id
        self.kind = kind
        self.color = color
        self.opacity = opacity
        self.width = width
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dashPattern = dashPattern
        self.blendMode = blendMode
        self.provenance = provenance
    }
}

public enum LottieSourceIntentStyleKind: String, Codable, Sendable, Equatable {
    case fill
    case stroke
    case gradientFill
    case gradientStroke
    case unsupported
}

public struct LottieSourceIntentStrokeDash: Codable, Sendable, Equatable {
    public var name: String?
    public var type: String?
    public var value: Double?
    public var isAnimated: Bool

    public init(name: String?, type: String?, value: Double?, isAnimated: Bool) {
        self.name = name
        self.type = type
        self.value = value
        self.isAnimated = isAnimated
    }
}

public struct LottieSourceIntentMask: Codable, Sendable, Equatable {
    public var name: String?
    public var mode: String
    public var inverted: Bool
    public var opacity: Double
    public var path: LottieSourceIntentPath?
    public var provenance: LottieSourceIntentProvenance

    public init(
        name: String?,
        mode: String,
        inverted: Bool,
        opacity: Double,
        path: LottieSourceIntentPath?,
        provenance: LottieSourceIntentProvenance
    ) {
        self.name = name
        self.mode = mode
        self.inverted = inverted
        self.opacity = opacity
        self.path = path
        self.provenance = provenance
    }
}

public struct LottieSourceIntentMatte: Codable, Sendable, Equatable {
    public var mode: Int
    public var sourceLayerIndex: Int?
    public var sourcePath: String?
    public var explicitSource: Bool
    public var provenance: LottieSourceIntentProvenance

    public init(
        mode: Int,
        sourceLayerIndex: Int?,
        sourcePath: String?,
        explicitSource: Bool,
        provenance: LottieSourceIntentProvenance
    ) {
        self.mode = mode
        self.sourceLayerIndex = sourceLayerIndex
        self.sourcePath = sourcePath
        self.explicitSource = explicitSource
        self.provenance = provenance
    }
}

public struct LottieSourceIntentDiagnostic: Codable, Sendable, Equatable {
    public var ruleID: String
    public var severity: LottieSourceIntentDiagnosticSeverity
    public var phase: LottieSourceIntentDiagnosticPhase
    public var classification: LottieSourceIntentFeatureClassification
    public var reason: String
    public var evidence: String?
    public var provenance: LottieSourceIntentProvenance

    public init(
        ruleID: String,
        severity: LottieSourceIntentDiagnosticSeverity,
        phase: LottieSourceIntentDiagnosticPhase,
        classification: LottieSourceIntentFeatureClassification,
        reason: String,
        evidence: String? = nil,
        provenance: LottieSourceIntentProvenance
    ) {
        self.ruleID = ruleID
        self.severity = severity
        self.phase = phase
        self.classification = classification
        self.reason = reason
        self.evidence = evidence
        self.provenance = provenance
    }
}

public enum LottieSourceIntentDiagnosticSeverity: String, Codable, Sendable, Equatable {
    case error
    case warning
    case note
}

public enum LottieSourceIntentDiagnosticPhase: String, Codable, Sendable, Equatable {
    case parse
    case source
    case semantic
    case lowering
}

public enum LottieSourceIntentFeatureClassification: String, Codable, Sendable, Equatable {
    case exact
    case approximate
    case reported
    case metadata
    case gap
}

public struct LottieSourceIntentProvenance: Codable, Sendable, Equatable {
    public var sourcePath: String
    public var jsonPath: String
    public var sourceRange: String?
    public var consumedFields: [String]
    public var preservedFields: [String]
    public var unrepresentedFields: [String]

    public init(
        sourcePath: String,
        jsonPath: String,
        sourceRange: String? = nil,
        consumedFields: [String] = [],
        preservedFields: [String] = [],
        unrepresentedFields: [String] = []
    ) {
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.sourceRange = sourceRange
        self.consumedFields = consumedFields
        self.preservedFields = preservedFields
        self.unrepresentedFields = unrepresentedFields
    }
}

public struct LottieSourceIntentRoundTrip: Codable, Sendable, Equatable {
    public var laws: [String]
    public var normalForm: String
    public var lossyFields: [String]

    public init(laws: [String], normalForm: String, lossyFields: [String]) {
        self.laws = laws
        self.normalForm = normalForm
        self.lossyFields = lossyFields
    }
}
