import Foundation
import LottieModel

public struct LottieRenderedArtifactManifest: Codable, Equatable, Sendable, Validatable {
    public var schema: Schema
    public var source: Source
    public var renderer: Renderer
    public var export: Export
    public var artifacts: [Artifact]
    public var evidence: Evidence
    public var findings: [Finding]

    public init(
        schema: Schema,
        source: Source,
        renderer: Renderer,
        export: Export,
        artifacts: [Artifact],
        evidence: Evidence,
        findings: [Finding]
    ) {
        self.schema = schema
        self.source = source
        self.renderer = renderer
        self.export = export
        self.artifacts = artifacts
        self.evidence = evidence
        self.findings = findings
    }

    public struct Schema: Codable, Equatable, Sendable, Validatable {
        public var name: String
        public var version: Int

        public init(name: String, version: Int) {
            self.name = name
            self.version = version
        }
    }

    public struct Source: Codable, Equatable, Sendable, Validatable {
        public var fixtureID: String
        public var path: String
        public var animationName: String?
        public var width: Double
        public var height: Double
        public var frameRate: Double
        public var inPoint: Double
        public var outPoint: Double

        public init(
            fixtureID: String,
            path: String,
            animationName: String?,
            width: Double,
            height: Double,
            frameRate: Double,
            inPoint: Double,
            outPoint: Double
        ) {
            self.fixtureID = fixtureID
            self.path = path
            self.animationName = animationName
            self.width = width
            self.height = height
            self.frameRate = frameRate
            self.inPoint = inPoint
            self.outPoint = outPoint
        }
    }

    public struct Renderer: Codable, Equatable, Sendable, Validatable {
        public var name: String
        public var backend: String
        public var version: String?
        public var command: String

        public init(name: String, backend: String, version: String?, command: String) {
            self.name = name
            self.backend = backend
            self.version = version
            self.command = command
        }
    }

    public struct Export: Codable, Equatable, Sendable, Validatable {
        public var kind: String
        public var policy: String
        public var scale: Double
        public var requestedFPS: Double
        public var generatedFrameCount: Int

        public init(kind: String, policy: String, scale: Double, requestedFPS: Double, generatedFrameCount: Int) {
            self.kind = kind
            self.policy = policy
            self.scale = scale
            self.requestedFPS = requestedFPS
            self.generatedFrameCount = generatedFrameCount
        }
    }

    public struct Artifact: Codable, Equatable, Sendable, Validatable {
        public var kind: String
        public var path: String
        public var frameIndex: Int?
        public var sourceFrame: Double?
        public var timeSeconds: Double?
        public var evidenceLinks: [EvidenceLink]?

        public init(
            kind: String,
            path: String,
            frameIndex: Int?,
            sourceFrame: Double?,
            timeSeconds: Double?,
            evidenceLinks: [EvidenceLink]? = nil
        ) {
            self.kind = kind
            self.path = path
            self.frameIndex = frameIndex
            self.sourceFrame = sourceFrame
            self.timeSeconds = timeSeconds
            self.evidenceLinks = evidenceLinks
        }

        public struct EvidenceLink: Codable, Equatable, Sendable, Validatable {
            public var kind: String
            public var path: String
            public var frameIndex: Int?
            public var sourceFrame: Double?
            public var timeSeconds: Double?
            public var rowAddress: String?
            public var note: String

            public init(
                kind: String,
                path: String,
                frameIndex: Int?,
                sourceFrame: Double?,
                timeSeconds: Double?,
                rowAddress: String?,
                note: String
            ) {
                self.kind = kind
                self.path = path
                self.frameIndex = frameIndex
                self.sourceFrame = sourceFrame
                self.timeSeconds = timeSeconds
                self.rowAddress = rowAddress
                self.note = note
            }
        }
    }

    public struct Evidence: Codable, Equatable, Sendable, Validatable {
        public var references: [Reference]

        public init(references: [Reference]) {
            self.references = references
        }

        public struct Reference: Codable, Equatable, Sendable, Validatable {
            public var kind: String
            public var path: String
            public var frameIndex: Int?
            public var sourceFrame: Double?
            public var note: String

