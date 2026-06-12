//
//  LottieRenderIR.swift
//  PureLottie
//

import LottieModel

/// One evaluated source frame, expressed without any PureLayer or PureDraw
/// dependency.
public struct LottieRenderFrame: Sendable, Equatable {
    /// Selected Lottie source frame.
    public var sourceFrame: Double
    /// Root composition frame rate.
    public var frameRate: Double
    /// Root composition width in points.
    public var width: Double
    /// Root composition height in points.
    public var height: Double
    /// Measured source layer graph facts for this frame.
    public var layerGraph: LottieLayerGraphTrace
    /// Back-to-front render nodes visible at `sourceFrame`.
    public var nodes: [LottieRenderNode]
    /// Semantic diagnostics found while evaluating this frame.
    public var diagnostics: [ValidationError]
}

/// Source provenance retained on every RenderIR node and draw term.
public struct LottieRenderSource: Sendable, Equatable {
    /// Human-readable source path, such as `root > layer 'Shape'`.
    public var sourcePath: String
    /// Authored Lottie JSON path.
    public var jsonPath: JSONPath
    /// Source range when available from a source-ranged document.
    public var sourceRange: SourceRange?
}

/// VM/debug identity for a RenderIR node.
public struct LottieRenderTraceIdentity: Sendable, Equatable {
    /// Stable node id for this frame emission.
    public var nodeID: LottieRenderNodeID
    /// VM operation represented by this concrete RenderIR node.
    public var instruction: LottieVMInstruction.Kind
    /// Current composition stack.
    public var compositionStack: [String]
    /// Current layer stack.
    public var layerStack: [String]
    /// Active transform stack.
    public var transformStack: [String]
    /// Active shape style stack.
    public var styleStack: [String]
    /// Active mask/matte stack.
    public var matteStack: [String]
    /// Human-readable explanation of why the node exists.
    public var reason: String
}

/// A visible layer-like item in an evaluated frame.
public struct LottieRenderNode: Sendable, Equatable {
    /// Render payload kind.
    public enum Kind: Sendable, Equatable {
        case shape(LottieRenderShape)
        case solid(LottieRenderSolid)
        case null
        case imagePlaceholder(LottieRenderAssetReference?)
        case textPlaceholder
        case precompositionBoundary(LottieRenderPrecomposition)
        case unsupportedLayer(rawType: Int)
    }

    /// Stable per-frame render id.
    public var id: LottieRenderNodeID
    /// Source provenance for the source layer/style that emitted the node.
    public var source: LottieRenderSource
    /// Debug identity mirroring the composition VM stack.
    public var trace: LottieRenderTraceIdentity
    /// Authored layer display name.
    public var layerName: String
    /// Authored layer index (`ind`), when present.
    public var layerIndex: Int?
    /// Layer-local source frame after `st`, `sr`, and `tm`.
    public var localFrame: Double
    /// Evaluated transform state for this frame.
    public var transform: LottieRenderTransform
    /// Evaluated layer opacity in `[0, 1]`.
    public var opacity: Double
    /// Evaluated masks attached to this layer.
    public var masks: [LottieRenderMask]
    /// Track matte requirement for this layer, when authored.
    public var matte: LottieRenderMatte?
    /// Track matte source marker (`td`) authored on this layer, when present.
    public var matteSourceMarker: Int?
    /// Node-level compositing facts currently modeled by PureLottie.
    public var compositing: LottieRenderCompositing
    /// Filter/effect placeholders retained for future lowering.
    public var filters: [LottieRenderFilter]
    /// Concrete payload.
    public var kind: Kind
    /// Human-readable explanation for frame-dump/debugger UI.
    public var explanation: String
}

/// Evaluated transform facts before backend-specific assignment.
public struct LottieRenderTransform: Sendable, Equatable {
    /// Layer-local transform state.
    public var local: LottieTransformState
    /// Matrix including parent and precomposition ancestry.
    public var worldMatrix: LottieTransformMatrix
    /// Human-readable transform source stack.
    public var transformStack: [String]
}

/// Evaluated layer mask.
public struct LottieRenderMask: Sendable, Equatable {
    /// Source provenance for the mask item.
    public var source: LottieRenderSource
    /// Authored mask name.
    public var name: String?
    /// Lottie mask mode (`a`, `s`, `i`, `n`, etc.).
    public var mode: String
    /// Whether the mask is inverted.
    public var isInverted: Bool
    /// Evaluated opacity in `[0, 1]`.
    public var opacity: Double
    /// Evaluated path, or `nil` when the source path could not be evaluated.
    public var path: LottieBezier?
}

/// Track matte edge retained before backend lowering.
public struct LottieRenderMatte: Sendable, Equatable {
    /// Track matte mode (`tt`).
    public var mode: Int
    /// Explicit source layer index (`tp`) or implicit previous layer index.
    public var sourceLayerIndex: Int?
    /// Human-readable source layer path, when resolvable.
    public var sourcePath: String?
    /// Whether the edge came from explicit `tp`.
    public var isExplicitSource: Bool
}

/// Node-level composite state.
public struct LottieRenderCompositing: Sendable, Equatable {
    /// Lottie layer blend mode, once modeled.
    public var blendMode: Int?
}

