//
//  LottieLayerGraphEvaluator.swift
//  PureLottie
//

import LottieModel

/// Source-frame layer graph evidence before RenderIR or PureLayer lowering.
public struct LottieLayerGraphTrace: Codable, Sendable, Equatable {
    /// Selected frame in the root Lottie source-frame domain.
    public var sourceFrame: Double
    /// Root composition frame-window semantics.
    public var frameWindow: LottieLayerGraphFrameWindowTrace
    /// Layer records in back-to-front traversal order, including skipped and
    /// non-rendering participants when they affect visible output.
    public var records: [LottieLayerGraphLayerTrace]
    /// Graph-level diagnostics.
    public var diagnostics: [LottieLayerGraphDiagnostic]

    public init(
        sourceFrame: Double,
        frameWindow: LottieLayerGraphFrameWindowTrace,
        records: [LottieLayerGraphLayerTrace],
        diagnostics: [LottieLayerGraphDiagnostic] = []
    ) {
        self.sourceFrame = sourceFrame
        self.frameWindow = frameWindow
        self.records = records
        self.diagnostics = diagnostics
    }

    /// Records that participate in output construction, including transform
    /// carriers and matte sources that do not emit ordinary pixels.
    public var participatingRecords: [LottieLayerGraphLayerTrace] {
        records.filter(\.participation.participatesInRenderGraph)
    }

    /// Participating layer source paths in back-to-front graph order.
    public var participatingSourcePaths: [String] {
        participatingRecords.map(\.sourcePath)
    }
}

public struct LottieLayerGraphFrameWindowTrace: Codable, Sendable, Equatable {
    public var inPoint: Double
    public var outPoint: Double
    public var selectedFrame: Double
    public var rule: String
    public var containsSelectedFrame: Bool
    public var referenceSemantics: [LottieLayerGraphReferenceSemantics]

    public init(
        inPoint: Double,
        outPoint: Double,
        selectedFrame: Double,
        rule: String = "ip <= frame < op",
        containsSelectedFrame: Bool,
        referenceSemantics: [LottieLayerGraphReferenceSemantics] = LottieLayerGraphReferenceSemantics.defaultFrameWindow
    ) {
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.selectedFrame = selectedFrame
        self.rule = rule
        self.containsSelectedFrame = containsSelectedFrame
        self.referenceSemantics = referenceSemantics
    }
}

public struct LottieLayerGraphReferenceSemantics: Codable, Sendable, Equatable {
    public var engine: String
    public var statement: String
    public var divergence: String?

    public init(engine: String, statement: String, divergence: String? = nil) {
        self.engine = engine
        self.statement = statement
        self.divergence = divergence
    }

    public static var defaultFrameWindow: [LottieLayerGraphReferenceSemantics] {
        [
            LottieLayerGraphReferenceSemantics(
                engine: "lottie-web",
                statement: "A layer is active when the selected source frame is greater than or equal to `ip` and strictly less than `op`."
            ),
            LottieLayerGraphReferenceSemantics(
                engine: "CoreAnimation/PureLayer lowering",
                statement: "The source evaluator keeps Lottie frame-window semantics; frame-to-second conversion happens only in the importer/lowering layer.",
                divergence: "CoreAnimation duration APIs are not used as source-frame truth."
            ),
        ]
    }
}

public struct LottieLayerGraphLayerTrace: Codable, Sendable, Equatable {
    public var sourcePath: String
    public var jsonPath: String
    public var compositionPath: String
    public var compositionStack: [String]
    public var arrayOffset: Int
    public var layerIndex: Int?
    public var name: String?
    public var type: LottieLayerGraphLayerType
    public var participation: LottieLayerGraphParticipation
    public var renderOrder: Int?
    public var visibility: LottieLayerGraphVisibilityTrace
    public var timing: LottieLayerGraphTimingTrace
    public var parentChain: [LottieLayerGraphParentTrace]
    public var masks: [LottieLayerGraphMaskTrace]
    public var matte: LottieLayerGraphMatteTrace?
    public var precomposition: LottieLayerGraphPrecompositionTrace?
    public var diagnostics: [LottieLayerGraphDiagnostic]

