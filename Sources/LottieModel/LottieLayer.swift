//
//  LottieLayer.swift
//  PureLottie
//

/// A layer in a composition, discriminated by the numeric `ty` field.
public enum LottieLayerType: Int, Sendable, Equatable {
    case precomposition = 0
    case solid = 1
    case image = 2
    case null = 3
    case shape = 4
    case text = 5
}

/// One layer of a composition. Times (`startTime`, `inPoint`, `outPoint`) are
/// frames, exactly as serialized; the importer converts to seconds.
public struct LottieLayer: Decodable, Sendable, Equatable {
    /// The raw `ty` value; `type` is `nil` for types outside the known set.
    public var rawType: Int
    public var name: String?
    /// The layer's id within its composition, referenced by `parent`.
    public var index: Int?
    /// The index of the transform-parent layer, when parented.
    public var parent: Int?
    /// The asset id a precomposition layer instantiates.
    public var referenceId: String?
    /// Track matte mode (`tt`). Values are preserved as authored.
    public var trackMatteType: Int?
    /// Track matte source marker (`td`). Values are preserved as authored.
    public var trackMatteSource: Int?
    /// Explicit track matte source layer index (`tp`), when present.
    public var trackMatteParent: Int?
    public var startTime: Double
    public var inPoint: Double
    public var outPoint: Double
    /// Time stretch; 1 is unstretched.
    public var stretch: Double
    /// Time remap (`tm`) values are serialized in seconds; evaluators convert
    /// them to source frames with the composition frame rate.
    public var timeRemap: AnimatedDouble?
    public var transform: LottieTransform?
    /// Whether this layer participates in Lottie's 2.5D/3D transform mode.
    public var is3D: Bool
    /// Auto-orient (`ao`) rotates the layer to follow the position path tangent.
    public var autoOrient: Int?
    /// Shape items, for shape layers.
    public var shapes: [LottieShape]?
    /// Solid-layer color as `#rrggbb`, with its size.
    public var solidColor: String?
    public var solidWidth: Double?
    public var solidHeight: Double?
    /// Precomposition viewport size.
    public var width: Double?
    public var height: Double?
    public var masks: [LottieMask]?
    public var isHidden: Bool

    public var type: LottieLayerType? {
        LottieLayerType(rawValue: rawType)
    }

    private enum CodingKeys: String, CodingKey {
        case rawType = "ty"
        case name = "nm"
        case index = "ind"
        case parent
        case referenceId = "refId"
        case trackMatteType = "tt"
        case trackMatteSource = "td"
        case trackMatteParent = "tp"
        case startTime = "st"
        case inPoint = "ip"
        case outPoint = "op"
        case stretch = "sr"
        case timeRemap = "tm"
        case transform = "ks"
        case is3D = "ddd"
        case autoOrient = "ao"
        case shapes
        case solidColor = "sc"
        case solidWidth = "sw"
        case solidHeight = "sh"
        case width = "w"
        case height = "h"
        case masks = "masksProperties"
        case hidden = "hd"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawType = try container.decode(Int.self, forKey: .rawType)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        parent = try container.decodeIfPresent(Int.self, forKey: .parent)
        referenceId = try container.decodeIfPresent(String.self, forKey: .referenceId)
        trackMatteType = try container.decodeIfPresent(Int.self, forKey: .trackMatteType)
        trackMatteSource = try container.decodeIfPresent(Int.self, forKey: .trackMatteSource)
        trackMatteParent = try container.decodeIfPresent(Int.self, forKey: .trackMatteParent)
        startTime = try container.decodeIfPresent(Double.self, forKey: .startTime) ?? 0
        inPoint = try container.decodeIfPresent(Double.self, forKey: .inPoint) ?? 0
        outPoint = try container.decodeIfPresent(Double.self, forKey: .outPoint) ?? 0
        stretch = try container.decodeIfPresent(Double.self, forKey: .stretch) ?? 1
        timeRemap = try container.decodeIfPresent(AnimatedDouble.self, forKey: .timeRemap)
        transform = try container.decodeIfPresent(LottieTransform.self, forKey: .transform)
        is3D = try (container.decodeIfPresent(Int.self, forKey: .is3D) ?? 0) != 0
        autoOrient = try container.decodeIfPresent(Int.self, forKey: .autoOrient)
        shapes = try container.decodeIfPresent([LottieShape].self, forKey: .shapes)
        solidColor = try container.decodeIfPresent(String.self, forKey: .solidColor)
        solidWidth = try container.decodeIfPresent(Double.self, forKey: .solidWidth)
        solidHeight = try container.decodeIfPresent(Double.self, forKey: .solidHeight)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
        masks = try container.decodeIfPresent([LottieMask].self, forKey: .masks)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }

    public var isAutoOriented: Bool {
        (autoOrient ?? 0) != 0
    }
}

/// A layer mask: a bezier path combined with the layer in `mode` ("a" add,
/// "s" subtract, "i" intersect, "n" none), optionally inverted.
public struct LottieMask: Decodable, Sendable, Equatable {
    public var name: String?
    public var mode: String
    public var path: AnimatedBezier
    public var opacity: AnimatedDouble?
    public var isInverted: Bool

    private enum CodingKeys: String, CodingKey {
        case name = "nm"
        case mode
        case path = "pt"
        case opacity = "o"
        case inverted = "inv"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "a"
        path = try container.decode(AnimatedBezier.self, forKey: .path)
        opacity = try container.decodeIfPresent(AnimatedDouble.self, forKey: .opacity)
        isInverted = try container.decodeIfPresent(Bool.self, forKey: .inverted) ?? false
    }
}