/// Placeholder for effect/filter terms once the model decodes `ef`.
public struct LottieRenderFilter: Sendable, Equatable {
    /// Source provenance for the effect.
    public var source: LottieRenderSource
    /// Authored effect name.
    public var name: String?
    /// Authored effect type identifier.
    public var type: String
}

/// Solid layer payload.
public struct LottieRenderSolid: Sendable, Equatable {
    /// Solid color as authored (`#rrggbb` or `#rrggbbaa`).
    public var colorHex: String
    /// Solid width in points.
    public var width: Double
    /// Solid height in points.
    public var height: Double
}

/// Image/precomposition asset reference retained by placeholder nodes.
public struct LottieRenderAssetReference: Sendable, Equatable {
    /// Asset id.
    public var id: String
    /// Asset display name.
    public var name: String?
    /// Asset width, when authored.
    public var width: Double?
    /// Asset height, when authored.
    public var height: Double?
}

/// Precomposition boundary retained in RenderIR.
public struct LottieRenderPrecomposition: Sendable, Equatable {
    /// Referenced asset id.
    public var assetID: String
    /// Precomposition width in points.
    public var width: Double
    /// Precomposition height in points.
    public var height: Double
}

/// Evaluated shape-layer payload.
public struct LottieRenderShape: Sendable, Equatable {
    /// Scoped shape nodes in draw order.
    public var nodes: [LottieRenderShapeNode]

    /// Flattened draw commands for inspection and simple frame dumps.
    public var draws: [LottieRenderShapeDraw] {
        nodes.flatMap(\.draws)
    }
}

/// Shape node after Lottie scoping and per-frame evaluation.
public enum LottieRenderShapeNode: Sendable, Equatable {
    case draw(LottieRenderShapeDraw)
    case transparencyGroup(LottieRenderShapeGroup)

    /// Draws contained in this node.
    public var draws: [LottieRenderShapeDraw] {
        switch self {
        case let .draw(draw):
            [draw]
        case let .transparencyGroup(group):
            group.nodes.flatMap(\.draws)
        }
    }
}

/// Atomic group opacity boundary for shape contents.
public struct LottieRenderShapeGroup: Sendable, Equatable {
    /// Source provenance for the group.
    public var source: LottieRenderSource
    /// Evaluated group opacity in `[0, 1]`.
    public var opacity: Double
    /// Whether the opacity property was animated.
    public var isOpacityAnimated: Bool
    /// Child shape nodes.
    public var nodes: [LottieRenderShapeNode]
}

/// A draw command in Lottie geometry terms, not PureDraw terms.
public struct LottieRenderShapeDraw: Sendable, Equatable {
    /// Source provenance for the style that opened this draw.
    public var source: LottieRenderSource
    /// Evaluated style.
    public var style: LottieRenderShapeStyle
    /// Evaluated geometry fragments affected by the style.
    public var fragments: [LottieRenderGeometryFragment]
    /// Measured trim-path source intent for the draw's trimmed fragments.
    public var trimTraces: [LottieSourceTrimTrace]
}

/// Evaluated fill or stroke style.
public enum LottieRenderShapeStyle: Sendable, Equatable {
    case fill(LottieRenderFillStyle)
    case stroke(LottieRenderStrokeStyle)

    /// Authored style blend mode, when present.
    public var blendMode: Int? {
        switch self {
        case let .fill(fill):
            fill.blendMode
        case let .stroke(stroke):
            stroke.blendMode
        }
    }
}

/// Evaluated fill style.
public struct LottieRenderFillStyle: Sendable, Equatable {
    /// RGBA unit components after frame evaluation.
    public var color: [Double]
    /// Evaluated opacity in `[0, 1]`.
    public var opacity: Double
    /// Fill rule (`1` winding, `2` even-odd).
    public var fillRule: Int?
    /// Authored blend mode.
    public var blendMode: Int?
    /// Whether the color came from keyframes.
    public var isColorAnimated: Bool
    /// Whether the opacity came from keyframes.
    public var isOpacityAnimated: Bool
}

/// Evaluated stroke style.
public struct LottieRenderStrokeStyle: Sendable, Equatable {
    /// RGBA unit components after frame evaluation.
    public var color: [Double]
    /// Evaluated opacity in `[0, 1]`.
    public var opacity: Double
    /// Evaluated width in points.
    public var width: Double
    /// Authored line cap.
    public var lineCap: Int?
    /// Authored line join.
    public var lineJoin: Int?
    /// Authored miter limit.
    public var miterLimit: Double?
    /// Evaluated secondary miter limit, when authored.
    public var secondaryMiterLimit: Double?
    /// Evaluated dash entries.
    public var dashPattern: [LottieRenderStrokeDash]
    /// Authored blend mode.
    public var blendMode: Int?
    /// Whether the color came from keyframes.
    public var isColorAnimated: Bool
    /// Whether the opacity came from keyframes.
    public var isOpacityAnimated: Bool
    /// Whether the width came from keyframes.
    public var isWidthAnimated: Bool
}

/// Evaluated stroke dash entry.
public struct LottieRenderStrokeDash: Sendable, Equatable {
    /// Authored dash entry name.
    public var name: String?
    /// Lottie dash type (`d`, `g`, or `o`).
    public var type: String?
    /// Evaluated dash value.
    public var value: Double?
    /// Whether the dash value came from keyframes.
    public var isAnimated: Bool
}