    public init(
        sourcePath: String,
        jsonPath: String,
        compositionPath: String,
        compositionStack: [String],
        arrayOffset: Int,
        layerIndex: Int?,
        name: String?,
        type: LottieLayerGraphLayerType,
        participation: LottieLayerGraphParticipation,
        renderOrder: Int?,
        visibility: LottieLayerGraphVisibilityTrace,
        timing: LottieLayerGraphTimingTrace,
        parentChain: [LottieLayerGraphParentTrace] = [],
        masks: [LottieLayerGraphMaskTrace] = [],
        matte: LottieLayerGraphMatteTrace? = nil,
        precomposition: LottieLayerGraphPrecompositionTrace? = nil,
        diagnostics: [LottieLayerGraphDiagnostic] = []
    ) {
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.compositionPath = compositionPath
        self.compositionStack = compositionStack
        self.arrayOffset = arrayOffset
        self.layerIndex = layerIndex
        self.name = name
        self.type = type
        self.participation = participation
        self.renderOrder = renderOrder
        self.visibility = visibility
        self.timing = timing
        self.parentChain = parentChain
        self.masks = masks
        self.matte = matte
        self.precomposition = precomposition
        self.diagnostics = diagnostics
    }
}

public enum LottieLayerGraphLayerType: String, Codable, Sendable, Equatable {
    case precomposition
    case solid
    case image
    case null
    case shape
    case text
    case unsupported
}

public enum LottieLayerGraphParticipation: String, Codable, Sendable, Equatable {
    /// A non-hidden, active layer with drawable content.
    case content
    /// A non-hidden, active null layer that contributes transform state.
    case transformCarrier
    /// A non-hidden, active precomp layer that opens a child composition.
    case precompositionBoundary
    /// A matte source layer. It participates in compositing, not ordinary
    /// content emission.
    case matteSource
    /// A hidden matte source layer retained for compositing evidence.
    case hiddenMatteSource
    /// A hidden transform parent retained for descendant world transforms.
    case hiddenParent
    /// A non-hidden layer outside its own frame window but still referenced as
    /// a transform parent.
    case transformParticipant
    /// A hidden layer with no graph role at this selected frame.
    case skippedHidden
    /// A non-hidden layer outside its half-open frame window.
    case skippedOutsideFrame

    public var participatesInRenderGraph: Bool {
        switch self {
        case .content,
             .transformCarrier,
             .precompositionBoundary,
             .matteSource,
             .hiddenMatteSource,
             .hiddenParent,
             .transformParticipant:
            true
        case .skippedHidden,
             .skippedOutsideFrame:
            false
        }
    }
}

public struct LottieLayerGraphVisibilityTrace: Codable, Sendable, Equatable {
    public var selectedFrame: Double
    public var inPoint: Double
    public var outPoint: Double
    public var isHidden: Bool
    public var windowRule: String
    public var containsFrame: Bool
    public var ordinaryContentVisible: Bool

    public init(
        selectedFrame: Double,
        inPoint: Double,
        outPoint: Double,
        isHidden: Bool,
        windowRule: String = "ip <= frame < op",
        containsFrame: Bool,
        ordinaryContentVisible: Bool
    ) {
        self.selectedFrame = selectedFrame
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.isHidden = isHidden
        self.windowRule = windowRule
        self.containsFrame = containsFrame
        self.ordinaryContentVisible = ordinaryContentVisible
    }
}

public struct LottieLayerGraphTimingTrace: Codable, Sendable, Equatable {
    public var mode: LottieLayerGraphTimingMode
    public var inputFrame: Double
    public var startTime: Double
    public var stretch: Double
    public var frameRate: Double
    public var localFrame: Double
    public var timeRemapSeconds: Double?
    public var timeRemapPropertyTrace: LottiePropertyEvaluationTrace?

    public init(
        mode: LottieLayerGraphTimingMode,
        inputFrame: Double,
        startTime: Double,
        stretch: Double,
        frameRate: Double,
        localFrame: Double,
        timeRemapSeconds: Double? = nil,
        timeRemapPropertyTrace: LottiePropertyEvaluationTrace? = nil
    ) {
        self.mode = mode
        self.inputFrame = inputFrame
        self.startTime = startTime
        self.stretch = stretch
        self.frameRate = frameRate
        self.localFrame = localFrame
        self.timeRemapSeconds = timeRemapSeconds
        self.timeRemapPropertyTrace = timeRemapPropertyTrace
    }
}

public enum LottieLayerGraphTimingMode: String, Codable, Sendable, Equatable {
    case startTimeAndStretch
    case timeRemapSeconds
    case invalidStretch
}

public struct LottieLayerGraphParentTrace: Codable, Sendable, Equatable {
    public var layerIndex: Int
    public var sourcePath: String
    public var jsonPath: String
    public var isHidden: Bool
    public var containsFrame: Bool

    public init(layerIndex: Int, sourcePath: String, jsonPath: String, isHidden: Bool, containsFrame: Bool) {
        self.layerIndex = layerIndex
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.isHidden = isHidden
        self.containsFrame = containsFrame
    }
}

