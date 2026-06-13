import Foundation
import LottieModel

/// A filesystem-backed review folder contract for PNG frame dumps.
///
/// The folder is valid only when the rendered artifact manifest, the timing
/// rationale in `oracle-summary.json`, and the actual PNG files agree. This is
/// deliberately an evaluation-layer type: it imports neither PureLayer nor
/// PureDraw, and it judges the measurable artifact boundary after rendering.
public struct LottieReviewFrameFolder: Sendable, Validatable {
    public var rootPath: String
    public var manifest: LottieRenderedArtifactManifest
    public var frameTiming: LottieArtifactFrameTiming
    public var files: [File]

    public init(
        rootPath: String,
        manifest: LottieRenderedArtifactManifest,
        frameTiming: LottieArtifactFrameTiming,
        files: [File]
    ) {
        self.rootPath = rootPath
        self.manifest = manifest
        self.frameTiming = frameTiming
        self.files = files
    }

    /// One PNG file discovered under the review folder, addressed by a
    /// manifest-relative path and measured byte count.
    public struct File: Equatable, Sendable, Validatable {
        public var relativePath: String
        public var byteCount: Int64

        /// Creates a discovered-file record for validation and tests.
        public init(relativePath: String, byteCount: Int64) {
            self.relativePath = relativePath
            self.byteCount = byteCount
        }
    }
}

public extension LottieReviewFrameFolder {
    /// Loads the rendered artifact manifest, the frame-timing summary, and all
    /// PNG files currently present under a review folder.
    static func load(from directory: URL, fileManager: FileManager = .default) throws -> Self {
        let manifestURL = directory.appendingPathComponent("rendered-artifact-manifest.json")
        let summaryURL = directory.appendingPathComponent("oracle-summary.json")
        let manifest = try LottieRenderedArtifactManifest.decodeValidated(from: Data(contentsOf: manifestURL))
        let summary = try JSONDecoder().decode(ReviewSummary.self, from: Data(contentsOf: summaryURL))
        return try LottieReviewFrameFolder(
            rootPath: directory.standardizedFileURL.path,
            manifest: manifest,
            frameTiming: summary.frameTiming,
            files: pngFiles(in: directory, fileManager: fileManager)
        )
    }

    /// Loads a review folder and immediately applies the default completeness
    /// validator, throwing a `ValidationErrorCollection` on semantic failures.
    static func loadValidated(
        from directory: URL,
        fileManager: FileManager = .default,
        using validator: LottieReviewFrameFolderValidator = LottieReviewFrameFolderValidator()
    ) throws -> Self {
        try load(from: directory, fileManager: fileManager)
            .validate(using: validator)
    }

    /// Validates the already-loaded review folder and returns it unchanged on
    /// success so callers can chain loading and validation.
    @discardableResult
    func validate(
        using validator: LottieReviewFrameFolderValidator = LottieReviewFrameFolderValidator()
    ) throws -> Self {
        try validator.validate(self)
        return self
    }

    private static func pngFiles(in directory: URL, fileManager: FileManager) throws -> [File] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [File] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "png" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let relativePath = relativePath(from: directory, to: url)
            else {
                continue
            }
            files.append(File(relativePath: relativePath, byteCount: Int64(values.fileSize ?? 0)))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func relativePath(from directory: URL, to file: URL) -> String? {
        let directoryPath = directory.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        if filePath == directoryPath { return "." }
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
}

public final class LottieReviewFrameFolderValidator {
    private var defaultValidations: [LottieReviewFrameFolderAnyValidation]
    private var customValidations: [LottieReviewFrameFolderAnyValidation]

    public init() {
        defaultValidations = LottieReviewFrameFolderBuiltinValidation.defaultValidations
        customValidations = []
    }

    private init(
        defaultValidations: [LottieReviewFrameFolderAnyValidation],
        customValidations: [LottieReviewFrameFolderAnyValidation]
    ) {
        self.defaultValidations = defaultValidations
        self.customValidations = customValidations
    }

    public static var blank: LottieReviewFrameFolderValidator {
        LottieReviewFrameFolderValidator(defaultValidations: [], customValidations: [])
    }

    public var validationDescriptions: [String] {
        activeValidations.map(\.description)
    }

