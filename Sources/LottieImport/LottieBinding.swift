//
//  LottieBinding.swift
//  PureLottie
//

import LottieModel

/// Compiler binding output for a Lottie document.
///
/// The binder resolves graph-shaped source facts before lowering: layer index
/// tables, parent chains, asset references, precomposition namespaces, and
/// track matte edges. It does not decide how to render those facts.
final class LottieBinding {
    let root: BoundComposition
    let assetsByID: [String: BoundAsset]
    let precompositionsByID: [String: BoundComposition]
    private let sourceDocument: LottieSourceDocument?

    init(
        root: BoundComposition,
        assetsByID: [String: BoundAsset],
        precompositionsByID: [String: BoundComposition],
        sourceDocument: LottieSourceDocument?
    ) {
        self.root = root
        self.assetsByID = assetsByID
        self.precompositionsByID = precompositionsByID
        self.sourceDocument = sourceDocument
    }

    func asset(id: String) -> BoundAsset? {
        assetsByID[id]
    }

    func precomposition(id: String) -> BoundComposition? {
        precompositionsByID[id]
    }

    func sourceRange(at path: JSONPath?) -> SourceRange? {
        guard let path else { return nil }
        return sourceDocument?.source.value(at: path)?.range
    }
}

final class BoundComposition {
    let path: String
    let sourcePath: JSONPath?
    let sourceSize: (width: Double, height: Double)?
    fileprivate(set) var layers: [BoundLayer] = []
    fileprivate(set) var layersByIndex: [Int: BoundLayer] = [:]

    init(path: String, sourcePath: JSONPath?, sourceSize: (width: Double, height: Double)?) {
        self.path = path
        self.sourcePath = sourcePath
        self.sourceSize = sourceSize
    }
}

final class BoundLayer {
    let layer: LottieLayer
    let offset: Int
    let path: String
    let sourcePath: JSONPath?
    fileprivate(set) var parents: [BoundLayerReference] = []
    fileprivate(set) var referencedAsset: BoundAsset?
    fileprivate(set) var matte: BoundMatte?

    init(layer: LottieLayer, offset: Int, path: String, sourcePath: JSONPath?) {
        self.layer = layer
        self.offset = offset
        self.path = path
        self.sourcePath = sourcePath
    }

    var reference: BoundLayerReference {
        BoundLayerReference(layer: layer, path: path, sourcePath: sourcePath)
    }
}

struct BoundLayerReference {
    let layer: LottieLayer
    let path: String
    let sourcePath: JSONPath?
}

struct BoundMatte {
    let mode: Int
    let source: BoundLayerReference?
    let usesExplicitSource: Bool
}

struct BoundAsset {
    let asset: LottieAsset
    let offset: Int
    let path: String
    let sourcePath: JSONPath?
}

final class LottieBinder {
    private let animation: LottieAnimation
    private let sourceDocument: LottieSourceDocument?
    private let report: ImportReportBuilder

    init(animation: LottieAnimation, sourceDocument: LottieSourceDocument?, report: ImportReportBuilder) {
        self.animation = animation
        self.sourceDocument = sourceDocument
        self.report = report
    }

    func bind() -> LottieBinding {
        let assetsByID = bindAssets(animation.assets)
        let root = bindComposition(
            path: "root",
            sourcePath: JSONPath([.key("layers")]),
            layers: animation.layers,
            sourceSize: (animation.width, animation.height)
        )
        var precompositionsByID: [String: BoundComposition] = [:]
        for asset in assetsByID.values where asset.asset.layers != nil {
            precompositionsByID[asset.asset.id] = bindComposition(
                path: "asset '\(asset.asset.id)'",
                sourcePath: asset.sourcePath?.appending(.key("layers")),
                layers: asset.asset.layers ?? [],
                sourceSize: assetSize(asset.asset)
            )
        }
        return LottieBinding(root: root, assetsByID: assetsByID, precompositionsByID: precompositionsByID, sourceDocument: sourceDocument)
    }

    private func bindAssets(_ assets: [LottieAsset]) -> [String: BoundAsset] {
        var result: [String: BoundAsset] = [:]
        for (offset, asset) in assets.enumerated() {
            let sourcePath = JSONPath([.key("assets"), .index(offset)])
            let bound = BoundAsset(asset: asset, offset: offset, path: "asset '\(asset.id)'", sourcePath: sourcePath)
            if result[asset.id] == nil {
                result[asset.id] = bound
            } else {
                report.skip(
                    "duplicate asset id '\(asset.id)'",
                    at: bound.path,
                    sourcePath: sourcePath.appending(.key("id")),
                    sourceRange: sourceRange(at: sourcePath.appending(.key("id")))
                )
            }
        }
        return result
    }

    private func bindComposition(
        path: String,
        sourcePath: JSONPath?,
        layers: [LottieLayer],
        sourceSize: (width: Double, height: Double)?
    ) -> BoundComposition {
        let composition = BoundComposition(path: path, sourcePath: sourcePath, sourceSize: sourceSize)
        var layersByIndex: [Int: BoundLayer] = [:]
        var boundLayers: [BoundLayer] = []

        for (offset, layer) in layers.enumerated() {
            let layerPath = "\(path) > layer '\(layer.name ?? "?")'"
            let layerSourcePath = sourcePath?.appending(.index(offset))
            let bound = BoundLayer(layer: layer, offset: offset, path: layerPath, sourcePath: layerSourcePath)
            boundLayers.append(bound)

            guard let index = layer.index else { continue }
            if layersByIndex[index] == nil {
                layersByIndex[index] = bound
            } else {
                report.skip(
                    "duplicate layer index \(index)",
                    at: layerPath,
                    sourcePath: layerSourcePath?.appending(.key("ind")),
                    sourceRange: sourceRange(at: layerSourcePath?.appending(.key("ind")))
                )
            }
        }

        composition.layers = boundLayers
        composition.layersByIndex = layersByIndex
        for layer in boundLayers {
            layer.parents = resolveParents(for: layer, in: composition)
            layer.referencedAsset = resolveAsset(for: layer)
            layer.matte = resolveMatte(for: layer, in: composition)
        }
        return composition
    }

