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
    public func lower(_ frame: LottieRenderFrame) -> LottieRenderLayerTree {
        let context = RenderIRLoweringContext(frame: frame)
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
    let report = ImportReportBuilder()

    init(frame: LottieRenderFrame) {
        self.frame = frame
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
            report.skip("image layer\(suffix)", at: node.source.sourcePath, sourcePath: node.source.jsonPath)
            layer = nil
        case .textPlaceholder:
            report.skip("text layer", at: node.source.sourcePath, sourcePath: node.source.jsonPath)
            layer = nil
        case let .precompositionBoundary(precomposition):
            report.approximate(
                "precomposition boundary '\(precomposition.assetID)' flattened into evaluated child nodes",
                at: node.source.sourcePath,
                sourcePath: node.source.jsonPath
            )
            layer = carrierLayer()
        case let .unsupportedLayer(rawType):
            report.skip("layer type \(rawType)", at: node.source.sourcePath, sourcePath: node.source.jsonPath)
            layer = nil
        }

        guard let layer else { return nil }
        apply(node, to: layer)
        applyMasks(node.masks, to: layer, at: node.source)
        return layer
    }

    private func reportNodeGaps(_ node: LottieRenderNode) {
        if let marker = node.matteSourceMarker {
            report.skip(
                "track matte source marker \(marker)",
                at: node.source.sourcePath,
                sourcePath: node.source.jsonPath.appending(.key("td"))
            )
        }
        if let matte = node.matte {
            var feature = "track matte mode \(matte.mode)"
            if let sourcePath = matte.sourcePath {
                feature += " using \(sourcePath)"
            }
            report.skip(feature, at: node.source.sourcePath, sourcePath: node.source.jsonPath.appending(.key("tt")))
        }
        if let blendMode = node.compositing.blendMode, blendMode != 0 {
            report.skip("layer blend mode \(blendMode)", at: node.source.sourcePath, sourcePath: node.source.jsonPath)
        }
        for filter in node.filters {
            report.skip("filter '\(filter.type)'", at: filter.source.sourcePath, sourcePath: filter.source.jsonPath)
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

    private func shapeLayerContainer(for shape: LottieRenderShape, node _: LottieRenderNode) -> Layer {
        let layer = carrierLayer()
        for sublayer in shapeLayers(for: shape.nodes, bounds: layer.bounds) {
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

    private func applyMasks(_ masks: [LottieRenderMask], to layer: Layer, at source: LottieRenderSource) {
        guard !masks.isEmpty else { return }
        guard masks.count == 1, let mask = masks.first else {
            report.skip("multiple masks", at: source.sourcePath, sourcePath: source.jsonPath)
            return
        }
        guard mask.mode == "a" || mask.mode == "n" else {
            report.skip("mask mode '\(mask.mode)'", at: mask.source.sourcePath, sourcePath: mask.source.jsonPath)
            return
        }
        guard mask.mode != "n" else { return }
        guard !mask.isInverted else {
            report.skip("inverted mask", at: mask.source.sourcePath, sourcePath: mask.source.jsonPath)
            return
        }
        guard let bezier = mask.path else {
            report.skip("missing mask path", at: mask.source.sourcePath, sourcePath: mask.source.jsonPath)
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

    private func shapeLayers(for nodes: [LottieRenderShapeNode], bounds: Rect) -> [Layer] {
        nodes.flatMap { node -> [Layer] in
            switch node {
            case let .draw(draw):
                shapeLayers(for: draw, bounds: bounds)
            case let .transparencyGroup(group):
                transparencyLayer(for: group, bounds: bounds)
            }
        }
    }

    private func shapeLayers(for draw: LottieRenderShapeDraw, bounds: Rect) -> [Layer] {
        let runs = pathRuns(for: draw)
        return runs.compactMap { run in
            shapeLayer(for: run.path, trim: run.trim, style: draw.style, bounds: bounds, source: draw.source)
        }
    }

    private func transparencyLayer(for group: LottieRenderShapeGroup, bounds: Rect) -> [Layer] {
        let childLayers = shapeLayers(for: group.nodes, bounds: bounds)
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
        source: LottieRenderSource
    ) -> ShapeLayer? {
        let layer = ShapeLayer()
        layer.bounds = bounds
        layer.position = Point(x: bounds.width / 2, y: bounds.height / 2)
        layer.fillColor = nil
        layer.path = path

        switch style {
        case let .fill(fill):
            apply(fill, to: layer, at: source)
            if let trim, !isIdentity(trim) {
                report.skip("trimmed fill path", at: source.sourcePath, sourcePath: source.jsonPath)
            }
        case let .stroke(stroke):
            apply(stroke, to: layer, at: source)
            if let trim {
                apply(trim, to: layer)
            }
        }
        return layer
    }

    private func apply(_ fill: LottieRenderFillStyle, to layer: ShapeLayer, at source: LottieRenderSource) {
        if let blendMode = fill.blendMode, blendMode != 0 {
            report.skip("fill blend mode", at: source.sourcePath, sourcePath: source.jsonPath)
        }
        layer.fillColor = color(from: fill.color, opacity: fill.opacity)
        layer.fillRule = fill.fillRule == 2 ? .evenOdd : .winding
    }

    private func apply(_ stroke: LottieRenderStrokeStyle, to layer: ShapeLayer, at source: LottieRenderSource) {
        if let blendMode = stroke.blendMode, blendMode != 0 {
            report.skip("stroke blend mode", at: source.sourcePath, sourcePath: source.jsonPath)
        }
        if let lineCap = stroke.lineCap, lineCap != 1 {
            report.skip("stroke line cap", at: source.sourcePath, sourcePath: source.jsonPath)
        }
        if let lineJoin = stroke.lineJoin, lineJoin != 1 {
            report.skip("stroke line join", at: source.sourcePath, sourcePath: source.jsonPath)
        }
        if let miterLimit = stroke.miterLimit, abs(miterLimit - 10) > 0.0001 {
            report.skip("stroke miter limit", at: source.sourcePath, sourcePath: source.jsonPath)
        }
        if stroke.secondaryMiterLimit != nil {
            report.skip("secondary stroke miter limit", at: source.sourcePath, sourcePath: source.jsonPath)
        }
        if hasDashPattern(stroke.dashPattern) {
            report.skip("stroke dash pattern", at: source.sourcePath, sourcePath: source.jsonPath)
        }
        layer.strokeColor = color(from: stroke.color, opacity: stroke.opacity)
        layer.lineWidth = stroke.width
    }

    private func apply(_ trim: LottieRenderTrim, to layer: ShapeLayer) {
        if trim.multiple == 2 {
            report.approximate("individual trim (trimmed as one length)", at: trim.source.sourcePath, sourcePath: trim.source.jsonPath)
        }
        if abs(trim.offset) > 0.0001 {
            report.skip("trim offset", at: trim.source.sourcePath, sourcePath: trim.source.jsonPath)
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

private extension [Double] {
    func scalar(_ index: Int, default defaultValue: Double = 0) -> Double {
        if indices.contains(index) { return self[index] }
        return last ?? defaultValue
    }
}
