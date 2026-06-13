import Foundation
import LottieModel

/// A machine-readable explanation for why a rendered artifact export contains
/// exactly the frames it contains. It records the Lottie source timing facts,
/// the export sampling policy, the arithmetic used to derive the count, and the
/// concrete source frame selected for every generated image.
public struct LottieArtifactFrameTiming: Codable, Equatable, Sendable, Validatable {
    public var policy: Policy
    public var source: Source
    public var request: Request
    public var derivation: Derivation
    public var samples: [Sample]

    public init(
        policy: Policy,
        source: Source,
        request: Request,
        derivation: Derivation,
        samples: [Sample]
    ) {
        self.policy = policy
        self.source = source
        self.request = request
        self.derivation = derivation
        self.samples = samples
    }

    /// The supported frame-selection policies for generated artifact reports.
    public enum Policy: String, Codable, Equatable, Sendable, Validatable {
        case apngHalfOpenWindow = "apng-half-open-window"
        case explicitSourceFrameList = "explicit-source-frame-list"
    }

    /// Root Lottie composition timing copied in frame units from the source
    /// model. The source window remains Lottie-native; seconds are derived only
    /// inside the export policy.
    public struct Source: Codable, Equatable, Sendable, Validatable {
        public var frameRate: Double
        public var inPoint: Double
        public var outPoint: Double
        public var durationSeconds: Double
        public var frameWindowSemantics: String

        public init(frameRate: Double, inPoint: Double, outPoint: Double) {
            self.frameRate = frameRate
            self.inPoint = inPoint
            self.outPoint = outPoint
            durationSeconds = frameRate > 0 ? max(0, (outPoint - inPoint) / frameRate) : 0
            frameWindowSemantics = "Lottie uses a half-open root window: ip <= frame < op."
        }

        public init(animation: LottieAnimation) {
            self.init(
                frameRate: animation.frameRate,
                inPoint: animation.inPoint,
                outPoint: animation.outPoint
            )
        }
    }

    /// The caller's sampling request before the policy turns it into concrete
    /// source frames. APNG exports use seconds and output FPS; still-frame dumps
    /// use the explicit source-frame list.
    public struct Request: Codable, Equatable, Sendable, Validatable {
        public var startSeconds: Double?
        public var exclusiveEndSeconds: Double?
        public var outputFPS: Double?
        public var outputFrameIntervalSeconds: Double?
        public var sourceFrames: [Double]?

        public init(
            startSeconds: Double?,
            exclusiveEndSeconds: Double?,
            outputFPS: Double?,
            outputFrameIntervalSeconds: Double?,
            sourceFrames: [Double]?
        ) {
            self.startSeconds = startSeconds
            self.exclusiveEndSeconds = exclusiveEndSeconds
            self.outputFPS = outputFPS
            self.outputFrameIntervalSeconds = outputFrameIntervalSeconds
            self.sourceFrames = sourceFrames
        }
    }

    /// The arithmetic contract used to derive `generatedFrameCount` from the
    /// request. The formula is stored as text for report readability and checked
    /// by validation against the concrete samples.
    public struct Derivation: Codable, Equatable, Sendable, Validatable {
        public var effectiveStartSeconds: Double?
        public var effectiveInclusiveEndSeconds: Double?
        public var generatedFrameCount: Int
        public var countFormula: String
        public var timeFormula: String
        public var sourceFrameFormula: String
        public var rationale: String

        public init(
            effectiveStartSeconds: Double?,
            effectiveInclusiveEndSeconds: Double?,
            generatedFrameCount: Int,
            countFormula: String,
            timeFormula: String,
            sourceFrameFormula: String,
            rationale: String
        ) {
            self.effectiveStartSeconds = effectiveStartSeconds
            self.effectiveInclusiveEndSeconds = effectiveInclusiveEndSeconds
            self.generatedFrameCount = generatedFrameCount
            self.countFormula = countFormula
            self.timeFormula = timeFormula
            self.sourceFrameFormula = sourceFrameFormula
            self.rationale = rationale
        }
    }

    /// One generated image's position in the export and the corresponding
    /// Lottie source frame. `timeSeconds` is always relative to the root
    /// composition in-point.
    public struct Sample: Codable, Equatable, Sendable, Validatable {
        public var index: Int
        public var timeSeconds: Double
        public var sourceFrame: Double