            public init(kind: String, path: String, frameIndex: Int?, sourceFrame: Double?, note: String) {
                self.kind = kind
                self.path = path
                self.frameIndex = frameIndex
                self.sourceFrame = sourceFrame
                self.note = note
            }
        }
    }

    public struct Finding: Codable, Equatable, Sendable, Validatable {
        public var phase: String
        public var ruleID: String
        public var path: String
        public var sourcePath: String?
        public var reason: String
        public var severity: String

        public init(phase: String, ruleID: String, path: String, sourcePath: String?, reason: String, severity: String) {
            self.phase = phase
            self.ruleID = ruleID
            self.path = path
            self.sourcePath = sourcePath
            self.reason = reason
            self.severity = severity
        }
    }
}

public final class LottieRenderedArtifactManifestValidator {
    private var defaultValidations: [LottieRenderedArtifactManifestAnyValidation]
    private var customValidations: [LottieRenderedArtifactManifestAnyValidation]

    public init() {
        defaultValidations = LottieRenderedArtifactManifestBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [LottieRenderedArtifactManifestAnyValidation],
        customValidations: [LottieRenderedArtifactManifestAnyValidation]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieRenderedArtifactManifestValidator {
        LottieRenderedArtifactManifestValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieRenderedArtifactManifest, some Validatable>) -> Self {
        customValidations.append(LottieRenderedArtifactManifestAnyValidation(validation))
        return self
    }

    @discardableResult
    public func validating(
        _ validation: KeyPath<LottieRenderedArtifactManifestBuiltinValidation.Type, Validation<LottieRenderedArtifactManifest, some Validatable>>
    ) -> Self {
        validating(LottieRenderedArtifactManifestBuiltinValidation.self[keyPath: validation])
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    public func validate(_ manifest: LottieRenderedArtifactManifest) throws {
        let errors = collectErrors(in: manifest)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    public func collectErrors(in manifest: LottieRenderedArtifactManifest) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(manifest, at: JSONPath(), in: manifest, errors: &errors)
        visit(manifest.schema, at: JSONPath([.key("schema")]), in: manifest, errors: &errors)
        visit(manifest.source, at: JSONPath([.key("source")]), in: manifest, errors: &errors)
        visit(manifest.renderer, at: JSONPath([.key("renderer")]), in: manifest, errors: &errors)
        visit(manifest.export, at: JSONPath([.key("export")]), in: manifest, errors: &errors)
        for artifactIndex in manifest.artifacts.indices {
            visit(
                manifest.artifacts[artifactIndex],
                at: JSONPath([.key("artifacts"), .index(artifactIndex)]),
                in: manifest,
                errors: &errors
            )
            if let evidenceLinks = manifest.artifacts[artifactIndex].evidenceLinks {
                for linkIndex in evidenceLinks.indices {
                    visit(
                        evidenceLinks[linkIndex],
                        at: JSONPath([.key("artifacts"), .index(artifactIndex), .key("evidenceLinks"), .index(linkIndex)]),
                        in: manifest,
                        errors: &errors
                    )
                }
            }
        }
        visit(manifest.evidence, at: JSONPath([.key("evidence")]), in: manifest, errors: &errors)
        for referenceIndex in manifest.evidence.references.indices {
            visit(
                manifest.evidence.references[referenceIndex],
                at: JSONPath([.key("evidence"), .key("references"), .index(referenceIndex)]),
                in: manifest,
                errors: &errors
            )
        }
        for findingIndex in manifest.findings.indices {
            visit(
                manifest.findings[findingIndex],
                at: JSONPath([.key("findings"), .index(findingIndex)]),
                in: manifest,
                errors: &errors
            )
        }
        return errors
    }

    private var activeValidations: [LottieRenderedArtifactManifestAnyValidation] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in manifest: LottieRenderedArtifactManifest,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: manifest))
        }
    }
}

public extension LottieRenderedArtifactManifest {
    static func decodeValidated(
        from data: Data,
        using validator: LottieRenderedArtifactManifestValidator = LottieRenderedArtifactManifestValidator()
    ) throws -> LottieRenderedArtifactManifest {
        do {
            return try JSONDecoder().decode(LottieRenderedArtifactManifest.self, from: data)
                .validate(using: validator)
        } catch let errors as ValidationErrorCollection {
            throw errors
        } catch let error as DecodingError {
            throw ValidationErrorCollection([Self.validationError(from: error)])
        }
    }