public struct LottieLayerGraphMaskTrace: Codable, Sendable, Equatable {
    public var sourcePath: String
    public var jsonPath: String
    public var targetLayerPath: String
    public var targetLayerJsonPath: String
    public var name: String?
    public var mode: String
    public var inverted: Bool
    public var opacity: Double
    public var path: LottieLayerGraphPathTrace?
    public var diagnostics: [LottieLayerGraphDiagnostic]

    public init(
        sourcePath: String,
        jsonPath: String,
        targetLayerPath: String,
        targetLayerJsonPath: String,
        name: String?,
        mode: String,
        inverted: Bool,
        opacity: Double,
        path: LottieLayerGraphPathTrace?,
        diagnostics: [LottieLayerGraphDiagnostic] = []
    ) {
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.targetLayerPath = targetLayerPath
        self.targetLayerJsonPath = targetLayerJsonPath
        self.name = name
        self.mode = mode
        self.inverted = inverted
        self.opacity = opacity
        self.path = path
        self.diagnostics = diagnostics
    }
}

public struct LottieLayerGraphPathTrace: Codable, Sendable, Equatable {
    public var closed: Bool
    public var vertices: [[Double]]
    public var inTangents: [[Double]]
    public var outTangents: [[Double]]

    public init(closed: Bool, vertices: [[Double]], inTangents: [[Double]], outTangents: [[Double]]) {
        self.closed = closed
        self.vertices = vertices
        self.inTangents = inTangents
        self.outTangents = outTangents
    }
}

public struct LottieLayerGraphMatteTrace: Codable, Sendable, Equatable {
    public var mode: Int
    public var sourceLayerIndex: Int?
    public var sourceLayerPath: String?
    public var sourceLayerJsonPath: String?
    public var targetLayerPath: String
    public var targetLayerJsonPath: String
    public var explicitSource: Bool
    public var sourceResolved: Bool
    public var diagnostics: [LottieLayerGraphDiagnostic]

    public init(
        mode: Int,
        sourceLayerIndex: Int?,
        sourceLayerPath: String?,
        sourceLayerJsonPath: String?,
        targetLayerPath: String,
        targetLayerJsonPath: String,
        explicitSource: Bool,
        sourceResolved: Bool,
        diagnostics: [LottieLayerGraphDiagnostic] = []
    ) {
        self.mode = mode
        self.sourceLayerIndex = sourceLayerIndex
        self.sourceLayerPath = sourceLayerPath
        self.sourceLayerJsonPath = sourceLayerJsonPath
        self.targetLayerPath = targetLayerPath
        self.targetLayerJsonPath = targetLayerJsonPath
        self.explicitSource = explicitSource
        self.sourceResolved = sourceResolved
        self.diagnostics = diagnostics
    }
}

public struct LottieLayerGraphPrecompositionTrace: Codable, Sendable, Equatable {
    public var assetID: String
    public var assetJsonPath: String?
    public var compositionPath: String
    public var localFrame: Double
    public var width: Double
    public var height: Double
    public var childLayerCount: Int

    public init(
        assetID: String,
        assetJsonPath: String?,
        compositionPath: String,
        localFrame: Double,
        width: Double,
        height: Double,
        childLayerCount: Int
    ) {
        self.assetID = assetID
        self.assetJsonPath = assetJsonPath
        self.compositionPath = compositionPath
        self.localFrame = localFrame
        self.width = width
        self.height = height
        self.childLayerCount = childLayerCount
    }
}

public struct LottieLayerGraphDiagnostic: Codable, Sendable, Equatable {
    public var ruleID: String
    public var severity: LottieLayerGraphDiagnosticSeverity
    public var classification: LottieLayerGraphFeatureClassification
    public var reason: String
    public var jsonPath: String
    public var sourcePath: String?
    public var targetPath: String?
    public var evidence: String?

    public init(
        ruleID: String,
        severity: LottieLayerGraphDiagnosticSeverity = .warning,
        classification: LottieLayerGraphFeatureClassification,
        reason: String,
        jsonPath: String,
        sourcePath: String? = nil,
        targetPath: String? = nil,
        evidence: String? = nil
    ) {
        self.ruleID = ruleID
        self.severity = severity
        self.classification = classification
        self.reason = reason
        self.jsonPath = jsonPath
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.evidence = evidence
    }
}

public enum LottieLayerGraphDiagnosticSeverity: String, Codable, Sendable, Equatable {
    case error
    case warning
    case note
}

public enum LottieLayerGraphFeatureClassification: String, Codable, Sendable, Equatable {
    case exact
    case approximate
    case reported
    case metadata
    case gap
}

/// Evaluates the Lottie layer graph into measurable source-frame facts.
public struct LottieLayerGraphEvaluator: Sendable {
    public let animation: LottieAnimation

    public init(animation: LottieAnimation) {
        self.animation = animation
    }

