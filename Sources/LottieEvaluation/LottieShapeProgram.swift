//
//  LottieShapeProgram.swift
//  PureLottie
//

import LottieModel

/// Source-level shape drawing program after Lottie scope semantics are applied.
///
/// This is still Lottie semantics, not renderer output. Geometry remains in
/// Lottie terms, styles are separate from geometry, and backend-specific path
/// construction is left to import/lowering.
public struct LottieShapeProgram: Sendable, Equatable {
    public var nodes: [Node]
    public var diagnostics: [ValidationError]

    public init(nodes: [Node], diagnostics: [ValidationError] = []) {
        self.nodes = nodes
        self.diagnostics = diagnostics
    }

    public enum Node: Sendable, Equatable {
        case styleRun(StyleRun)
        case group(Group)
    }

    public struct StyleRun: Sendable, Equatable {
        /// Human-readable source path for the style item.
        public var sourcePath: String
        /// Authored Lottie JSON path for the style item.
        public var jsonPath: JSONPath
        /// Fill or stroke style that opened this run.
        public var style: Style
        /// Geometry fragments affected by this style in Lottie reverse-walk scope.
        public var fragments: [GeometryFragment]

        public init(sourcePath: String, jsonPath: JSONPath, style: Style, fragments: [GeometryFragment]) {
            self.sourcePath = sourcePath
            self.jsonPath = jsonPath
            self.style = style
            self.fragments = fragments
        }
    }

    public struct Group: Sendable, Equatable {
        /// Human-readable source path for the group item.
        public var sourcePath: String
        /// Authored Lottie JSON path for the group item.
        public var jsonPath: JSONPath
        /// Group transform item, when authored.
        public var transform: ShapeTransform?
        /// Group opacity from the transform item, when authored.
        public var opacity: AnimatedDouble?
        /// Whether the group can pass through or must become an atomic layer.
        public var compositing: GroupCompositing
        /// Scoped child nodes produced from the group's item list.
        public var nodes: [Node]

        public init(
            sourcePath: String,
            jsonPath: JSONPath,
            transform: ShapeTransform?,
            opacity: AnimatedDouble?,
            compositing: GroupCompositing,
            nodes: [Node]
        ) {
            self.sourcePath = sourcePath
            self.jsonPath = jsonPath
            self.transform = transform
            self.opacity = opacity
            self.compositing = compositing
            self.nodes = nodes
        }
    }

    public enum GroupCompositing: String, Sendable, Equatable {
        case passThrough
        case atomicTransparency
    }

    public struct GeometryFragment: Sendable, Equatable {
        /// Human-readable source path for the geometry item.
        public var sourcePath: String
        /// Authored Lottie JSON path for the geometry item.
        public var jsonPath: JSONPath
        /// Geometry payload in Lottie source terms.
        public var geometry: Geometry
        /// Shape transforms active for this geometry.
        public var transformStack: [AppliedTransform]
        /// Shape modifiers active for this geometry.
        public var modifiers: [Modifier]

        public init(
            sourcePath: String,
            jsonPath: JSONPath,
            geometry: Geometry,
            transformStack: [AppliedTransform],
            modifiers: [Modifier]
        ) {
            self.sourcePath = sourcePath
            self.jsonPath = jsonPath
            self.geometry = geometry
            self.transformStack = transformStack
            self.modifiers = modifiers
        }
    }

    public enum Geometry: Sendable, Equatable {
        case path(ShapePath)
        case rectangle(ShapeRectangle)
        case ellipse(ShapeEllipse)
    }

    public struct AppliedTransform: Sendable, Equatable {
        /// Human-readable source path for the transform item.
        public var sourcePath: String
        /// Authored Lottie JSON path for the transform item.
        public var jsonPath: JSONPath
        /// Transform payload in Lottie source terms.
        public var transform: ShapeTransform

        public init(sourcePath: String, jsonPath: JSONPath, transform: ShapeTransform) {
            self.sourcePath = sourcePath
            self.jsonPath = jsonPath
            self.transform = transform
        }
    }

    public enum Style: Sendable, Equatable {
        case fill(ShapeFill)
        case stroke(ShapeStroke)
    }

    public enum Modifier: Sendable, Equatable {
        case trim(AppliedTrim)
    }

    public struct AppliedTrim: Sendable, Equatable {
        /// Human-readable source path for the trim modifier item.
        public var sourcePath: String
        /// Authored Lottie JSON path for the trim modifier item.
        public var jsonPath: JSONPath
        /// Trim payload in Lottie source terms.
        public var trim: ShapeTrim

        public init(sourcePath: String, jsonPath: JSONPath, trim: ShapeTrim) {
            self.sourcePath = sourcePath
            self.jsonPath = jsonPath
            self.trim = trim
        }
    }
}