    @discardableResult
    func validate(
        using validator: LottieRenderedArtifactManifestValidator = LottieRenderedArtifactManifestValidator()
    ) throws -> Self {
        try validator.validate(self)
        return self
    }

    private static func validationError(from error: DecodingError) -> ValidationError {
        switch error {
        case let .keyNotFound(key, context):
            return ValidationError(
                ruleID: "rendered-artifact-manifest.decode.key-not-found",
                reason: "Failed to satisfy: Rendered artifact manifest decodes as the typed schema",
                at: jsonPath(from: context.codingPath).appending(codingComponent(from: key)),
                phase: .parse,
                classification: .gap,
                evidence: context.debugDescription
            )
        case let .typeMismatch(_, context),
             let .valueNotFound(_, context),
             let .dataCorrupted(context):
            return decodingError(context: context)
        @unknown default:
            return ValidationError(
                ruleID: "rendered-artifact-manifest.decode.unknown",
                reason: "Failed to satisfy: Rendered artifact manifest decodes as the typed schema",
                at: JSONPath(),
                phase: .parse,
                classification: .gap
            )
        }
    }

    private static func decodingError(context: DecodingError.Context) -> ValidationError {
        ValidationError(
            ruleID: "rendered-artifact-manifest.decode",
            reason: "Failed to satisfy: Rendered artifact manifest decodes as the typed schema",
            at: jsonPath(from: context.codingPath),
            phase: .parse,
            classification: .gap,
            evidence: context.debugDescription
        )
    }

    private static func jsonPath(from codingPath: [any CodingKey]) -> JSONPath {
        JSONPath(codingPath.map(codingComponent(from:)))
    }

    private static func codingComponent(from key: any CodingKey) -> JSONPath.Component {
        if let index = key.intValue {
            return .index(index)
        }
        return .key(key.stringValue)
    }
}

public enum LottieRenderedArtifactManifestBuiltinValidation {
    public static let supportedExportKinds: Set<String> = [
        "apng",
        "png-sequence",
    ]

    public static let supportedArtifactKinds: Set<String> = [
        "apng",
        "geometry-csv",
        "geometry-json",
        "manifest",
        "png-frame",
        "report",
    ]

    public static let supportedEvidenceKinds: Set<String> = [
        "apng-report",
        "backend-evidence",
        "geometry-csv",
        "geometry-json",
        "import-report",
        "lottie-web-intent",
        "oracle-summary",
        "render-ir",
        "validation-report",
    ]

    public static let supportedEvidenceLinkKinds: Set<String> = supportedEvidenceKinds

    public static let geometryEvidenceKinds: Set<String> = [
        "geometry-csv",
        "geometry-json",
    ]

    public static let supportedFindingPhases: Set<String> = [
        "backend",
        "import",
        "renderIR",
        "validation",
    ]

    public static let supportedFindingSeverities: Set<String> = [
        "error",
        "note",
        "warning",
    ]

    fileprivate static var defaultValidations: [LottieRenderedArtifactManifestAnyValidation] {
        [
            LottieRenderedArtifactManifestAnyValidation(schemaNameAndVersionAreSupported),
            LottieRenderedArtifactManifestAnyValidation(sourceIdentityAndTimingArePresent),
            LottieRenderedArtifactManifestAnyValidation(rendererIdentityIsPresent),
            LottieRenderedArtifactManifestAnyValidation(exportPolicyIsComplete),
            LottieRenderedArtifactManifestAnyValidation(artifactRecordsArePathBearingAndUnique),
            LottieRenderedArtifactManifestAnyValidation(artifactEvidenceLinksArePathBearing),
            LottieRenderedArtifactManifestAnyValidation(frameArtifactsLinkSourceIntentAndGeometry),
            LottieRenderedArtifactManifestAnyValidation(evidenceReferencesArePathBearing),
            LottieRenderedArtifactManifestAnyValidation(evidenceContainsSourceIntentAndGeometry),
            LottieRenderedArtifactManifestAnyValidation(findingsArePathBearing),
        ]
    }