    public func trace(at sourceFrame: Double) -> LottieLayerGraphTrace {
        var evaluator = LottieLayerGraphTraceBuilder(animation: animation, rootSourceFrame: sourceFrame)
        return evaluator.trace()
    }
}

private struct LottieLayerGraphTraceBuilder {
    let animation: LottieAnimation
    let rootSourceFrame: Double
    let frameEvaluator: LottieFrameEvaluator
    var records: [LottieLayerGraphLayerTrace] = []
    var diagnostics: [LottieLayerGraphDiagnostic] = []
    var nextRenderOrder = 0
    var precompositionStack: [String] = []

    init(animation: LottieAnimation, rootSourceFrame: Double) {
        self.animation = animation
        self.rootSourceFrame = rootSourceFrame
        frameEvaluator = LottieFrameEvaluator(animation: animation)
    }

    mutating func trace() -> LottieLayerGraphTrace {
        let frameWindow = LottieLayerGraphFrameWindowTrace(
            inPoint: animation.inPoint,
            outPoint: animation.outPoint,
            selectedFrame: rootSourceFrame,
            containsSelectedFrame: frameEvaluator.containsCompositionFrame(rootSourceFrame)
        )

        guard frameWindow.containsSelectedFrame else {
            diagnostics.append(LottieLayerGraphDiagnostic(
                ruleID: "lottie.evaluation.layer-graph.composition-window",
                severity: .note,
                classification: .metadata,
                reason: "Selected source frame is outside the root composition half-open frame window.",
                jsonPath: "$",
                evidence: frameWindow.rule
            ))
            return LottieLayerGraphTrace(
                sourceFrame: rootSourceFrame,
                frameWindow: frameWindow,
                records: [],
                diagnostics: diagnostics
            )
        }

        evaluateComposition(
            name: animation.name ?? "root",
            layers: animation.layers,
            sourceFrame: rootSourceFrame,
            compositionPath: "root",
            layersJsonPath: JSONPath([.key("layers")]),
            compositionStack: []
        )

        return LottieLayerGraphTrace(
            sourceFrame: rootSourceFrame,
            frameWindow: frameWindow,
            records: records,
            diagnostics: diagnostics
        )
    }

    private mutating func evaluateComposition(
        name: String,
        layers: [LottieLayer],
        sourceFrame: Double,
        compositionPath: String,
        layersJsonPath: JSONPath,
        compositionStack: [String]
    ) {
        let stack = compositionStack + [name]
        let references = graphReferences(in: layers, at: sourceFrame)

        for (offset, layer) in layers.enumerated().reversed() {
            let jsonPath = layersJsonPath.appending(.index(offset))
            let sourcePath = layerPath(in: compositionPath, layer: layer)
            let visibility = visibilityTrace(for: layer, at: sourceFrame)
            var recordDiagnostics: [LottieLayerGraphDiagnostic] = []
            let timing = timingTrace(for: layer, at: sourceFrame, path: jsonPath, sourcePath: sourcePath, diagnostics: &recordDiagnostics)
            let participation = participation(
                for: layer,
                visibility: visibility,
                offset: offset,
                references: references
            )
            let renderOrder = renderOrder(for: participation)
            let masks = maskTraces(
                layer.masks ?? [],
                at: timing.localFrame,
                targetLayerPath: sourcePath,
                targetJsonPath: jsonPath,
                diagnostics: &recordDiagnostics
            )
            let matte = matteTrace(
                for: layer,
                offset: offset,
                layers: layers,
                compositionPath: compositionPath,
                jsonPath: jsonPath,
                diagnostics: &recordDiagnostics
            )
            let precomposition = precompositionTrace(
                for: layer,
                localFrame: timing.localFrame,
                sourcePath: sourcePath
            )
            let parents = parentChain(
                for: layer,
                layers: layers,
                compositionPath: compositionPath,
                layersJsonPath: layersJsonPath,
                sourceFrame: sourceFrame,
                diagnostics: &recordDiagnostics
            )

            let record = LottieLayerGraphLayerTrace(
                sourcePath: sourcePath,
                jsonPath: jsonPath.description,
                compositionPath: compositionPath,
                compositionStack: stack,
                arrayOffset: offset,
                layerIndex: layer.index,
                name: layer.name,
                type: layerGraphType(for: layer),
                participation: participation,
                renderOrder: renderOrder,
                visibility: visibility,
                timing: timing,
                parentChain: parents,
                masks: masks,
                matte: matte,
                precomposition: precomposition,
                diagnostics: recordDiagnostics
            )
            records.append(record)
            diagnostics.append(contentsOf: recordDiagnostics)

            if shouldDescendIntoPrecomposition(layer, participation: participation),
               let referenceID = layer.referenceId
            {
                evaluatePrecomposition(
                    referenceID,
                    from: layer,
                    localFrame: timing.localFrame,
                    layerPath: sourcePath,
                    compositionStack: stack
                )
            }
        }
    }

