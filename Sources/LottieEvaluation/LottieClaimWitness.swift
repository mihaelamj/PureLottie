import Foundation
import LottieModel

public enum LottieClaimWitnessStatus: String, Codable, Equatable, Sendable {
    case witnessed
    case asserted
    case blocked
}

public struct LottieClaimWitness: Codable, Equatable, Sendable, Validatable {
    public var status: LottieClaimWitnessStatus
    public var evidence: [String]
    public var reason: String

    public init(status: LottieClaimWitnessStatus, evidence: [String], reason: String) {
        self.status = status
        self.evidence = evidence
        self.reason = reason
    }
}

public enum LottieClaimWitnessValidation {
    public static func claimWitnessIsExplicit<Document: Validatable>(
        ruleIDPrefix: String,
        description: String
    ) -> Validation<Document, LottieClaimWitness> {
        Validation(
            ruleID: "\(ruleIDPrefix).explicit",
            description: description,
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
                errors.append(error(
                    ruleID: "\(ruleIDPrefix).reason",
                    description: description,
                    path: context.codingPath.appending(.key("reason"))
                ))
            }
            if context.subject.status == .witnessed, context.subject.evidence.isEmpty {
                errors.append(error(
                    ruleID: "\(ruleIDPrefix).evidence",
                    description: description,
                    path: context.codingPath.appending(.key("evidence"))
                ))
            }
            if context.subject.evidence.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                errors.append(error(
                    ruleID: "\(ruleIDPrefix).evidence.path",
                    description: description,
                    path: context.codingPath.appending(.key("evidence"))
                ))
            }
            return errors
        }
    }

    private static func error(
        ruleID: String,
        description: String,
        path: JSONPath
    ) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "Failed to satisfy: \(description)",
            at: path,
            phase: .source,
            classification: .reported
        )
    }
}