        public init(index: Int, timeSeconds: Double, sourceFrame: Double) {
            self.index = index
            self.timeSeconds = timeSeconds
            self.sourceFrame = sourceFrame
        }
    }

    /// Builds the timing explanation used by `LottieAPNGDump`. The requested
    /// end is exclusive, so the last output sample is one output-frame interval
    /// before that end; this preserves Lottie's `ip <= frame < op` source
    /// window in seconds.
    public static func apngHalfOpenWindow(
        source: Source,
        requestedStartSeconds: Double,
        requestedExclusiveEndSeconds: Double,
        outputFPS: Double
    ) -> Self {
        let interval = outputFPS > 0 ? 1 / outputFPS : 0
        let inclusiveEnd = inclusiveSampleEnd(
            start: requestedStartSeconds,
            exclusiveEnd: requestedExclusiveEndSeconds,
            fps: outputFPS
        )
        let times = sampleTimes(start: requestedStartSeconds, end: inclusiveEnd, fps: outputFPS)
        let samples = times.enumerated().map { index, time in
            Sample(index: index, timeSeconds: time, sourceFrame: source.inPoint + time * source.frameRate)
        }
        let delta = max(0, inclusiveEnd - requestedStartSeconds)
        let countFormula = "max(1, round(max(0, effectiveInclusiveEndSeconds - startSeconds) * outputFPS) + 1)"
        let rationale = [
            "APNG export samples Lottie's half-open root window ip <= frame < op.",
            "The requested exclusive end is \(number(requestedExclusiveEndSeconds))s.",
            "The last sampled timestamp is \(number(inclusiveEnd))s after subtracting one output interval",
            "(1 / \(number(outputFPS)) fps = \(number(interval))s).",
            "The generated frame count is max(1, round(\(number(delta)) * \(number(outputFPS))) + 1) = \(samples.count).",
        ].joined(separator: " ")
        return LottieArtifactFrameTiming(
            policy: .apngHalfOpenWindow,
            source: source,
            request: Request(
                startSeconds: requestedStartSeconds,
                exclusiveEndSeconds: requestedExclusiveEndSeconds,
                outputFPS: outputFPS,
                outputFrameIntervalSeconds: interval,
                sourceFrames: nil
            ),
            derivation: Derivation(
                effectiveStartSeconds: requestedStartSeconds,
                effectiveInclusiveEndSeconds: inclusiveEnd,
                generatedFrameCount: samples.count,
                countFormula: countFormula,
                timeFormula: "linearly interpolate generatedFrameCount timestamps from startSeconds to effectiveInclusiveEndSeconds",
                sourceFrameFormula: "sourceFrame = ip + timeSeconds * fr",
                rationale: rationale
            ),
            samples: samples
        )
    }

    /// Builds the timing explanation used by `LottieFrameDump`. Each requested
    /// source frame is rendered directly; seconds are recorded only to align the
    /// frame with downstream reports.
    public static func explicitSourceFrameList(source: Source, sourceFrames: [Double]) -> Self {
        let samples = sourceFrames.enumerated().map { index, sourceFrame in
            Sample(
                index: index,
                timeSeconds: source.frameRate > 0 ? max(0, (sourceFrame - source.inPoint) / source.frameRate) : 0,
                sourceFrame: sourceFrame
            )
        }
        let rationale = [
            "Still-frame export renders the explicit source-frame list in order.",
            "The generated frame count is requestedSourceFrames.count = \(samples.count).",
            "Each timeSeconds value is max(0, (sourceFrame - ip) / fr).",
        ].joined(separator: " ")
        return LottieArtifactFrameTiming(
            policy: .explicitSourceFrameList,
            source: source,
            request: Request(
                startSeconds: nil,
                exclusiveEndSeconds: nil,
                outputFPS: nil,
                outputFrameIntervalSeconds: nil,
                sourceFrames: sourceFrames
            ),
            derivation: Derivation(
                effectiveStartSeconds: nil,
                effectiveInclusiveEndSeconds: nil,
                generatedFrameCount: samples.count,
                countFormula: "requestedSourceFrames.count",
                timeFormula: "timeSeconds = max(0, (sourceFrame - ip) / fr)",
                sourceFrameFormula: "sourceFrame is each requested source-frame value",
                rationale: rationale
            ),
            samples: samples
        )
    }