/// Builds a `LottieShapeProgram` from a Lottie shape item list.
///
/// Lottie-web walks each item array in reverse. Styles and modifiers encountered
/// during that reverse walk affect the preceding geometry in source order. This
/// builder preserves that behavior while exposing the result without rendering.
public struct LottieShapeProgramBuilder: Sendable {
    public init() {}

    public func program(
        for items: [LottieShape],
        sourcePath: String,
        jsonPath: JSONPath = JSONPath()
    ) -> LottieShapeProgram {
        var diagnostics: [ValidationError] = []
        let scope = ShapeProgramScope()
        let nodes = scope.nodes(
            for: items,
            at: sourcePath,
            jsonPath: jsonPath,
            inheritedStyles: [],
            inheritedTransformStack: [],
            inheritedModifiers: [],
            diagnostics: &diagnostics
        )
        return LottieShapeProgram(nodes: nodes, diagnostics: diagnostics)
    }
}

private final class ShapeProgramStyleAccumulator {
    let sourcePath: String
    let jsonPath: JSONPath
    let style: LottieShapeProgram.Style
    private var fragments: [LottieShapeProgram.GeometryFragment] = []

    init(sourcePath: String, jsonPath: JSONPath, style: LottieShapeProgram.Style) {
        self.sourcePath = sourcePath
        self.jsonPath = jsonPath
        self.style = style
    }

    func append(_ fragment: LottieShapeProgram.GeometryFragment) {
        fragments.append(fragment)
    }

    func node() -> LottieShapeProgram.Node? {
        guard !fragments.isEmpty else { return nil }
        return .styleRun(LottieShapeProgram.StyleRun(
            sourcePath: sourcePath,
            jsonPath: jsonPath,
            style: style,
            fragments: fragments
        ))
    }
}

private enum ShapeProgramNodeBuilder {
    case style(ShapeProgramStyleAccumulator)
    case group(LottieShapeProgram.Group)

    var node: LottieShapeProgram.Node? {
        switch self {
        case let .style(style):
            style.node()
        case let .group(group):
            group.nodes.isEmpty ? nil : .group(group)
        }
    }
}

