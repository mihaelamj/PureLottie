//
//  LottieCompositionVM.swift
//  PureLottie
//

import Foundation
import LottieModel

/// Stable identifier assigned to a VM-emitted render node for one execution.
///
/// The id is deterministic within a single `run(at:mode:)` call and names the
/// render-intent placeholder that future RenderIR/PureLayer lowering can map.
public struct LottieRenderNodeID: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The 1-based render-node sequence number.
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: LottieRenderNodeID, rhs: LottieRenderNodeID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        "render#\(rawValue)"
    }
}

/// Controls how much trace data the composition VM records.
public enum LottieVMTraceMode: String, Sendable {
    /// Records structural execution plus debug-only value evaluation records.
    case debug
    /// Records structural execution and render-node decisions only.
    case fast
}

/// One operation in the domain-specific Lottie composition VM.
///
/// Instructions are semantic operations, not bytecode for a general runtime.
/// They are intentionally named after Lottie traversal concepts so an IDE can
/// expose step-in/step-over behavior without inspecting recursive Swift calls.
public struct LottieVMInstruction: Sendable, Equatable {
    /// The operation category for one VM trace step.
    public enum Kind: String, Sendable {
        case enterComposition
        case leaveComposition
        case enterLayer
        case leaveLayer
        case evaluateLocalFrame
        case evaluateTransform
        case enterGroup
        case leaveGroup
        case pushStyle
        case popStyle
        case applyModifier
        case enterMatte
        case leaveMatte
        case enterPrecomposition
        case leavePrecomposition
        case emitRenderNode
        case semanticDecision
        case skipLayer
    }

    /// Instruction category.
    public var kind: Kind
    /// Human-readable display label, usually the layer, style, or asset name.
    public var label: String

    public init(kind: Kind, label: String = "") {
        self.kind = kind
        self.label = label
    }
}

/// The visible VM stack state after a trace step.
///
/// This is the state an IDE debugger needs for step-back and inspection:
/// source frame, composition/layer ancestry, shape transform/style context,
/// opacity/matte context, and the current source path.
public struct LottieVMState: Sendable, Equatable {
    /// Selected Lottie source frame, not seconds.
    public var frameClock: Double
    /// Active root/precomposition stack.
    public var compositionStack: [String]
    /// Active layer source paths.
    public var layerStack: [String]
    /// Active shape transform source paths.
    public var transformStack: [String]
    /// Active style source paths.
    public var styleStack: [String]
    /// Active atomic opacity/compositing contexts.
    public var opacityStack: [String]
    /// Active mask or matte source paths.
    public var matteStack: [String]
    /// Current human-readable Lottie source path.
    public var sourcePath: String

    public init(
        frameClock: Double,
        compositionStack: [String] = [],
        layerStack: [String] = [],
        transformStack: [String] = [],
        styleStack: [String] = [],
        opacityStack: [String] = [],
        matteStack: [String] = [],
        sourcePath: String = "root"
    ) {
        self.frameClock = frameClock
        self.compositionStack = compositionStack
        self.layerStack = layerStack
        self.transformStack = transformStack
        self.styleStack = styleStack
        self.opacityStack = opacityStack
        self.matteStack = matteStack
        self.sourcePath = sourcePath
    }
}

/// One recorded VM step, including source identity and evaluated values.
public struct LottieVMTraceRecord: Sendable, Equatable, CustomStringConvertible {
    /// Zero-based trace step.
    public var step: Int
    /// VM operation executed at this step.
    public var instruction: LottieVMInstruction
    /// Human-readable source path, such as `root > layer 'Badge'`.
    public var sourcePath: String
    /// Authored Lottie JSON path when available.
    public var jsonPath: JSONPath
    /// Source text range when the parsed source retained one.
    public var sourceRange: SourceRange?
    /// Evaluated scalar/vector facts rendered as stable debugger strings.
    public var evaluatedValues: [String: String]
    /// Render node emitted by this step, if any.
    public var renderNodeID: LottieRenderNodeID?
    /// VM stack state after this step.
    public var state: LottieVMState