    private static func inclusiveSampleEnd(start: Double, exclusiveEnd end: Double, fps: Double) -> Double {
        guard end > start, fps > 0 else { return start }
        return max(start, end - 1 / fps)
    }

    private static func sampleTimes(start: Double, end: Double, fps: Double) -> [Double] {
        let frameCount = max(1, Int((max(0, end - start) * fps).rounded()) + 1)
        guard frameCount > 1 else { return [start] }
        return (0 ..< frameCount).map { index in
            let progress = Double(index) / Double(frameCount - 1)
            return start + (end - start) * progress
        }
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}

/// Validates an artifact frame-timing explanation using the same composable,
/// path-bearing validation idiom as the Lottie source and manifest validators.
public final class LottieArtifactFrameTimingValidator {
    private var defaultValidations: [LottieArtifactFrameTimingAnyValidation]
    private var customValidations: [LottieArtifactFrameTimingAnyValidation]

    public init() {
        defaultValidations = LottieArtifactFrameTimingBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [LottieArtifactFrameTimingAnyValidation],
        customValidations: [LottieArtifactFrameTimingAnyValidation]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieArtifactFrameTimingValidator {
        LottieArtifactFrameTimingValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieArtifactFrameTiming, some Validatable>) -> Self {
        customValidations.append(LottieArtifactFrameTimingAnyValidation(validation))
        return self
    }

    @discardableResult
    public func validating(
        _ validation: KeyPath<LottieArtifactFrameTimingBuiltinValidation.Type, Validation<LottieArtifactFrameTiming, some Validatable>>
    ) -> Self {
        validating(LottieArtifactFrameTimingBuiltinValidation.self[keyPath: validation])
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    public func validate(_ timing: LottieArtifactFrameTiming) throws {
        let errors = collectErrors(in: timing)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    public func collectErrors(in timing: LottieArtifactFrameTiming) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(timing, at: JSONPath(), in: timing, errors: &errors)
        visit(timing.policy, at: JSONPath([.key("policy")]), in: timing, errors: &errors)
        visit(timing.source, at: JSONPath([.key("source")]), in: timing, errors: &errors)
        visit(timing.request, at: JSONPath([.key("request")]), in: timing, errors: &errors)
        visit(timing.derivation, at: JSONPath([.key("derivation")]), in: timing, errors: &errors)
        for index in timing.samples.indices {
            visit(
                timing.samples[index],
                at: JSONPath([.key("samples"), .index(index)]),
                in: timing,
                errors: &errors
            )
        }
        return errors
    }

    private var activeValidations: [LottieArtifactFrameTimingAnyValidation] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in timing: LottieArtifactFrameTiming,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: timing))
        }
    }
}

public extension LottieArtifactFrameTiming {
    @discardableResult
    func validate(using validator: LottieArtifactFrameTimingValidator = LottieArtifactFrameTimingValidator()) throws -> Self {
        try validator.validate(self)
        return self
    }
}

public enum LottieArtifactFrameTimingBuiltinValidation {
    fileprivate static var defaultValidations: [LottieArtifactFrameTimingAnyValidation] {
        [
            LottieArtifactFrameTimingAnyValidation(sourceTimingIsFiniteAndOrdered),
            LottieArtifactFrameTimingAnyValidation(derivationHasFormulaAndRationale),
            LottieArtifactFrameTimingAnyValidation(generatedFrameCountMatchesSamples),
            LottieArtifactFrameTimingAnyValidation(samplesUseContiguousIndexes),
            LottieArtifactFrameTimingAnyValidation(samplesMatchSourceTimingFormula),
            LottieArtifactFrameTimingAnyValidation(apngPolicyRecordsWindowAndFPS),
            LottieArtifactFrameTimingAnyValidation(explicitPolicyRecordsRequestedFrames),
        ]
    }

