import Foundation
import LottieEvaluation
import LottieModel
import Testing

@Suite("Rendered artifact manifest validation")
struct LottieRenderedArtifactManifestTests {
    @Test("near-miss valid rendered artifact manifest passes")
    func nearMissValidRenderedArtifactManifestPasses() throws {
        let manifest = try validManifest()

        try manifest.validate()

        #expect(manifest.schema.name == "purelottie.rendered-artifact-manifest")
        #expect(manifest.export.kind == "png-sequence")
        #expect(manifest.export.generatedFrameCount == 2)
        #expect(manifest.artifacts.map(\.path) == [
            "frames/frame_0000.00.png",
            "frames/frame_0005.00.png",
        ])
        #expect(manifest.evidence.references.contains { $0.kind == "lottie-web-intent" })
        #expect(manifest.evidence.references.contains { $0.kind == "geometry-json" })
    }

    @Test("rendered artifact manifest can be constructed through public API")
    func renderedArtifactManifestCanBeConstructedThroughPublicAPI() throws {
        let manifest = LottieRenderedArtifactManifest(
            schema: .init(name: "purelottie.rendered-artifact-manifest", version: 1),
            source: .init(
                fixtureID: "eligible-shape-position",
                path: "Tests/Fixtures/LottieOracle/eligible-shape-position.json",
                animationName: "Position",
                width: 100,
                height: 100,
                frameRate: 10,
                inPoint: 0,
                outPoint: 10
            ),
            renderer: .init(
                name: "LottieFrameDump",
                backend: "PureLayer",
                version: "local",
                command: "swift run LottieFrameDump --input fixture --output frames --frames 0,5"
            ),
            export: .init(
                kind: "png-sequence",
                policy: "explicit source-frame list",
                scale: 2,
                requestedFPS: 10,
                generatedFrameCount: 1
            ),
            artifacts: [
                .init(
                    kind: "png-frame",
                    path: "frames/frame_0000000.00.png",
                    frameIndex: 0,
                    sourceFrame: 0,
                    timeSeconds: 0,
                    evidenceLinks: [
                        .init(
                            kind: "lottie-web-intent",
                            path: "Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json",
                            frameIndex: 0,
                            sourceFrame: 0,
                            timeSeconds: 0,
                            rowAddress: "$.frames[0]",
                            note: "Browser source-intent row for the rendered source frame."
                        ),
                        .init(
                            kind: "geometry-json",
                            path: "frames/purelayer-geometry.json",
                            frameIndex: 0,
                            sourceFrame: 0,
                            timeSeconds: 0,
                            rowAddress: "$.frames[0]",
                            note: "PureLayer geometry trace row for the rendered source frame."
                        ),
                    ]
                ),
            ],
            evidence: .init(references: [
                .init(
                    kind: "lottie-web-intent",
                    path: "Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json",
                    frameIndex: 0,
                    sourceFrame: 0,
                    note: "Measured browser source intent for the exported source frame."
                ),
                .init(
                    kind: "geometry-json",
                    path: "frames/purelayer-geometry.json",
                    frameIndex: 0,
                    sourceFrame: 0,
                    note: "PureLayer geometry trace for the exported frame set."
                ),
            ]),
            findings: []
        )

        try manifest.validate()

        #expect(manifest.artifacts.count == 1)
        #expect(manifest.findings.isEmpty)
    }

    @Test("invalid rendered artifact manifest reports exact JSON paths")
    func invalidRenderedArtifactManifestReportsExactJSONPaths() throws {
        var manifest = try validManifest()
        manifest.schema.version = 2
        manifest.source.path = ""
        manifest.source.frameRate = 0
        manifest.source.outPoint = manifest.source.inPoint
        manifest.renderer.name = ""
        manifest.export.kind = "gif"
        manifest.export.generatedFrameCount = 0
        manifest.artifacts[0].path = ""
        manifest.artifacts[0].sourceFrame = nil
        manifest.artifacts[0].evidenceLinks?[0].path = ""
        manifest.artifacts[0].evidenceLinks?[0].rowAddress = "frames[0]"
        manifest.artifacts[0].evidenceLinks?[0].sourceFrame = 9
        manifest.artifacts[1].evidenceLinks = []
        manifest.evidence.references[0].path = ""
        manifest.evidence.references[0].note = "short"
        manifest.evidence.references.removeLast()
        manifest.findings[0].phase = "guess"
        manifest.findings[0].path = ""

        let paths = Set(LottieRenderedArtifactManifestValidator()
            .collectErrors(in: manifest)
            .map(\.codingPath.description))

        #expect(paths.contains("$.schema.version"))
        #expect(paths.contains("$.source.path"))
        #expect(paths.contains("$.source.frameRate"))
        #expect(paths.contains("$.source.outPoint"))
        #expect(paths.contains("$.renderer.name"))
        #expect(paths.contains("$.export.kind"))
        #expect(paths.contains("$.export.generatedFrameCount"))
        #expect(paths.contains("$.artifacts[0].path"))
        #expect(paths.contains("$.artifacts[0].sourceFrame"))
        #expect(paths.contains("$.artifacts[0].evidenceLinks[0].path"))
        #expect(paths.contains("$.artifacts[0].evidenceLinks[0].rowAddress"))
        #expect(paths.contains("$.artifacts[0].evidenceLinks[0].sourceFrame"))
        #expect(paths.contains("$.artifacts[1].evidenceLinks"))
        #expect(paths.contains("$.evidence.references[0].path"))
        #expect(paths.contains("$.evidence.references[0].note"))
        #expect(paths.contains("$.evidence.references"))
        #expect(paths.contains("$.findings[0].phase"))
        #expect(paths.contains("$.findings[0].path"))
    }

    @Test("missing rendered artifact manifest keys decode as validation errors with paths")
    func missingRenderedArtifactManifestKeysDecodeAsValidationErrorsWithPaths() throws {
        let source = """
        {
          "schema": { "name": "purelottie.rendered-artifact-manifest", "version": 1 },
          "source": {
            "fixtureID": "eligible-shape-position",
            "path": "Tests/Fixtures/LottieOracle/eligible-shape-position.json",
            "width": 100,
            "height": 100,
            "frameRate": 10,
            "inPoint": 0,
            "outPoint": 10
          }
        }
        """

        do {
            _ = try LottieRenderedArtifactManifest.decodeValidated(from: Data(source.utf8))
            Issue.record("Expected missing renderer key to fail validated decode.")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].ruleID == "rendered-artifact-manifest.decode.key-not-found")
            #expect(errors.values[0].codingPath.description == "$.renderer")
        } catch {
            Issue.record("Expected ValidationErrorCollection, got \(error).")
        }
    }

    @Test("rendered artifact manifest links each frame to source intent and geometry")
    func renderedArtifactManifestLinksEachFrameToSourceIntentAndGeometry() throws {
        let manifest = try validManifest()

        let firstFrameLinks = try #require(manifest.artifacts[0].evidenceLinks)

        #expect(firstFrameLinks.map(\.kind) == ["lottie-web-intent", "geometry-json"])
        #expect(firstFrameLinks.allSatisfy { $0.sourceFrame == manifest.artifacts[0].sourceFrame })
        #expect(firstFrameLinks.allSatisfy { $0.timeSeconds == manifest.artifacts[0].timeSeconds })
        #expect(firstFrameLinks.allSatisfy { $0.rowAddress?.hasPrefix("$.frames") == true })
    }

    @Test("rendered artifact manifest rejects missing frame evidence chain")
    func renderedArtifactManifestRejectsMissingFrameEvidenceChain() throws {
        var manifest = try validManifest()
        manifest.artifacts[0].evidenceLinks = [
            .init(
                kind: "import-report",
                path: "reports/import.tsv",
                frameIndex: 0,
                sourceFrame: 0,
                timeSeconds: 0,
                rowAddress: nil,
                note: "Import report alone is not enough evidence for a rendered frame."
            ),
        ]

        let paths = Set(LottieRenderedArtifactManifestValidator()
            .collectErrors(in: manifest)
            .map(\.codingPath.description))

        #expect(paths.contains("$.artifacts[0].evidenceLinks"))
        #expect(paths.contains("$.artifacts[0].evidenceLinks[0].path"))
    }

    @Test("rendered artifact manifest rejects wrong-kind evidence reference for linked path")
    func renderedArtifactManifestRejectsWrongKindEvidenceReferenceForLinkedPath() throws {
        var manifest = try validManifest()
        manifest.evidence.references[0].kind = "oracle-summary"

        let errors = LottieRenderedArtifactManifestValidator()
            .collectErrors(in: manifest)

        #expect(errors.contains {
            $0.ruleID == "rendered-artifact-manifest.artifact-evidence.reference" &&
                $0.codingPath.description == "$.artifacts[0].evidenceLinks[0].path"
        })
    }

    @Test("rendered artifact manifest rejects generated frame count drift")
    func renderedArtifactManifestRejectsGeneratedFrameCountDrift() throws {
        var manifest = try validManifest()
        manifest.export.generatedFrameCount = 1

        let errors = LottieRenderedArtifactManifestValidator()
            .collectErrors(in: manifest)

        #expect(errors.contains {
            $0.ruleID == "rendered-artifact-manifest.export.frame-count" &&
                $0.codingPath.description == "$.export.generatedFrameCount"
        })
    }

    @Test("rendered artifact manifest rejects malformed evidence row address")
    func renderedArtifactManifestRejectsMalformedEvidenceRowAddress() throws {
        var manifest = try validManifest()
        manifest.artifacts[0].evidenceLinks?[0].rowAddress = "$.frames[x]"

        let errors = LottieRenderedArtifactManifestValidator()
            .collectErrors(in: manifest)

        #expect(errors.contains {
            $0.ruleID == "rendered-artifact-manifest.artifact-evidence.path-bearing" &&
                $0.codingPath.description == "$.artifacts[0].evidenceLinks[0].rowAddress"
        })
    }

    @Test("default rendered artifact manifest validation set is composable and removable")
    func defaultRenderedArtifactManifestValidationSetIsComposableAndRemovable() throws {
        var manifest = try validManifest()
        manifest.schema.version = 2
        let schemaDescription = LottieRenderedArtifactManifestBuiltinValidation
            .schemaNameAndVersionAreSupported
            .description

        #expect(
            LottieRenderedArtifactManifestValidator()
                .collectErrors(in: manifest)
                .contains { $0.codingPath.description == "$.schema.version" }
        )
        #expect(
            LottieRenderedArtifactManifestValidator()
                .withoutValidating(schemaDescription)
                .collectErrors(in: manifest)
                .contains { $0.codingPath.description == "$.schema.version" } == false
        )
        #expect(
            LottieRenderedArtifactManifestValidator.blank
                .validating(\.schemaNameAndVersionAreSupported)
                .validationDescriptions == [schemaDescription]
        )
    }

    @Test("rendered artifact manifest documents every default validation description")
    func renderedArtifactManifestDocumentsEveryDefaultValidationDescription() throws {
        let documentation = try String(contentsOf: repositoryRoot()
            .appendingPathComponent("docs/lottie-format/rendered-artifact-manifest.md"))
        for description in LottieRenderedArtifactManifestValidator().validationDescriptions {
            #expect(documentation.contains(description), "Missing validation description: \(description)")
        }
    }

    private func validManifest() throws -> LottieRenderedArtifactManifest {
        try LottieRenderedArtifactManifest.decodeValidated(from: Data(validManifestJSON.utf8))
    }

    private var validManifestJSON: String {
        """
        {
          "schema": {
            "name": "purelottie.rendered-artifact-manifest",
            "version": 1
          },
          "source": {
            "fixtureID": "eligible-shape-position",
            "path": "Tests/Fixtures/LottieOracle/eligible-shape-position.json",
            "animationName": "Position",
            "width": 100,
            "height": 100,
            "frameRate": 10,
            "inPoint": 0,
            "outPoint": 10
          },
          "renderer": {
            "name": "LottieFrameDump",
            "backend": "PureLayer",
            "version": "local",
            "command": "swift run LottieFrameDump --input fixture --output frames --frames 0,5"
          },
          "export": {
            "kind": "png-sequence",
            "policy": "explicit source-frame list",
            "scale": 2,
            "requestedFPS": 10,
            "generatedFrameCount": 2
          },
          "artifacts": [
            {
              "kind": "png-frame",
              "path": "frames/frame_0000.00.png",
              "frameIndex": 0,
              "sourceFrame": 0,
              "timeSeconds": 0,
              "evidenceLinks": [
                {
                  "kind": "lottie-web-intent",
                  "path": "Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json",
                  "frameIndex": 0,
                  "sourceFrame": 0,
                  "timeSeconds": 0,
                  "rowAddress": "$.frames[0]",
                  "note": "Browser source-intent row for the rendered source frame."
                },
                {
                  "kind": "geometry-json",
                  "path": "frames/purelayer-geometry.json",
                  "frameIndex": 0,
                  "sourceFrame": 0,
                  "timeSeconds": 0,
                  "rowAddress": "$.frames[0]",
                  "note": "PureLayer geometry trace row for the rendered source frame."
                }
              ]
            },
            {
              "kind": "png-frame",
              "path": "frames/frame_0005.00.png",
              "frameIndex": 1,
              "sourceFrame": 5,
              "timeSeconds": 0.5,
              "evidenceLinks": [
                {
                  "kind": "lottie-web-intent",
                  "path": "Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json",
                  "frameIndex": 1,
                  "sourceFrame": 5,
                  "timeSeconds": 0.5,
                  "rowAddress": "$.frames[1]",
                  "note": "Browser source-intent row for the rendered source frame."
                },
                {
                  "kind": "geometry-json",
                  "path": "frames/purelayer-geometry.json",
                  "frameIndex": 1,
                  "sourceFrame": 5,
                  "timeSeconds": 0.5,
                  "rowAddress": "$.frames[1]",
                  "note": "PureLayer geometry trace row for the rendered source frame."
                }
              ]
            }
          ],
          "evidence": {
            "references": [
              {
                "kind": "lottie-web-intent",
                "path": "Tests/Fixtures/LottieOracle/lottie-web-intent/eligible-shape-position.json",
                "frameIndex": 0,
                "sourceFrame": 0,
                "note": "Measured browser source intent for the exported source frame."
              },
              {
                "kind": "geometry-json",
                "path": "frames/purelayer-geometry.json",
                "frameIndex": 0,
                "sourceFrame": 0,
                "note": "PureLayer geometry trace for the exported frame set."
              }
            ]
          },
          "findings": [
            {
              "phase": "validation",
              "ruleID": "lottie.root.frame-window",
              "path": "$.op",
              "sourcePath": "composition",
              "reason": "Synthetic near-miss finding keeps path-bearing validation exercised.",
              "severity": "note"
            }
          ]
        }
        """
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
