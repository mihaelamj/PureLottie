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
    case polystar(ShapePolystar)
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
        case let .polystar(polystar): polystar.name
        case let .fill(fill): fill.name
        case let .stroke(stroke): stroke.name
        case let .trim(trim): trim.name
        case let .transform(transform): transform.name
        case let .unsupported(_, name): name
        }
    }

    /// The `hd` flag. Hidden shapes are part of the document model but do not
    /// contribute geometry or style when importing.
    public var isHidden: Bool {
        switch self {
        case let .group(group): group.isHidden == true
        case let .path(path): path.isHidden == true
        case let .rectangle(rectangle): rectangle.isHidden == true
        case let .ellipse(ellipse): ellipse.isHidden == true
        case let .polystar(polystar): polystar.isHidden == true
        case let .fill(fill): fill.isHidden == true
        case let .stroke(stroke): stroke.isHidden == true
        case let .trim(trim): trim.isHidden == true
        case let .transform(transform): transform.isHidden == true
        case .unsupported: false
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
        case "sr":
            self = try .polystar(ShapePolystar(from: decoder))
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
    public var isHidden: Bool?
    public var items: [LottieShape]

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case isHidden = "hd"
        case items = "it"
    }
}

/// An `sh` bezier path.
public struct ShapePath: Decodable, Sendable, Equatable {
    public var name: String?
    public var isHidden: Bool?
    /// Authored path direction (`d`), when present.
    public var direction: Int?
    public var shape: AnimatedBezier

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case isHidden = "hd"
        case direction = "d"
        case shape = "ks"
    }
}

/// An `rc` rectangle primitive, positioned by center.
public struct ShapeRectangle: Decodable, Sendable, Equatable {
    public var name: String?
    public var isHidden: Bool?
    /// Authored path direction (`d`), when present.
    public var direction: Int?
    public var position: AnimatedVector
    public var size: AnimatedVector
    public var roundness: AnimatedDouble?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case isHidden = "hd"
        case direction = "d"
        case position = "p"
        case size = "s"
        case roundness = "r"
    }
}

/// An `el` ellipse primitive, positioned by center.
public struct ShapeEllipse: Decodable, Sendable, Equatable {
    public var name: String?
    public var isHidden: Bool?
    /// Authored path direction (`d`), when present.
    public var direction: Int?
    public var position: AnimatedVector
    public var size: AnimatedVector

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case isHidden = "hd"
        case direction = "d"
        case position = "p"
        case size = "s"
    }
}

/// An `sr` polystar primitive. Lottie uses `sy: 1` for star and `sy: 2` for
/// polygon; semantic interpretation is done by `LottieEvaluation`.
public struct ShapePolystar: Decodable, Sendable, Equatable {
    public var name: String?
    public var isHidden: Bool?
    public var starType: Int?
    public var direction: Int?
    public var points: AnimatedDouble?
    public var position: AnimatedVector?
    public var rotation: AnimatedDouble?
    public var innerRadius: AnimatedDouble?
    public var innerRoundness: AnimatedDouble?
    public var outerRadius: AnimatedDouble?
    public var outerRoundness: AnimatedDouble?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case isHidden = "hd"
        case starType = "sy"
        case direction = "d"
        case points = "pt"
        case position = "p"
        case rotation = "r"
        case innerRadius = "ir"
        case innerRoundness = "is"
        case outerRadius = "or"
        case outerRoundness = "os"
    }
}

/// An `fl` solid fill: RGB(A) color in unit components plus percent opacity.
public struct ShapeFill: Decodable, Sendable, Equatable {
    public var name: String?
    public var isHidden: Bool?
    public var color: AnimatedVector
    public var opacity: AnimatedDouble?
    /// 1 = non-zero winding, 2 = even-odd.
    public var fillRule: Int?
    /// Lottie blend mode (`bm`) for this style, when authored.
    public var blendMode: Int?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case isHidden = "hd"
        case color = "c"
        case opacity = "o"
        case fillRule = "r"
        case blendMode = "bm"
    }
}

/// An `st` stroke: color, percent opacity, and width in points.
public struct ShapeStroke: Decodable, Sendable, Equatable {
    public var name: String?
    public var isHidden: Bool?
    public var color: AnimatedVector
    public var opacity: AnimatedDouble?
    public var width: AnimatedDouble
    /// 1 = butt, 2 = round, 3 = projecting/square.
    public var lineCap: Int?
    /// 1 = miter, 2 = round, 3 = bevel.
    public var lineJoin: Int?
    public var miterLimit: Double?
    public var secondaryMiterLimit: AnimatedDouble?
    public var dashPattern: [ShapeStrokeDash]?
    /// Lottie blend mode (`bm`) for this style, when authored.
    public var blendMode: Int?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case isHidden = "hd"
        case color = "c"
        case opacity = "o"
        case width = "w"
        case lineCap = "lc"
        case lineJoin = "lj"
        case miterLimit = "ml"
        case secondaryMiterLimit = "ml2"
        case dashPattern = "d"
        case blendMode = "bm"
    }
}

/// One entry in a stroke dash array (`d`).
///
/// Bodymovin writes `n` as `d` (dash), `g` (gap), or `o` (offset), with `v`
/// carrying the animated scalar value.
public struct ShapeStrokeDash: Decodable, Sendable, Equatable {
    public var name: String?
    public var type: String?
    public var value: AnimatedDouble?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case type = "n"
        case value = "v"
    }
}

/// A `tm` trim-paths modifier: start/end/offset as percentages of the path
/// length. `multiple` (`m`) selects simultaneous (1) or individual (2)
/// trimming when several paths precede the modifier.
public struct ShapeTrim: Decodable, Sendable, Equatable {
    public var name: String?
    public var isHidden: Bool?
    public var start: AnimatedDouble
    public var end: AnimatedDouble
    public var offset: AnimatedDouble?
    public var multiple: Int?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case isHidden = "hd"
        case start = "s"
        case end = "e"
        case offset = "o"
        case multiple = "m"
    }
}

/// A `tr` group transform: same anatomy as a layer transform.
public struct ShapeTransform: Decodable, Sendable, Equatable {
    public var name: String?
    public var isHidden: Bool?
    public var anchor: AnimatedVector?
    public var position: AnimatedVector?
    public var scale: AnimatedVector?
    public var rotation: AnimatedDouble?
    public var opacity: AnimatedDouble?

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case isHidden = "hd"
        case anchor = "a"
        case position = "p"
        case scale = "s"
        case rotation = "r"
        case opacity = "o"
    }
}