    public static var sourceTimingIsFiniteAndOrdered:
        Validation<LottieArtifactFrameTiming, LottieArtifactFrameTiming.Source>
    {
        Validation(
            ruleID: "artifact-frame-timing.source.timing",
            description: "Artifact frame timing source frame rate is positive and frame window is ordered",
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if !context.subject.frameRate.isFinite || context.subject.frameRate <= 0 {
                errors.append(error(
                    ruleID: "artifact-frame-timing.source.frame-rate",
                    description: "Artifact frame timing source frame rate is positive and frame window is ordered",
                    path: context.codingPath.appending(.key("frameRate"))
                ))
            }
            if !context.subject.inPoint.isFinite {
                errors.append(error(
                    ruleID: "artifact-frame-timing.source.in-point",
                    description: "Artifact frame timing source frame rate is positive and frame window is ordered",
                    path: context.codingPath.appending(.key("inPoint"))
                ))
            }
            if !context.subject.outPoint.isFinite || context.subject.outPoint < context.subject.inPoint {
                errors.append(error(
                    ruleID: "artifact-frame-timing.source.out-point",
                    description: "Artifact frame timing source frame rate is positive and frame window is ordered",
                    path: context.codingPath.appending(.key("outPoint"))
                ))
            }
            if context.subject.frameRate > 0 {
                let expectedDuration = max(0, (context.subject.outPoint - context.subject.inPoint) / context.subject.frameRate)
                if !context.subject.durationSeconds.isFinite || !isClose(context.subject.durationSeconds, expectedDuration) {
                    errors.append(error(
                        ruleID: "artifact-frame-timing.source.duration",
                        description: "Artifact frame timing source frame rate is positive and frame window is ordered",
                        path: context.codingPath.appending(.key("durationSeconds"))
                    ))
                }
            }
            return errors
        }
    }

    public static var derivationHasFormulaAndRationale:
        Validation<LottieArtifactFrameTiming, LottieArtifactFrameTiming.Derivation>
    {
        Validation(
            ruleID: "artifact-frame-timing.derivation.explained",
            description: "Artifact frame timing derivation records formulas and a specific rationale"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.generatedFrameCount < 0 {
                errors.append(error(
                    ruleID: "artifact-frame-timing.derivation.count",
                    description: "Artifact frame timing derivation records formulas and a specific rationale",
                    path: context.codingPath.appending(.key("generatedFrameCount"))
                ))
            }
            for (field, value) in [
                ("countFormula", context.subject.countFormula),
                ("timeFormula", context.subject.timeFormula),
                ("sourceFrameFormula", context.subject.sourceFrameFormula),
            ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(error(
                    ruleID: "artifact-frame-timing.derivation.formula",
                    description: "Artifact frame timing derivation records formulas and a specific rationale",
                    path: context.codingPath.appending(.key(field))
                ))
            }
            if context.subject.rationale.trimmingCharacters(in: .whitespacesAndNewlines).count < 80 {
                errors.append(error(
                    ruleID: "artifact-frame-timing.derivation.rationale",
                    description: "Artifact frame timing derivation records formulas and a specific rationale",
                    path: context.codingPath.appending(.key("rationale"))
                ))
            }
            return errors
        }
    }

    public static var generatedFrameCountMatchesSamples:
        Validation<LottieArtifactFrameTiming, LottieArtifactFrameTiming>
    {
        Validation(
            ruleID: "artifact-frame-timing.count.matches-samples",
            description: "Artifact frame timing generated frame count matches the sample list"
        ) { context in
            context.subject.derivation.generatedFrameCount == context.subject.samples.count
                ? []
                : [
                    error(
                        ruleID: "artifact-frame-timing.count.mismatch",
                        description: "Artifact frame timing generated frame count matches the sample list",
                        path: context.codingPath.appending(.key("derivation")).appending(.key("generatedFrameCount"))
                    ),
                ]
        }
    }

    public static var samplesUseContiguousIndexes:
        Validation<LottieArtifactFrameTiming, LottieArtifactFrameTiming>
    {
        Validation(
            ruleID: "artifact-frame-timing.samples.indexes",
            description: "Artifact frame timing samples use contiguous zero-based indexes"
        ) { context in
            context.subject.samples.enumerated().compactMap { expected, sample in
                sample.index == expected
                    ? nil
                    : error(
                        ruleID: "artifact-frame-timing.sample.index",
                        description: "Artifact frame timing samples use contiguous zero-based indexes",
                        path: context.codingPath
                            .appending(.key("samples"))
                            .appending(.index(expected))
                            .appending(.key("index"))
                    )
            }
        }
    }

