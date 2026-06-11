//
//  LottieShape.swift
//  PureLottie
//

/// One item in a shape layer's `shapes` list, discriminated by the `ty` field.
///
/// The supported subset is decoded into typed payloads; everything else is
/// preserved as `.unsupported` so the importer can report it by name instead of
/// dropping it silently.
public indirect enum LottieShape: Sendable, Equatable {
    case group(ShapeGroup)
    case path(ShapePath)
    case rectangle(ShapeRectangle)
    case ellipse(ShapeEllipse)
    case fill(ShapeFill)
    case stroke(ShapeStroke)
    case trim(ShapeTrim)
    case transform(ShapeTransform)
    case unsupported(type: String, name: String?)

    /// The `nm` display name, when the payload carries one.
    public var name: String? {
        switch self {
        case let .group(group): group.name
        case let .path(path): path.name
        case let .rectangle(rectangle): rectangle.name
        case let .ellipse(ellipse): ellipse.name
        case let .fill(fill): fill.name
        case let .stroke(stroke): stroke.name
        case let .trim(trim): trim.name
        case let .transform(transform): transform.name
        case let .unsupported(_, name): name
        }
    }
}

extension LottieShape: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type = "ty"
        case name = "nm"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "gr":
            self = try .group(ShapeGroup(from: decoder))
        case "sh":
            self = try .path(ShapePath(from: decoder))
        case "rc":
            self = try .rectangle(ShapeRectangle(from: decoder))
        case "el":
            self = try .ellipse(ShapeEllipse(from: decoder))
        case "fl":
            self = try .fill(ShapeFill(from: decoder))
        case "st":
            self = try .stroke(ShapeStroke(from: decoder))
        case "tm":
            self = try .trim(ShapeTrim(from: decoder))
        case "tr":
            self = try .transform(ShapeTransform(from: decoder))
        default:
            self = try .unsupported(type: type, name: container.decodeIfPresent(String.self, forKey: .name))
        }
    }
}

/// A `gr` group: nested items drawn together, with the group's own transform as
/// the trailing `tr` item.
public struct ShapeGroup: Decodable, Sendable, Equatable {
    public var name: String?
    public var items: [LottieShape]

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case items = "it"
    }
}

/// An `sh` bezier path.
public struct ShapePath: Decodable, Sendable, Equatable {
    public var name: String?
    public var shape: AnimatedBezier

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case shape = "ks"
    }
}

/// An `rc` rectangle primitive, positioned by center.
public struct ShapeRectangle: Decodable, Sendable, Equatable {
    public var name: String?
    public var position: AnimatedVector
    public var size: AnimatedVector
    public var roundness: AnimatedDouble?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case position = "p"
        case size = "s"
        case roundness = "r"
    }
}

/// An `el` ellipse primitive, positioned by center.
public struct ShapeEllipse: Decodable, Sendable, Equatable {
    public var name: String?
    public var position: AnimatedVector
    public var size: AnimatedVector

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case position = "p"
        case size = "s"
    }
}

/// An `fl` solid fill: RGB(A) color in unit components plus percent opacity.
public struct ShapeFill: Decodable, Sendable, Equatable {
    public var name: String?
    public var color: AnimatedVector
    public var opacity: AnimatedDouble?
    /// 1 = non-zero winding, 2 = even-odd.
    public var fillRule: Int?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case color = "c"
        case opacity = "o"
        case fillRule = "r"
    }
}

/// An `st` stroke: color, percent opacity, and width in points.
public struct ShapeStroke: Decodable, Sendable, Equatable {
    public var name: String?
    public var color: AnimatedVector
    public var opacity: AnimatedDouble?
    public var width: AnimatedDouble

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case color = "c"
        case opacity = "o"
        case width = "w"
    }
}

/// A `tm` trim-paths modifier: start/end/offset as percentages of the path
/// length. `multiple` (`m`) selects simultaneous (1) or individual (2)
/// trimming when several paths precede the modifier.
public struct ShapeTrim: Decodable, Sendable, Equatable {
    public var name: String?
    public var start: AnimatedDouble
    public var end: AnimatedDouble
    public var offset: AnimatedDouble?
    public var multiple: Int?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case start = "s"
        case end = "e"
        case offset = "o"
        case multiple = "m"
    }
}

/// A `tr` group transform: same anatomy as a layer transform.
public struct ShapeTransform: Decodable, Sendable, Equatable {
    public var name: String?
    public var anchor: AnimatedVector?
    public var position: AnimatedVector?
    public var scale: AnimatedVector?
    public var rotation: AnimatedDouble?
    public var opacity: AnimatedDouble?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case anchor = "a"
        case position = "p"
        case scale = "s"
        case rotation = "r"
        case opacity = "o"
    }
}
