//
//  DrawingProgram.swift
//  PureLottie
//

import LottieModel
import PureLayer

/// PureLottie's internal drawing DSL.
///
/// The terms intentionally follow PureDraw/PureLayer vocabulary: a draw command
/// has a `Path` and `Paint`; a grouped subtree is a PureLayer-style transparency
/// layer when its opacity affects compositing. Lottie-specific data is retained
/// only where the importer still needs it for animation lowering or reporting.
struct DrawingProgram {
    var nodes: [Node]

    enum Node {
        case draw(DrawCommand)
        case transparencyLayer(TransparencyLayer)
    }

    struct DrawCommand {
        var sourcePath: String
        var path: Path
        var paint: Paint
        var trim: ShapeTrim?
    }

    struct TransparencyLayer {
        var sourcePath: String
        var opacity: AnimatedDouble?
        var nodes: [Node]
    }

    enum Paint {
        case fill(ShapeFill)
        case stroke(ShapeStroke)
    }
}

/// Builds a `DrawingProgram` from one Lottie shape item list.
struct DrawingProgramBuilder {
    let context: ImportContext

    func program(for items: [LottieShape], at sourcePath: String) -> DrawingProgram {
        let scope = DrawingProgramScope(context: context)
        return DrawingProgram(nodes: scope.nodes(
            for: items,
            at: sourcePath,
            inheritedStyles: [],
            inheritedTransform: .identity,
            inheritedTrim: nil
        ))
    }
}

private final class DrawingStyleAccumulator {
    private struct PathRun {
        var path: Path
        var trim: ShapeTrim?
    }

    let sourcePath: String
    let paint: DrawingProgram.Paint
    private var runs: [PathRun] = []

    init(sourcePath: String, paint: DrawingProgram.Paint) {
        self.sourcePath = sourcePath
        self.paint = paint
    }

    func append(_ path: Path, trim: ShapeTrim?) {
        guard !path.isEmpty else { return }
        if let last = runs.last, last.trim == trim {
            var merged = last.path
            merged.addPath(path)
            runs[runs.count - 1] = PathRun(path: merged, trim: trim)
        } else {
            runs.append(PathRun(path: path, trim: trim))
        }
    }

    func nodes() -> [DrawingProgram.Node] {
        runs
            .filter { !$0.path.isEmpty }
            .map { run in
                .draw(DrawingProgram.DrawCommand(
                    sourcePath: sourcePath,
                    path: run.path,
                    paint: paint,
                    trim: run.trim
                ))
            }
    }
}

private enum DrawingProgramNodeBuilder {
    case style(DrawingStyleAccumulator)
    case transparencyLayer(DrawingProgram.TransparencyLayer)

    var nodes: [DrawingProgram.Node] {
        switch self {
        case let .style(style):
            style.nodes()
        case let .transparencyLayer(layer):
            layer.nodes.isEmpty ? [] : [.transparencyLayer(layer)]
        }
    }
}

private struct DrawingProgramScope {
    let context: ImportContext