    public static var samplesMatchSourceTimingFormula:
        Validation<LottieArtifactFrameTiming, LottieArtifactFrameTiming>
    {
        Validation(
            ruleID: "artifact-frame-timing.samples.formula",
            description: "Artifact frame timing samples match the declared source frame and time formulas"
        ) { context in
            var errors: [ValidationError] = []
            for index in context.subject.samples.indices {
                let sample = context.subject.samples[index]
                let samplePath = context.codingPath.appending(.key("samples")).appending(.index(index))
                if !sample.timeSeconds.isFinite {
                    errors.append(error(
                        ruleID: "artifact-frame-timing.sample.time-finite",
                        description: "Artifact frame timing samples match the declared source frame and time formulas",
                        path: samplePath.appending(.key("timeSeconds"))
                    ))
                }
                if !sample.sourceFrame.isFinite {
                    errors.append(error(
                        ruleID: "artifact-frame-timing.sample.source-frame-finite",
                        description: "Artifact frame timing samples match the declared source frame and time formulas",
                        path: samplePath.appending(.key("sourceFrame"))
                    ))
                }
                switch context.subject.policy {
                case .apngHalfOpenWindow:
                    if let expectedTime = apngSampleTime(context.subject, index: index) {
                        if !isClose(sample.timeSeconds, expectedTime) {
                            errors.append(error(
                                ruleID: "artifact-frame-timing.sample.apng-time",
                                description: "Artifact frame timing samples match the declared source frame and time formulas",
                                path: samplePath.appending(.key("timeSeconds"))
                            ))
                        }
                    }
                    let expectedFrame = context.subject.source.inPoint
                        + sample.timeSeconds * context.subject.source.frameRate
                    if !isClose(sample.sourceFrame, expectedFrame) {
                        errors.append(error(
                            ruleID: "artifact-frame-timing.sample.apng-source-frame",
                            description: "Artifact frame timing samples match the declared source frame and time formulas",
                            path: samplePath.appending(.key("sourceFrame"))
                        ))
                    }
                case .explicitSourceFrameList:
                    guard context.subject.source.frameRate > 0 else { break }
                    let expectedTime = max(
                        0,
                        (sample.sourceFrame - context.subject.source.inPoint) / context.subject.source.frameRate
                    )
                    if !isClose(sample.timeSeconds, expectedTime) {
                        errors.append(error(
                            ruleID: "artifact-frame-timing.sample.explicit-time",
                            description: "Artifact frame timing samples match the declared source frame and time formulas",
                            path: samplePath.appending(.key("timeSeconds"))
                        ))
                    }
                }
            }
            return errors
        }
    }

    public static var apngPolicyRecordsWindowAndFPS:
        Validation<LottieArtifactFrameTiming, LottieArtifactFrameTiming>
    {
        Validation(
            ruleID: "artifact-frame-timing.apng.request",
            description: "APNG artifact frame timing records start exclusive end output fps and inclusive sample end",
            check: { context in
                var errors: [ValidationError] = []
                if !(context.subject.request.startSeconds.map(\.isFinite) ?? false) {
                    errors.append(policyError("startSeconds", context))
                }
                if !(context.subject.request.exclusiveEndSeconds.map(\.isFinite) ?? false) {
                    errors.append(policyError("exclusiveEndSeconds", context))
                }
                if !(context.subject.request.outputFPS.map { $0.isFinite && $0 > 0 } ?? false) {
                    errors.append(policyError("outputFPS", context))
                }
                if !(context.subject.request.outputFrameIntervalSeconds.map { $0.isFinite && $0 > 0 } ?? false) {
                    errors.append(policyError("outputFrameIntervalSeconds", context))
                }
                if !(context.subject.derivation.effectiveStartSeconds.map(\.isFinite) ?? false) {
                    errors.append(derivationPolicyError("effectiveStartSeconds", context))
                }
                if !(context.subject.derivation.effectiveInclusiveEndSeconds.map(\.isFinite) ?? false) {
                    errors.append(derivationPolicyError("effectiveInclusiveEndSeconds", context))
                }
                if context.subject.request.sourceFrames != nil {
                    errors.append(policyError("sourceFrames", context))
                }
                return errors
            },
            when: { context in context.subject.policy == .apngHalfOpenWindow }
        )
    }

