@testable import LottieImport
@testable import LottieModel
import PureLayer
import XCTest
#if canImport(AppKit)
    import AppKit
#endif

final class LottieImportTests: XCTestCase {
    func testSimpleImport() throws {
        let jsonString = """
        {
            "v": "5.7.1",
            "ip": 0,
            "op": 180,
            "fr": 60,
            "w": 512,
            "h": 512,
            "layers": [
                {
                    "ty": 4,
                    "nm": "ShapeLayer",
                    "ip": 0,
                    "op": 180,
                    "st": 0,
                    "ks": {
                        "a": { "a": 0, "k": [0, 0] },
                        "p": { "a": 0, "k": [100, 100] },
                        "s": { "a": 0, "k": [100, 100] },
                        "r": { "a": 0, "k": 0 },
                        "o": { "a": 0, "k": 100 }
                    },
                    "shapes": [
                        {
                            "ty": "gr",
                            "nm": "Group 1",
                            "it": [
                                {
                                    "ty": "rc",
                                    "nm": "Rectangle 1",
                                    "p": { "a": 0, "k": [0, 0] },
                                    "s": { "a": 0, "k": [50, 50] }
                                },
                                {
                                    "ty": "fl",
                                    "nm": "Fill 1",
                                    "c": { "a": 0, "k": [1, 0, 0] }
                                },
                                {
                                    "ty": "tr",
                                    "nm": "Transform 1",
                                    "p": { "a": 0, "k": [10, 20] }
                                }
                            ]
                        }
                    ]
                }
            ]
        }
        """
        guard let data = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert jsonString to data")
            return
        }
        let animation = try LottieAnimation.decode(from: data)
        let importer = LottieImporter()
        let scene = importer.scene(from: animation)

