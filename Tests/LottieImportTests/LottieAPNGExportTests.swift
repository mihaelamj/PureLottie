import Foundation
import LottieImport
import PureLayer
import Testing

@Suite("Lottie APNG export")
struct LottieAPNGExportTests {
    @Test("validated Lottie imports export through PureLayer as animated PNG")
    func validatedLottieImportsExportThroughPureLayerAsAnimatedPNG() throws {
        let data = try Data(contentsOf: fixture("eligible-shape-position.json"))
        let scene = try LottieImporter().scene(from: data)
        #expect(scene.report.isClean)

        let apng = try MovieExporter().animatedPNG(
            of: scene.root,
            size: PixelSize(width: 128, height: 128),
            from: 0,
            to: 1,
            fps: 12
        )

        #expect(Array(apng.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        let chunkTypes = chunkTypes(apng)
        #expect(chunkTypes.contains("acTL"))
        #expect(chunkTypes.contains("fdAT"))
        #expect(chunkTypes.filter { $0 == "fcTL" }.count == 13)
        #expect(animationControlFrameCount(apng) == 13)
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LottieOracle", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func chunkTypes(_ bytes: [UInt8]) -> [String] {
        var types: [String] = []
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(readUInt32(bytes, at: offset))
            guard offset + 12 + length <= bytes.count else { break }
            let typeBytes = bytes[(offset + 4) ..< (offset + 8)]
            if let type = String(bytes: typeBytes, encoding: .ascii) {
                types.append(type)
            }
            offset += 12 + length
        }
        return types
    }

    private func animationControlFrameCount(_ bytes: [UInt8]) -> Int? {
        var offset = 8
        while offset + 20 <= bytes.count {
            let length = Int(readUInt32(bytes, at: offset))
            guard offset + 12 + length <= bytes.count else { break }
            let typeBytes = bytes[(offset + 4) ..< (offset + 8)]
            guard String(bytes: typeBytes, encoding: .ascii) == "acTL" else {
                offset += 12 + length
                continue
            }
            guard length >= 4 else { return nil }
            return Int(readUInt32(bytes, at: offset + 8))
        }
        return nil
    }

    private func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 |
            UInt32(bytes[offset + 1]) << 16 |
            UInt32(bytes[offset + 2]) << 8 |
            UInt32(bytes[offset + 3])
    }
}