    public static var explicitPolicyRecordsRequestedFrames:
        Validation<LottieArtifactFrameTiming, LottieArtifactFrameTiming>
    {
        Validation(
            ruleID: "artifact-frame-timing.explicit.request",
            description: "Explicit artifact frame timing records the requested source-frame list",
            check: { context in
                guard let frames = context.subject.request.sourceFrames else {
                    return [explicitPolicyError("sourceFrames", context)]
                }
                var errors: [ValidationError] = []
                if frames.count != context.subject.samples.count {
                    errors.append(explicitPolicyError("sourceFrames", context))
                }
                let pairedCount = min(frames.count, context.subject.samples.count)
                for index in 0 ..< pairedCount {
                    if !isClose(frames[index], context.subject.samples[index].sourceFrame) {
                        errors.append(error(
                            ruleID: "artifact-frame-timing.explicit.requested-frame",
                            description: "Explicit artifact frame timing records the requested source-frame list",
                            path: context.codingPath
                                .appending(.key("request"))
                                .appending(.key("sourceFrames"))
                                .appending(.index(index))
                        ))
                    }
                }
                return errors
            },
            when: { context in context.subject.policy == .explicitSourceFrameList }
        )
    }

    private static func policyError(
        _ field: String,
        _ context: ValidationContext<LottieArtifactFrameTiming, LottieArtifactFrameTiming>
    ) -> ValidationError {
        error(
            ruleID: "artifact-frame-timing.policy.request",
            description: "APNG artifact frame timing records start exclusive end output fps and inclusive sample end",
            path: context.codingPath.appending(.key("request")).appending(.key(field))
        )
    }

    private static func derivationPolicyError(
        _ field: String,
        _ context: ValidationContext<LottieArtifactFrameTiming, LottieArtifactFrameTiming>
    ) -> ValidationError {
        error(
            ruleID: "artifact-frame-timing.policy.derivation",
            description: "APNG artifact frame timing records start exclusive end output fps and inclusive sample end",
            path: context.codingPath.appending(.key("derivation")).appending(.key(field))
        )
    }

    private static func explicitPolicyError(
        _ field: String,
        _ context: ValidationContext<LottieArtifactFrameTiming, LottieArtifactFrameTiming>
    ) -> ValidationError {
        error(
            ruleID: "artifact-frame-timing.explicit.request",
            description: "Explicit artifact frame timing records the requested source-frame list",
            path: context.codingPath.appending(.key("request")).appending(.key(field))
        )
    }

    private static func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.000_001
    }

    private static func apngSampleTime(_ timing: LottieArtifactFrameTiming, index: Int) -> Double? {
        guard let start = timing.derivation.effectiveStartSeconds,
              let end = timing.derivation.effectiveInclusiveEndSeconds
        else { return nil }
        guard timing.samples.indices.contains(index) else { return nil }
        guard timing.derivation.generatedFrameCount > 1 else { return start }
        let progress = Double(index) / Double(timing.derivation.generatedFrameCount - 1)
        return start + (end - start) * progress
    }

    private static func error(
        ruleID: String,
        description: String,
        path: JSONPath,
        evidence: String? = nil
    ) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "Failed to satisfy: \(description)",
            at: path,
            phase: .source,
            classification: .reported,
            evidence: evidence
        )
    }
}

private struct LottieArtifactFrameTimingAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, LottieArtifactFrameTiming) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<LottieArtifactFrameTiming, Subject>) {
        ruleID = validation.ruleID
        description = validation.description
        applyClosure = { input, path, document in
            guard let subject = input as? Subject else { return [] }
            return validation.apply(to: subject, at: path, in: document)
        }
    }

    func apply(
        to subject: any Validatable,
        at codingPath: JSONPath,
        in document: LottieArtifactFrameTiming
    ) -> [ValidationError] {
        applyClosure(subject, codingPath, document)
    }
}