    public init(
        step: Int,
        instruction: LottieVMInstruction,
        sourcePath: String,
        jsonPath: JSONPath,
        sourceRange: SourceRange? = nil,
        evaluatedValues: [String: String] = [:],
        renderNodeID: LottieRenderNodeID? = nil,
        state: LottieVMState
    ) {
        self.step = step
        self.instruction = instruction
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.sourceRange = sourceRange
        self.evaluatedValues = evaluatedValues
        self.renderNodeID = renderNodeID
        self.state = state
    }

    public var description: String {
        var parts = [
            "#\(step)",
            instruction.kind.rawValue,
            sourcePath,
        ]
        if !instruction.label.isEmpty {
            parts.append("label=\(instruction.label)")
        }
        if let renderNodeID {
            parts.append(renderNodeID.description)
        }
        if !evaluatedValues.isEmpty {
            let values = evaluatedValues
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
            parts.append("{\(values)}")
        }
        return parts.joined(separator: " | ")
    }
}

/// Snapshot of VM stack state retained for practical step-back.
public struct LottieVMCheckpoint: Sendable, Equatable {
    /// Trace step at which the checkpoint was captured.
    public var step: Int
    /// VM stack state after `step`.
    public var state: LottieVMState

    public init(step: Int, state: LottieVMState) {
        self.step = step
        self.state = state
    }
}

/// Result of executing the composition VM for one selected source frame.
public struct LottieVMResult: Sendable, Equatable {
    /// Trace mode used for this run.
    public var mode: LottieVMTraceMode
    /// Ordered trace records produced by the run.
    public var trace: [LottieVMTraceRecord]
    /// Periodic state checkpoints for debugger step-back.
    public var checkpoints: [LottieVMCheckpoint]
    /// Semantic diagnostics collected during VM execution.
    public var diagnostics: [ValidationError]

    public init(
        mode: LottieVMTraceMode,
        trace: [LottieVMTraceRecord],
        checkpoints: [LottieVMCheckpoint],
        diagnostics: [ValidationError]
    ) {
        self.mode = mode
        self.trace = trace
        self.checkpoints = checkpoints
        self.diagnostics = diagnostics
    }

    /// Unique render node ids in first-emission order.
    public var renderNodeIDs: [LottieRenderNodeID] {
        trace.compactMap(\.renderNodeID).uniqued()
    }

    /// Newline-delimited human-readable trace for diagnostics and tests.
    public var readableTrace: String {
        trace.map(\.description).joined(separator: "\n")
    }

    /// Returns the most recent state at or before `step`.
    public func state(after step: Int) -> LottieVMState? {
        trace.last { $0.step <= step }?.state
    }

    /// Returns the most recent checkpoint at or before `step`.
    public func checkpoint(beforeOrAt step: Int) -> LottieVMCheckpoint? {
        checkpoints.last { $0.step <= step }
    }
}

/// Deterministic source-frame VM for Lottie semantic execution.
///
/// The VM is intentionally domain-specific: it makes composition traversal,
/// layer decisions, shape-program execution, evaluated values, and placeholder
/// render-node emission explicit for debugging and future IDE stepping. It does
/// not import or construct PureLayer/PureDraw objects.
public struct LottieCompositionVM: Sendable {
    /// Animation decoded from Lottie source.
    public var animation: LottieAnimation
    /// Trace checkpoint cadence, clamped to at least 1.
    public var checkpointInterval: Int

    public init(animation: LottieAnimation, checkpointInterval: Int = 8) {
        self.animation = animation
        self.checkpointInterval = max(checkpointInterval, 1)
    }

    /// Executes the VM for one Lottie source frame.
    public func run(at sourceFrame: Double, mode: LottieVMTraceMode = .debug) -> LottieVMResult {
        var executor = LottieVMExecutor(
            animation: animation,
            sourceFrame: sourceFrame,
            mode: mode,
            checkpointInterval: checkpointInterval
        )
        executor.run()
        return executor.result()
    }
}

private struct LottieVMExecutor {
    let animation: LottieAnimation
    let frameEvaluator: LottieFrameEvaluator
    let transformEvaluator: LottieTransformEvaluator
    let sourceFrame: Double
    let mode: LottieVMTraceMode
    let checkpointInterval: Int
    var state: LottieVMState
    var trace: [LottieVMTraceRecord] = []
    var checkpoints: [LottieVMCheckpoint] = []
    var diagnostics: [ValidationError] = []
    var nextRenderNodeID = 1
    var precompositionStack: [String] = []