    func nodes(
        for items: [LottieShape],
        at sourcePath: String,
        inheritedStyles: [DrawingStyleAccumulator],
        inheritedTransform: AffineTransform,
        inheritedTrim: ShapeTrim?
    ) -> [DrawingProgram.Node] {
        var builders: [DrawingProgramNodeBuilder] = []
        var activeStyles = inheritedStyles
        var activeTransform = inheritedTransform
        var activeTrim = inheritedTrim
        var hasLocalTransform = false

        for item in items.reversed() {
            switch item {
            case let .group(group):
                guard group.isHidden != true else { continue }
                let groupSourcePath = "\(sourcePath) > group '\(group.name ?? "?")'"
                let groupNodes = nodes(
                    for: group.items,
                    at: groupSourcePath,
                    inheritedStyles: activeStyles,
                    inheritedTransform: activeTransform,
                    inheritedTrim: activeTrim
                )
                builders.append(.transparencyLayer(DrawingProgram.TransparencyLayer(
                    sourcePath: groupSourcePath,
                    opacity: group.transform?.opacity,
                    nodes: groupNodes
                )))
            case let .path(shapePath):
                guard shapePath.isHidden != true else { continue }
                if shapePath.shape.isAnimated {
                    context.report.skip("path morph", at: "\(sourcePath) > path '\(shapePath.name ?? "?")'")
                }
                if let bezier = shapePath.shape.initialValue {
                    var path = Path()
                    PathBuilder.path(from: bezier, into: &path)
                    append(path, to: activeStyles, transform: activeTransform, trim: activeTrim)
                }
            case let .rectangle(rectangle):
                guard rectangle.isHidden != true else { continue }
                if rectangle.position.isAnimated || rectangle.size.isAnimated {
                    context.report.skip("animated rectangle geometry", at: "\(sourcePath) > rectangle '\(rectangle.name ?? "?")'")
                }
                var path = Path()
                PathBuilder.rectangle(rectangle, into: &path)
                append(path, to: activeStyles, transform: activeTransform, trim: activeTrim)
            case let .ellipse(ellipse):
                guard ellipse.isHidden != true else { continue }
                if ellipse.position.isAnimated || ellipse.size.isAnimated {
                    context.report.skip("animated ellipse geometry", at: "\(sourcePath) > ellipse '\(ellipse.name ?? "?")'")
                }
                var path = Path()
                PathBuilder.ellipse(ellipse, into: &path)
                append(path, to: activeStyles, transform: activeTransform, trim: activeTrim)
            case let .fill(fill):
                guard fill.isHidden != true else { continue }
                let style = DrawingStyleAccumulator(
                    sourcePath: "\(sourcePath) > fill '\(fill.name ?? "?")'",
                    paint: .fill(fill)
                )
                activeStyles.append(style)
                builders.append(.style(style))
            case let .stroke(stroke):
                guard stroke.isHidden != true else { continue }
                let style = DrawingStyleAccumulator(
                    sourcePath: "\(sourcePath) > stroke '\(stroke.name ?? "?")'",
                    paint: .stroke(stroke)
                )
                activeStyles.append(style)
                builders.append(.style(style))
            case let .trim(trim):
                guard trim.isHidden != true else { continue }
                if activeTrim != nil {
                    context.report.approximate("stacked trim paths", at: "\(sourcePath) > trim '\(trim.name ?? "?")'")
                }
                activeTrim = trim
            case let .transform(transform):
                guard transform.isHidden != true else { continue }
                if hasLocalTransform {
                    context.report.approximate("multiple shape transforms", at: "\(sourcePath) > transform '\(transform.name ?? "?")'")
                }
                hasLocalTransform = true
                activeTransform = affine(for: transform, at: "\(sourcePath) > transform '\(transform.name ?? "?")'")
                    .concatenating(activeTransform)
            case let .unsupported(type, name):
                context.report.skip("shape type '\(type)'", at: "\(sourcePath) > '\(name ?? "?")'")
            }
        }

        return builders.flatMap(\.nodes)
    }

    private func append(
        _ path: Path,
        to styles: [DrawingStyleAccumulator],
        transform: AffineTransform,
        trim: ShapeTrim?
    ) {
        let transformed = path.applying(transform)
        for style in styles {
            style.append(transformed, trim: trim)
        }
    }

    /// Static shape transforms are baked into the PureDraw path. Animated
    /// transforms are reported and the initial pose is used.
    private func affine(for transform: ShapeTransform, at sourcePath: String) -> AffineTransform {
        let animated = (transform.anchor?.isAnimated ?? false)
            || (transform.position?.isAnimated ?? false)
            || (transform.scale?.isAnimated ?? false)
            || (transform.rotation?.isAnimated ?? false)
        if animated {
            context.report.skip("animated shape transform", at: sourcePath)
        }
        let anchor = transform.anchor?.initialValue ?? []
        let position = transform.position?.initialValue ?? []
        let scale = transform.scale?.initialValue ?? []
        let rotation = (transform.rotation?.initialValue ?? 0) * .pi / 180
        return AffineTransform.translation(x: -(anchor.component(0) ?? 0), y: -(anchor.component(1) ?? 0))
            .concatenating(.scale(x: (scale.component(0) ?? 100) / 100, y: (scale.component(1) ?? 100) / 100))
            .concatenating(.rotation(angle: rotation))
            .concatenating(.translation(x: position.component(0) ?? 0, y: position.component(1) ?? 0))
    }
}

private extension ShapeGroup {
    var transform: ShapeTransform? {
        items.reversed().compactMap { item -> ShapeTransform? in
            if case let .transform(transform) = item, transform.isHidden != true { return transform }
            return nil
        }.first
    }
}