    @discardableResult
    public func validating(_ validation: Validation<LottieReviewFrameFolder, some Validatable>) -> Self {
        customValidations.append(LottieReviewFrameFolderAnyValidation(validation))
        return self
    }

    @discardableResult
    public func validating(
        _ validation: KeyPath<LottieReviewFrameFolderBuiltinValidation.Type, Validation<LottieReviewFrameFolder, some Validatable>>
    ) -> Self {
        validating(LottieReviewFrameFolderBuiltinValidation.self[keyPath: validation])
    }

    @discardableResult
    public func withoutValidating(_ descriptions: String...) -> Self {
        let removed = Set(descriptions)
        defaultValidations.removeAll { removed.contains($0.description) }
        customValidations.removeAll { removed.contains($0.description) }
        return self
    }

    public func validate(_ folder: LottieReviewFrameFolder) throws {
        let errors = collectErrors(in: folder)
        guard errors.isEmpty else {
            throw ValidationErrorCollection(errors)
        }
    }

    public func collectErrors(in folder: LottieReviewFrameFolder) -> [ValidationError] {
        var errors: [ValidationError] = []
        visit(folder, at: JSONPath(), in: folder, errors: &errors)
        for index in folder.files.indices {
            visit(
                folder.files[index],
                at: JSONPath([.key("files"), .index(index)]),
                in: folder,
                errors: &errors
            )
        }
        return errors
    }

    private var activeValidations: [LottieReviewFrameFolderAnyValidation] {
        defaultValidations + customValidations
    }

    private func visit(
        _ subject: any Validatable,
        at path: JSONPath,
        in folder: LottieReviewFrameFolder,
        errors: inout [ValidationError]
    ) {
        for validation in activeValidations {
            errors.append(contentsOf: validation.apply(to: subject, at: path, in: folder))
        }
    }
}

public enum LottieReviewFrameFolderBuiltinValidation {
    fileprivate static var defaultValidations: [LottieReviewFrameFolderAnyValidation] {
        [
            LottieReviewFrameFolderAnyValidation(manifestAndTimingAreValid),
            LottieReviewFrameFolderAnyValidation(generatedFrameCountMatchesManifestAndTiming),
            LottieReviewFrameFolderAnyValidation(frameArtifactsMatchTimingSamples),
            LottieReviewFrameFolderAnyValidation(frameArtifactPathsStayInsideFolder),
            LottieReviewFrameFolderAnyValidation(expectedFrameFilesExistAndAreNonEmpty),
            LottieReviewFrameFolderAnyValidation(folderContainsNoUnexpectedPNGFrames),
            LottieReviewFrameFolderAnyValidation(oneFrameExportsRequireOneFrameSourceWindow),
        ]
    }

    public static var manifestAndTimingAreValid:
        Validation<LottieReviewFrameFolder, LottieReviewFrameFolder>
    {
        Validation(
            ruleID: "review-frame-folder.typed-inputs.valid",
            description: "Review frame folders carry valid rendered artifact manifests and frame timing rationales"
        ) { context in
            prefixed(
                LottieRenderedArtifactManifestValidator().collectErrors(in: context.subject.manifest),
                with: .key("manifest")
            ) + prefixed(
                LottieArtifactFrameTimingValidator().collectErrors(in: context.subject.frameTiming),
                with: .key("frameTiming")
            )
        }
    }

    public static var generatedFrameCountMatchesManifestAndTiming:
        Validation<LottieReviewFrameFolder, LottieReviewFrameFolder>
    {
        Validation(
            ruleID: "review-frame-folder.frame-count.matches",
            description: "Review frame folder generated frame count matches manifest artifacts and timing samples"
        ) { context in
            let artifacts = pngFrameArtifacts(in: context.subject.manifest)
            let timing = context.subject.frameTiming
            var errors: [ValidationError] = []
            if context.subject.manifest.export.generatedFrameCount != artifacts.count {
                errors.append(error(
                    ruleID: "review-frame-folder.manifest.generated-count",
                    description: "Review frame folder generated frame count matches manifest artifacts and timing samples",
                    at: path("manifest", "export", "generatedFrameCount")
                ))
            }
            if timing.derivation.generatedFrameCount != artifacts.count {
                errors.append(error(
                    ruleID: "review-frame-folder.timing.generated-count",
                    description: "Review frame folder generated frame count matches manifest artifacts and timing samples",
                    at: path("frameTiming", "derivation", "generatedFrameCount")
                ))
            }
            if timing.samples.count != artifacts.count {
                errors.append(error(
                    ruleID: "review-frame-folder.timing.sample-count",
                    description: "Review frame folder generated frame count matches manifest artifacts and timing samples",
                    at: path("frameTiming", "samples")
                ))
            }
            return errors
        }
    }

