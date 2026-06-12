//
//  LottieRenderIRLowerer.swift
//  PureLottie
//

import LottieEvaluation
import LottieModel
import PureLayer

/// A PureLayer tree produced from one evaluated RenderIR frame.
public struct LottieRenderLayerTree {
    /// Root PureLayer node.
    public let root: Layer
    /// Backend-lowering findings for unsupported target capabilities.
    public let report: ImportReport
}

/// Lowers evaluated `LottieRenderFrame` values into PureLayer.
///
/// This type is a backend pass. It must not re-run Lottie semantic evaluation:
/// all timing, transform, style, mask, and geometry values consumed here already
/// came from `LottieEvaluation`.
public struct LottieRenderIRLowerer {
    public init() {}

    /// Builds a PureLayer tree for one evaluated frame.
    public func lower(
        _ frame: LottieRenderFrame,
        evidenceContext: LottieBackendEvidenceContext = .init()
    ) -> LottieRenderLayerTree {
        let context = RenderIRLoweringContext(frame: frame, evidenceContext: evidenceContext)
        context.reportFrameDiagnostics(frame.diagnostics)

        let root = Layer()
        root.bounds = Rect(x: 0, y: 0, width: frame.width, height: frame.height)
        root.position = Point(x: frame.width / 2, y: frame.height / 2)
        root.masksToBounds = true

        for node in frame.nodes {
            guard let layer = context.layer(for: node) else { continue }
            root.addSublayer(layer)
        }

        return LottieRenderLayerTree(root: root, report: context.report.report())
    }
}

private final class RenderIRLoweringContext {
    let frame: LottieRenderFrame
    let evidenceContext: LottieBackendEvidenceContext
    let report = ImportReportBuilder()

    init(frame: LottieRenderFrame, evidenceContext: LottieBackendEvidenceContext) {
        self.frame = frame
        self.evidenceContext = evidenceContext
    }

    func reportFrameDiagnostics(_ diagnostics: [ValidationError]) {
        for diagnostic in diagnostics {
            let path = diagnostic.evidence ?? diagnostic.codingPath.description
            switch diagnostic.classification {
            case .approximate:
                report.approximate(diagnostic.reason, at: path, sourcePath: diagnostic.codingPath, sourceRange: diagnostic.range)
            case .exact, .metadata:
                continue
            case .reported, .gap:
                report.skip(diagnostic.reason, at: path, sourcePath: diagnostic.codingPath, sourceRange: diagnostic.range)
            }
        }
    }

    func layer(for node: LottieRenderNode) -> Layer? {
        reportNodeGaps(node)

        let layer: Layer?
        switch node.kind {
        case let .shape(shape):
            layer = shapeLayerContainer(for: shape, node: node)
        case let .solid(solid):
            layer = solidLayer(for: solid)
        case .null:
            layer = carrierLayer()
        case let .imagePlaceholder(asset):
            let suffix = asset.map { " '\($0.id)'" } ?? ""
            skipBackend("image layer\(suffix)", at: node.source, node: node)
            layer = nil
        case .textPlaceholder:
            skipBackend("text layer", at: node.source, node: node)
            layer = nil
        case let .precompositionBoundary(precomposition):
            approximateBackend(
                "precomposition boundary '\(precomposition.assetID)' flattened into evaluated child nodes",
                at: node.source,
                node: node
            )
            layer = carrierLayer()
        case let .unsupportedLayer(rawType):
            skipBackend("layer type \(rawType)", at: node.source, node: node)
            layer = nil
        }

        guard let layer else { return nil }
        apply(node, to: layer)
        applyMasks(node.masks, to: layer, at: node)
        return layer
    }

