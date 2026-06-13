//
//  ImportReport.swift
//  PureLottie
//

import LottieModel

/// Evidence proving why a RenderIR-to-PureLayer lowering finding belongs to a
/// backend capability gap, an intentional approximation, or a PureLottie
/// semantic defect investigation.
public struct LottieBackendGapEvidence: Sendable, Equatable {
    /// Which side should own the next investigation.
    public enum Owner: String, Sendable {
        /// PureLottie understood the Lottie/RenderIR semantics, but the backend
        /// cannot represent the required operation yet.
        case backendCapability
        /// PureLottie semantic evaluation is suspect and must be fixed before
        /// filing a backend issue.
        case pureLottieSemantics
        /// The conformance matrix explicitly marks this as an approximation.
        case intentionalApproximation
    }

    /// VM trace facts attached to the RenderIR node that exposed the gap.
    public struct VMTrace: Sendable, Equatable {
        public var nodeID: String?
        public var instruction: String?
        public var compositionStack: [String]
        public var layerStack: [String]
        public var transformStack: [String]
        public var styleStack: [String]
        public var matteStack: [String]
        public var reason: String?

        public init(
            nodeID: String? = nil,
            instruction: String? = nil,
            compositionStack: [String] = [],
            layerStack: [String] = [],
            transformStack: [String] = [],
            styleStack: [String] = [],
            matteStack: [String] = [],
            reason: String? = nil
        ) {
            self.nodeID = nodeID
            self.instruction = instruction
            self.compositionStack = compositionStack
            self.layerStack = layerStack
            self.transformStack = transformStack
            self.styleStack = styleStack
            self.matteStack = matteStack
            self.reason = reason
        }
    }

    /// RenderIR node facts needed to reproduce the lowering decision.
    public struct RenderNode: Sendable, Equatable {
        public var nodeID: String
        public var kind: String
        public var layerName: String
        public var layerIndex: Int?
        public var sourcePath: String
        public var jsonPath: String
        public var localFrame: Double
        public var opacity: Double
        public var explanation: String

        public init(
            nodeID: String,
            kind: String,
            layerName: String,
            layerIndex: Int? = nil,
            sourcePath: String,
            jsonPath: String,
            localFrame: Double,
            opacity: Double,
            explanation: String
        ) {
            self.nodeID = nodeID
            self.kind = kind
            self.layerName = layerName
            self.layerIndex = layerIndex
            self.sourcePath = sourcePath
            self.jsonPath = jsonPath
            self.localFrame = localFrame
            self.opacity = opacity
            self.explanation = explanation
        }
    }

    /// Specific RenderIR term that required unsupported backend behavior.
    public struct RenderTerm: Sendable, Equatable {
        public var kind: String
        public var sourcePath: String
        public var jsonPath: String
        public var values: [String: String]

        public init(
            kind: String,
            sourcePath: String,
            jsonPath: String,
            values: [String: String] = [:]
        ) {
            self.kind = kind
            self.sourcePath = sourcePath
            self.jsonPath = jsonPath
            self.values = values
        }
    }

    /// Layer-graph facts for the source layer involved in the backend decision.
    public struct LayerGraphRecord: Sendable, Equatable {
        public var sourcePath: String
        public var jsonPath: String
        public var participation: String
        public var renderOrder: Int?
        public var maskCount: Int
        public var matteMode: Int?
        public var matteSourcePath: String?
        public var matteTargetPath: String?
        public var timingMode: String
        public var timingInputFrame: Double
        public var timingStartTime: Double
        public var timingStretch: Double
        public var timingFrameRate: Double
        public var timingLocalFrame: Double
        public var timingTimeRemapSeconds: Double?
        public var timingTimeRemapPropertyPath: String?
        public var precompositionAssetID: String?
        public var precompositionPath: String?
        public var precompositionLocalFrame: Double?
        public var precompositionChildLayerCount: Int?
        public var diagnosticRuleIDs: [String]