/// One evaluated geometry fragment in a style run.
public struct LottieRenderGeometryFragment: Sendable, Equatable {
    /// Source provenance for the geometry item.
    public var source: LottieRenderSource
    /// Evaluated geometry payload.
    public var geometry: LottieRenderGeometry
    /// Expanded Lottie source-space contour before PureDraw/PureLayer lowering.
    public var sourceGeometry: LottieSourceGeometryTrace
    /// Evaluated shape transforms active on this fragment.
    public var transformStack: [LottieRenderShapeTransform]
    /// Evaluated shape modifiers active on this fragment.
    public var modifiers: [LottieRenderShapeModifier]
}

/// Evaluated geometry payload.
public enum LottieRenderGeometry: Sendable, Equatable {
    case path(LottieBezier)
    case rectangle(center: [Double], size: [Double], roundness: Double)
    case ellipse(center: [Double], size: [Double])
}

/// Evaluated shape transform.
public struct LottieRenderShapeTransform: Sendable, Equatable {
    /// Source provenance for the transform item.
    public var source: LottieRenderSource
    /// Evaluated anchor point.
    public var anchor: [Double]
    /// Evaluated position.
    public var position: [Double]
    /// Evaluated scale percent.
    public var scale: [Double]
    /// Evaluated clockwise rotation in degrees.
    public var rotationDegrees: Double
    /// Evaluated transform opacity in `[0, 1]`.
    public var opacity: Double
    /// Whether any transform component came from keyframes.
    public var isAnimated: Bool
}

/// Evaluated shape modifier.
public enum LottieRenderShapeModifier: Sendable, Equatable {
    case trim(LottieRenderTrim)
}

/// Evaluated trim-path modifier.
public struct LottieRenderTrim: Sendable, Equatable {
    /// Source provenance for the trim item.
    public var source: LottieRenderSource
    /// Evaluated start percent.
    public var start: Double
    /// Evaluated end percent.
    public var end: Double
    /// Evaluated offset percent.
    public var offset: Double
    /// Lottie trim mode (`1` simultaneous, `2` individual).
    public var multiple: Int?
    /// Whether any trim component came from keyframes.
    public var isAnimated: Bool
}

/// Builds `LottieRenderFrame` values from a decoded Lottie document.
///
/// The builder belongs to the semantic/evaluation layer: it imports only
/// `LottieModel`, evaluates source-frame Lottie facts, and leaves all
/// PureLayer/PureDraw object construction to `LottieImport`.
public struct LottieRenderIRBuilder: Sendable {
    /// Animation to evaluate.
    public let animation: LottieAnimation

    public init(animation: LottieAnimation) {
        self.animation = animation
    }

    /// Emits an evaluated RenderIR frame at `sourceFrame`.
    public func frame(at sourceFrame: Double) -> LottieRenderFrame {
        var emitter = LottieRenderFrameEmitter(animation: animation)
        return emitter.frame(at: sourceFrame)
    }
}

private struct LottieRenderFrameEmitter {
    let animation: LottieAnimation
    let frameEvaluator: LottieFrameEvaluator
    let transformEvaluator: LottieTransformEvaluator
    let layerGraphEvaluator: LottieLayerGraphEvaluator
    let geometryEvaluator: LottieSourceGeometryEvaluator
    let trimEvaluator: LottieSourceTrimEvaluator
    var diagnostics: [ValidationError] = []
    var nextNodeID = 1
    var precompositionStack: [String] = []

    init(animation: LottieAnimation) {
        self.animation = animation
        frameEvaluator = LottieFrameEvaluator(animation: animation)
        transformEvaluator = LottieTransformEvaluator(animation: animation)
        layerGraphEvaluator = LottieLayerGraphEvaluator(animation: animation)
        geometryEvaluator = LottieSourceGeometryEvaluator(animation: animation)
        trimEvaluator = LottieSourceTrimEvaluator()
    }

    mutating func frame(at sourceFrame: Double) -> LottieRenderFrame {
        let layerGraph = layerGraphEvaluator.trace(at: sourceFrame)
        let nodes: [LottieRenderNode] = if frameEvaluator.containsCompositionFrame(sourceFrame) {
            compositionNodes(
                name: animation.name ?? "root",
                layers: animation.layers,
                sourceFrame: sourceFrame,
                compositionPath: "root",
                jsonPath: JSONPath([.key("layers")]),
                compositionStack: [],
                layerStackPrefix: [],
                transformStackPrefix: [],
                inheritedMatrix: .identity
            )
        } else {
            []
        }

        return LottieRenderFrame(
            sourceFrame: sourceFrame,
            frameRate: animation.frameRate,
            width: animation.width,
            height: animation.height,
            layerGraph: layerGraph,
            nodes: nodes,
            diagnostics: diagnostics
        )
    }