    private func reportNodeGaps(_ node: LottieRenderNode) {
        if let marker = node.matteSourceMarker {
            let jsonPath = node.source.jsonPath.appending(.key("td"))
            skipBackend(
                "track matte source marker \(marker)",
                at: node.source,
                node: node,
                jsonPath: jsonPath,
                term: evidenceTerm(
                    "matteSourceMarker",
                    source: node.source,
                    jsonPath: jsonPath,
                    values: ["marker": "\(marker)"]
                )
            )
        }
        if let matte = node.matte {
            var feature = "track matte mode \(matte.mode)"
            if let sourcePath = matte.sourcePath {
                feature += " using \(sourcePath)"
            }
            let jsonPath = node.source.jsonPath.appending(.key("tt"))
            skipBackend(
                feature,
                at: node.source,
                node: node,
                jsonPath: jsonPath,
                term: evidenceTerm(
                    "trackMatte",
                    source: node.source,
                    jsonPath: jsonPath,
                    values: [
                        "explicitSource": "\(matte.isExplicitSource)",
                        "mode": "\(matte.mode)",
                        "sourceLayerIndex": matte.sourceLayerIndex.map(String.init) ?? "",
                        "sourcePath": matte.sourcePath ?? "",
                    ]
                )
            )
        }
        if let blendMode = node.compositing.blendMode, blendMode != 0 {
            skipBackend(
                "layer blend mode \(blendMode)",
                at: node.source,
                node: node,
                term: evidenceTerm("layerCompositing", source: node.source, values: ["blendMode": "\(blendMode)"])
            )
        }
        for filter in node.filters {
            skipBackend(
                "filter '\(filter.type)'",
                at: filter.source,
                node: node,
                term: evidenceTerm(
                    "filter",
                    source: filter.source,
                    values: [
                        "name": filter.name ?? "",
                        "type": filter.type,
                    ]
                )
            )
        }
    }

    private func carrierLayer() -> Layer {
        let layer = Layer()
        layer.bounds = Rect(x: 0, y: 0, width: frame.width, height: frame.height)
        layer.backgroundColor = nil
        return layer
    }

    private func solidLayer(for solid: LottieRenderSolid) -> Layer {
        let layer = Layer()
        layer.bounds = Rect(x: 0, y: 0, width: solid.width, height: solid.height)
        layer.backgroundColor = LottieImporter.color(hex: solid.colorHex)
        return layer
    }

    private func shapeLayerContainer(for shape: LottieRenderShape, node: LottieRenderNode) -> Layer {
        let layer = carrierLayer()
        for sublayer in shapeLayers(for: shape.nodes, bounds: layer.bounds, node: node) {
            layer.addSublayer(sublayer)
        }
        return layer
    }

    private func apply(_ node: LottieRenderNode, to layer: Layer) {
        layer.name = node.id.description
        layer.anchorPoint = Point(x: 0, y: 0)
        layer.anchorPointZ = 0
        layer.position = Point(x: 0, y: 0)
        layer.opacity = node.opacity
        layer.transform = transform3D(from: node.transform.worldMatrix)
    }

    private func transform3D(from matrix: LottieTransformMatrix) -> Transform3D {
        let values = matrix.values
        return Transform3D(
            m11: values[0], m12: values[1], m13: values[2], m14: values[3],
            m21: values[4], m22: values[5], m23: values[6], m24: values[7],
            m31: values[8], m32: values[9], m33: values[10], m34: values[11],
            m41: values[12], m42: values[13], m43: values[14], m44: values[15]
        )
    }

    private func applyMasks(_ masks: [LottieRenderMask], to layer: Layer, at node: LottieRenderNode) {
        guard !masks.isEmpty else { return }
        guard masks.count == 1, let mask = masks.first else {
            skipBackend("multiple masks", at: node.source, node: node)
            return
        }
        guard mask.mode == "a" || mask.mode == "n" else {
            skipBackend(
                "mask mode '\(mask.mode)'",
                at: mask.source,
                node: node,
                term: evidenceTerm("mask", source: mask.source, values: maskEvidenceValues(mask))
            )
            return
        }
        guard mask.mode != "n" else { return }
        guard !mask.isInverted else {
            skipBackend(
                "inverted mask",
                at: mask.source,
                node: node,
                term: evidenceTerm("mask", source: mask.source, values: maskEvidenceValues(mask))
            )
            return
        }
        guard let bezier = mask.path else {
            skipBackend(
                "missing mask path",
                at: mask.source,
                node: node,
                term: evidenceTerm("mask", source: mask.source, values: maskEvidenceValues(mask))
            )
            return
        }

        var path = Path()
        PathBuilder.path(from: bezier, into: &path)
        let maskLayer = ShapeLayer()
        maskLayer.bounds = layer.bounds
        maskLayer.position = Point(x: layer.bounds.width / 2, y: layer.bounds.height / 2)
        maskLayer.path = path
        maskLayer.fillColor = Color(red: 0, green: 0, blue: 0, alpha: mask.opacity)
        layer.mask = maskLayer
    }