    private func resolveParents(for layer: BoundLayer, in composition: BoundComposition) -> [BoundLayerReference] {
        var cursor = layer.layer.parent
        var seen: Set<Int> = []
        var ancestors: [BoundLayerReference] = []

        while let parentIndex = cursor {
            guard seen.insert(parentIndex).inserted else {
                report.skip(
                    "parent cycle through layer index \(parentIndex)",
                    at: layer.path,
                    sourcePath: layer.sourcePath?.appending(.key("parent")),
                    sourceRange: sourceRange(at: layer.sourcePath?.appending(.key("parent")))
                )
                return []
            }
            guard let parent = composition.layersByIndex[parentIndex] else {
                report.skip(
                    "missing parent layer \(parentIndex)",
                    at: layer.path,
                    sourcePath: layer.sourcePath?.appending(.key("parent")),
                    sourceRange: sourceRange(at: layer.sourcePath?.appending(.key("parent")))
                )
                return ancestors
            }
            guard parent !== layer else {
                report.skip(
                    "parent cycle through layer index \(parentIndex)",
                    at: layer.path,
                    sourcePath: layer.sourcePath?.appending(.key("parent")),
                    sourceRange: sourceRange(at: layer.sourcePath?.appending(.key("parent")))
                )
                return []
            }
            ancestors.append(parent.reference)
            cursor = parent.layer.parent
        }

        return ancestors
    }

    private func resolveAsset(for layer: BoundLayer) -> BoundAsset? {
        guard layer.layer.type == .precomposition || layer.layer.type == .image else { return nil }
        guard let referenceID = layer.layer.referenceId else {
            report.skip(
                "missing asset reference",
                at: layer.path,
                sourcePath: layer.sourcePath?.appending(.key("refId")),
                sourceRange: sourceRange(at: layer.sourcePath)
            )
            return nil
        }
        guard let asset = bindableAsset(id: referenceID) else {
            report.skip(
                "missing asset '\(referenceID)'",
                at: layer.path,
                sourcePath: layer.sourcePath?.appending(.key("refId")),
                sourceRange: sourceRange(at: layer.sourcePath?.appending(.key("refId")))
            )
            return nil
        }
        if layer.layer.type == .precomposition, asset.asset.layers == nil {
            report.skip(
                "precomposition with non-composition asset '\(referenceID)'",
                at: layer.path,
                sourcePath: layer.sourcePath?.appending(.key("refId")),
                sourceRange: sourceRange(at: layer.sourcePath?.appending(.key("refId")))
            )
        }
        return asset
    }

    private func resolveMatte(for layer: BoundLayer, in composition: BoundComposition) -> BoundMatte? {
        guard let mode = layer.layer.trackMatteType else { return nil }
        guard mode != 0 else { return nil }

        if let explicitIndex = layer.layer.trackMatteParent {
            guard let source = composition.layersByIndex[explicitIndex] else {
                report.skip(
                    "missing track matte layer \(explicitIndex)",
                    at: layer.path,
                    sourcePath: layer.sourcePath?.appending(.key("tp")),
                    sourceRange: sourceRange(at: layer.sourcePath?.appending(.key("tp")))
                )
                return BoundMatte(mode: mode, source: nil, usesExplicitSource: true)
            }
            return BoundMatte(mode: mode, source: source.reference, usesExplicitSource: true)
        }

        let sourceOffset = layer.offset - 1
        guard composition.layers.indices.contains(sourceOffset) else {
            report.skip(
                "missing implicit track matte layer",
                at: layer.path,
                sourcePath: layer.sourcePath?.appending(.key("tt")),
                sourceRange: sourceRange(at: layer.sourcePath?.appending(.key("tt")))
            )
            return BoundMatte(mode: mode, source: nil, usesExplicitSource: false)
        }
        return BoundMatte(mode: mode, source: composition.layers[sourceOffset].reference, usesExplicitSource: false)
    }

    private func bindableAsset(id: String) -> BoundAsset? {
        guard let assets = sourceDocument?.source.member("assets")?.arrayValues else {
            return animation.assets.enumerated().compactMap { offset, asset in
                asset.id == id ? BoundAsset(asset: asset, offset: offset, path: "asset '\(asset.id)'", sourcePath: nil) : nil
            }.first
        }
        for (offset, asset) in animation.assets.enumerated() where asset.id == id {
            let sourcePath = JSONPath([.key("assets"), .index(offset)])
            guard assets.indices.contains(offset) else {
                return BoundAsset(asset: asset, offset: offset, path: "asset '\(asset.id)'", sourcePath: sourcePath)
            }
            return BoundAsset(asset: asset, offset: offset, path: "asset '\(asset.id)'", sourcePath: sourcePath)
        }
        return nil
    }

    private func assetSize(_ asset: LottieAsset) -> (width: Double, height: Double)? {
        guard let width = asset.width, let height = asset.height else { return nil }
        return (width, height)
    }

    private func sourceRange(at path: JSONPath?) -> SourceRange? {
        guard let path else { return nil }
        return sourceDocument?.source.value(at: path)?.range
    }
}
