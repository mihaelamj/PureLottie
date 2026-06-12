//
//  ShapeBuilder.swift
//  PureLottie
//

import LottieModel
import PureLayer

/// Lowers a shape layer's drawing program onto `ShapeLayer`s.
///
/// The `DrawingProgram` preserves Lottie's ordered scope semantics using
/// PureDraw/PureLayer terms. This type performs the PureLayer-specific lowering
/// and records anything that cannot be represented exactly.
struct ShapeBuilder {
    let context: ImportContext

    /// Builds the layers for `items` in draw order.
    func layers(for items: [LottieShape], bounds: Rect, at path: String) -> [Layer] {
        let program = DrawingProgramBuilder(context: context).program(for: items, at: path)
        return layers(for: program.nodes, bounds: bounds)
    }

    private func layers(for nodes: [DrawingProgram.Node], bounds: Rect) -> [Layer] {
        nodes.flatMap { node -> [Layer] in
            switch node {
            case let .draw(draw):
                return shapeLayer(for: draw, bounds: bounds).map { [$0] } ?? []
            case let .transparencyLayer(layer):
                return transparencyLayer(for: layer, bounds: bounds)
            }
        }
    }

    private func shapeLayer(for draw: DrawingProgram.DrawCommand, bounds: Rect) -> ShapeLayer? {
        let layer = ShapeLayer()
        layer.bounds = bounds
        layer.position = Point(x: bounds.width / 2, y: bounds.height / 2)
        layer.fillColor = nil
        layer.path = draw.path

        switch draw.paint {
        case let .fill(fill):
            apply(fill, to: layer, at: draw.sourcePath)
            if let trim = draw.trim, !isIdentity(trim) {
                context.report.skip("trimmed fill path", at: draw.sourcePath)
            }
        case let .stroke(stroke):
            apply(stroke, to: layer, at: draw.sourcePath)
            if let trim = draw.trim {
                apply(trim, to: layer, at: draw.sourcePath)
            }
        }
        return layer
    }

    private func transparencyLayer(for node: DrawingProgram.TransparencyLayer, bounds: Rect) -> [Layer] {
        let childLayers = layers(for: node.nodes, bounds: bounds)
        guard !childLayers.isEmpty else { return [] }

        guard let opacity = node.opacity else { return childLayers }
        if opacity.isAnimated {
            context.report.skip("animated group opacity", at: node.sourcePath)
        }
        let staticOpacity = min(max(opacity.initialValue / 100, 0), 1)
        guard abs(staticOpacity - 1) > 0.0001 else { return childLayers }

        let layer = Layer()
        layer.bounds = bounds
        layer.position = Point(x: bounds.width / 2, y: bounds.height / 2)
        layer.backgroundColor = nil
        layer.opacity = staticOpacity
        for child in childLayers {
            layer.addSublayer(child)
        }
        return [layer]
    }

    private func apply(_ fill: ShapeFill, to layer: ShapeLayer, at path: String) {
        if fill.color.isAnimated {
            context.report.skip("animated fill color", at: path)
        }
        if fill.opacity?.isAnimated == true {
            context.report.skip("animated fill opacity", at: path)
        }
        layer.fillColor = color(from: fill.color.initialValue, opacityPercent: fill.opacity?.initialValue ?? 100)
        layer.fillRule = fill.fillRule == 2 ? .evenOdd : .winding
    }

    private func apply(_ stroke: ShapeStroke, to layer: ShapeLayer, at path: String) {
        if stroke.color.isAnimated {
            context.report.skip("animated stroke color", at: path)
        }
        if stroke.opacity?.isAnimated == true {
            context.report.skip("animated stroke opacity", at: path)
        }
        if stroke.width.isAnimated {
            context.report.skip("animated stroke width", at: path)
        }
        layer.strokeColor = color(from: stroke.color.initialValue, opacityPercent: stroke.opacity?.initialValue ?? 100)
        layer.lineWidth = stroke.width.initialValue
    }

    private func apply(_ trim: ShapeTrim, to layer: ShapeLayer, at path: String) {
        if trim.multiple == 2 {
            context.report.approximate("individual trim (trimmed as one length)", at: path)
        }
        if let offset = trim.offset, offset.isAnimated || abs(offset.initialValue) > 0.0001 {
            context.report.skip("trim offset", at: path)
        }
        let fraction = { (percent: Double) in min(max(percent / 100, 0), 1) }
        layer.strokeStart = fraction(trim.start.initialValue)
        layer.strokeEnd = fraction(trim.end.initialValue)
        if case let .keyframed(keyframes) = trim.start {
            let samples = ScalarTimeline.samples(
                from: keyframes,
                dimension: 0,
                frameRate: context.frameRate,
                startFrame: context.startFrame,
                map: fraction
            )
            if let animation = ScalarTimeline.animation(keyPath: "strokeStart", samples: samples, sceneDuration: context.duration, beginTime: context.timeShift) {
                layer.add(animation, forKey: "lottie.strokeStart")
            }
        }
        if case let .keyframed(keyframes) = trim.end {
            let samples = ScalarTimeline.samples(
                from: keyframes,
                dimension: 0,
                frameRate: context.frameRate,
                startFrame: context.startFrame,
                map: fraction
            )
            if let animation = ScalarTimeline.animation(keyPath: "strokeEnd", samples: samples, sceneDuration: context.duration, beginTime: context.timeShift) {
                layer.add(animation, forKey: "lottie.strokeEnd")
            }
        }
    }

    private func isIdentity(_ trim: ShapeTrim) -> Bool {
        if trim.start.isAnimated || trim.end.isAnimated || trim.offset?.isAnimated == true {
            return false
        }
        return abs(trim.start.initialValue) <= 0.0001
            && abs(trim.end.initialValue - 100) <= 0.0001
            && abs(trim.offset?.initialValue ?? 0) <= 0.0001
    }

    private func color(from components: [Double], opacityPercent: Double) -> Color {
        Color(
            red: components.component(0) ?? 0,
            green: components.component(1) ?? 0,
            blue: components.component(2) ?? 0,
            alpha: (components.count > 3 ? components[3] : 1) * min(max(opacityPercent / 100, 0), 1)
        )
    }
}