        XCTAssertNotNil(scene.root)
        XCTAssertEqual(scene.width, 512)
        XCTAssertEqual(scene.height, 512)
        XCTAssertEqual(scene.duration, 3.0) // 180 / 60
        XCTAssertTrue(scene.report.isClean)
    }

    func testNestedGroupTransforms() throws {
        let jsonString = """
        {
            "v": "5.7.1",
            "ip": 0,
            "op": 180,
            "fr": 60,
            "w": 512,
            "h": 512,
            "layers": [
                {
                    "ty": 4,
                    "nm": "ShapeLayer",
                    "ip": 0,
                    "op": 180,
                    "st": 0,
                    "ks": {
                        "a": { "a": 0, "k": [0, 0] },
                        "p": { "a": 0, "k": [0, 0] },
                        "s": { "a": 0, "k": [100, 100] },
                        "r": { "a": 0, "k": 0 },
                        "o": { "a": 0, "k": 100 }
                    },
                    "shapes": [
                        {
                            "ty": "gr",
                            "nm": "ParentGroup",
                            "it": [
                                {
                                    "ty": "gr",
                                    "nm": "ChildGroup",
                                    "it": [
                                        {
                                            "ty": "rc",
                                            "nm": "Rectangle",
                                            "p": { "a": 0, "k": [0, 0] },
                                            "s": { "a": 0, "k": [50, 50] }
                                        },
                                        {
                                            "ty": "fl",
                                            "nm": "Fill",
                                            "c": { "a": 0, "k": [1, 0, 0] }
                                        },
                                        {
                                            "ty": "tr",
                                            "nm": "ChildTransform",
                                            "p": { "a": 0, "k": [10, 20] }
                                        }
                                    ]
                                },
                                {
                                    "ty": "tr",
                                    "nm": "ParentTransform",
                                    "p": { "a": 0, "k": [100, 200] }
                                }
                            ]
                        }
                    ]
                }
            ]
        }
        """
        guard let data = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert jsonString to data")
            return
        }
        let animation = try LottieAnimation.decode(from: data)
        let importer = LottieImporter()
        let scene = importer.scene(from: animation)

        XCTAssertTrue(scene.report.isClean)

        func findShapeLayer(in layer: Layer) -> ShapeLayer? {
            if let shape = layer as? ShapeLayer { return shape }
            for sub in layer.sublayers {
                if let found = findShapeLayer(in: sub) { return found }
            }
            return nil
        }

        guard let shapeLayer = findShapeLayer(in: scene.root) else {
            XCTFail("Expected a ShapeLayer")
            return
        }

        guard let path = shapeLayer.path else {
            XCTFail("Expected path to not be nil")
            return
        }
        let bounds = path.boundingBox

        // If nested transforms accumulated correctly, position should be [110, 220],
        // so for rect of [50, 50] centered at 0, bounds should be:
        // x = 110 - 25 = 85
        // y = 220 - 25 = 195
        XCTAssertEqual(bounds.origin.x, 85.0, accuracy: 0.001)
        XCTAssertEqual(bounds.origin.y, 195.0, accuracy: 0.001)
        XCTAssertEqual(bounds.width, 50.0, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 50.0, accuracy: 0.001)
    }

    func testScaleAnimatedRotationStaticOrder() throws {
        let jsonString = """
        {
            "v": "5.7.1",
            "ip": 0,
            "op": 180,
            "fr": 60,
            "w": 512,
            "h": 512,
            "layers": [
                {
                    "ty": 4,
                    "nm": "ShapeLayer",
                    "ip": 0,
                    "op": 180,
                    "st": 0,
                    "ks": {
                        "a": { "a": 0, "k": [0, 0] },
                        "p": { "a": 0, "k": [100, 100] },
                        "s": {
                            "a": 1,
                            "k": [
                                {
                                    "t": 0,
                                    "s": [100, 100],
                                    "o": { "x": 0.333, "y": 0 },
                                    "i": { "x": 0.667, "y": 1 }
                                },
                                {
                                    "t": 180,
                                    "s": [200, 100]
                                }
                            ]
                        },
                        "r": { "a": 0, "k": 45 },
                        "o": { "a": 0, "k": 100 }
                    },
                    "shapes": []
                }
            ]
        }
        """
        guard let data = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert jsonString to data")
            return
        }
        let animation = try LottieAnimation.decode(from: data)
        let importer = LottieImporter()
        let scene = importer.scene(from: animation)

        // Find the imported shape layer.
        guard let layer = scene.root.sublayers.first else {
            XCTFail("Expected imported shape layer")
            return
        }

        // Under our fix, because scale is animated and rotation is static (45 deg),
        // rotation should be represented as a constant keyframe animation rather than baked,
        // so that resolvedTransform does not apply scale on top of a rotated basis.
        XCTAssertNotNil(layer.animation(forKey: "lottie.rotation"))
        XCTAssertEqual(layer.transform, Transform3D.identity)
    }

    func testExportFixturesToAPNG() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsDir = thisFile.deletingLastPathComponent()
        let examplesDir = testsDir.appendingPathComponent("Samples").path
        let outputDir = ProcessInfo.processInfo.environment["LOTTIE_TEST_MOVIES_DIR"] ?? FileManager.default.temporaryDirectory.path

        let fm = FileManager.default
        let fixtures = try fm.contentsOfDirectory(atPath: examplesDir).filter { $0.hasSuffix(".json") }

        for fixture in fixtures {
            let fixturePath = "\(examplesDir)/\(fixture)"
            let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
            let animation = try LottieAnimation.decode(from: data)
            let importer = LottieImporter()
            let scene = importer.scene(from: animation)

            print("--- Fixture: \(fixture) ---")
            print("Report: \(scene.report)")
            print("Duration: \(scene.duration)s, FPS: \(scene.frameRate)")

            /// Check if there are any animations in the imported scene tree
            func hasAnimations(_ layer: Layer) -> Bool {
                if !layer.animationKeys().isEmpty { return true }
                for sub in layer.sublayers {
                    if hasAnimations(sub) { return true }
                }
                return false
            }

            let animated = hasAnimations(scene.root)
            print("Has animations: \(animated)")

            let exporter = MovieExporter()
            let outputPath = "\(outputDir)/\(fixture.replacingOccurrences(of: ".json", with: ".png"))"
            let outputURL = URL(fileURLWithPath: outputPath)

            var width = Int(scene.width)
            var height = Int(scene.height)
            if width > 512 || height > 512 {
                let ratio = min(512.0 / Double(width), 512.0 / Double(height))
                width = Int(Double(width) * ratio)
                height = Int(Double(height) * ratio)
            }
            let size = PixelSize(width: width > 0 ? width : 512, height: height > 0 ? height : 512)

            if animated {
                let fps = 10.0
                let duration = min(scene.duration > 0 ? scene.duration : 1.0, 2.0)

                try exporter.writeAnimatedPNG(
                    of: scene.root,
                    size: size,
                    from: 0,
                    to: duration,
                    fps: fps,
                    to: outputURL
                )
                print("Successfully rendered animated fixture to \(outputPath)")
            } else {
                try exporter.writeScreenshot(
                    of: scene.root,
                    size: size,
                    at: 0.0,
                    to: outputURL
                )
                print("Successfully rendered static screenshot to \(outputPath)")
            }
        }
    }

    func testTransformActuallyAnimates() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsDir = thisFile.deletingLastPathComponent()
        let examplesDir = testsDir.appendingPathComponent("Samples").path
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(examplesDir)/TwitterHeart.json"))
        let animation = try LottieAnimation.decode(from: data)
        let importer = LottieImporter()
        let scene = importer.scene(from: animation)

        let root = scene.root
        let exporter = MovieExporter()
        let size = PixelSize(width: Int(scene.width), height: Int(scene.height))
        let frames = try exporter.frames(of: root, size: size, from: 0.0, to: 2.0, frameCount: 20)

        let outputDir = ProcessInfo.processInfo.environment["LOTTIE_TEST_FRAMES_DIR"] ?? (NSTemporaryDirectory() + "lottie_frames")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        for (i, _) in frames.enumerated() {
            let progress = Double(i) / 19.0
            let time = 2.0 * progress
            let path = "\(outputDir)/frame_\(i).png"
            if let pngData = try? exporter.screenshot(of: root, size: size, at: time) {
                try? Data(pngData).write(to: URL(fileURLWithPath: path))
            }
        }

        let allIdentical = frames.allSatisfy { $0.data == frames[0].data }
        XCTAssertFalse(allIdentical, "All frames are identical!")
    }

    func testDebugTimeline() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsDir = thisFile.deletingLastPathComponent()
        let examplesDir = testsDir.appendingPathComponent("Samples").path
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(examplesDir)/Watermelon.json"))
        let animation = try LottieAnimation.decode(from: data)
        let importer = LottieImporter()
        let scene = importer.scene(from: animation)

        func printTree(_ layer: Layer, prefix: String = "", at time: Double) {
            let pres = layer.presentation(at: time)
            let layerName = layer.name ?? "unnamed"
            print(
                "\(prefix)- Layer: \(layerName), type: \(type(of: layer)), pos: \(pres.position), transform: \(pres.transform), opacity: \(pres.opacity), animKeys: \(layer.animationKeys())"
            )
            for sub in layer.sublayers {
                printTree(sub, prefix: prefix + "  ", at: time)
            }
        }

        print("=== PRESENTATION AT T=0.0 ===")
        printTree(scene.root, at: 0.0)
        print("=== PRESENTATION AT T=0.5 ===")
        printTree(scene.root, at: 0.5)
        print("=== PRESENTATION AT T=1.0 ===")
        printTree(scene.root, at: 1.0)
        print("=== PRESENTATION AT T=1.5 ===")
        printTree(scene.root, at: 1.5)
        print("=== PRESENTATION AT T=2.0 ===")
        printTree(scene.root, at: 2.0)
        print("=== PRESENTATION AT T=5.0 ===")
        printTree(scene.root, at: 5.0)

        print("=== DRAW LIST AT T=5.0 ===")
        let list = Compositor().drawList(for: scene.root, at: 5.0)
        for cmd in list.commands {
            print("  \(cmd)")
        }
    }

    func testPureLayerPositioning() {
        let root = Layer()
        root.bounds = Rect(x: 0, y: 0, width: 200, height: 200)
        root.position = Point(x: 100, y: 100)

        let parent = Layer()
        parent.bounds = Rect(x: 0, y: 0, width: 100, height: 100)
        parent.position = Point(x: 150, y: 150) // offset inside root

        let child = Layer()
        child.bounds = Rect(x: 0, y: 0, width: 20, height: 20)
        child.position = Point(x: 50, y: 50) // centered in parent
        child.backgroundColor = Color(red: 1, green: 0, blue: 0, alpha: 1)

        parent.addSublayer(child)
        root.addSublayer(parent)

        let list = Compositor().drawList(for: root, at: 0)
        print("=== DRAW LIST COMMANDS ===")
        for cmd in list.commands {
            print(cmd)
        }
    }

    func testDumpWatermelonDetails() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsDir = thisFile.deletingLastPathComponent()
        let examplesDir = testsDir.appendingPathComponent("Samples").path
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(examplesDir)/Watermelon.json"))
        let animation = try LottieAnimation.decode(from: data)
        let importer = LottieImporter()
        let scene = importer.scene(from: animation)
        let exporter = MovieExporter()
        let size = PixelSize(width: Int(scene.width), height: Int(scene.height))

        for t in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0] {
            if let pngData = try? exporter.screenshot(of: scene.root, size: size, at: t) {
                let path = "/Users/mmj/.gemini/antigravity-cli/brain/bb4484fe-0766-4982-9bc6-80c9926fef2d/scratch/watermelon_frame_\(t).png"
                try? Data(pngData).write(to: URL(fileURLWithPath: path))

                var nonZero = 0
                #if canImport(AppKit)
                    if let rep = NSBitmapImageRep(data: Data(pngData)) {
                        for y in 0 ..< rep.pixelsHigh {
                            for x in 0 ..< rep.pixelsWide {
                                if rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.01 {
                                    nonZero += 1
                                }
                            }
                        }
                    }
                #endif
                print("T = \(t)s: size: \(pngData.count), non-zero alpha pixels: \(nonZero)")
            }
        }
    }
}