    private mutating func compositionNodes(
        name: String,
        layers: [LottieLayer],
        sourceFrame: Double,
        compositionPath: String,
        jsonPath: JSONPath,
        compositionStack: [String],
        layerStackPrefix: [String],
        transformStackPrefix: [String],
        inheritedMatrix: LottieTransformMatrix
    ) -> [LottieRenderNode] {
        let stack = compositionStack + [name]
        var nodes: [LottieRenderNode] = []

        for (offset, layer) in layers.enumerated().reversed() {
            guard !layer.isHidden else { continue }
            guard isVisible(layer, at: sourceFrame) else { continue }
            nodes.append(contentsOf: layerNodes(
                layer,
                offset: offset,
                layers: layers,
                sourceFrame: sourceFrame,
                compositionPath: compositionPath,
                jsonPath: jsonPath.appending(.index(offset)),
                compositionStack: stack,
                layerStackPrefix: layerStackPrefix,
                transformStackPrefix: transformStackPrefix,
                inheritedMatrix: inheritedMatrix
            ))
        }

        return nodes
    }

    private func isVisible(_ layer: LottieLayer, at sourceFrame: Double) -> Bool {
        sourceFrame >= layer.inPoint && sourceFrame < layer.outPoint
    }

    private mutating func layerNodes(
        _ layer: LottieLayer,
        offset: Int,
        layers: [LottieLayer],
        sourceFrame: Double,
        compositionPath: String,
        jsonPath: JSONPath,
        compositionStack: [String],
        layerStackPrefix: [String],
        transformStackPrefix: [String],
        inheritedMatrix: LottieTransformMatrix
    ) -> [LottieRenderNode] {
        let path = layerPath(in: compositionPath, layer: layer)
        let localFrame = frameEvaluator.localFrame(for: layer, at: sourceFrame, path: jsonPath)
        diagnostics.append(contentsOf: localFrame.diagnostics)

        let localTransform = transformEvaluator.localTransform(for: layer, at: localFrame.value, path: jsonPath)
        let worldTransform = transformEvaluator.worldTransform(for: layer, in: layers, at: localFrame.value, path: jsonPath)
        diagnostics.append(contentsOf: worldTransform.diagnostics)

        let transformStack = transformStackPrefix + layerTransformStack(
            layer,
            in: layers,
            compositionPath: compositionPath,
            layerPath: path
        )
        let transform = LottieRenderTransform(
            local: localTransform.value,
            worldMatrix: worldTransform.value.matrix.concatenating(inheritedMatrix),
            transformStack: transformStack
        )
        let opacity = evaluatedOpacity(for: layer, at: localFrame.value, jsonPath: jsonPath)
        let masks = evaluatedMasks(layer.masks ?? [], at: localFrame.value, jsonPath: jsonPath.appending(.key("masksProperties")), layerPath: path)
        let matte = matte(for: layer, offset: offset, layers: layers, compositionPath: compositionPath)
        let source = LottieRenderSource(sourcePath: path, jsonPath: jsonPath, sourceRange: nil)

        switch layer.type {
        case .shape:
            return [
                node(
                    source: source,
                    layer: layer,
                    localFrame: localFrame.value,
                    transform: transform,
                    opacity: opacity,
                    masks: masks,
                    matte: matte,
                    compositionStack: compositionStack,
                    layerStack: layerStackPrefix + [path],
                    transformStack: transformStack,
                    styleStack: [],
                    kind: .shape(evaluatedShape(layer.shapes ?? [], at: localFrame.value, sourcePath: path, jsonPath: jsonPath.appending(.key("shapes")))),
                    explanation: "Layer is visible at the selected source frame and emits evaluated shape draws."
                ),
            ]
        case .solid:
            return [
                node(
                    source: source,
                    layer: layer,
                    localFrame: localFrame.value,
                    transform: transform,
                    opacity: opacity,
                    masks: masks,
                    matte: matte,
                    compositionStack: compositionStack,
                    layerStack: layerStackPrefix + [path],
                    transformStack: transformStack,
                    styleStack: [],
                    kind: .solid(LottieRenderSolid(
                        colorHex: layer.solidColor ?? "#000000",
                        width: layer.solidWidth ?? 0,
                        height: layer.solidHeight ?? 0
                    )),
                    explanation: "Layer is visible at the selected source frame and emits an evaluated solid rectangle."
                ),
            ]
        case .null:
            return [
                node(
                    source: source,
                    layer: layer,
                    localFrame: localFrame.value,
                    transform: transform,
                    opacity: opacity,
                    masks: masks,
                    matte: matte,
                    compositionStack: compositionStack,
                    layerStack: layerStackPrefix + [path],
                    transformStack: transformStack,
                    styleStack: [],
                    kind: .null,
                    explanation: "Null layer is visible and retained as a transform carrier."
                ),
            ]
        case .image:
            return [
                node(
                    source: source,
                    layer: layer,
                    localFrame: localFrame.value,
                    transform: transform,
                    opacity: opacity,
                    masks: masks,
                    matte: matte,
                    compositionStack: compositionStack,
                    layerStack: layerStackPrefix + [path],
                    transformStack: transformStack,
                    styleStack: [],
                    kind: .imagePlaceholder(assetReference(id: layer.referenceId)),
                    explanation: "Image layer is visible, but pixel loading is a backend capability."
                ),
            ]
        case .text:
            return [
                node(
                    source: source,
                    layer: layer,
                    localFrame: localFrame.value,
                    transform: transform,
                    opacity: opacity,
                    masks: masks,
                    matte: matte,
                    compositionStack: compositionStack,
                    layerStack: layerStackPrefix + [path],
                    transformStack: transformStack,
                    styleStack: [],
                    kind: .textPlaceholder,
                    explanation: "Text layer is visible, but text layout is not modeled yet."
                ),
            ]
        case .precomposition:
            return precompositionNodes(
                layer,
                source: source,
                localFrame: localFrame.value,
                transform: transform,
                opacity: opacity,
                masks: masks,
                matte: matte,
                compositionStack: compositionStack,
                layerStack: layerStackPrefix + [path],
                transformStack: transformStack,
                jsonPath: jsonPath,
                layerPath: path
            )
        case .none:
            return [
                node(
                    source: source,
                    layer: layer,
                    localFrame: localFrame.value,
                    transform: transform,
                    opacity: opacity,
                    masks: masks,
                    matte: matte,
                    compositionStack: compositionStack,
                    layerStack: layerStackPrefix + [path],
                    transformStack: transformStack,
                    styleStack: [],
                    kind: .unsupportedLayer(rawType: layer.rawType),
                    explanation: "Layer type is not part of the modeled Lottie subset."
                ),
            ]
        }
    }