        public init(
            sourcePath: String,
            jsonPath: String,
            participation: String,
            renderOrder: Int? = nil,
            maskCount: Int,
            matteMode: Int? = nil,
            matteSourcePath: String? = nil,
            matteTargetPath: String? = nil,
            timingMode: String = "",
            timingInputFrame: Double = 0,
            timingStartTime: Double = 0,
            timingStretch: Double = 1,
            timingFrameRate: Double = 0,
            timingLocalFrame: Double = 0,
            timingTimeRemapSeconds: Double? = nil,
            timingTimeRemapPropertyPath: String? = nil,
            precompositionAssetID: String? = nil,
            precompositionPath: String? = nil,
            precompositionLocalFrame: Double? = nil,
            precompositionChildLayerCount: Int? = nil,
            diagnosticRuleIDs: [String] = []
        ) {
            self.sourcePath = sourcePath
            self.jsonPath = jsonPath
            self.participation = participation
            self.renderOrder = renderOrder
            self.maskCount = maskCount
            self.matteMode = matteMode
            self.matteSourcePath = matteSourcePath
            self.matteTargetPath = matteTargetPath
            self.timingMode = timingMode
            self.timingInputFrame = timingInputFrame
            self.timingStartTime = timingStartTime
            self.timingStretch = timingStretch
            self.timingFrameRate = timingFrameRate
            self.timingLocalFrame = timingLocalFrame
            self.timingTimeRemapSeconds = timingTimeRemapSeconds
            self.timingTimeRemapPropertyPath = timingTimeRemapPropertyPath
            self.precompositionAssetID = precompositionAssetID
            self.precompositionPath = precompositionPath
            self.precompositionLocalFrame = precompositionLocalFrame
            self.precompositionChildLayerCount = precompositionChildLayerCount
            self.diagnosticRuleIDs = diagnosticRuleIDs
        }
    }

    /// Investigation owner.
    public var owner: Owner
    /// Source fixture path or id when known.
    public var sourceFixture: String?
    /// Source frame that produced this evidence.
    public var sourceFrame: Double
    /// Root composition frame rate.
    public var frameRate: Double
    /// Human-readable Lottie source path for the exact finding.
    public var lottiePath: String
    /// Authored JSON path for the exact finding.
    public var jsonPath: String?
    /// Source range for the exact finding, when available.
    public var sourceRange: SourceRange?
    /// VM trace facts for the RenderIR node.
    public var vmTrace: VMTrace?
    /// RenderIR node that reached backend lowering.
    public var renderNode: RenderNode?
    /// RenderIR term that could not be lowered exactly.
    public var renderTerm: RenderTerm?
    /// Layer graph record that produced the RenderIR node or term.
    public var layerGraphRecord: LayerGraphRecord?
    /// Pinned lottie-web frame artifact, when an oracle generated one.
    public var expectedLottieWebFrameArtifact: String?
    /// PureLayer/PureDraw output frame artifact, when generated.
    public var pureLayerFrameArtifact: String?

    public init(
        owner: Owner,
        sourceFixture: String? = nil,
        sourceFrame: Double,
        frameRate: Double,
        lottiePath: String,
        jsonPath: String? = nil,
        sourceRange: SourceRange? = nil,
        vmTrace: VMTrace? = nil,
        renderNode: RenderNode? = nil,
        renderTerm: RenderTerm? = nil,
        layerGraphRecord: LayerGraphRecord? = nil,
        expectedLottieWebFrameArtifact: String? = nil,
        pureLayerFrameArtifact: String? = nil
    ) {
        self.owner = owner
        self.sourceFixture = sourceFixture
        self.sourceFrame = sourceFrame
        self.frameRate = frameRate
        self.lottiePath = lottiePath
        self.jsonPath = jsonPath
        self.sourceRange = sourceRange
        self.vmTrace = vmTrace
        self.renderNode = renderNode
        self.renderTerm = renderTerm
        self.layerGraphRecord = layerGraphRecord
        self.expectedLottieWebFrameArtifact = expectedLottieWebFrameArtifact
        self.pureLayerFrameArtifact = pureLayerFrameArtifact
    }
}

/// Optional artifact context threaded through backend lowering evidence.
public struct LottieBackendEvidenceContext: Sendable, Equatable {
    public var sourceFixture: String?
    public var expectedLottieWebFrameArtifact: String?
    public var pureLayerFrameArtifact: String?

    public init(
        sourceFixture: String? = nil,
        expectedLottieWebFrameArtifact: String? = nil,
        pureLayerFrameArtifact: String? = nil
    ) {
        self.sourceFixture = sourceFixture
        self.expectedLottieWebFrameArtifact = expectedLottieWebFrameArtifact
        self.pureLayerFrameArtifact = pureLayerFrameArtifact
    }
}