    private mutating func evaluatePrecomposition(
        _ referenceID: String,
        from _: LottieLayer,
        localFrame: Double,
        layerPath: String,
        compositionStack: [String]
    ) {
        guard !precompositionStack.contains(referenceID) else {
            diagnostics.append(LottieLayerGraphDiagnostic(
                ruleID: "lottie.evaluation.layer-graph.precomposition.recursive",
                classification: .gap,
                reason: "Recursive precomposition references cannot be evaluated into a finite layer graph.",
                jsonPath: "$",
                sourcePath: layerPath,
                evidence: referenceID
            ))
            return
        }
        guard let assetIndex = animation.assets.firstIndex(where: { $0.id == referenceID }),
              let assetLayers = animation.assets[assetIndex].layers
        else {
            diagnostics.append(LottieLayerGraphDiagnostic(
                ruleID: "lottie.evaluation.layer-graph.precomposition.missing",
                classification: .gap,
                reason: "Precomposition layer references no modeled composition asset.",
                jsonPath: "$",
                sourcePath: layerPath,
                evidence: referenceID
            ))
            return
        }

        precompositionStack.append(referenceID)
        evaluateComposition(
            name: "precomp:\(referenceID)",
            layers: assetLayers,
            sourceFrame: localFrame,
            compositionPath: "\(layerPath) > precomp '\(referenceID)'",
            layersJsonPath: JSONPath([.key("assets"), .index(assetIndex), .key("layers")]),
            compositionStack: compositionStack
        )
        precompositionStack.removeLast()
    }

    private func graphReferences(in layers: [LottieLayer], at sourceFrame: Double) -> LayerGraphReferences {
        var parentOffsets = Set<Int>()
        var matteSourceOffsets = Set<Int>()
        let byIndex = indexedLayers(layers)

        for (offset, layer) in layers.enumerated() where ordinaryContentVisible(layer, at: sourceFrame) {
            var parentCursor = layer.parent
            var visited: Set<Int> = []
            while let parentIndex = parentCursor,
                  let parent = byIndex[parentIndex],
                  visited.insert(parentIndex).inserted
            {
                parentOffsets.insert(parent.offset)
                parentCursor = parent.layer.parent
            }

            guard let matteMode = layer.trackMatteType, matteMode != 0 else { continue }
            let sourceOffset: Int? = if let explicitIndex = layer.trackMatteParent {
                byIndex[explicitIndex]?.offset
            } else {
                layers.indices.contains(offset - 1) ? offset - 1 : nil
            }
            guard let sourceOffset else { continue }
            matteSourceOffsets.insert(sourceOffset)
        }

        return LayerGraphReferences(parentOffsets: parentOffsets, matteSourceOffsets: matteSourceOffsets)
    }

    private func visibilityTrace(for layer: LottieLayer, at sourceFrame: Double) -> LottieLayerGraphVisibilityTrace {
        let containsFrame = LottieFrameWindow(inPoint: layer.inPoint, outPoint: layer.outPoint).contains(sourceFrame)
        return LottieLayerGraphVisibilityTrace(
            selectedFrame: sourceFrame,
            inPoint: layer.inPoint,
            outPoint: layer.outPoint,
            isHidden: layer.isHidden,
            containsFrame: containsFrame,
            ordinaryContentVisible: containsFrame && !layer.isHidden
        )
    }

    private func ordinaryContentVisible(_ layer: LottieLayer, at sourceFrame: Double) -> Bool {
        !layer.isHidden && LottieFrameWindow(inPoint: layer.inPoint, outPoint: layer.outPoint).contains(sourceFrame)
    }

    private mutating func renderOrder(for participation: LottieLayerGraphParticipation) -> Int? {
        guard participation.participatesInRenderGraph else { return nil }
        let order = nextRenderOrder
        nextRenderOrder += 1
        return order
    }

    private func participation(
        for layer: LottieLayer,
        visibility: LottieLayerGraphVisibilityTrace,
        offset: Int,
        references: LayerGraphReferences
    ) -> LottieLayerGraphParticipation {
        if references.matteSourceOffsets.contains(offset) {
            return layer.isHidden ? .hiddenMatteSource : .matteSource
        }
        if references.parentOffsets.contains(offset) {
            if layer.isHidden {
                return .hiddenParent
            }
            if !visibility.containsFrame {
                return .transformParticipant
            }
        }
        if layer.isHidden {
            return .skippedHidden
        }
        guard visibility.containsFrame else {
            return .skippedOutsideFrame
        }
        if layer.type == .null {
            return .transformCarrier
        }
        if layer.type == .precomposition {
            return .precompositionBoundary
        }
        return .content
    }