    private func shapeLayers(for nodes: [LottieRenderShapeNode], bounds: Rect, node: LottieRenderNode) -> [Layer] {
        nodes.flatMap { shapeNode -> [Layer] in
            switch shapeNode {
            case let .draw(draw):
                shapeLayers(for: draw, bounds: bounds, node: node)
            case let .transparencyGroup(group):
                transparencyLayer(for: group, bounds: bounds, node: node)
            }
        }
    }

    private func shapeLayers(for draw: LottieRenderShapeDraw, bounds: Rect, node: LottieRenderNode) -> [Layer] {
        let runs = pathRuns(for: draw)
        return runs.compactMap { run in
            shapeLayer(for: run.path, trim: run.trim, style: draw.style, bounds: bounds, source: draw.source, node: node)
        }
    }

    private func transparencyLayer(for group: LottieRenderShapeGroup, bounds: Rect, node: LottieRenderNode) -> [Layer] {
        let childLayers = shapeLayers(for: group.nodes, bounds: bounds, node: node)
        guard !childLayers.isEmpty else { return [] }
        guard abs(group.opacity - 1) > 0.0001 else { return childLayers }

        let layer = Layer()
        layer.bounds = bounds
        layer.position = Point(x: bounds.width / 2, y: bounds.height / 2)
        layer.backgroundColor = nil
        layer.opacity = group.opacity
        for child in childLayers {
            layer.addSublayer(child)
        }
        return [layer]
    }

    private struct PathRun: Equatable {
        var path: Path
        var trim: LottieRenderTrim?
    }

    private func pathRuns(for draw: LottieRenderShapeDraw) -> [PathRun] {
        var runs: [PathRun] = []
        for fragment in draw.fragments {
            guard let path = path(for: fragment), !path.isEmpty else { continue }
            let trim = trim(in: fragment.modifiers)
            if let last = runs.last, last.trim == trim {
                var merged = last.path
                merged.addPath(path)
                runs[runs.count - 1] = PathRun(path: merged, trim: trim)
            } else {
                runs.append(PathRun(path: path, trim: trim))
            }
        }
        return runs
    }

    private func path(for fragment: LottieRenderGeometryFragment) -> Path? {
        var path = Path()
        switch fragment.geometry {
        case let .path(bezier):
            PathBuilder.path(from: bezier, into: &path)
        case let .rectangle(center, size, roundness):
            let width = size.scalar(0)
            let height = size.scalar(1)
            let rect = Rect(
                x: center.scalar(0) - width / 2,
                y: center.scalar(1) - height / 2,
                width: width,
                height: height
            )
            if roundness > 0 {
                path.addRoundedRect(in: rect, cornerWidth: roundness, cornerHeight: roundness)
            } else {
                path.addRect(rect)
            }
        case let .ellipse(center, size):
            path.addEllipse(in: Rect(
                x: center.scalar(0) - size.scalar(0) / 2,
                y: center.scalar(1) - size.scalar(1) / 2,
                width: size.scalar(0),
                height: size.scalar(1)
            ))
        }
        guard !path.isEmpty else { return nil }
        return path.applying(affine(for: fragment.transformStack))
    }

