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

    @Test("additive mask clips the box to the geometric intersection (PureLayer mask is correct)")
    func additiveMaskClipsToIntersection() throws {
        // Box rc p=[32,32] s=[40,30] -> x[12,52] y[17,47]. Mask "Left Half" verts
        // [[12,12],[34,12],[34,52],[12,52]] -> x[12,34] y[12,52]. Additive mask shows
        // the box where the mask is: box ∩ mask = x[12,34] y[17,47]. The render must
        // clip to that intersection, not the full box. (Verified: unmasked covers
        // 1200px, masked 660px = the 22x30 intersection. #134's mask item attributed
        // this to PureLayer in error; the geometry proves PureLayer renders it right.)
        let json = """
        {"v":"5.7.4","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"ind":1,"ip":0,"op":10,"ks":{},
          "masksProperties":[{"inv":false,"mode":"a","pt":{"a":0,"k":{"i":[[0,0],[0,0],[0,0],[0,0]],"o":[[0,0],[0,0],[0,0],[0,0]],"v":[[12,12],[34,12],[34,52],[12,52]],"c":true}},"o":{"a":0,"k":100}}],
          "shapes":[{"ty":"rc","p":{"a":0,"k":[32,32]},"s":{"a":0,"k":[40,30]},"r":{"a":0,"k":0}},{"ty":"fl","c":{"a":0,"k":[1,0,0,1]},"o":{"a":0,"k":100}}]}]}
        """
        let box = try coveredBoundingBox(json)
        #expect(box.maxX >= 0, "nothing painted")
        let margin = 2
        #expect(abs(box.minX - 12) <= margin, "left \(box.minX) vs intersection 12")
        #expect(abs(box.maxX - 34) <= margin, "right \(box.maxX) vs intersection 34 (clipped from box's 52)")
        #expect(abs(box.minY - 17) <= margin, "top \(box.minY) vs intersection 17")
        #expect(abs(box.maxY - 47) <= margin, "bottom \(box.maxY) vs intersection 47")
    }

    @Test("rounded rectangle renders at the rect bounding box (corners do not change the bbox)")
    func roundedRectangleCoversRectBounds() throws {
        // rc p=[32,32] s=[34,22] r=6 -> x[15,49] y[21,43]. Rounding cuts the corners
        // but does not change the bounding box. (#134 flagged a ~1.5% divergence vs
        // lottie-web; that is corner anti-aliasing, not a misplaced or wrong-size box.)
        let json = """
        {"v":"5.7.4","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"ind":1,"ip":0,"op":10,"ks":{},"shapes":[
          {"ty":"rc","p":{"a":0,"k":[32,32]},"s":{"a":0,"k":[34,22]},"r":{"a":0,"k":6}},
          {"ty":"fl","c":{"a":0,"k":[0,0.5,1,1]},"o":{"a":0,"k":100}}
        ]}]}
        """
        let box = try coveredBoundingBox(json)
        #expect(box.maxX >= 0, "nothing painted")
        let margin = 2
        #expect(abs(box.minX - 15) <= margin, "left \(box.minX) vs 15")
        #expect(abs(box.maxX - 49) <= margin, "right \(box.maxX) vs 49")
        #expect(abs(box.minY - 21) <= margin, "top \(box.minY) vs 21")
        #expect(abs(box.maxY - 43) <= margin, "bottom \(box.maxY) vs 43")
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