    public static var frameArtifactsMatchTimingSamples:
        Validation<LottieReviewFrameFolder, LottieReviewFrameFolder>
    {
        Validation(
            ruleID: "review-frame-folder.frame-artifacts.match-timing",
            description: "Review frame folder frame artifacts match timing sample frame indexes source frames and seconds"
        ) { context in
            let artifacts = pngFrameArtifacts(in: context.subject.manifest)
            let samplesByIndex = samplesByIndex(in: context.subject.frameTiming)
            var errors: [ValidationError] = []
            for record in artifacts {
                let artifactPath = path("manifest", "artifacts").appending(.index(record.index))
                guard let frameIndex = record.artifact.frameIndex,
                      let sample = samplesByIndex[frameIndex]
                else {
                    errors.append(error(
                        ruleID: "review-frame-folder.frame-artifact.index",
                        description: "Review frame folder frame artifacts match timing sample frame indexes source frames and seconds",
                        at: artifactPath.appending(.key("frameIndex"))
                    ))
                    continue
                }
                if record.artifact.sourceFrame.map({ isClose($0, sample.sourceFrame) }) != true {
                    errors.append(error(
                        ruleID: "review-frame-folder.frame-artifact.source-frame",
                        description: "Review frame folder frame artifacts match timing sample frame indexes source frames and seconds",
                        at: artifactPath.appending(.key("sourceFrame"))
                    ))
                }
                if record.artifact.timeSeconds.map({ isClose($0, sample.timeSeconds) }) != true {
                    errors.append(error(
                        ruleID: "review-frame-folder.frame-artifact.time",
                        description: "Review frame folder frame artifacts match timing sample frame indexes source frames and seconds",
                        at: artifactPath.appending(.key("timeSeconds"))
                    ))
                }
            }
            return errors
        }
    }

    public static var frameArtifactPathsStayInsideFolder:
        Validation<LottieReviewFrameFolder, LottieReviewFrameFolder>
    {
        Validation(
            ruleID: "review-frame-folder.frame-paths.relative",
            description: "Review frame folder png artifact paths stay inside the reviewed folder"
        ) { context in
            pngFrameArtifacts(in: context.subject.manifest).compactMap { record in
                isFolderRelative(record.artifact.path)
                    ? nil
                    : error(
                        ruleID: "review-frame-folder.frame-path.relative",
                        description: "Review frame folder png artifact paths stay inside the reviewed folder",
                        at: path("manifest", "artifacts").appending(.index(record.index)).appending(.key("path"))
                    )
            }
        }
    }

    public static var expectedFrameFilesExistAndAreNonEmpty:
        Validation<LottieReviewFrameFolder, LottieReviewFrameFolder>
    {
        Validation(
            ruleID: "review-frame-folder.frame-files.present",
            description: "Review frame folder contains every expected png frame as a non-empty file"
        ) { context in
            let filesByPath = filesByPath(in: context.subject)
            var errors: [ValidationError] = []
            for record in pngFrameArtifacts(in: context.subject.manifest) {
                let artifactPath = path("manifest", "artifacts").appending(.index(record.index)).appending(.key("path"))
                guard let file = filesByPath[record.artifact.path] else {
                    errors.append(error(
                        ruleID: "review-frame-folder.frame-file.present",
                        description: "Review frame folder contains every expected png frame as a non-empty file",
                        at: artifactPath
                    ))
                    continue
                }
                if file.byteCount <= 0 {
                    errors.append(error(
                        ruleID: "review-frame-folder.frame-file.non-empty",
                        description: "Review frame folder contains every expected png frame as a non-empty file",
                        at: artifactPath
                    ))
                }
            }
            return errors
        }
    }

