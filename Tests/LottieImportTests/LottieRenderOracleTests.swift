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
/// order. The per-pixel analytic coverage oracle further down builds on it.
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
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
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

    @Test("split-position ellipse renders the full shape (PureLayer#160 masksToBounds fix verified)")
    func splitPositionEllipseRendersFullShape() throws {
        // Ellipse shape p=[0,0] s=[16,16] under a split layer position (x animated, frame-0
        // value 18; y static 32). The shape sits at its local origin and the layer transform
        // places it; full ellipse centred at (18,32), radius 8 -> x[10,26] y[24,40], entirely
        // inside the 64x64 canvas. Before the PureLayer#160 fix the canvas masksToBounds clip
        // was offset by the layer translation and ate the negative-local half, rendering only
        // the +x,+y quadrant (~x[18,25] y[32,39]). This asserts the full shape now renders.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/LottieOracle/split-position-ellipse.json")
        let json = try String(contentsOf: url, encoding: .utf8)
        let box = try coveredBoundingBox(json)
        #expect(box.maxX >= 0, "nothing painted")
        let margin = 2
        #expect(abs(box.minX - 10) <= margin, "left \(box.minX) vs 10 (was clipped to 18)")
        #expect(abs(box.maxX - 26) <= margin, "right \(box.maxX) vs 26")
        #expect(abs(box.minY - 24) <= margin, "top \(box.minY) vs 24 (was clipped to 32)")
        #expect(abs(box.maxY - 40) <= margin, "bottom \(box.maxY) vs 40")
    }

    @Test("raw cubic-bezier stroke renders along the curve, not the chord (#134 final item)")
    func rawCubicBezierStrokeFollowsCurve() throws {
        // raw-bezier-cubic.json: one open cubic, width-4 round-cap/join stroke, no layer
        // offset. Control points from the fixture's v/i/o:
        //   P0 = v0           = (12,50)
        //   P1 = v0 + o0      = (30,22)
        //   P2 = v1 + i1      = (34,42)
        //   P3 = v1           = (52,14)
        // X is monotone (12<30<34<52) and Y'(t)=0 -> 24t^2-24t+7=0 has discriminant -96
        // (no real roots), so Y is monotone too: the curve bbox equals the vertex bbox
        // [12,52]x[14,50]. A round stroke is the curve dilated by the half-width (2), so the
        // painted bbox is [10,54]x[12,52]. Decisively: sampled curve points are painted, and
        // at t=0.25 the curve sits at ~(23.3,36.5), ~3.3px off the straight chord, so a
        // chord render (ignoring the tangents) would leave that point unpainted.
        func cubic(_ t: Double) -> (Double, Double) {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return (
                a * 12 + b * 30 + c * 34 + d * 52,
                a * 50 + b * 22 + c * 42 + d * 14
            )
        }
        let image = try renderFixtureImage("raw-bezier-cubic.json")
        let bytesPerPixel = image.bitsPerPixel / 8
        func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
            let offset = y * image.bytesPerRow + x * bytesPerPixel
            return image.data[offset ..< offset + bytesPerPixel]
        }
        let background = pixel(0, 0)
        func painted(_ x: Int, _ y: Int) -> Bool {
            pixel(x, y) != background
        }

        // Every sampled point on the cubic is under the stroke (width 4, so the centreline
        // is painted). A straight-chord render fails the off-chord samples around t=0.25.
        for i in 0 ... 10 {
            let (px, py) = cubic(Double(i) / 10)
            let x = Int(px.rounded()), y = Int(py.rounded())
            #expect(painted(x, y), "curve point t=\(Double(i) / 10) (\(x),\(y)) is not painted")
        }
        // The off-chord bulge specifically (a chord stroke would not reach this pixel).
        #expect(painted(23, 36), "off-chord curve point (23,36) must be painted (proves cubic, not chord)")

        // Painted bbox = curve bbox dilated by the stroke half-width (round cap/join).
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0 ..< image.height {
            for x in 0 ..< image.width where painted(x, y) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        let margin = 2
        #expect(abs(minX - 10) <= margin, "left \(minX) vs 10")
        #expect(abs(maxX - 54) <= margin, "right \(maxX) vs 54")
        #expect(abs(minY - 12) <= margin, "top \(minY) vs 12")
        #expect(abs(maxY - 52) <= margin, "bottom \(maxY) vs 52")
    }

    @Test("shape multiply blend renders the exact closed form magenta x yellow = red (#178)")
    func shapeMultiplyBlendModeRendersExactValue() throws {
        // Foreground magenta (1,0,1), fill bm=1 (multiply), drawn on top of background
        // yellow (1,1,0); the rects overlap at (32,32). The separable multiply of opaque
        // colours is componentwise: (1,0,1) x (1,1,0) = (1,0,0) = red, fully opaque. That
        // closed form is the independent reference. To avoid assuming a pixel byte order,
        // the references are themselves rendered as solid fills of the predicted colours
        // and compared as whole pixels:
        //   - extended-compositor overlap MUST equal a solid red fill (the multiply result);
        //   - standard-compositor overlap MUST equal a solid magenta fill (plain source-over).
        // "it differs from standard" is not enough; the value must be the one the math gives.
        let overlap = """
        {"v":"5.7.4","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"ind":1,"ip":0,"op":10,"ks":{},"shapes":[
          {"ty":"gr","it":[
            {"ty":"rc","p":{"a":0,"k":[38,32]},"s":{"a":0,"k":[28,28]},"r":{"a":0,"k":0}},
            {"ty":"fl","c":{"a":0,"k":[1,0,1,1]},"o":{"a":0,"k":100},"bm":1},
            {"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
          ]},
          {"ty":"gr","it":[
            {"ty":"rc","p":{"a":0,"k":[26,32]},"s":{"a":0,"k":[28,28]},"r":{"a":0,"k":0}},
            {"ty":"fl","c":{"a":0,"k":[1,1,0,1]},"o":{"a":0,"k":100}},
            {"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
          ]}
        ]}]}
        """
        func solidFill(_ r: Double, _ g: Double, _ b: Double) -> String {
            """
            {"v":"5.7.4","fr":10,"ip":0,"op":10,"w":64,"h":64,"layers":[{"ty":4,"ind":1,"ip":0,"op":10,"ks":{},"shapes":[
              {"ty":"rc","p":{"a":0,"k":[32,32]},"s":{"a":0,"k":[40,40]},"r":{"a":0,"k":0}},
              {"ty":"fl","c":{"a":0,"k":[\(r),\(g),\(b),1]},"o":{"a":0,"k":100}}
            ]}]}
            """
        }
        func centre(_ image: Image) -> [UInt8] {
            let bpp = image.bitsPerPixel / 8
            let offset = 32 * image.bytesPerRow + 32 * bpp
            return Array(image.data[offset ..< offset + bpp])
        }
        let stdOverlap = try centre(renderImage(overlap, extended: false))
        let extOverlap = try centre(renderImage(overlap, extended: true))
        let red = try centre(renderImage(solidFill(1, 0, 0)))
        let magenta = try centre(renderImage(solidFill(1, 0, 1)))
        let yellow = try centre(renderImage(solidFill(1, 1, 0)))

        // Guard against a degenerate check: the three reference colours must be distinct.
        #expect(red != magenta && red != yellow && magenta != yellow, "reference colours collapsed: \(red) \(magenta) \(yellow)")
        // Closed-form value checks.
        #expect(extOverlap == red, "multiply overlap must equal magenta x yellow = red; got \(extOverlap) vs red \(red)")
        #expect(stdOverlap == magenta, "standard source-over overlap must equal magenta; got \(stdOverlap) vs magenta \(magenta)")
    }

    // MARK: - Per-pixel analytic coverage oracle (#140)

    // The bounding-box checks above catch a moved/resized/dropped shape but say
    // nothing about the interior. These check coverage per pixel against an
    // independent analytic reference (point-in-shape from the #139-exact geometry),
    // not the renderer and not a browser: every pixel whose centre is strictly
    // inside the shape (by more than the 1px anti-aliasing band) must be painted,
    // and every pixel strictly outside must be background. The boundary band is
    // excluded because anti-aliasing legitimately makes it partial.

    @Test("filled rectangle: every interior pixel painted, every exterior pixel background (#140)")
    func rectanglePerPixelCoverageMatchesAnalyticReference() throws {
        // rc p=[40,60] s=[60,30] -> x[10,70] y[45,75].
        let json = """
        {"v":"5.7.4","fr":30,"ip":0,"op":30,"w":100,"h":100,"layers":[{"ty":4,"ind":1,"ip":0,"op":30,"ks":{},"shapes":[
          {"ty":"rc","p":{"a":0,"k":[40,60]},"s":{"a":0,"k":[60,30]},"r":{"a":0,"k":0}},
          {"ty":"fl","c":{"a":0,"k":[0,0,1,1]},"o":{"a":0,"k":100}}
        ]}]}
        """
        let image = try renderImage(json)
        let painted = paintedMask(image)
        let (a, b, c, d) = (10.0, 70.0, 45.0, 75.0) // x[a,b] y[c,d]
        var interior = 0, exterior = 0
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let fx = Double(x) + 0.5, fy = Double(y) + 0.5
                let insideBy = min(fx - a, b - fx, fy - c, d - fy) // >0 inside, <0 outside
                if insideBy > 1 {
                    interior += 1
                    #expect(painted(x, y), "interior pixel (\(x),\(y)) is not painted")
                } else if insideBy < -1 {
                    exterior += 1
                    #expect(!painted(x, y), "exterior pixel (\(x),\(y)) is painted")
                }
            }
        }
        #expect(interior > 500 && exterior > 500, "coverage check was near-vacuous: interior=\(interior) exterior=\(exterior)")
    }

    @Test("filled ellipse: every interior pixel painted, every exterior pixel background (#140)")
    func ellipsePerPixelCoverageMatchesAnalyticReference() throws {
        // el p=[50,50] s=[40,20] -> centre (50,50), rx=20, ry=10.
        let json = """
        {"v":"5.7.4","fr":30,"ip":0,"op":30,"w":100,"h":100,"layers":[{"ty":4,"ind":1,"ip":0,"op":30,"ks":{},"shapes":[
          {"ty":"el","p":{"a":0,"k":[50,50]},"s":{"a":0,"k":[40,20]}},
          {"ty":"fl","c":{"a":0,"k":[1,0,0,1]},"o":{"a":0,"k":100}}
        ]}]}
        """
        let image = try renderImage(json)
        let painted = paintedMask(image)
        let (cx, cy, rx, ry) = (50.0, 50.0, 20.0, 10.0)
        func norm(_ fx: Double, _ fy: Double, _ rrx: Double, _ rry: Double) -> Double {
            let dx = (fx - cx) / rrx, dy = (fy - cy) / rry
            return dx * dx + dy * dy
        }
        var interior = 0, exterior = 0
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let fx = Double(x) + 0.5, fy = Double(y) + 0.5
                if norm(fx, fy, rx - 1, ry - 1) < 1 { // inside even with radii shrunk by 1px
                    interior += 1
                    #expect(painted(x, y), "interior pixel (\(x),\(y)) is not painted")
                } else if norm(fx, fy, rx + 1, ry + 1) > 1 { // outside even with radii grown by 1px
                    exterior += 1
                    #expect(!painted(x, y), "exterior pixel (\(x),\(y)) is painted")
                }
            }
        }
        #expect(interior > 200 && exterior > 500, "coverage check was near-vacuous: interior=\(interior) exterior=\(exterior)")
    }

    @Test("filled polygon and star: per-pixel coverage matches closed-form point-in-polygon (#140)")
    func polystarPerPixelCoverageMatchesClosedForm() throws {
        // Closed-form polystar vertices, the same form proven exact in #139
        // (LottiePolystarExactnessTests): vertex i at angle -pi/2 + rot + (2pi/count)*i,
        // radius `or` (polygon) or alternating `or`/`ir` (star, count = pt*2), about the
        // centre. #139 proves these vertices; this proves the fill covers exactly the
        // polygon they span. The edges are straight (no rounding), so point-in-polygon is
        // the exact interior. A 1.5px band around every edge is excluded for anti-aliasing.
        func vertices(count: Int, rotationDeg: Double, radius: (Int) -> Double) -> [(Double, Double)] {
            let step = 2 * Double.pi / Double(count)
            return (0 ..< count).map { i in
                let angle = -Double.pi / 2 + rotationDeg * Double.pi / 180 + step * Double(i)
                return (32 + radius(i) * cos(angle), 32 + radius(i) * sin(angle))
            }
        }
        // polygon-five.json: pt=5, or=18, r=18. star-five.json: pt=5 -> 10 verts, or=20, ir=8, r=-18.
        let pentagon = vertices(count: 5, rotationDeg: 18) { _ in 18 }
        let star = vertices(count: 10, rotationDeg: -18) { $0.isMultiple(of: 2) ? 20 : 8 }
        try assertPolygonCoverage(fixture: "polygon-five.json", polygon: pentagon)
        try assertPolygonCoverage(fixture: "star-five.json", polygon: star)
    }

    /// Render a polystar fixture and assert, per pixel, that the fill covers exactly the
    /// interior of `polygon`: every pixel centre strictly inside (more than 1.5px from any
    /// edge) is painted, every pixel strictly outside is background.
    private func assertPolygonCoverage(fixture: String, polygon: [(Double, Double)]) throws {
        let image = try renderFixtureImage(fixture)
        let painted = paintedMask(image)
        var interior = 0, exterior = 0
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let fx = Double(x) + 0.5, fy = Double(y) + 0.5
                if minEdgeDistance(fx, fy, polygon) <= 1.5 { continue } // anti-aliasing band
                if pointInPolygon(fx, fy, polygon) {
                    interior += 1
                    #expect(painted(x, y), "\(fixture): interior pixel (\(x),\(y)) is not painted")
                } else {
                    exterior += 1
                    #expect(!painted(x, y), "\(fixture): exterior pixel (\(x),\(y)) is painted")
                }
            }
        }
        #expect(interior > 100 && exterior > 100, "\(fixture): coverage near-vacuous: interior=\(interior) exterior=\(exterior)")
    }

    /// Even-odd ray-cast point-in-polygon (the polystar edges form a simple polygon).
    private func pointInPolygon(_ px: Double, _ py: Double, _ poly: [(Double, Double)]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0 ..< poly.count {
            let (xi, yi) = poly[i], (xj, yj) = poly[j]
            if (yi > py) != (yj > py), px < (xj - xi) * (py - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Minimum distance from a point to any edge of the polygon (for the AA band).
    private func minEdgeDistance(_ px: Double, _ py: Double, _ poly: [(Double, Double)]) -> Double {
        var best = Double.greatestFiniteMagnitude
        var j = poly.count - 1
        for i in 0 ..< poly.count {
            let (ax, ay) = poly[j], (bx, by) = poly[i]
            let dx = bx - ax, dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
            let cx = ax + t * dx, cy = ay + t * dy
            best = min(best, ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot())
            j = i
        }
        return best
    }

    /// A painted-pixel predicate: a pixel differs from the (background) corner pixel.
    private func paintedMask(_ image: Image) -> (Int, Int) -> Bool {
        let bpp = image.bitsPerPixel / 8
        let data = image.data, bytesPerRow = image.bytesPerRow
        func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
            let offset = y * bytesPerRow + x * bpp
            return data[offset ..< offset + bpp]
        }
        let background = pixel(0, 0)
        return { x, y in pixel(x, y) != background }
    }

    /// Render an imported single-layer Lottie through the real engine and return
    /// the bounding box of pixels that differ from the (background) corner pixel.
    private func coveredBoundingBox(_ json: String) throws -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        let image = try renderImage(json)
        let bytesPerPixel = image.bitsPerPixel / 8
        func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
            let offset = y * image.bytesPerRow + x * bytesPerPixel
            return image.data[offset ..< offset + bytesPerPixel]
        }
        let background = pixel(0, 0)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0 ..< image.height {
            for x in 0 ..< image.width where pixel(x, y) != background {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        return (minX, minY, maxX, maxY)
    }

    /// Render an imported single-layer Lottie JSON string through the real engine.
    /// `extended` selects PureLayer's extended compositor (which applies shape blend
    /// modes); the default standard compositor is faithful Core Animation.
    private func renderImage(_ json: String, extended: Bool = false) throws -> Image {
        let animation = try LottieAnimation.decode(from: Data(json.utf8))
        let frame = LottieRenderIRBuilder(animation: animation).frame(at: 0)
        let tree = LottieRenderIRLowerer().lower(frame)
        let root = LottieRenderSurface.root(tree.root, width: animation.width, height: animation.height, scale: 1)
        let size = LottieRenderSurface.pixelSize(width: animation.width, height: animation.height, scale: 1)
        let compositor = extended ? Compositor(extensions: .extended) : Compositor()
        return try SoftwareBackend().render(compositor.drawList(for: root, at: 0), size: size)
    }

    /// Render an oracle fixture file through the real engine.
    private func renderFixtureImage(_ name: String) throws -> Image {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/LottieOracle/\(name)")
        return try renderImage(String(contentsOf: url, encoding: .utf8))
    }
}