    private func timingTrace(
        for layer: LottieLayer,
        at inputFrame: Double,
        path: JSONPath,
        sourcePath: String,
        diagnostics: inout [LottieLayerGraphDiagnostic]
    ) -> LottieLayerGraphTimingTrace {
        if let timeRemap = layer.timeRemap, !LottieFaultInjector.isActive(.skippedPrecompTimeRemap) {
            let result = frameEvaluator.evaluate(
                timeRemap,
                at: inputFrame,
                path: path.appending(.key("tm")),
                offsetFrame: layer.startTime
            )
            appendDiagnostics(
                result.diagnostics,
                sourcePath: sourcePath,
                targetPath: nil,
                into: &diagnostics
            )
            var frame = result.value * animation.frameRate
            if frame == layer.outPoint {
                frame = layer.outPoint - 1
            }
            return LottieLayerGraphTimingTrace(
                mode: .timeRemapSeconds,
                inputFrame: inputFrame,
                startTime: layer.startTime,
                stretch: layer.stretch,
                frameRate: animation.frameRate,
                localFrame: frame,
                timeRemapSeconds: result.value,
                timeRemapPropertyTrace: result.trace
            )
        }

        guard abs(layer.stretch) > 0.0001 else {
            diagnostics.append(LottieLayerGraphDiagnostic(
                ruleID: "lottie.evaluation.layer-graph.layer-stretch.nonzero",
                classification: .gap,
                reason: "Layer stretch `sr` must be non-zero before local frame evaluation.",
                jsonPath: path.appending(.key("sr")).description,
                sourcePath: sourcePath
            ))
            return LottieLayerGraphTimingTrace(
                mode: .invalidStretch,
                inputFrame: inputFrame,
                startTime: layer.startTime,
                stretch: layer.stretch,
                frameRate: animation.frameRate,
                localFrame: 0
            )
        }

        return LottieLayerGraphTimingTrace(
            mode: .startTimeAndStretch,
            inputFrame: inputFrame,
            startTime: layer.startTime,
            stretch: layer.stretch,
            frameRate: animation.frameRate,
            localFrame: (inputFrame - layer.startTime) / layer.stretch
        )
    }

    private func parentChain(
        for layer: LottieLayer,
        layers: [LottieLayer],
        compositionPath: String,
        layersJsonPath: JSONPath,
        sourceFrame: Double,
        diagnostics: inout [LottieLayerGraphDiagnostic]
    ) -> [LottieLayerGraphParentTrace] {
        let byIndex = indexedLayers(layers)
        var chain: [LottieLayerGraphParentTrace] = []
        var cursor = layer.parent
        var visited: Set<Int> = []

        while let parentIndex = cursor {
            guard let parent = byIndex[parentIndex] else {
                diagnostics.append(LottieLayerGraphDiagnostic(
                    ruleID: "lottie.evaluation.layer-graph.parent.missing",
                    classification: .gap,
                    reason: "Layer parent index `\(parentIndex)` does not resolve inside this composition.",
                    jsonPath: layersJsonPath.description,
                    sourcePath: layerPath(in: compositionPath, layer: layer),
                    evidence: "\(parentIndex)"
                ))
                return chain
            }
            guard visited.insert(parentIndex).inserted else {
                diagnostics.append(LottieLayerGraphDiagnostic(
                    ruleID: "lottie.evaluation.layer-graph.parent.cycle",
                    classification: .gap,
                    reason: "Layer parent transform chain must be acyclic before evaluation.",
                    jsonPath: layersJsonPath.appending(.index(parent.offset)).appending(.key("parent")).description,
                    sourcePath: layerPath(in: compositionPath, layer: parent.layer)
                ))
                return chain
            }
            chain.append(LottieLayerGraphParentTrace(
                layerIndex: parentIndex,
                sourcePath: layerPath(in: compositionPath, layer: parent.layer),
                jsonPath: layersJsonPath.appending(.index(parent.offset)).description,
                isHidden: parent.layer.isHidden,
                containsFrame: LottieFrameWindow(inPoint: parent.layer.inPoint, outPoint: parent.layer.outPoint).contains(sourceFrame)
            ))
            cursor = parent.layer.parent
        }

        return chain
    }