/// Everything the importer could not map exactly, by location.
///
/// The importer's contract: a Lottie feature is either mapped correctly or
/// recorded here. A clean report means the scene renders as authored (within
/// the importer's documented approximations, which are also findings).
public struct ImportReport: Sendable, Equatable {
    /// How the importer handled an unmappable feature.
    public enum Disposition: String, Sendable {
        /// The feature was dropped; the scene renders without it.
        case skipped
        /// The feature was mapped inexactly (for example, a curved motion path
        /// rendered as straight segments between keyframes).
        case approximated
    }

    public struct Finding: Sendable, Equatable {
        /// Where in the document the feature was found, for example
        /// `layer 'Star' > group 'Group 1'`.
        public let path: String
        /// Source JSON path when the importer can infer one from source order.
        public let sourcePath: String?
        /// Source JSON range when the importer was given source-ranged data.
        public let sourceRange: SourceRange?
        /// The feature, for example `animated fill color`.
        public let feature: String
        public let disposition: Disposition
        /// Structured backend evidence when this finding came from RenderIR
        /// lowering into PureLayer/PureDraw.
        public let evidence: LottieBackendGapEvidence?

        public init(
            path: String,
            sourcePath: String? = nil,
            sourceRange: SourceRange? = nil,
            feature: String,
            disposition: Disposition,
            evidence: LottieBackendGapEvidence? = nil
        ) {
            self.path = path
            self.sourcePath = sourcePath
            self.sourceRange = sourceRange
            self.feature = feature
            self.disposition = disposition
            self.evidence = evidence
        }
    }

    public var findings: [Finding]

    public var isClean: Bool {
        findings.isEmpty
    }

    public init(findings: [Finding] = []) {
        self.findings = findings
    }
}

/// Mutable collector threaded through the import walk.
final class ImportReportBuilder {
    private(set) var findings: [ImportReport.Finding] = []

    func skip(
        _ feature: String,
        at path: String,
        sourcePath: JSONPath? = nil,
        sourceRange: SourceRange? = nil,
        evidence: LottieBackendGapEvidence? = nil
    ) {
        findings.append(.init(
            path: path,
            sourcePath: sourcePath?.description,
            sourceRange: sourceRange,
            feature: feature,
            disposition: .skipped,
            evidence: evidence
        ))
    }

    func approximate(
        _ feature: String,
        at path: String,
        sourcePath: JSONPath? = nil,
        sourceRange: SourceRange? = nil,
        evidence: LottieBackendGapEvidence? = nil
    ) {
        findings.append(.init(
            path: path,
            sourcePath: sourcePath?.description,
            sourceRange: sourceRange,
            feature: feature,
            disposition: .approximated,
            evidence: evidence
        ))
    }

    func reportTransformDiagnostics(_ diagnostics: [ValidationError], at path: String) {
        for diagnostic in diagnostics where diagnostic.ruleID.hasPrefix("lottie.evaluation.transform.") {
            skip(feature(for: diagnostic), at: "\(path) \(diagnostic.codingPath.description)")
        }
    }

    func reportShapeDiagnostics(_ diagnostics: [ValidationError]) {
        for diagnostic in diagnostics where diagnostic.ruleID.hasPrefix("lottie.evaluation.shape.")
            || diagnostic.ruleID.hasPrefix("lottie.evaluation.geometry.")
        {
            let path = diagnostic.evidence ?? diagnostic.codingPath.description
            switch diagnostic.classification {
            case .approximate:
                approximate(diagnostic.reason, at: path)
            case .exact, .metadata:
                continue
            case .reported, .gap:
                skip(diagnostic.reason, at: path)
            }
        }
    }

    func report() -> ImportReport {
        ImportReport(findings: findings)
    }

    private func feature(for diagnostic: ValidationError) -> String {
        switch diagnostic.ruleID {
        case "lottie.evaluation.transform.skew.unsupported":
            "unsupported transform skew"
        case "lottie.evaluation.transform.3d.unsupported":
            "unsupported 3D transform"
        case "lottie.evaluation.transform.auto-orient.unsupported":
            "unsupported auto-orient transform"
        case "lottie.evaluation.transform.parent-cycle":
            "unsupported parent transform cycle"
        case "lottie.evaluation.transform.parent-depth":
            "unsupported parent transform depth"
        default:
            diagnostic.reason
        }
    }
}