    init(animation: LottieAnimation, sourceFrame: Double, mode: LottieVMTraceMode, checkpointInterval: Int) {
        self.animation = animation
        frameEvaluator = LottieFrameEvaluator(animation: animation)
        transformEvaluator = LottieTransformEvaluator(animation: animation)
        self.sourceFrame = sourceFrame
        self.mode = mode
        self.checkpointInterval = checkpointInterval
        state = LottieVMState(frameClock: sourceFrame)
    }

    mutating func run() {
        executeComposition(
            name: animation.name ?? "root",
            layers: animation.layers,
            path: "root",
            jsonPath: JSONPath([.key("layers")])
        )
    }

    func result() -> LottieVMResult {
        LottieVMResult(
            mode: mode,
            trace: trace,
            checkpoints: checkpoints,
            diagnostics: diagnostics
        )
    }

    private mutating func executeComposition(name: String, layers: [LottieLayer], path: String, jsonPath: JSONPath) {
        state.compositionStack.append(name)
        state.sourcePath = path
        record(.init(kind: .enterComposition, label: name), sourcePath: path, jsonPath: jsonPath)

        for (offset, layer) in layers.enumerated().reversed() {
            executeLayer(
                layer,
                layers: layers,
                path: "\(path) > layer '\(layer.name ?? "?")'",
                jsonPath: jsonPath.appending(.index(offset))
            )
        }

        state.sourcePath = path
        record(.init(kind: .leaveComposition, label: name), sourcePath: path, jsonPath: jsonPath)
        state.compositionStack.removeLast()
    }

    private mutating func executeLayer(_ layer: LottieLayer, layers: [LottieLayer], path: String, jsonPath: JSONPath) {
        guard !layer.isHidden else {
            record(
                .init(kind: .skipLayer, label: layer.name ?? "?"),
                sourcePath: path,
                jsonPath: jsonPath,
                values: ["reason": "hidden"]
            )
            return
        }
        guard frameEvaluator.isLayerVisible(layer, at: sourceFrame) else {
            record(
                .init(kind: .skipLayer, label: layer.name ?? "?"),
                sourcePath: path,
                jsonPath: jsonPath,
                values: [
                    "reason": "outsideFrameWindow",
                    "ip": number(layer.inPoint),
                    "op": number(layer.outPoint),
                ]
            )
            return
        }

        state.layerStack.append(path)
        state.transformStack.append("\(path) > transform")
        state.sourcePath = path
        record(
            .init(kind: .enterLayer, label: layer.name ?? "?"),
            sourcePath: path,
            jsonPath: jsonPath,
            values: ["type": "\(layer.rawType)"]
        )

        evaluateTimingAndTransform(layer, layers: layers, path: path, jsonPath: jsonPath)
        executeMasks(layer.masks ?? [], path: path, jsonPath: jsonPath.appending(.key("masksProperties")))

        switch layer.type {
        case .shape:
            executeShapeLayer(layer, path: path, jsonPath: jsonPath)
        case .solid:
            emitRenderNode(
                label: "solid",
                sourcePath: path,
                jsonPath: jsonPath,
                values: [
                    "color": layer.solidColor ?? "#000000",
                    "width": number(layer.solidWidth ?? 0),
                    "height": number(layer.solidHeight ?? 0),
                ]
            )
        case .null:
            record(.init(kind: .semanticDecision, label: "null layer has no pixels"), sourcePath: path, jsonPath: jsonPath)
        case .precomposition:
            executePrecomposition(layer, path: path, jsonPath: jsonPath)
        default:
            record(
                .init(kind: .semanticDecision, label: "unsupported layer"),
                sourcePath: path,
                jsonPath: jsonPath,
                values: ["type": "\(layer.rawType)"]
            )
        }

        state.sourcePath = path
        record(.init(kind: .leaveLayer, label: layer.name ?? "?"), sourcePath: path, jsonPath: jsonPath)
        state.transformStack.removeLast()
        state.layerStack.removeLast()
    }