    private mutating func node(
        source: LottieRenderSource,
        layer: LottieLayer,
        localFrame: Double,
        transform: LottieRenderTransform,
        opacity: Double,
        masks: [LottieRenderMask],
        matte: LottieRenderMatte?,
        compositionStack: [String],
        layerStack: [String],
        transformStack: [String],
        styleStack: [String],
        kind: LottieRenderNode.Kind,
        explanation: String
    ) -> LottieRenderNode {
        let id = LottieRenderNodeID(rawValue: nextNodeID)
        nextNodeID += 1
        let trace = LottieRenderTraceIdentity(
            nodeID: id,
            instruction: .emitRenderNode,
            compositionStack: compositionStack,
            layerStack: layerStack,
            transformStack: transformStack,
            styleStack: styleStack,
            matteStack: masks.map(\.source.sourcePath) + matte.map { [$0.sourcePath ?? source.sourcePath] }.orEmpty,
            reason: explanation
        )
        return LottieRenderNode(
            id: id,
            source: source,
            trace: trace,
            layerName: layer.name ?? "?",
            layerIndex: layer.index,
            localFrame: localFrame,
            transform: transform,
            opacity: opacity,
            masks: masks,
            matte: matte,
            matteSourceMarker: layer.trackMatteSource,
            compositing: LottieRenderCompositing(blendMode: nil),
            filters: [],
            kind: kind,
            explanation: explanation
        )
    }

    private mutating func precompositionNodes(
        _ layer: LottieLayer,
        source: LottieRenderSource,
        localFrame: Double,
        transform: LottieRenderTransform,
        opacity: Double,
        masks: [LottieRenderMask],
        matte: LottieRenderMatte?,
        compositionStack: [String],
        layerStack: [String],
        transformStack: [String],
        jsonPath: JSONPath,
        layerPath: String
    ) -> [LottieRenderNode] {
        guard let referenceID = layer.referenceId,
              let asset = animation.precomposition(id: referenceID),
              let assetLayers = asset.layers
        else {
            return [
                node(
                    source: source,
                    layer: layer,
                    localFrame: localFrame,
                    transform: transform,
                    opacity: opacity,
                    masks: masks,
                    matte: matte,
                    compositionStack: compositionStack,
                    layerStack: layerStack,
                    transformStack: transformStack,
                    styleStack: [],
                    kind: .unsupportedLayer(rawType: layer.rawType),
                    explanation: "Precomposition layer references no modeled composition asset."
                ),
            ]
        }
        guard !precompositionStack.contains(referenceID) else {
            diagnostics.append(diagnostic(
                ruleID: "lottie.evaluation.precomposition.recursive",
                reason: "Recursive precomposition reference cannot be evaluated into RenderIR.",
                path: jsonPath.appending(.key("refId")),
                sourcePath: layerPath,
                classification: .gap
            ))
            return []
        }

        let boundary = node(
            source: source,
            layer: layer,
            localFrame: localFrame,
            transform: transform,
            opacity: opacity,
            masks: masks,
            matte: matte,
            compositionStack: compositionStack,
            layerStack: layerStack,
            transformStack: transformStack,
            styleStack: [],
            kind: .precompositionBoundary(LottieRenderPrecomposition(
                assetID: referenceID,
                width: layer.width ?? asset.width ?? animation.width,
                height: layer.height ?? asset.height ?? animation.height
            )),
            explanation: "Precomposition layer is visible and opens an asset composition namespace."
        )

        let assetIndex = animation.assets.firstIndex { $0.id == referenceID } ?? 0
        precompositionStack.append(referenceID)
        let childNodes = compositionNodes(
            name: "precomp:\(referenceID)",
            layers: assetLayers,
            sourceFrame: localFrame,
            compositionPath: "\(layerPath) > precomp '\(referenceID)'",
            jsonPath: JSONPath([.key("assets"), .index(assetIndex), .key("layers")]),
            compositionStack: compositionStack,
            layerStackPrefix: layerStack,
            transformStackPrefix: transformStack,
            inheritedMatrix: transform.worldMatrix
        )
        precompositionStack.removeLast()
        return [boundary] + childNodes
    }

    private mutating func evaluatedOpacity(for layer: LottieLayer, at localFrame: Double, jsonPath: JSONPath) -> Double {
        guard let opacity = layer.transform?.opacity else { return 1 }
        let result = frameEvaluator.evaluate(opacity, at: localFrame, path: jsonPath.appending(.key("ks")).appending(.key("o")))
        diagnostics.append(contentsOf: result.diagnostics)
        return clamp(result.value / 100)
    }

