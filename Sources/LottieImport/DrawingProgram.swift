//
//  DrawingProgram.swift
//  PureLottie
//

import LottieEvaluation
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
        let semantic = LottieShapeProgramBuilder().program(for: items, sourcePath: sourcePath)
        context.report.reportShapeDiagnostics(semantic.diagnostics)
        return DrawingProgram(nodes: DrawingProgramLowerer(context: context).nodes(for: semantic.nodes))
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

private struct DrawingProgramLowerer {
    let context: ImportContext

    func nodes(for nodes: [LottieShapeProgram.Node]) -> [DrawingProgram.Node] {
        nodes.flatMap { node -> [DrawingProgram.Node] in
            switch node {
            case let .styleRun(run):
                return styleNodes(for: run)
            case let .group(group):
                return groupNode(for: group).map { [$0] } ?? []
            }
        }
    }

    private func styleNodes(for run: LottieShapeProgram.StyleRun) -> [DrawingProgram.Node] {
        let accumulator = DrawingStyleAccumulator(sourcePath: run.sourcePath, paint: paint(for: run.style))
        for fragment in run.fragments {
            guard let path = path(for: fragment) else { continue }
            accumulator.append(path, trim: trim(in: fragment.modifiers))
        }
        return accumulator.nodes()
    }

    private func groupNode(for group: LottieShapeProgram.Group) -> DrawingProgram.Node? {
        let childNodes = nodes(for: group.nodes)
        guard !childNodes.isEmpty else { return nil }
        return .transparencyLayer(DrawingProgram.TransparencyLayer(
            sourcePath: group.sourcePath,
            opacity: group.opacity,
            nodes: childNodes
        ))
    }

    private func paint(for style: LottieShapeProgram.Style) -> DrawingProgram.Paint {
        switch style {
        case let .fill(fill):
            .fill(fill)
        case let .stroke(stroke):
            .stroke(stroke)
        }
    }

    private func path(for fragment: LottieShapeProgram.GeometryFragment) -> Path? {
        let geometry = LottieSourceGeometryEvaluator(animation: context.animation).evaluate(
            fragment.geometry,
            at: context.startFrame,
            sourcePath: fragment.sourcePath,
            jsonPath: fragment.jsonPath
        )
        context.report.reportShapeDiagnostics(geometry.diagnostics)

        var path = Path()
        PathBuilder.path(from: geometry.value.bezier, into: &path)

        guard !path.isEmpty else { return nil }
        return path.applying(affine(for: fragment.transformStack))
    }

    private func trim(in modifiers: [LottieShapeProgram.Modifier]) -> ShapeTrim? {
        modifiers.compactMap { modifier -> ShapeTrim? in
            if case let .trim(applied) = modifier { return applied.trim }
            return nil
        }.last
    }

    private func affine(for transformStack: [LottieShapeProgram.AppliedTransform]) -> AffineTransform {
        transformStack.reduce(.identity) { result, applied in
            result.concatenating(affine(for: applied.transform, at: applied.sourcePath))
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
