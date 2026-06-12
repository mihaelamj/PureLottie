//
//  ImportReport.swift
//  PureLottie
//

import LottieModel

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

        public init(
            path: String,
            sourcePath: String? = nil,
            sourceRange: SourceRange? = nil,
            feature: String,
            disposition: Disposition
        ) {
            self.path = path
            self.sourcePath = sourcePath
            self.sourceRange = sourceRange
            self.feature = feature
            self.disposition = disposition
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

    func skip(_ feature: String, at path: String, sourcePath: JSONPath? = nil, sourceRange: SourceRange? = nil) {
        findings.append(.init(path: path, sourcePath: sourcePath?.description, sourceRange: sourceRange, feature: feature, disposition: .skipped))
    }

    func approximate(_ feature: String, at path: String, sourcePath: JSONPath? = nil, sourceRange: SourceRange? = nil) {
        findings.append(.init(path: path, sourcePath: sourcePath?.description, sourceRange: sourceRange, feature: feature, disposition: .approximated))
    }

    func reportTransformDiagnostics(_ diagnostics: [ValidationError], at path: String) {
        for diagnostic in diagnostics where diagnostic.ruleID.hasPrefix("lottie.evaluation.transform.") {
            skip(feature(for: diagnostic), at: "\(path) \(diagnostic.codingPath.description)")
        }
    }

    func reportShapeDiagnostics(_ diagnostics: [ValidationError]) {
        for diagnostic in diagnostics where diagnostic.ruleID.hasPrefix("lottie.evaluation.shape.") {
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