    private mutating func evaluatedMasks(
        _ masks: [LottieMask],
        at localFrame: Double,
        jsonPath: JSONPath,
        layerPath: String
    ) -> [LottieRenderMask] {
        masks.enumerated().map { offset, mask in
            let itemPath = jsonPath.appending(.index(offset))
            let source = LottieRenderSource(
                sourcePath: "\(layerPath) > mask '\(mask.name ?? "?")'",
                jsonPath: itemPath,
                sourceRange: nil
            )
            let path = frameEvaluator.evaluate(mask.path, at: localFrame, path: itemPath.appending(.key("pt")))
            diagnostics.append(contentsOf: path.diagnostics)
            let opacity: Double
            if let maskOpacity = mask.opacity {
                let result = frameEvaluator.evaluate(maskOpacity, at: localFrame, path: itemPath.appending(.key("o")))
                diagnostics.append(contentsOf: result.diagnostics)
                opacity = clamp(result.value / 100)
            } else {
                opacity = 1
            }
            return LottieRenderMask(
                source: source,
                name: mask.name,
                mode: mask.mode,
                isInverted: mask.isInverted,
                opacity: opacity,
                path: path.value
            )
        }
    }

    private func matte(
        for layer: LottieLayer,
        offset: Int,
        layers: [LottieLayer],
        compositionPath: String
    ) -> LottieRenderMatte? {
        guard let mode = layer.trackMatteType, mode != 0 else { return nil }
        if let explicit = layer.trackMatteParent {
            let source = layers.first { $0.index == explicit }
            return LottieRenderMatte(
                mode: mode,
                sourceLayerIndex: explicit,
                sourcePath: source.map { layerPath(in: compositionPath, layer: $0) },
                isExplicitSource: true
            )
        }
        let sourceOffset = offset - 1
        let source = layers.indices.contains(sourceOffset) ? layers[sourceOffset] : nil
        return LottieRenderMatte(
            mode: mode,
            sourceLayerIndex: source?.index,
            sourcePath: source.map { layerPath(in: compositionPath, layer: $0) },
            isExplicitSource: false
        )
    }

    private mutating func evaluatedShape(_ items: [LottieShape], at localFrame: Double, sourcePath: String, jsonPath: JSONPath) -> LottieRenderShape {
        let program = LottieShapeProgramBuilder().program(for: items, sourcePath: sourcePath, jsonPath: jsonPath)
        diagnostics.append(contentsOf: program.diagnostics.filter { !isHandledByRenderIR($0) })
        return LottieRenderShape(nodes: evaluatedShapeNodes(program.nodes, at: localFrame))
    }

    private mutating func evaluatedShapeNodes(_ nodes: [LottieShapeProgram.Node], at localFrame: Double) -> [LottieRenderShapeNode] {
        nodes.compactMap { node -> LottieRenderShapeNode? in
            switch node {
            case let .styleRun(run):
                let fragments = run.fragments.compactMap { evaluatedFragment($0, at: localFrame) }
                let draw = LottieRenderShapeDraw(
                    source: LottieRenderSource(sourcePath: run.sourcePath, jsonPath: run.jsonPath, sourceRange: nil),
                    style: evaluatedStyle(run.style, at: localFrame, sourcePath: run.sourcePath, jsonPath: run.jsonPath),
                    fragments: fragments,
                    trimTraces: trimTraces(for: fragments, at: localFrame)
                )
                return draw.fragments.isEmpty ? nil : .draw(draw)
            case let .group(group):
                let children = evaluatedShapeNodes(group.nodes, at: localFrame)
                guard !children.isEmpty else { return nil }
                let opacity = group.opacity.map { opacity in
                    let result = frameEvaluator.evaluate(opacity, at: localFrame, path: group.jsonPath.appending(.key("o")))
                    diagnostics.append(contentsOf: result.diagnostics)
                    return clamp(result.value / 100)
                } ?? 1
                return .transparencyGroup(LottieRenderShapeGroup(
                    source: LottieRenderSource(sourcePath: group.sourcePath, jsonPath: group.jsonPath, sourceRange: nil),
                    opacity: opacity,
                    isOpacityAnimated: group.opacity?.isAnimated == true,
                    nodes: children
                ))
            }
        }
    }

    private mutating func trimTraces(
        for fragments: [LottieRenderGeometryFragment],
        at localFrame: Double
    ) -> [LottieSourceTrimTrace] {
        var traces: [LottieSourceTrimTrace] = []
        var runTrim: LottieRenderTrim?
        var runFragments: [LottieRenderGeometryFragment] = []

        func flush() {
            guard let trim = runTrim, !runFragments.isEmpty else { return }
            let result = trimEvaluator.evaluate(
                trim: trim,
                paths: runFragments.map(\.sourceGeometry),
                sourceFrame: localFrame
            )
            diagnostics.append(contentsOf: result.diagnostics)
            traces.append(result.value)
        }

        for fragment in fragments {
            let trim = trim(in: fragment.modifiers)
            if trim == runTrim {
                if trim != nil {
                    runFragments.append(fragment)
                }
            } else {
                flush()
                runTrim = trim
                runFragments = trim == nil ? [] : [fragment]
            }
        }
        flush()
        return traces
    }