    private mutating func evaluateTimingAndTransform(_ layer: LottieLayer, layers: [LottieLayer], path: String, jsonPath: JSONPath) {
        let localFrame = frameEvaluator.localFrame(for: layer, at: sourceFrame, path: jsonPath)
        diagnostics.append(contentsOf: localFrame.diagnostics)
        record(
            .init(kind: .evaluateLocalFrame, label: layer.name ?? "?"),
            sourcePath: path,
            jsonPath: jsonPath,
            values: ["localFrame": number(localFrame.value)],
            debugOnly: true
        )

        let transform = transformEvaluator.worldTransform(for: layer, in: layers, at: sourceFrame, path: jsonPath)
        diagnostics.append(contentsOf: transform.diagnostics)
        let matrix = transform.value.matrix.values.prefix(16).map(number).joined(separator: ",")
        record(
            .init(kind: .evaluateTransform, label: layer.name ?? "?"),
            sourcePath: path,
            jsonPath: jsonPath.appending(.key("ks")),
            values: [
                "matrix": matrix,
                "position": vector(transform.value.position),
                "rotationZ": number(transform.value.rotationZDegrees),
            ],
            debugOnly: true
        )
    }

    private mutating func executeMasks(_ masks: [LottieMask], path: String, jsonPath: JSONPath) {
        for (offset, mask) in masks.enumerated() {
            let maskPath = "\(path) > mask '\(mask.name ?? "?")'"
            let itemPath = jsonPath.appending(.index(offset))
            state.matteStack.append(maskPath)
            record(
                .init(kind: .enterMatte, label: mask.name ?? "?"),
                sourcePath: maskPath,
                jsonPath: itemPath,
                values: ["mode": mask.mode, "inverted": "\(mask.isInverted)"]
            )
            record(.init(kind: .leaveMatte, label: mask.name ?? "?"), sourcePath: maskPath, jsonPath: itemPath)
            state.matteStack.removeLast()
        }
    }

    private mutating func executeShapeLayer(_ layer: LottieLayer, path: String, jsonPath: JSONPath) {
        let program = LottieShapeProgramBuilder().program(
            for: layer.shapes ?? [],
            sourcePath: path,
            jsonPath: jsonPath.appending(.key("shapes"))
        )
        diagnostics.append(contentsOf: program.diagnostics)
        for diagnostic in program.diagnostics {
            record(
                .init(kind: .semanticDecision, label: diagnostic.reason),
                sourcePath: diagnostic.evidence ?? path,
                jsonPath: diagnostic.codingPath,
                values: [
                    "rule": diagnostic.ruleID,
                    "classification": diagnostic.classification.rawValue,
                ],
                sourceRange: diagnostic.range,
                debugOnly: true
            )
        }
        executeShapeNodes(program.nodes)
    }

    private mutating func executeShapeNodes(_ nodes: [LottieShapeProgram.Node]) {
        for node in nodes {
            switch node {
            case let .styleRun(run):
                state.styleStack.append(run.sourcePath)
                record(
                    .init(kind: .pushStyle, label: styleName(run.style)),
                    sourcePath: run.sourcePath,
                    jsonPath: run.jsonPath,
                    values: ["fragments": "\(run.fragments.count)"]
                )
                recordModifiers(in: run)
                emitRenderNode(
                    label: "shape.\(styleName(run.style))",
                    sourcePath: run.sourcePath,
                    jsonPath: run.jsonPath,
                    values: [
                        "fragments": "\(run.fragments.count)",
                        "modifiers": "\(run.fragments.flatMap(\.modifiers).count)",
                    ]
                )
                record(.init(kind: .popStyle, label: styleName(run.style)), sourcePath: run.sourcePath, jsonPath: run.jsonPath)
                state.styleStack.removeLast()
            case let .group(group):
                state.transformStack.append(contentsOf: groupTransformLabels(group))
                if group.compositing == .atomicTransparency {
                    state.opacityStack.append(group.sourcePath)
                }
                record(
                    .init(kind: .enterGroup, label: group.sourcePath),
                    sourcePath: group.sourcePath,
                    jsonPath: group.jsonPath,
                    values: [
                        "compositing": group.compositing.rawValue,
                        "opacity": group.opacity.map { number($0.initialValue) } ?? "100",
                    ]
                )
                executeShapeNodes(group.nodes)
                record(.init(kind: .leaveGroup, label: group.sourcePath), sourcePath: group.sourcePath, jsonPath: group.jsonPath)
                if group.compositing == .atomicTransparency {
                    state.opacityStack.removeLast()
                }
                state.transformStack.removeLast(groupTransformLabels(group).count)
            }
        }
    }

