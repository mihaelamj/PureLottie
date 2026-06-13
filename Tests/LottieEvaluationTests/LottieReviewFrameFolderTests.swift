import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Review frame folder validation")
struct LottieReviewFrameFolderTests {
    @Test("valid review frame folder loads from disk and validates")
    func validReviewFrameFolderLoadsFromDiskAndValidates() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let timing = frameTiming(sourceFrames: [0, 5], outPoint: 10)
        let manifest = manifest(
            timing: timing,
            framePaths: ["frame_0000.00.png", "frame_0005.00.png"]
        )
        try writeReviewFolder(
            directory: directory,
            manifest: manifest,
            timing: timing,
            frameFiles: [
                "frame_0000.00.png": Data([0x89, 0x50, 0x4E, 0x47]),
                "frame_0005.00.png": Data([0x89, 0x50, 0x4E, 0x47]),
            ]
        )

        let folder = try LottieReviewFrameFolder.loadValidated(from: directory)

        #expect(folder.files.map(\.relativePath) == ["frame_0000.00.png", "frame_0005.00.png"])
        #expect(folder.manifest.export.generatedFrameCount == 2)
        #expect(folder.frameTiming.derivation.generatedFrameCount == 2)
    }

    @Test("review frame folder rejects missing expected frame files")
    func reviewFrameFolderRejectsMissingExpectedFrameFiles() {
        let folder = folder(
            frameFiles: [
                .init(relativePath: "frame_0000.00.png", byteCount: 4),
            ]
        )

        let errors = LottieReviewFrameFolderValidator()
            .collectErrors(in: folder)

        #expect(errors.contains {
            $0.ruleID == "review-frame-folder.frame-file.present" &&
                $0.codingPath.description == "$.manifest.artifacts[1].path"
        })
    }

    @Test("review frame folder rejects empty frame files")
    func reviewFrameFolderRejectsEmptyFrameFiles() {
        let folder = folder(
            frameFiles: [
                .init(relativePath: "frame_0000.00.png", byteCount: 4),
                .init(relativePath: "frame_0005.00.png", byteCount: 0),
            ]
        )

        let errors = LottieReviewFrameFolderValidator()
            .collectErrors(in: folder)

        #expect(errors.contains {
            $0.ruleID == "review-frame-folder.frame-file.non-empty" &&
                $0.codingPath.description == "$.manifest.artifacts[1].path"
        })
    }

    @Test("review frame folder rejects unexpected extra png files")
    func reviewFrameFolderRejectsUnexpectedExtraPNGFiles() {
        let folder = folder(
            frameFiles: [
                .init(relativePath: "frame_0000.00.png", byteCount: 4),
                .init(relativePath: "frame_0005.00.png", byteCount: 4),
                .init(relativePath: "frame_0099.00.png", byteCount: 4),
            ]
        )

        let errors = LottieReviewFrameFolderValidator()
            .collectErrors(in: folder)

        #expect(errors.contains {
            $0.ruleID == "review-frame-folder.frame-file.unexpected" &&
                $0.codingPath.description == "$.files[2].relativePath"
        })
    }

    @Test("review frame folder rejects manifest count drift from timing")
    func reviewFrameFolderRejectsManifestCountDriftFromTiming() {
        let timing = frameTiming(sourceFrames: [0, 5], outPoint: 10)
        var manifest = manifest(timing: timing, framePaths: ["frame_0000.00.png", "frame_0005.00.png"])
        manifest.export.generatedFrameCount = 1
        let folder = LottieReviewFrameFolder(
            rootPath: "/tmp/review",
            manifest: manifest,
            frameTiming: timing,
            files: [
                .init(relativePath: "frame_0000.00.png", byteCount: 4),
                .init(relativePath: "frame_0005.00.png", byteCount: 4),
            ]
        )

        let errors = LottieReviewFrameFolderValidator()
            .collectErrors(in: folder)

        #expect(errors.contains {
            $0.ruleID == "review-frame-folder.manifest.generated-count" &&
                $0.codingPath.description == "$.manifest.export.generatedFrameCount"
        })
    }

    @Test("review frame folder rejects frame artifact drift from timing samples")
    func reviewFrameFolderRejectsFrameArtifactDriftFromTimingSamples() {
        let timing = frameTiming(sourceFrames: [0, 5], outPoint: 10)
        var manifest = manifest(timing: timing, framePaths: ["frame_0000.00.png", "frame_0005.00.png"])
        manifest.artifacts[1].sourceFrame = 4
        let folder = LottieReviewFrameFolder(
            rootPath: "/tmp/review",
            manifest: manifest,
            frameTiming: timing,
            files: [
                .init(relativePath: "frame_0000.00.png", byteCount: 4),
                .init(relativePath: "frame_0005.00.png", byteCount: 4),
            ]
        )

        let errors = LottieReviewFrameFolderValidator()
            .collectErrors(in: folder)

        #expect(errors.contains {
            $0.ruleID == "review-frame-folder.frame-artifact.source-frame" &&
                $0.codingPath.description == "$.manifest.artifacts[1].sourceFrame"
        })
    }

    @Test("review frame folder reports invalid timing instead of trapping on duplicate sample indexes")
    func reviewFrameFolderReportsInvalidTimingInsteadOfTrappingOnDuplicateSampleIndexes() {
        var timing = frameTiming(sourceFrames: [0, 5], outPoint: 10)
        timing.samples[1].index = 0
        let folder = LottieReviewFrameFolder(
            rootPath: "/tmp/review",
            manifest: manifest(timing: timing, framePaths: ["frame_0000.00.png", "frame_0005.00.png"]),
            frameTiming: timing,
            files: [
                .init(relativePath: "frame_0000.00.png", byteCount: 4),
                .init(relativePath: "frame_0005.00.png", byteCount: 4),
            ]
        )

        let errors = LottieReviewFrameFolderValidator()
            .collectErrors(in: folder)

        #expect(errors.contains {
            $0.ruleID == "artifact-frame-timing.sample.index" &&
                $0.codingPath.description == "$.frameTiming.samples[1].index"
        })
    }

    @Test("review frame folder rejects one-frame placeholders for multi-frame source windows")
    func reviewFrameFolderRejectsOneFramePlaceholdersForMultiFrameSourceWindows() {
        let timing = frameTiming(sourceFrames: [0], outPoint: 10)
        let folder = LottieReviewFrameFolder(
            rootPath: "/tmp/review",
            manifest: manifest(timing: timing, framePaths: ["frame_0000.00.png"]),
            frameTiming: timing,
            files: [
                .init(relativePath: "frame_0000.00.png", byteCount: 4),
            ]
        )

        let errors = LottieReviewFrameFolderValidator()
            .collectErrors(in: folder)

        #expect(errors.contains {
            $0.ruleID == "review-frame-folder.one-frame.source-window" &&
                $0.codingPath.description == "$.frameTiming.source.outPoint"
        })
    }

    @Test("review frame folder accepts one generated frame only for one-frame source windows")
    func reviewFrameFolderAcceptsOneGeneratedFrameOnlyForOneFrameSourceWindows() throws {
        let timing = frameTiming(sourceFrames: [0], outPoint: 1)
        let folder = LottieReviewFrameFolder(
            rootPath: "/tmp/review",
            manifest: manifest(timing: timing, framePaths: ["frame_0000.00.png"]),
            frameTiming: timing,
            files: [
                .init(relativePath: "frame_0000.00.png", byteCount: 4),
            ]
        )

        try folder.validate()

        #expect(folder.manifest.export.generatedFrameCount == 1)
    }

    @Test("review frame folder validation set is composable and removable")
    func reviewFrameFolderValidationSetIsComposableAndRemovable() {
        let timing = frameTiming(sourceFrames: [0], outPoint: 10)
        let folder = LottieReviewFrameFolder(
            rootPath: "/tmp/review",
            manifest: manifest(timing: timing, framePaths: ["frame_0000.00.png"]),
            frameTiming: timing,
            files: [
                .init(relativePath: "frame_0000.00.png", byteCount: 4),
            ]
        )
        let description = LottieReviewFrameFolderBuiltinValidation
            .oneFrameExportsRequireOneFrameSourceWindow
            .description

        #expect(
            LottieReviewFrameFolderValidator()
                .collectErrors(in: folder)
                .contains { $0.ruleID == "review-frame-folder.one-frame.source-window" }
        )
        #expect(
            LottieReviewFrameFolderValidator()
                .withoutValidating(description)
                .collectErrors(in: folder)
                .contains { $0.ruleID == "review-frame-folder.one-frame.source-window" } == false
        )
        #expect(
            LottieReviewFrameFolderValidator.blank
                .validating(\.oneFrameExportsRequireOneFrameSourceWindow)
                .validationDescriptions == [description]
        )
    }

    @Test("review frame folder documents every default validation description")
    func reviewFrameFolderDocumentsEveryDefaultValidationDescription() throws {
        let documentation = try String(contentsOf: repositoryRoot()
            .appendingPathComponent("docs/lottie-format/rendered-artifact-manifest.md"))
        for description in LottieReviewFrameFolderValidator().validationDescriptions {
            #expect(documentation.contains(description), "Missing validation description: \(description)")
        }
    }

    private func folder(frameFiles: [LottieReviewFrameFolder.File]) -> LottieReviewFrameFolder {
        let timing = frameTiming(sourceFrames: [0, 5], outPoint: 10)
        return LottieReviewFrameFolder(
            rootPath: "/tmp/review",
            manifest: manifest(timing: timing, framePaths: ["frame_0000.00.png", "frame_0005.00.png"]),
            frameTiming: timing,
            files: frameFiles
        )
    }

    private func frameTiming(sourceFrames: [Double], outPoint: Double) -> LottieArtifactFrameTiming {
        LottieArtifactFrameTiming.explicitSourceFrameList(
            source: .init(frameRate: 10, inPoint: 0, outPoint: outPoint),
            sourceFrames: sourceFrames
        )
    }

    private func manifest(
        timing: LottieArtifactFrameTiming,
        framePaths: [String]
    ) -> LottieRenderedArtifactManifest {
        let artifacts = zip(timing.samples, framePaths).map { sample, framePath in
            LottieRenderedArtifactManifest.Artifact(
                kind: "png-frame",
                path: framePath,
                frameIndex: sample.index,
                sourceFrame: sample.sourceFrame,
                timeSeconds: sample.timeSeconds,
                evidenceLinks: [
                    .init(
                        kind: "lottie-web-intent",
                        path: "../lottie-web-intent.json",
                        frameIndex: sample.index,
                        sourceFrame: sample.sourceFrame,
                        timeSeconds: sample.timeSeconds,
                        rowAddress: "$.frames[\(sample.index)]",
                        note: "Browser source-intent row for this rendered source frame."
                    ),
                    .init(
                        kind: "geometry-json",
                        path: "purelayer-geometry.json",
                        frameIndex: sample.index,
                        sourceFrame: sample.sourceFrame,
                        timeSeconds: sample.timeSeconds,
                        rowAddress: "$.frames[\(sample.index)]",
                        note: "PureLayer geometry trace row for this rendered source frame."
                    ),
                ]
            )
        }
        return LottieRenderedArtifactManifest(
            schema: .init(name: "purelottie.rendered-artifact-manifest", version: 1),
            source: .init(
                fixtureID: "fixture",
                path: "Tests/Fixtures/LottieOracle/fixture.json",
                animationName: "Fixture",
                width: 100,
                height: 100,
                frameRate: timing.source.frameRate,
                inPoint: timing.source.inPoint,
                outPoint: timing.source.outPoint
            ),
            renderer: .init(
                name: "LottieFrameDump",
                backend: "PureLayer",
                version: "local",
                command: "swift run LottieFrameDump --input fixture --output frames --frames 0,5 --lottie-web-intent intent.json"
            ),
            export: .init(
                kind: "png-sequence",
                policy: timing.policy.rawValue,
                scale: 1,
                requestedFPS: timing.source.frameRate,
                generatedFrameCount: artifacts.count
            ),
            artifacts: artifacts,
            evidence: .init(references: [
                .init(
                    kind: "lottie-web-intent",
                    path: "../lottie-web-intent.json",
                    frameIndex: nil,
                    sourceFrame: nil,
                    note: "Measured browser source-intent rows for the exported source frames."
                ),
                .init(
                    kind: "geometry-json",
                    path: "purelayer-geometry.json",
                    frameIndex: nil,
                    sourceFrame: nil,
                    note: "PureLayer geometry trace rows for the exported frame set."
                ),
            ]),
            findings: []
        )
    }

    private func writeReviewFolder(
        directory: URL,
        manifest: LottieRenderedArtifactManifest,
        timing: LottieArtifactFrameTiming,
        frameFiles: [String: Data]
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest)
            .write(to: directory.appendingPathComponent("rendered-artifact-manifest.json"))
        try encoder.encode(Summary(frameTiming: timing))
            .write(to: directory.appendingPathComponent("oracle-summary.json"))
        for (path, data) in frameFiles {
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PureLottieReviewFrameFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct Summary: Encodable {
    var frameTiming: LottieArtifactFrameTiming
}