    private func trim(in modifiers: [LottieRenderShapeModifier]) -> LottieRenderTrim? {
        modifiers.compactMap { modifier -> LottieRenderTrim? in
            if case let .trim(trim) = modifier { return trim }
            return nil
        }.first
    }

    private mutating func evaluatedStyle(
        _ style: LottieShapeProgram.Style,
        at localFrame: Double,
        sourcePath _: String,
        jsonPath: JSONPath
    ) -> LottieRenderShapeStyle {
        switch style {
        case let .fill(fill):
            let color = frameEvaluator.evaluate(fill.color, at: localFrame, path: jsonPath.appending(.key("c")))
            diagnostics.append(contentsOf: color.diagnostics)
            let opacity = fill.opacity.map { opacity in
                let result = frameEvaluator.evaluate(opacity, at: localFrame, path: jsonPath.appending(.key("o")))
                diagnostics.append(contentsOf: result.diagnostics)
                return clamp(result.value / 100)
            } ?? 1
            return .fill(LottieRenderFillStyle(
                color: color.value,
                opacity: opacity,
                fillRule: fill.fillRule,
                blendMode: fill.blendMode,
                isColorAnimated: fill.color.isAnimated,
                isOpacityAnimated: fill.opacity?.isAnimated == true
            ))
        case let .stroke(stroke):
            let color = frameEvaluator.evaluate(stroke.color, at: localFrame, path: jsonPath.appending(.key("c")))
            let width = frameEvaluator.evaluate(stroke.width, at: localFrame, path: jsonPath.appending(.key("w")))
            diagnostics.append(contentsOf: color.diagnostics + width.diagnostics)
            let opacity = stroke.opacity.map { opacity in
                let result = frameEvaluator.evaluate(opacity, at: localFrame, path: jsonPath.appending(.key("o")))
                diagnostics.append(contentsOf: result.diagnostics)
                return clamp(result.value / 100)
            } ?? 1
            let secondary = stroke.secondaryMiterLimit.map { limit in
                let result = frameEvaluator.evaluate(limit, at: localFrame, path: jsonPath.appending(.key("ml2")))
                diagnostics.append(contentsOf: result.diagnostics)
                return result.value
            }
            let dashPattern = (stroke.dashPattern ?? []).enumerated().map { offset, dash in
                let value = dash.value.map { value -> Double in
                    let result = frameEvaluator.evaluate(value, at: localFrame, path: jsonPath.appending(.key("d")).appending(.index(offset)).appending(.key("v")))
                    diagnostics.append(contentsOf: result.diagnostics)
                    return result.value
                }
                return LottieRenderStrokeDash(
                    name: dash.name,
                    type: dash.type,
                    value: value,
                    isAnimated: dash.value?.isAnimated == true
                )
            }
            return .stroke(LottieRenderStrokeStyle(
                color: color.value,
                opacity: opacity,
                width: width.value,
                lineCap: stroke.lineCap,
                lineJoin: stroke.lineJoin,
                miterLimit: stroke.miterLimit,
                secondaryMiterLimit: secondary,
                dashPattern: dashPattern,
                blendMode: stroke.blendMode,
                isColorAnimated: stroke.color.isAnimated,
                isOpacityAnimated: stroke.opacity?.isAnimated == true,
                isWidthAnimated: stroke.width.isAnimated
            ))
        }
    }

    private mutating func evaluatedFragment(_ fragment: LottieShapeProgram.GeometryFragment, at localFrame: Double) -> LottieRenderGeometryFragment? {
        let sourceGeometry = geometryEvaluator.evaluate(
            fragment.geometry,
            at: localFrame,
            sourcePath: fragment.sourcePath,
            jsonPath: fragment.jsonPath
        )
        diagnostics.append(contentsOf: sourceGeometry.diagnostics)
        guard let geometry = evaluatedGeometry(fragment.geometry, sourceGeometry: sourceGeometry.value) else {
            return nil
        }
        return LottieRenderGeometryFragment(
            source: LottieRenderSource(sourcePath: fragment.sourcePath, jsonPath: fragment.jsonPath, sourceRange: nil),
            geometry: geometry,
            sourceGeometry: sourceGeometry.value,
            transformStack: fragment.transformStack.map { evaluatedTransform($0, at: localFrame) },
            modifiers: fragment.modifiers.map { evaluatedModifier($0, at: localFrame) }
        )
    }

    private mutating func evaluatedGeometry(
        _ geometry: LottieShapeProgram.Geometry,
        sourceGeometry: LottieSourceGeometryTrace
    ) -> LottieRenderGeometry? {
        switch geometry {
        case .path, .polystar:
            .path(sourceGeometry.bezier)
        case .rectangle:
            .rectangle(
                center: sourceGeometry.fieldValue("p") ?? [],
                size: sourceGeometry.fieldValue("s") ?? [],
                roundness: sourceGeometry.fieldValue("r")?.first ?? 0
            )
        case .ellipse:
            .ellipse(
                center: sourceGeometry.fieldValue("p") ?? [],
                size: sourceGeometry.fieldValue("s") ?? []
            )
        }
    }