    public static var folderContainsNoUnexpectedPNGFrames:
        Validation<LottieReviewFrameFolder, LottieReviewFrameFolder>
    {
        Validation(
            ruleID: "review-frame-folder.frame-files.no-extra",
            description: "Review frame folder contains no unexpected png frame files"
        ) { context in
            let expectedPaths = Set(pngFrameArtifacts(in: context.subject.manifest).map(\.artifact.path))
            return context.subject.files.enumerated().compactMap { fileIndex, file in
                expectedPaths.contains(file.relativePath)
                    ? nil
                    : error(
                        ruleID: "review-frame-folder.frame-file.unexpected",
                        description: "Review frame folder contains no unexpected png frame files",
                        at: path("files").appending(.index(fileIndex)).appending(.key("relativePath"))
                    )
            }
        }
    }

    public static var oneFrameExportsRequireOneFrameSourceWindow:
        Validation<LottieReviewFrameFolder, LottieReviewFrameFolder>
    {
        Validation(
            ruleID: "review-frame-folder.one-frame.source-window",
            description: "Review frame folder one-frame exports are backed by a one-frame source window"
        ) { context in
            let artifacts = pngFrameArtifacts(in: context.subject.manifest)
            guard artifacts.count == 1 else { return [] }
            let sourceWindow = context.subject.frameTiming.source.outPoint - context.subject.frameTiming.source.inPoint
            guard sourceWindow <= 1.000_001 else {
                return [
                    error(
                        ruleID: "review-frame-folder.one-frame.source-window",
                        description: "Review frame folder one-frame exports are backed by a one-frame source window",
                        at: path("frameTiming", "source", "outPoint")
                    ),
                ]
            }
            return []
        }
    }

    private struct ArtifactRecord {
        var index: Int
        var artifact: LottieRenderedArtifactManifest.Artifact
    }

    private static func pngFrameArtifacts(in manifest: LottieRenderedArtifactManifest) -> [ArtifactRecord] {
        manifest.artifacts.enumerated().compactMap { index, artifact in
            artifact.kind == "png-frame" ? ArtifactRecord(index: index, artifact: artifact) : nil
        }
    }

    private static func samplesByIndex(
        in timing: LottieArtifactFrameTiming
    ) -> [Int: LottieArtifactFrameTiming.Sample] {
        var samples: [Int: LottieArtifactFrameTiming.Sample] = [:]
        for sample in timing.samples where samples[sample.index] == nil {
            samples[sample.index] = sample
        }
        return samples
    }

    private static func filesByPath(
        in folder: LottieReviewFrameFolder
    ) -> [String: LottieReviewFrameFolder.File] {
        var files: [String: LottieReviewFrameFolder.File] = [:]
        for file in folder.files where files[file.relativePath] == nil {
            files[file.relativePath] = file
        }
        return files
    }

    private static func prefixed(_ errors: [ValidationError], with component: JSONPath.Component) -> [ValidationError] {
        errors.map { validationError in
            ValidationError(
                ruleID: validationError.ruleID,
                reason: validationError.reason,
                at: JSONPath([component] + validationError.codingPath.components),
                range: validationError.range,
                severity: validationError.severity,
                phase: validationError.phase,
                classification: validationError.classification,
                evidence: validationError.evidence
            )
        }
    }

    private static func isFolderRelative(_ value: String) -> Bool {
        guard !value.hasPrefix("/") else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    private static func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs.isFinite && rhs.isFinite && abs(lhs - rhs) <= 0.000_001
    }

    private static func path(_ components: String...) -> JSONPath {
        JSONPath(components.map { .key($0) })
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

private struct LottieReviewFrameFolderAnyValidation {
    let ruleID: String
    let description: String
    private let applyClosure: (any Validatable, JSONPath, LottieReviewFrameFolder) -> [ValidationError]

    init<Subject: Validatable>(_ validation: Validation<LottieReviewFrameFolder, Subject>) {
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
        in document: LottieReviewFrameFolder
    ) -> [ValidationError] {
        applyClosure(subject, path, document)
    }
}

private struct ReviewSummary: Decodable {
    var frameTiming: LottieArtifactFrameTiming
}