    private func affine(for transformStack: [LottieRenderShapeTransform]) -> AffineTransform {
        transformStack.reduce(.identity) { result, transform in
            result.concatenating(affine(for: transform))
        }
    }

    private func affine(for transform: LottieRenderShapeTransform) -> AffineTransform {
        AffineTransform.translation(
            x: -transform.anchor.scalar(0),
            y: -transform.anchor.scalar(1)
        )
        .concatenating(.scale(
            x: transform.scale.scalar(0, default: 100) / 100,
            y: transform.scale.scalar(1, default: 100) / 100
        ))
        .concatenating(.rotation(angle: transform.rotationDegrees * .pi / 180))
        .concatenating(.translation(
            x: transform.position.scalar(0),
            y: transform.position.scalar(1)
        ))
    }

    private func shapeLayer(
        for path: Path,
        trim: LottieRenderTrim?,
        style: LottieRenderShapeStyle,
        bounds: Rect,
        source: LottieRenderSource,
        node: LottieRenderNode
    ) -> ShapeLayer? {
        let layer = ShapeLayer()
        layer.bounds = bounds
        layer.position = Point(x: bounds.width / 2, y: bounds.height / 2)
        layer.fillColor = nil
        layer.path = path

        switch style {
        case let .fill(fill):
            apply(fill, to: layer, at: source, node: node)
            if let trim, !isIdentity(trim) {
                skipBackend(
                    "trimmed fill path",
                    at: source,
                    node: node,
                    term: evidenceTerm("trimmedFill", source: trim.source, values: trimEvidenceValues(trim))
                )
            }
        case let .stroke(stroke):
            apply(stroke, to: layer, at: source, node: node)
            if let trim {
                apply(trim, to: layer, node: node)
            }
        }
        return layer
    }

    private func apply(_ fill: LottieRenderFillStyle, to layer: ShapeLayer, at source: LottieRenderSource, node: LottieRenderNode) {
        if let blendMode = fill.blendMode, blendMode != 0 {
            skipBackend(
                "fill blend mode",
                at: source,
                node: node,
                term: evidenceTerm("fillStyle", source: source, values: fillEvidenceValues(fill))
            )
        }
        layer.fillColor = color(from: fill.color, opacity: fill.opacity)
        layer.fillRule = fill.fillRule == 2 ? .evenOdd : .winding
    }

    private func apply(_ stroke: LottieRenderStrokeStyle, to layer: ShapeLayer, at source: LottieRenderSource, node: LottieRenderNode) {
        if let blendMode = stroke.blendMode, blendMode != 0 {
            skipBackend(
                "stroke blend mode",
                at: source,
                node: node,
                term: evidenceTerm("strokeStyle", source: source, values: strokeEvidenceValues(stroke))
            )
        }
        if let lineCap = stroke.lineCap, lineCap != 1 {
            skipBackend(
                "stroke line cap",
                at: source,
                node: node,
                term: evidenceTerm("strokeStyle", source: source, values: strokeEvidenceValues(stroke))
            )
        }
        if let lineJoin = stroke.lineJoin, lineJoin != 1 {
            skipBackend(
                "stroke line join",
                at: source,
                node: node,
                term: evidenceTerm("strokeStyle", source: source, values: strokeEvidenceValues(stroke))
            )
        }
        if let miterLimit = stroke.miterLimit, abs(miterLimit - 10) > 0.0001 {
            skipBackend(
                "stroke miter limit",
                at: source,
                node: node,
                term: evidenceTerm("strokeStyle", source: source, values: strokeEvidenceValues(stroke))
            )
        }
        if stroke.secondaryMiterLimit != nil {
            skipBackend(
                "secondary stroke miter limit",
                at: source,
                node: node,
                term: evidenceTerm("strokeStyle", source: source, values: strokeEvidenceValues(stroke))
            )
        }
        if hasDashPattern(stroke.dashPattern) {
            skipBackend(
                "stroke dash pattern",
                at: source,
                node: node,
                term: evidenceTerm("strokeStyle", source: source, values: strokeEvidenceValues(stroke))
            )
        }
        layer.strokeColor = color(from: stroke.color, opacity: stroke.opacity)
        layer.lineWidth = stroke.width
    }

