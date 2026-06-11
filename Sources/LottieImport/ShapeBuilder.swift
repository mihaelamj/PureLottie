//
//  ShapeBuilder.swift
//  PureLottie
//

import LottieModel
import PureLayer

/// Maps a shape layer's item list onto `ShapeLayer`s.
///
/// Each group with geometry and at least one style becomes one `ShapeLayer`
/// whose path is the group's combined geometry; nested groups become sibling
/// layers. A `tm` trim modifier maps onto `strokeStart`/`strokeEnd`, including
/// animated trims.
struct ShapeBuilder {
    let context: ImportContext

    /// Builds the layers for `items`, bottom-most first (PureLayer draws later
    /// sublayers on top; Lottie lists topmost items first).
    func layers(for items: [LottieShape], bounds: Rect, at path: String) -> [Layer] {
        var result: [Layer] = []
        if let shapeLayer = shapeLayer(for: items, bounds: bounds, at: path) {
            result.append(shapeLayer)
        }
        for item in items.reversed() {
            if case let .group(group) = item {
                let groupPath = "\(path) > group '\(group.name ?? "?")'"
                result.append(contentsOf: layers(for: group.items, bounds: bounds, at: groupPath))
            }
        }
        return result
    }

    /// One `ShapeLayer` from the level's own geometry and styles, or `nil`
    /// when the level has no drawable geometry.
    private func shapeLayer(for items: [LottieShape], bounds: Rect, at path: String) -> ShapeLayer? {
        var geometry = Path()
        var fill: ShapeFill?
        var stroke: ShapeStroke?
        var trim: ShapeTrim?
        var groupTransform: ShapeTransform?

        for item in items {
            switch item {
            case .group:
                break // Recursed by `layers(for:bounds:at:)`.
            case let .path(shapePath):
                if shapePath.shape.isAnimated {
                    context.report.skip("path morph", at: "\(path) > path '\(shapePath.name ?? "?")'")
                }
                if let bezier = shapePath.shape.initialValue {
                    PathBuilder.path(from: bezier, into: &geometry)
                }
            case let .rectangle(rectangle):
                if rectangle.position.isAnimated || rectangle.size.isAnimated {
                    context.report.skip("animated rectangle geometry", at: path)
                }
                PathBuilder.rectangle(rectangle, into: &geometry)
            case let .ellipse(ellipse):
                if ellipse.position.isAnimated || ellipse.size.isAnimated {
                    context.report.skip("animated ellipse geometry", at: path)
                }
                PathBuilder.ellipse(ellipse, into: &geometry)
            case let .fill(shapeFill):
                fill = shapeFill
            case let .stroke(shapeStroke):
                stroke = shapeStroke
            case let .trim(shapeTrim):
                trim = shapeTrim
            case let .transform(transform):
                groupTransform = transform
            case let .unsupported(type, name):
                context.report.skip("shape type '\(type)'", at: "\(path) > '\(name ?? "?")'")
            }
        }

        guard !geometry.isEmpty, fill != nil || stroke != nil else { return nil }

        let layer = ShapeLayer()
        layer.bounds = bounds
        layer.position = Point(x: bounds.width / 2, y: bounds.height / 2)
        layer.fillColor = nil
        if let groupTransform {
            geometry = applied(groupTransform, to: geometry, at: path)
        }
        layer.path = geometry

        if let fill {
            apply(fill, to: layer, at: path)
        }
        if let stroke {
            apply(stroke, to: layer, at: path)
        }
        if let trim {
            apply(trim, to: layer, at: path)
        }
        return layer
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

    /// Bakes a static group transform into the geometry; an animated group
    /// transform is reported and its initial pose baked.
    private func applied(_ transform: ShapeTransform, to geometry: Path, at path: String) -> Path {
        let animated = (transform.anchor?.isAnimated ?? false)
            || (transform.position?.isAnimated ?? false)
            || (transform.scale?.isAnimated ?? false)
            || (transform.rotation?.isAnimated ?? false)
        if animated {
            context.report.skip("animated group transform", at: path)
        }
        if transform.opacity?.isAnimated == true {
            context.report.skip("animated group opacity", at: path)
        }
        let anchor = transform.anchor?.initialValue ?? []
        let position = transform.position?.initialValue ?? []
        let scale = transform.scale?.initialValue ?? []
        let rotation = (transform.rotation?.initialValue ?? 0) * .pi / 180
        let affine = AffineTransform.translation(x: -(anchor.component(0) ?? 0), y: -(anchor.component(1) ?? 0))
            .concatenating(.scale(x: (scale.component(0) ?? 100) / 100, y: (scale.component(1) ?? 100) / 100))
            .concatenating(.rotation(angle: rotation))
            .concatenating(.translation(x: position.component(0) ?? 0, y: position.component(1) ?? 0))
        return geometry.applying(affine)
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