    private func maskTraces(
        _ masks: [LottieMask],
        at localFrame: Double,
        targetLayerPath: String,
        targetJsonPath: JSONPath,
        diagnostics: inout [LottieLayerGraphDiagnostic]
    ) -> [LottieLayerGraphMaskTrace] {
        masks.enumerated().map { offset, mask in
            let jsonPath = targetJsonPath.appending(.key("masksProperties")).appending(.index(offset))
            let sourcePath = "\(targetLayerPath) > mask '\(mask.name ?? "?")'"
            var maskDiagnostics: [LottieLayerGraphDiagnostic] = [
                LottieLayerGraphDiagnostic(
                    ruleID: "lottie.evaluation.layer-graph.mask.edge",
                    severity: .note,
                    classification: .metadata,
                    reason: "Layer mask source and target are recorded before backend lowering.",
                    jsonPath: jsonPath.description,
                    sourcePath: sourcePath,
                    targetPath: targetLayerPath
                ),
            ]

            let path = frameEvaluator.evaluate(mask.path, at: localFrame, path: jsonPath.appending(.key("pt")))
            appendDiagnostics(path.diagnostics, sourcePath: sourcePath, targetPath: targetLayerPath, into: &maskDiagnostics)
            let opacity: Double
            if let maskOpacity = mask.opacity {
                let result = frameEvaluator.evaluate(maskOpacity, at: localFrame, path: jsonPath.appending(.key("o")))
                appendDiagnostics(result.diagnostics, sourcePath: sourcePath, targetPath: targetLayerPath, into: &maskDiagnostics)
                opacity = clamp(result.value / 100)
            } else {
                opacity = 1
            }

            if mask.mode != "a" {
                maskDiagnostics.append(LottieLayerGraphDiagnostic(
                    ruleID: "lottie.evaluation.layer-graph.mask.mode",
                    classification: .reported,
                    reason: "Mask modes other than additive must remain explicit before backend lowering.",
                    jsonPath: jsonPath.appending(.key("mode")).description,
                    sourcePath: sourcePath,
                    targetPath: targetLayerPath,
                    evidence: mask.mode
                ))
            }
            if mask.isInverted {
                maskDiagnostics.append(LottieLayerGraphDiagnostic(
                    ruleID: "lottie.evaluation.layer-graph.mask.inverted",
                    classification: .reported,
                    reason: "Inverted masks must remain explicit before backend lowering.",
                    jsonPath: jsonPath.appending(.key("inv")).description,
                    sourcePath: sourcePath,
                    targetPath: targetLayerPath
                ))
            }

            diagnostics.append(contentsOf: maskDiagnostics)
            return LottieLayerGraphMaskTrace(
                sourcePath: sourcePath,
                jsonPath: jsonPath.description,
                targetLayerPath: targetLayerPath,
                targetLayerJsonPath: targetJsonPath.description,
                name: mask.name,
                mode: mask.mode,
                inverted: mask.isInverted,
                opacity: opacity,
                path: path.value.map(pathTrace),
                diagnostics: maskDiagnostics
            )
        }
    }

    private func matteTrace(
        for layer: LottieLayer,
        offset: Int,
        layers: [LottieLayer],
        compositionPath: String,
        jsonPath: JSONPath,
        diagnostics: inout [LottieLayerGraphDiagnostic]
    ) -> LottieLayerGraphMatteTrace? {
        guard let mode = layer.trackMatteType, mode != 0 else { return nil }

        let sourceOffset: Int?
        let sourceIndex: Int?
        let explicit: Bool
        if let explicitIndex = layer.trackMatteParent {
            sourceOffset = layers.firstIndex { $0.index == explicitIndex }
            sourceIndex = explicitIndex
            explicit = true
        } else {
            sourceOffset = layers.indices.contains(offset - 1) ? offset - 1 : nil
            sourceIndex = sourceOffset.flatMap { layers[$0].index }
            explicit = false
        }

        let sourceLayer = sourceOffset.map { layers[$0] }
        let sourcePath = sourceLayer.map { layerPath(in: compositionPath, layer: $0) }
        let sourceJsonPath = sourceOffset.map { siblingLayerJsonPath(from: jsonPath, offset: $0).description }
        var matteDiagnostics: [LottieLayerGraphDiagnostic] = [
            LottieLayerGraphDiagnostic(
                ruleID: "lottie.evaluation.layer-graph.matte.edge",
                severity: .note,
                classification: .metadata,
                reason: "Track matte source and target are recorded before backend lowering.",
                jsonPath: jsonPath.appending(.key("tt")).description,
                sourcePath: sourcePath,
                targetPath: layerPath(in: compositionPath, layer: layer),
                evidence: "mode=\(mode)"
            ),
        ]

        if sourceLayer == nil {
            matteDiagnostics.append(LottieLayerGraphDiagnostic(
                ruleID: "lottie.evaluation.layer-graph.matte.missing-source",
                classification: .gap,
                reason: "Track matte source layer must resolve before compositing can be evaluated.",
                jsonPath: jsonPath.appending(.key(explicit ? "tp" : "tt")).description,
                sourcePath: nil,
                targetPath: layerPath(in: compositionPath, layer: layer),
                evidence: sourceIndex.map(String.init)
            ))
        }

        diagnostics.append(contentsOf: matteDiagnostics)
        return LottieLayerGraphMatteTrace(
            mode: mode,
            sourceLayerIndex: sourceIndex,
            sourceLayerPath: sourcePath,
            sourceLayerJsonPath: sourceJsonPath,
            targetLayerPath: layerPath(in: compositionPath, layer: layer),
            targetLayerJsonPath: jsonPath.description,
            explicitSource: explicit,
            sourceResolved: sourceLayer != nil,
            diagnostics: matteDiagnostics
        )
    }