    private func apply(_ trim: LottieRenderTrim, to layer: ShapeLayer, node: LottieRenderNode) {
        if trim.multiple == 2 {
            approximateBackend(
                "individual trim (trimmed as one length)",
                at: trim.source,
                node: node,
                term: evidenceTerm("trimPath", source: trim.source, values: trimEvidenceValues(trim))
            )
        }
        if abs(trim.offset) > 0.0001 {
            skipBackend(
                "trim offset",
                at: trim.source,
                node: node,
                term: evidenceTerm("trimPath", source: trim.source, values: trimEvidenceValues(trim))
            )
        }
        layer.strokeStart = fraction(trim.start)
        layer.strokeEnd = fraction(trim.end)
    }

    private func trim(in modifiers: [LottieRenderShapeModifier]) -> LottieRenderTrim? {
        modifiers.compactMap { modifier -> LottieRenderTrim? in
            if case let .trim(trim) = modifier { return trim }
            return nil
        }.last
    }

    private func isIdentity(_ trim: LottieRenderTrim) -> Bool {
        abs(trim.start) <= 0.0001
            && abs(trim.end - 100) <= 0.0001
            && abs(trim.offset) <= 0.0001
    }

    private func hasDashPattern(_ dashPattern: [LottieRenderStrokeDash]) -> Bool {
        dashPattern.contains { dash in
            dash.isAnimated || abs(dash.value ?? 0) > 0.0001
        }
    }

    private func skipBackend(
        _ feature: String,
        at source: LottieRenderSource,
        node: LottieRenderNode?,
        jsonPath: JSONPath? = nil,
        term: LottieBackendGapEvidence.RenderTerm? = nil
    ) {
        let findingJSONPath = jsonPath ?? source.jsonPath
        report.skip(
            feature,
            at: source.sourcePath,
            sourcePath: findingJSONPath,
            sourceRange: source.sourceRange,
            evidence: backendEvidence(
                owner: .backendCapability,
                at: source,
                jsonPath: findingJSONPath,
                node: node,
                term: term
            )
        )
    }

    private func approximateBackend(
        _ feature: String,
        at source: LottieRenderSource,
        node: LottieRenderNode?,
        jsonPath: JSONPath? = nil,
        term: LottieBackendGapEvidence.RenderTerm? = nil
    ) {
        let findingJSONPath = jsonPath ?? source.jsonPath
        report.approximate(
            feature,
            at: source.sourcePath,
            sourcePath: findingJSONPath,
            sourceRange: source.sourceRange,
            evidence: backendEvidence(
                owner: .intentionalApproximation,
                at: source,
                jsonPath: findingJSONPath,
                node: node,
                term: term
            )
        )
    }

    private func backendEvidence(
        owner: LottieBackendGapEvidence.Owner,
        at source: LottieRenderSource,
        jsonPath: JSONPath,
        node: LottieRenderNode?,
        term: LottieBackendGapEvidence.RenderTerm?
    ) -> LottieBackendGapEvidence {
        LottieBackendGapEvidence(
            owner: owner,
            sourceFixture: evidenceContext.sourceFixture,
            sourceFrame: frame.sourceFrame,
            frameRate: frame.frameRate,
            lottiePath: source.sourcePath,
            jsonPath: jsonPath.description,
            sourceRange: source.sourceRange,
            vmTrace: node.map(traceEvidence),
            renderNode: node.map(renderNodeEvidence),
            renderTerm: term,
            expectedLottieWebFrameArtifact: evidenceContext.expectedLottieWebFrameArtifact,
            pureLayerFrameArtifact: evidenceContext.pureLayerFrameArtifact
        )
    }