private struct ShapeProgramScope {
    func nodes(
        for items: [LottieShape],
        at sourcePath: String,
        jsonPath: JSONPath,
        inheritedStyles: [ShapeProgramStyleAccumulator],
        inheritedTransformStack: [LottieShapeProgram.AppliedTransform],
        inheritedModifiers: [LottieShapeProgram.Modifier],
        diagnostics: inout [ValidationError]
    ) -> [LottieShapeProgram.Node] {
        var builders: [ShapeProgramNodeBuilder] = []
        var activeStyles = inheritedStyles
        var activeTransformStack = inheritedTransformStack
        var activeModifiers = inheritedModifiers
        var hasLocalTransform = false

        for offset in items.indices.reversed() {
            let item = items[offset]
            let itemPath = jsonPath.appending(.index(offset))
            switch item {
            case let .group(group):
                guard group.isHidden != true else { continue }
                let groupSourcePath = "\(sourcePath) > group '\(group.name ?? "?")'"
                let transform = group.transform
                let groupNodes = nodes(
                    for: group.items,
                    at: groupSourcePath,
                    jsonPath: itemPath.appending(.key("it")),
                    inheritedStyles: activeStyles,
                    inheritedTransformStack: activeTransformStack,
                    inheritedModifiers: activeModifiers,
                    diagnostics: &diagnostics
                )
                builders.append(.group(LottieShapeProgram.Group(
                    sourcePath: groupSourcePath,
                    jsonPath: itemPath,
                    transform: transform,
                    opacity: transform?.opacity,
                    compositing: compositing(for: transform?.opacity),
                    nodes: groupNodes
                )))
            case let .path(shapePath):
                guard shapePath.isHidden != true else { continue }
                if shapePath.shape.isAnimated {
                    diagnostics.append(diagnostic(
                        ruleID: "lottie.evaluation.shape.path-morph.unsupported",
                        feature: "path morph",
                        path: itemPath.appending(.key("ks")),
                        sourcePath: "\(sourcePath) > path '\(shapePath.name ?? "?")'",
                        classification: .approximate
                    ))
                }
                append(
                    .path(shapePath),
                    sourcePath: "\(sourcePath) > path '\(shapePath.name ?? "?")'",
                    jsonPath: itemPath,
                    transformStack: activeTransformStack,
                    modifiers: activeModifiers,
                    to: activeStyles
                )
            case let .rectangle(rectangle):
                guard rectangle.isHidden != true else { continue }
                if rectangle.position.isAnimated || rectangle.size.isAnimated {
                    diagnostics.append(diagnostic(
                        ruleID: "lottie.evaluation.shape.rectangle.animated-geometry.unsupported",
                        feature: "animated rectangle geometry",
                        path: itemPath,
                        sourcePath: "\(sourcePath) > rectangle '\(rectangle.name ?? "?")'",
                        classification: .gap
                    ))
                }
                append(
                    .rectangle(rectangle),
                    sourcePath: "\(sourcePath) > rectangle '\(rectangle.name ?? "?")'",
                    jsonPath: itemPath,
                    transformStack: activeTransformStack,
                    modifiers: activeModifiers,
                    to: activeStyles
                )
            case let .ellipse(ellipse):
                guard ellipse.isHidden != true else { continue }
                if ellipse.position.isAnimated || ellipse.size.isAnimated {
                    diagnostics.append(diagnostic(
                        ruleID: "lottie.evaluation.shape.ellipse.animated-geometry.unsupported",
                        feature: "animated ellipse geometry",
                        path: itemPath,
                        sourcePath: "\(sourcePath) > ellipse '\(ellipse.name ?? "?")'",
                        classification: .gap
                    ))
                }
                append(
                    .ellipse(ellipse),
                    sourcePath: "\(sourcePath) > ellipse '\(ellipse.name ?? "?")'",
                    jsonPath: itemPath,
                    transformStack: activeTransformStack,
                    modifiers: activeModifiers,
                    to: activeStyles
                )
            case let .fill(fill):
                guard fill.isHidden != true else { continue }
                let style = ShapeProgramStyleAccumulator(
                    sourcePath: "\(sourcePath) > fill '\(fill.name ?? "?")'",
                    jsonPath: itemPath,
                    style: .fill(fill)
                )
                activeStyles.append(style)
                builders.append(.style(style))
            case let .stroke(stroke):
                guard stroke.isHidden != true else { continue }
                let style = ShapeProgramStyleAccumulator(
                    sourcePath: "\(sourcePath) > stroke '\(stroke.name ?? "?")'",
                    jsonPath: itemPath,
                    style: .stroke(stroke)
                )
                activeStyles.append(style)
                builders.append(.style(style))
            case let .trim(trim):
                guard trim.isHidden != true else { continue }
                if !activeModifiers.isEmpty {
                    diagnostics.append(diagnostic(
                        ruleID: "lottie.evaluation.shape.trim.stacked",
                        feature: "stacked trim paths",
                        path: itemPath,
                        sourcePath: "\(sourcePath) > trim '\(trim.name ?? "?")'",
                        classification: .approximate
                    ))
                }
                activeModifiers = [
                    .trim(LottieShapeProgram.AppliedTrim(
                        sourcePath: "\(sourcePath) > trim '\(trim.name ?? "?")'",
                        jsonPath: itemPath,
                        trim: trim
                    )),
                ]
            case let .transform(transform):
                guard transform.isHidden != true else { continue }
                if hasLocalTransform {
                    diagnostics.append(diagnostic(
                        ruleID: "lottie.evaluation.shape.transform.multiple",
                        feature: "multiple shape transforms",
                        path: itemPath,
                        sourcePath: "\(sourcePath) > transform '\(transform.name ?? "?")'",
                        classification: .approximate
                    ))
                }
                hasLocalTransform = true
                activeTransformStack = [
                    LottieShapeProgram.AppliedTransform(
                        sourcePath: "\(sourcePath) > transform '\(transform.name ?? "?")'",
                        jsonPath: itemPath,
                        transform: transform
                    ),
                ] + activeTransformStack
            case let .unsupported(type, name):
                diagnostics.append(diagnostic(
                    ruleID: "lottie.evaluation.shape.unsupported-type",
                    feature: "shape type '\(type)'",
                    path: itemPath,
                    sourcePath: "\(sourcePath) > '\(name ?? "?")'",
                    classification: .reported
                ))
            }
        }

        return builders.compactMap(\.node)
    }

    private func append(
        _ geometry: LottieShapeProgram.Geometry,
        sourcePath: String,
        jsonPath: JSONPath,
        transformStack: [LottieShapeProgram.AppliedTransform],
        modifiers: [LottieShapeProgram.Modifier],
        to styles: [ShapeProgramStyleAccumulator]
    ) {
        guard !styles.isEmpty else { return }
        let fragment = LottieShapeProgram.GeometryFragment(
            sourcePath: sourcePath,
            jsonPath: jsonPath,
            geometry: geometry,
            transformStack: transformStack,
            modifiers: modifiers
        )
        for style in styles {
            style.append(fragment)
        }
    }

    private func compositing(for opacity: AnimatedDouble?) -> LottieShapeProgram.GroupCompositing {
        guard let opacity else { return .passThrough }
        if opacity.isAnimated || abs(opacity.initialValue - 100) > 0.0001 {
            return .atomicTransparency
        }
        return .passThrough
    }

    private func diagnostic(
        ruleID: String,
        feature: String,
        path: JSONPath,
        sourcePath: String,
        classification: FeatureClassification
    ) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: feature,
            at: path,
            severity: .warning,
            phase: .semantic,
            classification: classification,
            evidence: sourcePath
        )
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