    private func precompositionTrace(
        for layer: LottieLayer,
        localFrame: Double,
        sourcePath: String
    ) -> LottieLayerGraphPrecompositionTrace? {
        guard layer.type == .precomposition, let referenceID = layer.referenceId else { return nil }
        let assetIndex = animation.assets.firstIndex { $0.id == referenceID }
        let asset = assetIndex.map { animation.assets[$0] }
        return LottieLayerGraphPrecompositionTrace(
            assetID: referenceID,
            assetJsonPath: assetIndex.map { JSONPath([.key("assets"), .index($0)]).description },
            compositionPath: "\(sourcePath) > precomp '\(referenceID)'",
            localFrame: localFrame,
            width: layer.width ?? asset?.width ?? animation.width,
            height: layer.height ?? asset?.height ?? animation.height,
            childLayerCount: asset?.layers?.count ?? 0
        )
    }

    private func shouldDescendIntoPrecomposition(
        _ layer: LottieLayer,
        participation: LottieLayerGraphParticipation
    ) -> Bool {
        guard layer.type == .precomposition else { return false }
        switch participation {
        case .precompositionBoundary,
             .matteSource,
             .hiddenMatteSource:
            return true
        case .content,
             .transformCarrier,
             .hiddenParent,
             .transformParticipant,
             .skippedHidden,
             .skippedOutsideFrame:
            return false
        }
    }

    private func appendDiagnostics(
        _ errors: [ValidationError],
        sourcePath: String?,
        targetPath: String?,
        into diagnostics: inout [LottieLayerGraphDiagnostic]
    ) {
        diagnostics.append(contentsOf: errors.map { error in
            LottieLayerGraphDiagnostic(
                ruleID: error.ruleID,
                severity: graphSeverity(error.severity),
                classification: graphClassification(error.classification),
                reason: error.reason,
                jsonPath: error.codingPath.description,
                sourcePath: sourcePath ?? error.evidence,
                targetPath: targetPath,
                evidence: error.evidence
            )
        })
    }

    private func layerGraphType(for layer: LottieLayer) -> LottieLayerGraphLayerType {
        switch layer.type {
        case .precomposition:
            .precomposition
        case .solid:
            .solid
        case .image:
            .image
        case .null:
            .null
        case .shape:
            .shape
        case .text:
            .text
        case .none:
            .unsupported
        }
    }

    private func indexedLayers(_ layers: [LottieLayer]) -> [Int: IndexedLayer] {
        Dictionary(
            layers.enumerated().compactMap { offset, layer in
                layer.index.map { ($0, IndexedLayer(layer: layer, offset: offset)) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func layerPath(in compositionPath: String, layer: LottieLayer) -> String {
        "\(compositionPath) > layer '\(layer.name ?? "?")'"
    }

    private func siblingLayerJsonPath(from path: JSONPath, offset: Int) -> JSONPath {
        var components = path.components
        if !components.isEmpty {
            components.removeLast()
        }
        components.append(.index(offset))
        return JSONPath(components)
    }

    private func pathTrace(for bezier: LottieBezier) -> LottieLayerGraphPathTrace {
        LottieLayerGraphPathTrace(
            closed: bezier.isClosed,
            vertices: bezier.vertices,
            inTangents: bezier.inTangents,
            outTangents: bezier.outTangents
        )
    }

    private func graphSeverity(_ severity: ValidationSeverity) -> LottieLayerGraphDiagnosticSeverity {
        switch severity {
        case .error:
            .error
        case .warning:
            .warning
        case .note:
            .note
        }
    }

    private func graphClassification(_ classification: FeatureClassification) -> LottieLayerGraphFeatureClassification {
        switch classification {
        case .exact:
            .exact
        case .approximate:
            .approximate
        case .reported:
            .reported
        case .metadata:
            .metadata
        case .gap:
            .gap
        }
    }
}

private struct IndexedLayer {
    var layer: LottieLayer
    var offset: Int
}

private struct LayerGraphReferences {
    var parentOffsets: Set<Int>
    var matteSourceOffsets: Set<Int>
}

private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