    private func traceEvidence(for node: LottieRenderNode) -> LottieBackendGapEvidence.VMTrace {
        LottieBackendGapEvidence.VMTrace(
            nodeID: node.trace.nodeID.description,
            instruction: node.trace.instruction.rawValue,
            compositionStack: node.trace.compositionStack,
            layerStack: node.trace.layerStack,
            transformStack: node.trace.transformStack,
            styleStack: node.trace.styleStack,
            matteStack: node.trace.matteStack,
            reason: node.trace.reason
        )
    }

    private func renderNodeEvidence(for node: LottieRenderNode) -> LottieBackendGapEvidence.RenderNode {
        LottieBackendGapEvidence.RenderNode(
            nodeID: node.id.description,
            kind: node.kind.evidenceKind,
            layerName: node.layerName,
            layerIndex: node.layerIndex,
            sourcePath: node.source.sourcePath,
            jsonPath: node.source.jsonPath.description,
            localFrame: node.localFrame,
            opacity: node.opacity,
            explanation: node.explanation
        )
    }

    private func evidenceTerm(
        _ kind: String,
        source: LottieRenderSource,
        jsonPath: JSONPath? = nil,
        values: [String: String] = [:]
    ) -> LottieBackendGapEvidence.RenderTerm {
        LottieBackendGapEvidence.RenderTerm(
            kind: kind,
            sourcePath: source.sourcePath,
            jsonPath: (jsonPath ?? source.jsonPath).description,
            values: values
        )
    }

    private func maskEvidenceValues(_ mask: LottieRenderMask) -> [String: String] {
        [
            "inverted": "\(mask.isInverted)",
            "mode": mask.mode,
            "name": mask.name ?? "",
            "opacity": "\(mask.opacity)",
            "pathEvaluated": "\(mask.path != nil)",
        ]
    }

    private func fillEvidenceValues(_ fill: LottieRenderFillStyle) -> [String: String] {
        [
            "blendMode": fill.blendMode.map { String($0) } ?? "",
            "color": fill.color.map { String($0) }.joined(separator: ","),
            "fillRule": fill.fillRule.map { String($0) } ?? "",
            "opacity": "\(fill.opacity)",
        ]
    }

    private func strokeEvidenceValues(_ stroke: LottieRenderStrokeStyle) -> [String: String] {
        [
            "blendMode": stroke.blendMode.map { String($0) } ?? "",
            "dashCount": "\(stroke.dashPattern.count)",
            "lineCap": stroke.lineCap.map { String($0) } ?? "",
            "lineJoin": stroke.lineJoin.map { String($0) } ?? "",
            "miterLimit": stroke.miterLimit.map { String($0) } ?? "",
            "secondaryMiterLimit": stroke.secondaryMiterLimit.map { String($0) } ?? "",
            "width": "\(stroke.width)",
        ]
    }

    private func trimEvidenceValues(_ trim: LottieRenderTrim) -> [String: String] {
        [
            "end": "\(trim.end)",
            "multiple": trim.multiple.map { String($0) } ?? "",
            "offset": "\(trim.offset)",
            "start": "\(trim.start)",
        ]
    }

    private func color(from components: [Double], opacity: Double) -> Color {
        Color(
            red: components.scalar(0),
            green: components.scalar(1),
            blue: components.scalar(2),
            alpha: (components.count > 3 ? components[3] : 1) * opacity
        )
    }

    private func fraction(_ percent: Double) -> Double {
        min(max(percent / 100, 0), 1)
    }
}

private extension LottieRenderNode.Kind {
    var evidenceKind: String {
        switch self {
        case .shape:
            "shape"
        case .solid:
            "solid"
        case .null:
            "null"
        case .imagePlaceholder:
            "imagePlaceholder"
        case .textPlaceholder:
            "textPlaceholder"
        case .precompositionBoundary:
            "precompositionBoundary"
        case let .unsupportedLayer(rawType):
            "unsupportedLayer(\(rawType))"
        }
    }
}

private extension [Double] {
    func scalar(_ index: Int, default defaultValue: Double = 0) -> Double {
        if indices.contains(index) { return self[index] }
        return last ?? defaultValue
    }
}