    private mutating func recordModifiers(in run: LottieShapeProgram.StyleRun) {
        for fragment in run.fragments {
            for modifier in fragment.modifiers {
                switch modifier {
                case let .trim(applied):
                    record(
                        .init(kind: .applyModifier, label: "trim"),
                        sourcePath: applied.sourcePath,
                        jsonPath: applied.jsonPath,
                        values: [
                            "target": fragment.sourcePath,
                            "start": number(applied.trim.start.initialValue),
                            "end": number(applied.trim.end.initialValue),
                            "offset": number(applied.trim.offset?.initialValue ?? 0),
                        ]
                    )
                }
            }
        }
    }

    private mutating func executePrecomposition(_ layer: LottieLayer, path: String, jsonPath: JSONPath) {
        guard let referenceId = layer.referenceId,
              let asset = animation.precomposition(id: referenceId),
              let assetLayers = asset.layers
        else {
            record(.init(kind: .semanticDecision, label: "missing precomposition"), sourcePath: path, jsonPath: jsonPath)
            return
        }
        guard !precompositionStack.contains(referenceId) else {
            record(.init(kind: .semanticDecision, label: "recursive precomposition"), sourcePath: path, jsonPath: jsonPath)
            return
        }

        precompositionStack.append(referenceId)
        record(.init(kind: .enterPrecomposition, label: referenceId), sourcePath: path, jsonPath: jsonPath)
        let assetIndex = animation.assets.firstIndex { $0.id == referenceId } ?? 0
        executeComposition(
            name: "precomp:\(referenceId)",
            layers: assetLayers,
            path: "\(path) > precomp '\(referenceId)'",
            jsonPath: JSONPath([.key("assets"), .index(assetIndex), .key("layers")])
        )
        record(.init(kind: .leavePrecomposition, label: referenceId), sourcePath: path, jsonPath: jsonPath)
        precompositionStack.removeLast()
    }

    private mutating func emitRenderNode(label: String, sourcePath: String, jsonPath: JSONPath, values: [String: String]) {
        let id = LottieRenderNodeID(rawValue: nextRenderNodeID)
        nextRenderNodeID += 1
        record(
            .init(kind: .emitRenderNode, label: label),
            sourcePath: sourcePath,
            jsonPath: jsonPath,
            values: values,
            renderNodeID: id
        )
    }

    private mutating func record(
        _ instruction: LottieVMInstruction,
        sourcePath: String,
        jsonPath: JSONPath,
        values: [String: String] = [:],
        renderNodeID: LottieRenderNodeID? = nil,
        sourceRange: SourceRange? = nil,
        debugOnly: Bool = false
    ) {
        guard mode == .debug || !debugOnly else { return }
        state.sourcePath = sourcePath
        let record = LottieVMTraceRecord(
            step: trace.count,
            instruction: instruction,
            sourcePath: sourcePath,
            jsonPath: jsonPath,
            sourceRange: sourceRange,
            evaluatedValues: values,
            renderNodeID: renderNodeID,
            state: state
        )
        trace.append(record)
        if record.step.isMultiple(of: checkpointInterval) {
            checkpoints.append(LottieVMCheckpoint(step: record.step, state: state))
        }
    }

    private func styleName(_ style: LottieShapeProgram.Style) -> String {
        switch style {
        case .fill:
            "fill"
        case .stroke:
            "stroke"
        }
    }

    private func groupTransformLabels(_ group: LottieShapeProgram.Group) -> [String] {
        guard group.transform != nil else { return [] }
        return ["\(group.sourcePath) > transform"]
    }

    private func number(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.6g", value)
    }

    private func vector(_ values: [Double]) -> String {
        "[\(values.map(number).joined(separator: ","))]"
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
