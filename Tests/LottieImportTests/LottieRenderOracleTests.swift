import Foundation
import LottieEvaluation
import LottieImport
import LottieModel
import PureLayer
import Testing

/// Render oracle, first piece (issue #140): check the real engine's render of an
/// imported Lottie shape against what the #139-verified geometry predicts.
///
/// The render is produced by the real drawing engine (PureLayer's Compositor +
/// SoftwareBackend, the same path LottieFrameDump uses), not a reinvented
/// rasterizer. The reference is independent of the import: the source geometry is
/// already proven exact in #139, so its bounding box predicts where covered
/// pixels must be. Rendering the import and checking the covered-pixel bounding
/// box against that prediction catches import/lowering bugs that move, resize, or
/// drop a shape (the class #134 records) without depending on the pixel byte
/// order. It is the foundation the per-pixel comparison will build on.
///
/// Status: `sampled` (one curated shape, checked against the geometry prediction
/// with an anti-aliasing margin).
@Suite("Lottie render oracle")
struct LottieRenderOracleTests {
    @Test("imported ellipse fill renders covering the geometry-predicted bounding box")
    func ellipseFillCoversPredictedBox() throws {
        // Ellipse centred at (50,50), size 40x20 -> covers x in [30,70], y in [40,60].
        let json = """
        {"v":"5.7.4","fr":30,"ip":0,"op":30,"w":100,"h":100,"layers":[{"ty":4,"ind":1,"ip":0,"op":30,"ks":{},"shapes":[
          {"ty":"el","nm":"E","p":{"a":0,"k":[50,50]},"s":{"a":0,"k":[40,20]}},
          {"ty":"fl","nm":"F","c":{"a":0,"k":[1,0,0,1]},"o":{"a":0,"k":100}}
        ]}]}
        """
        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 0)
        let tree = LottieRenderIRLowerer().lower(frame)
        let root = LottieRenderSurface.root(tree.root, width: animation.width, height: animation.height, scale: 1)
        let size = LottieRenderSurface.pixelSize(width: animation.width, height: animation.height, scale: 1)

        let image = try SoftwareBackend().render(Compositor().drawList(for: root, at: 0), size: size)

        let bytesPerPixel = image.bitsPerPixel / 8
        func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
            let offset = y * image.bytesPerRow + x * bytesPerPixel
            return image.data[offset ..< offset + bytesPerPixel]
        }
        // The render background is the corner pixel; covered pixels differ from it.
        // This is byte-order agnostic: it only asks "is this pixel painted".
        let background = pixel(0, 0)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0 ..< image.height {
            for x in 0 ..< image.width where pixel(x, y) != background {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }

        #expect(maxX >= 0, "nothing was painted: the imported fill did not render")
        let margin = 2 // anti-aliased edge tolerance, in pixels
        #expect(abs(minX - 30) <= margin, "left edge \(minX) vs predicted 30")
        #expect(abs(maxX - 70) <= margin, "right edge \(maxX) vs predicted 70")
        #expect(abs(minY - 40) <= margin, "top edge \(minY) vs predicted 40")
        #expect(abs(maxY - 60) <= margin, "bottom edge \(maxY) vs predicted 60")
        // The shape is actually painted at its centre (not a hollow/edge artifact).
        #expect(pixel(50, 50) != background, "centre pixel is unpainted")
    }

    @Test("imported rectangle fill renders covering the geometry-predicted bounding box")
    func rectangleFillCoversPredictedBox() throws {
        // Rectangle centred at (40,60), size 60x30 -> covers x in [10,70], y in [45,75].
        let json = """
        {"v":"5.7.4","fr":30,"ip":0,"op":30,"w":100,"h":100,"layers":[{"ty":4,"ind":1,"ip":0,"op":30,"ks":{},"shapes":[
          {"ty":"rc","nm":"R","d":1,"p":{"a":0,"k":[40,60]},"s":{"a":0,"k":[60,30]},"r":{"a":0,"k":0}},
          {"ty":"fl","nm":"F","c":{"a":0,"k":[0,0,1,1]},"o":{"a":0,"k":100}}
        ]}]}
        """
        let box = try coveredBoundingBox(json)
        #expect(box.maxX >= 0, "nothing was painted: the imported fill did not render")
        let margin = 2
        #expect(abs(box.minX - 10) <= margin, "left edge \(box.minX) vs predicted 10")
        #expect(abs(box.maxX - 70) <= margin, "right edge \(box.maxX) vs predicted 70")
        #expect(abs(box.minY - 45) <= margin, "top edge \(box.minY) vs predicted 45")
        #expect(abs(box.maxY - 75) <= margin, "bottom edge \(box.maxY) vs predicted 75")
    }

    /// Render an imported single-layer Lottie through the real engine and return
    /// the bounding box of pixels that differ from the (background) corner pixel.
    private func coveredBoundingBox(_ json: String) throws -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 0)
        let tree = LottieRenderIRLowerer().lower(frame)
        let root = LottieRenderSurface.root(tree.root, width: animation.width, height: animation.height, scale: 1)
        let size = LottieRenderSurface.pixelSize(width: animation.width, height: animation.height, scale: 1)
        let image = try SoftwareBackend().render(Compositor().drawList(for: root, at: 0), size: size)
        let bytesPerPixel = image.bitsPerPixel / 8
        func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
            let offset = y * image.bytesPerRow + x * bytesPerPixel
            return image.data[offset ..< offset + bytesPerPixel]
        }
        let background = pixel(0, 0)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0 ..< image.height {
            for x in 0 ..< image.width where pixel(x, y) != background {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        return (minX, minY, maxX, maxY)
    }
}