    private mutating func evaluatedTransform(_ applied: LottieShapeProgram.AppliedTransform, at localFrame: Double) -> LottieRenderShapeTransform {
        let transform = applied.transform
        let anchor = transform.anchor.map { value -> [Double] in
            let result = frameEvaluator.evaluate(value, at: localFrame, path: applied.jsonPath.appending(.key("a")))
            diagnostics.append(contentsOf: result.diagnostics)
            return result.value
        } ?? [0, 0]
        let position = transform.position.map { value -> [Double] in
            let result = frameEvaluator.evaluate(value, at: localFrame, path: applied.jsonPath.appending(.key("p")))
            diagnostics.append(contentsOf: result.diagnostics)
            return result.value
        } ?? [0, 0]
        let scale = transform.scale.map { value -> [Double] in
            let result = frameEvaluator.evaluate(value, at: localFrame, path: applied.jsonPath.appending(.key("s")))
            diagnostics.append(contentsOf: result.diagnostics)
            return result.value
        } ?? [100, 100]
        let rotation = transform.rotation.map { value -> Double in
            let result = frameEvaluator.evaluate(value, at: localFrame, path: applied.jsonPath.appending(.key("r")))
            diagnostics.append(contentsOf: result.diagnostics)
            return result.value
        } ?? 0
        let opacity = transform.opacity.map { value -> Double in
            let result = frameEvaluator.evaluate(value, at: localFrame, path: applied.jsonPath.appending(.key("o")))
            diagnostics.append(contentsOf: result.diagnostics)
            return clamp(result.value / 100)
        } ?? 1
        return LottieRenderShapeTransform(
            source: LottieRenderSource(sourcePath: applied.sourcePath, jsonPath: applied.jsonPath, sourceRange: nil),
            anchor: anchor,
            position: position,
            scale: scale,
            rotationDegrees: rotation,
            opacity: opacity,
            isAnimated: transform.anchor?.isAnimated == true
                || transform.position?.isAnimated == true
                || transform.scale?.isAnimated == true
                || transform.rotation?.isAnimated == true
                || transform.opacity?.isAnimated == true
        )
    }

    private mutating func evaluatedModifier(_ modifier: LottieShapeProgram.Modifier, at localFrame: Double) -> LottieRenderShapeModifier {
        switch modifier {
        case let .trim(applied):
            let trim = applied.trim
            let start = frameEvaluator.evaluate(trim.start, at: localFrame, path: applied.jsonPath.appending(.key("s")))
            let end = frameEvaluator.evaluate(trim.end, at: localFrame, path: applied.jsonPath.appending(.key("e")))
            diagnostics.append(contentsOf: start.diagnostics + end.diagnostics)
            let offset = trim.offset.map { value -> Double in
                let result = frameEvaluator.evaluate(value, at: localFrame, path: applied.jsonPath.appending(.key("o")))
                diagnostics.append(contentsOf: result.diagnostics)
                return result.value
            } ?? 0
            return .trim(LottieRenderTrim(
                source: LottieRenderSource(sourcePath: applied.sourcePath, jsonPath: applied.jsonPath, sourceRange: nil),
                start: start.value,
                end: end.value,
                offset: offset,
                multiple: trim.multiple,
                isAnimated: trim.start.isAnimated || trim.end.isAnimated || trim.offset?.isAnimated == true
            ))
        }
    }

    private func layerTransformStack(
        _ layer: LottieLayer,
        in layers: [LottieLayer],
        compositionPath: String,
        layerPath: String
    ) -> [String] {
        let byIndex = Dictionary(
            layers.compactMap { item in
                item.index.map { ($0, item) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var stack = ["\(layerPath) > transform"]
        var cursor = layer.parent
        var visited: Set<Int> = []
        while let parentIndex = cursor, let parent = byIndex[parentIndex], visited.insert(parentIndex).inserted {
            stack.append("\(self.layerPath(in: compositionPath, layer: parent)) > transform")
            cursor = parent.parent
        }
        return stack
    }

    private func layerPath(in compositionPath: String, layer: LottieLayer) -> String {
        "\(compositionPath) > layer '\(layer.name ?? "?")'"
    }

    private func assetReference(id: String?) -> LottieRenderAssetReference? {
        guard let id, let asset = animation.assets.first(where: { $0.id == id }) else { return nil }
        return LottieRenderAssetReference(
            id: asset.id,
            name: asset.name,
            width: asset.width,
            height: asset.height
        )
    }

    private func diagnostic(
        ruleID: String,
        reason: String,
        path: JSONPath,
        sourcePath: String,
        classification: FeatureClassification
    ) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: reason,
            at: path,
            severity: .warning,
            phase: .semantic,
            classification: classification,
            evidence: sourcePath
        )
    }

    private func isHandledByRenderIR(_ diagnostic: ValidationError) -> Bool {
        switch diagnostic.ruleID {
        case "lottie.evaluation.shape.rectangle.animated-geometry.unsupported",
             "lottie.evaluation.shape.ellipse.animated-geometry.unsupported",
             "lottie.evaluation.shape.polystar.animated-geometry.unsupported":
            true
        default:
            false
        }
    }
}

private extension LottieSourceGeometryTrace {
    func fieldValue(_ field: String) -> [Double]? {
        sourceFields.first { $0.field == field }?.value
    }
}

private extension [String]? {
    var orEmpty: [String] {
        self ?? []
    }
}

private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