    public static var schemaNameAndVersionAreSupported:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Schema>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.schema.supported",
            description: "Rendered artifact manifest schema name is purelottie.rendered-artifact-manifest and version is 1",
            phase: .source
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.name != "purelottie.rendered-artifact-manifest" {
                errors.append(error(
                    ruleID: "rendered-artifact-manifest.schema.name",
                    description: "Rendered artifact manifest schema name is purelottie.rendered-artifact-manifest and version is 1",
                    at: context.codingPath.appending(.key("name"))
                ))
            }
            if context.subject.version != 1 {
                errors.append(error(
                    ruleID: "rendered-artifact-manifest.schema.version",
                    description: "Rendered artifact manifest schema name is purelottie.rendered-artifact-manifest and version is 1",
                    at: context.codingPath.appending(.key("version"))
                ))
            }
            return errors
        }
    }

    public static var sourceIdentityAndTimingArePresent:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Source>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.source.complete",
            description: "Rendered artifact source identity timing and dimensions are present"
        ) { context in
            var errors: [ValidationError] = []
            if isBlank(context.subject.fixtureID) {
                errors.append(sourceError("fixtureID", context))
            }
            if isBlank(context.subject.path) {
                errors.append(sourceError("path", context))
            }
            if !isPositiveFinite(context.subject.width) {
                errors.append(sourceError("width", context))
            }
            if !isPositiveFinite(context.subject.height) {
                errors.append(sourceError("height", context))
            }
            if !isPositiveFinite(context.subject.frameRate) {
                errors.append(sourceError("frameRate", context))
            }
            if !isFinite(context.subject.inPoint) {
                errors.append(sourceError("inPoint", context))
            }
            if !isFinite(context.subject.outPoint) || context.subject.outPoint <= context.subject.inPoint {
                errors.append(sourceError("outPoint", context))
            }
            return errors
        }
    }

    public static var rendererIdentityIsPresent:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Renderer>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.renderer.complete",
            description: "Rendered artifact renderer identity backend and command are present"
        ) { context in
            var errors: [ValidationError] = []
            if isBlank(context.subject.name) {
                errors.append(rendererError("name", context))
            }
            if isBlank(context.subject.backend) {
                errors.append(rendererError("backend", context))
            }
            if isBlank(context.subject.command) {
                errors.append(rendererError("command", context))
            }
            return errors
        }
    }

    public static var exportPolicyIsComplete:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Export>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.export.complete",
            description: "Rendered artifact export policy declares kind scale fps and generated frame count"
        ) { context in
            var errors: [ValidationError] = []
            if !supportedExportKinds.contains(context.subject.kind) {
                errors.append(exportError("kind", context))
            }
            if isBlank(context.subject.policy) {
                errors.append(exportError("policy", context))
            }
            if !isPositiveFinite(context.subject.scale) {
                errors.append(exportError("scale", context))
            }
            if !isPositiveFinite(context.subject.requestedFPS) {
                errors.append(exportError("requestedFPS", context))
            }
            if context.subject.generatedFrameCount <= 0 {
                errors.append(exportError("generatedFrameCount", context))
            }
            return errors
        }
    }

    public static var artifactRecordsArePathBearingAndUnique:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.artifacts.path-bearing",
            description: "Rendered artifact records are path-bearing unique and frame-addressed when needed"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.artifacts.isEmpty {
                errors.append(error(
                    ruleID: "rendered-artifact-manifest.artifacts.present",
                    description: "Rendered artifact records are path-bearing unique and frame-addressed when needed",
                    at: context.codingPath.appending(.key("artifacts"))
                ))
            }

            var seenPaths: Set<String> = []
            for artifactIndex in context.subject.artifacts.indices {
                let artifact = context.subject.artifacts[artifactIndex]
                let artifactPath = context.codingPath.appending(.key("artifacts")).appending(.index(artifactIndex))
                if !supportedArtifactKinds.contains(artifact.kind) {
                    errors.append(error(
                        ruleID: "rendered-artifact-manifest.artifact.kind",
                        description: "Rendered artifact records are path-bearing unique and frame-addressed when needed",
                        at: artifactPath.appending(.key("kind"))
                    ))
                }
                if isBlank(artifact.path) || seenPaths.contains(artifact.path) {
                    errors.append(error(
                        ruleID: "rendered-artifact-manifest.artifact.path",
                        description: "Rendered artifact records are path-bearing unique and frame-addressed when needed",
                        at: artifactPath.appending(.key("path"))
                    ))
                }
                seenPaths.insert(artifact.path)
                if artifact.kind == "png-frame" {
                    if artifact.frameIndex == nil {
                        errors.append(frameArtifactError("frameIndex", artifactPath))
                    }
                    if artifact.sourceFrame.map(isFinite) != true {
                        errors.append(frameArtifactError("sourceFrame", artifactPath))
                    }
                    if artifact.timeSeconds.map({ isFinite($0) && $0 >= 0 }) != true {
                        errors.append(frameArtifactError("timeSeconds", artifactPath))
                    }
                    if artifact.evidenceLinks?.isEmpty != false {
                        errors.append(frameArtifactError("evidenceLinks", artifactPath))
                    }
                }
            }
            return errors
        }
    }

    public static var artifactEvidenceLinksArePathBearing:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Artifact.EvidenceLink>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.artifact-evidence.path-bearing",
            description: "Rendered artifact evidence links use stable kinds paths frame addresses and notes"
        ) { context in
            var errors: [ValidationError] = []
            if !supportedEvidenceLinkKinds.contains(context.subject.kind) {
                errors.append(artifactEvidenceLinkError("kind", context))
            }
            if isBlank(context.subject.path) {
                errors.append(artifactEvidenceLinkError("path", context))
            }
            if let frameIndex = context.subject.frameIndex, frameIndex < 0 {
                errors.append(artifactEvidenceLinkError("frameIndex", context))
            }
            if let sourceFrame = context.subject.sourceFrame, !isFinite(sourceFrame) {
                errors.append(artifactEvidenceLinkError("sourceFrame", context))
            }
            if let timeSeconds = context.subject.timeSeconds, !isFinite(timeSeconds) || timeSeconds < 0 {
                errors.append(artifactEvidenceLinkError("timeSeconds", context))
            }
            if evidenceLinkRequiresRowAddress(context.subject.kind) {
                if context.subject.rowAddress.map(isBlank) != false {
                    errors.append(artifactEvidenceLinkError("rowAddress", context))
                } else if evidenceLinkRequiresJSONFrameAddress(context.subject.kind),
                          context.subject.rowAddress.map(isJSONFrameRowAddress) != true
                {
                    errors.append(artifactEvidenceLinkError("rowAddress", context))
                }
            }
            if context.subject.note.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                errors.append(artifactEvidenceLinkError("note", context))
            }
            return errors
        }
    }

    public static var frameArtifactsLinkSourceIntentAndGeometry:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.artifact-evidence.required",
            description: "Rendered frame artifacts link to source-intent and geometry evidence for the same frame"
        ) { context in
            var errors: [ValidationError] = []
            let evidenceKeys = Set(context.subject.evidence.references.map(evidenceKey))
            for artifactIndex in context.subject.artifacts.indices {
                let artifact = context.subject.artifacts[artifactIndex]
                guard artifact.kind == "png-frame" else { continue }
                let artifactPath = context.codingPath.appending(.key("artifacts")).appending(.index(artifactIndex))
                let links = artifact.evidenceLinks ?? []
                if !links.contains(where: { $0.kind == "lottie-web-intent" }) {
                    errors.append(frameArtifactError("evidenceLinks", artifactPath))
                }
                if !links.contains(where: { geometryEvidenceKinds.contains($0.kind) }) {
                    errors.append(frameArtifactError("evidenceLinks", artifactPath))
                }
                for linkIndex in links.indices {
                    let link = links[linkIndex]
                    let linkPath = artifactPath.appending(.key("evidenceLinks")).appending(.index(linkIndex))
                    if !evidenceKeys.contains(evidenceKey(link)) {
                        errors.append(error(
                            ruleID: "rendered-artifact-manifest.artifact-evidence.reference",
                            description: "Rendered frame artifacts link to source-intent and geometry evidence for the same frame",
                            at: linkPath.appending(.key("path"))
                        ))
                    }
                    if link.frameIndex != artifact.frameIndex {
                        errors.append(frameArtifactEvidenceAddressError("frameIndex", linkPath))
                    }
                    if !optionalDoublesMatch(link.sourceFrame, artifact.sourceFrame) {
                        errors.append(frameArtifactEvidenceAddressError("sourceFrame", linkPath))
                    }
                    if !optionalDoublesMatch(link.timeSeconds, artifact.timeSeconds) {
                        errors.append(frameArtifactEvidenceAddressError("timeSeconds", linkPath))
                    }
                }
            }
            return errors
        }
    }

    public static var evidenceReferencesArePathBearing:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Evidence.Reference>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.evidence.path-bearing",
            description: "Rendered artifact evidence references use stable kinds non-empty paths and notes"
        ) { context in
            var errors: [ValidationError] = []
            if !supportedEvidenceKinds.contains(context.subject.kind) {
                errors.append(evidenceError("kind", context))
            }
            if isBlank(context.subject.path) {
                errors.append(evidenceError("path", context))
            }
            if context.subject.note.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                errors.append(evidenceError("note", context))
            }
            if let frameIndex = context.subject.frameIndex, frameIndex < 0 {
                errors.append(evidenceError("frameIndex", context))
            }
            if let sourceFrame = context.subject.sourceFrame, !isFinite(sourceFrame) {
                errors.append(evidenceError("sourceFrame", context))
            }
            return errors
        }
    }

    public static var evidenceContainsSourceIntentAndGeometry:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Evidence>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.evidence.required",
            description: "Rendered artifact evidence includes source-intent and geometry references"
        ) { context in
            var errors: [ValidationError] = []
            if context.subject.references.isEmpty {
                errors.append(error(
                    ruleID: "rendered-artifact-manifest.evidence.present",
                    description: "Rendered artifact evidence includes source-intent and geometry references",
                    at: context.codingPath.appending(.key("references"))
                ))
            }
            if !context.subject.references.contains(where: { $0.kind == "lottie-web-intent" }) {
                errors.append(error(
                    ruleID: "rendered-artifact-manifest.evidence.source-intent",
                    description: "Rendered artifact evidence includes source-intent and geometry references",
                    at: context.codingPath.appending(.key("references"))
                ))
            }
            if !context.subject.references.contains(where: { geometryEvidenceKinds.contains($0.kind) }) {
                errors.append(error(
                    ruleID: "rendered-artifact-manifest.evidence.geometry",
                    description: "Rendered artifact evidence includes source-intent and geometry references",
                    at: context.codingPath.appending(.key("references"))
                ))
            }
            return errors
        }
    }

    public static var findingsArePathBearing:
        Validation<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Finding>
    {
        Validation(
            ruleID: "rendered-artifact-manifest.finding.path-bearing",
            description: "Rendered artifact findings contain stable phase severity rule id path and reason"
        ) { context in
            var errors: [ValidationError] = []
            if !supportedFindingPhases.contains(context.subject.phase) {
                errors.append(findingError("phase", context))
            }
            if isBlank(context.subject.ruleID) {
                errors.append(findingError("ruleID", context))
            }
            if isBlank(context.subject.path) {
                errors.append(findingError("path", context))
            }
            if isBlank(context.subject.reason) {
                errors.append(findingError("reason", context))
            }
            if !supportedFindingSeverities.contains(context.subject.severity) {
                errors.append(findingError("severity", context))
            }
            return errors
        }
    }

    private static func sourceError(
        _ key: String,
        _ context: ValidationContext<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Source>
    ) -> ValidationError {
        error(
            ruleID: "rendered-artifact-manifest.source.complete",
            description: "Rendered artifact source identity timing and dimensions are present",
            at: context.codingPath.appending(.key(key))
        )
    }

    private static func rendererError(
        _ key: String,
        _ context: ValidationContext<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Renderer>
    ) -> ValidationError {
        error(
            ruleID: "rendered-artifact-manifest.renderer.complete",
            description: "Rendered artifact renderer identity backend and command are present",
            at: context.codingPath.appending(.key(key))
        )
    }

    private static func exportError(
        _ key: String,
        _ context: ValidationContext<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Export>
    ) -> ValidationError {
        error(
            ruleID: "rendered-artifact-manifest.export.complete",
            description: "Rendered artifact export policy declares kind scale fps and generated frame count",
            at: context.codingPath.appending(.key(key))
        )
    }

    private static func frameArtifactError(_ key: String, _ artifactPath: JSONPath) -> ValidationError {
        error(
            ruleID: "rendered-artifact-manifest.artifact.frame-address",
            description: "Rendered artifact records are path-bearing unique and frame-addressed when needed",
            at: artifactPath.appending(.key(key))
        )
    }

    private static func evidenceError(
        _ key: String,
        _ context: ValidationContext<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Evidence.Reference>
    ) -> ValidationError {
        error(
            ruleID: "rendered-artifact-manifest.evidence.path-bearing",
            description: "Rendered artifact evidence references use stable kinds non-empty paths and notes",
            at: context.codingPath.appending(.key(key))
        )
    }

    private static func artifactEvidenceLinkError(
        _ key: String,
        _ context: ValidationContext<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Artifact.EvidenceLink>
    ) -> ValidationError {
        error(
            ruleID: "rendered-artifact-manifest.artifact-evidence.path-bearing",
            description: "Rendered artifact evidence links use stable kinds paths frame addresses and notes",
            at: context.codingPath.appending(.key(key))
        )
    }

    private static func frameArtifactEvidenceAddressError(_ key: String, _ linkPath: JSONPath) -> ValidationError {
        error(
            ruleID: "rendered-artifact-manifest.artifact-evidence.address",
            description: "Rendered frame artifacts link to source-intent and geometry evidence for the same frame",
            at: linkPath.appending(.key(key))
        )
    }

    private static func findingError(
        _ key: String,
        _ context: ValidationContext<LottieRenderedArtifactManifest, LottieRenderedArtifactManifest.Finding>
    ) -> ValidationError {
        error(
            ruleID: "rendered-artifact-manifest.finding.path-bearing",
            description: "Rendered artifact findings contain stable phase severity rule id path and reason",
            at: context.codingPath.appending(.key(key))
        )
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isPositiveFinite(_ value: Double) -> Bool {
        isFinite(value) && value > 0
    }

    private static func isFinite(_ value: Double) -> Bool {
        value.isFinite
    }

    private static func evidenceLinkRequiresRowAddress(_ kind: String) -> Bool {
        kind == "lottie-web-intent" || geometryEvidenceKinds.contains(kind)
    }

    private static func evidenceLinkRequiresJSONFrameAddress(_ kind: String) -> Bool {
        kind == "lottie-web-intent" || kind == "geometry-json"
    }

    private static func isJSONFrameRowAddress(_ value: String) -> Bool {
        let prefix = "$.frames["
        guard value.hasPrefix(prefix), value.hasSuffix("]") else { return false }
        let start = value.index(value.startIndex, offsetBy: prefix.count)
        let end = value.index(before: value.endIndex)
        let index = value[start ..< end]
        return !index.isEmpty && index.allSatisfy(\.isNumber)
    }

    private static func evidenceKey(_ reference: LottieRenderedArtifactManifest.Evidence.Reference) -> String {
        "\(reference.kind)\u{1F}\(reference.path)"
    }

    private static func evidenceKey(_ link: LottieRenderedArtifactManifest.Artifact.EvidenceLink) -> String {
        "\(link.kind)\u{1F}\(link.path)"
    }

    private static func optionalDoublesMatch(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            isFinite(lhs) && isFinite(rhs) && abs(lhs - rhs) <= 0.000_001
        case (.none, .none):
            true
        default:
            false
        }
    }

    private static func error(ruleID: String, description: String, at path: JSONPath) -> ValidationError {
        ValidationError(
            ruleID: ruleID,
            reason: "Failed to satisfy: \(description)",
            at: path,
            phase: .semantic,
            classification: .reported
        )
    }
}

private struct LottieRenderedArtifactManifestAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, LottieRenderedArtifactManifest) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<LottieRenderedArtifactManifest, Subject>) {
        ruleID = validation.ruleID
        description = validation.description
        applyClosure = { subject, path, document in
            guard let subject = subject as? Subject else { return [] }
            return validation.apply(to: subject, at: path, in: document)
        }
    }

    func apply(
        to subject: any Validatable,
        at path: JSONPath,
        in document: LottieRenderedArtifactManifest
    ) -> [ValidationError] {
        applyClosure(subject, path, document)
    }
}
