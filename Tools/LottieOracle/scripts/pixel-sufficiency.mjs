// Numeric -> pixel sufficiency gate (issue #130).
//
// Proves that numeric agreement with lottie-web implies the imported
// PureLayer/PureDraw primitives RENDER the same image -- i.e. the numeric
// quantities the oracle compares (matrices, paths, bounds, opacity, trim) are
// SUFFICIENT to determine the render. For every fixture that carries a committed
// lottie-web numeric intent trace (the numeric-eligible set), this renders the
// imported primitives (LottieFrameDump) and lottie-web (render-reference.mjs) at
// the same frames and asserts the rendered frames agree within a pixel tolerance.
//
// The pixel tolerance is `assumed`, not derived: lottie-web rasterizes via
// Chromium SVG and PureLayer via its own rasterizer, so there is no portable
// cross-renderer error bound (same limit the #115 audit recorded for
// bounds/path-length). Empirically the gap is anti-aliasing-level (<= 4/255 on
// the curated fixtures), so MAX_CHANNEL_DELTA is set conservatively above that;
// it still catches gross divergence (wrong/missing layer, wrong position).

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { PNG } from 'pngjs';
import { renderReferenceFrames } from './render-reference.mjs';
import { frameFileName } from './compare-images.mjs';

const oracleRoot = path.resolve(import.meta.dirname, '..');
const repoRoot = path.resolve(oracleRoot, '..', '..');

// Sufficiency-violation criterion (status: assumed). A fixture violates
// numeric -> pixel sufficiency when more than STRUCTURAL_FRACTION of pixels
// diverge beyond AA_TOLERANCE after compositing. The cut is evidence-placed:
// across the curated numeric-eligible set the diff fraction falls into two
// clusters with an empty gap between them (anti-aliased curved/rotated edges
// stay <= 0.32% of pixels; dropped or wrong features start at >= 0.88%), so
// 0.5% sits in the gap and classifies without a renderer-specific magic number.
// The cut is still assumed, not derived: cross-renderer AA has no portable
// bound (same status the #115 audit recorded for bounds/path-length).
const STRUCTURAL_FRACTION = 0.005;

function locateFrameDump() {
  const candidates = execFileSync('find', [
    path.join(repoRoot, '.build'), '-name', 'LottieFrameDump', '-type', 'f', '-perm', '+111'
  ]).toString().trim().split('\n').filter(Boolean);
  if (candidates.length === 0) {
    throw new Error('LottieFrameDump not built. Run: swift build --product LottieFrameDump');
  }
  return candidates[0];
}

// Composite one straight-alpha RGBA channel value over an opaque background.
// PNG stores straight (non-premultiplied) alpha, so a fully transparent pixel
// keeps an arbitrary RGB that must NOT be compared directly: the two renderers
// legitimately disagree on the color of invisible pixels (PureLayer keeps the
// fill color in transparent anti-aliased fringe pixels; Chromium zeroes them).
// Compositing collapses every invisible pixel to the background on both sides.
function over(channel, alpha, bg) {
  const a = alpha / 255;
  return channel * a + bg * (1 - a);
}

// Two pixels composite-identically over BOTH black and white iff they have the
// same alpha and the same premultiplied color -- the exact cross-renderer
// equality we want. So the comparison metric is the max composited-channel
// delta over both backgrounds; transparent pixels contribute zero.
//
// A single max-delta is not enough to classify a divergence: anti-aliasing on a
// curved or rotated edge touches only the ~1px boundary ring (a tiny fraction of
// pixels at a high local delta), while a dropped feature (an ignored mask, a
// missing dash pattern, a wrong fill region) differs over a whole area. So this
// also reports diffPixelFraction: the share of pixels whose composited delta
// exceeds AA_TOLERANCE. Structural gaps stand out by fraction, tolerance-free.
const AA_TOLERANCE = 32; // per-channel composited headroom for sub-pixel edge AA

function comparePNGs(aPath, bPath) {
  const a = PNG.sync.read(fs.readFileSync(aPath));
  const b = PNG.sync.read(fs.readFileSync(bPath));
  if (a.width !== b.width || a.height !== b.height) {
    return { dimMismatch: `${a.width}x${a.height} vs ${b.width}x${b.height}`, maxChannelDelta: 255, diffPixelFraction: 1 };
  }
  let maxChannelDelta = 0;
  let diffPixels = 0;
  const totalPixels = a.data.length / 4;
  for (let i = 0; i < a.data.length; i += 4) {
    const aA = a.data[i + 3];
    const bA = b.data[i + 3];
    let pixelDelta = 0;
    for (let c = 0; c < 3; c += 1) {
      for (const bg of [0, 255]) {
        const d = Math.abs(over(a.data[i + c], aA, bg) - over(b.data[i + c], bA, bg));
        if (d > pixelDelta) pixelDelta = d;
      }
    }
    if (pixelDelta > maxChannelDelta) maxChannelDelta = pixelDelta;
    if (pixelDelta > AA_TOLERANCE) diffPixels += 1;
  }
  return {
    maxChannelDelta: Math.round(maxChannelDelta),
    diffPixelFraction: Number((diffPixels / totalPixels).toFixed(4)),
  };
}

// Sequential driver: renderReferenceFrames is async, so run fixtures one at a time.
async function run() {
  const frameDump = locateFrameDump();
  const fixtures = JSON.parse(fs.readFileSync(path.join(oracleRoot, 'oracle-fixtures.json'), 'utf8'));
  const entries = (Array.isArray(fixtures) ? fixtures : fixtures.fixtures)
    .filter((f) => typeof f.lottieWebIntent === 'string');

  const results = [];
  for (const fx of entries) {
    const lottie = path.resolve(oracleRoot, fx.lottie);
    const intent = path.resolve(oracleRoot, fx.lottieWebIntent);
    const frames = fx.frames.map((f) => Number(f.frame));
    const scale = fx.scale ?? 1;
    const base = path.join(oracleRoot, '.build', 'pixel-sufficiency', fx.id);
    const plDir = path.join(base, 'purelayer');
    const webDir = path.join(base, 'web');
    fs.rmSync(base, { recursive: true, force: true });
    fs.mkdirSync(plDir, { recursive: true });

    execFileSync(frameDump, [
      '--input', lottie, '--lottie-web-intent', intent,
      '--output', plDir, '--frames', frames.join(','), '--scale', String(scale)
    ], { stdio: 'pipe' });
    await renderReferenceFrames({ input: lottie, output: webDir, frames, scale, renderer: 'svg' });

    for (const frame of frames) {
      const fn = frameFileName(frame);
      const cmp = comparePNGs(path.join(plDir, fn), path.join(webDir, fn));
      const pass = !cmp.dimMismatch && cmp.diffPixelFraction <= STRUCTURAL_FRACTION;
      results.push({ fixture: fx.id, frame, ...cmp, pass });
    }
  }
  return results;
}

run().then((results) => {
  const failures = results.filter((r) => !r.pass);
  // Per-fixture roll-up: a fixture violates sufficiency if any of its frames do.
  const byFixture = {};
  for (const r of results) {
    const f = (byFixture[r.fixture] ||= { fixture: r.fixture, maxChannelDelta: 0, diffPixelFraction: 0, pass: true });
    f.maxChannelDelta = Math.max(f.maxChannelDelta, r.maxChannelDelta);
    f.diffPixelFraction = Math.max(f.diffPixelFraction, r.diffPixelFraction);
    f.pass = f.pass && r.pass;
  }
  const violations = Object.values(byFixture)
    .filter((f) => !f.pass)
    .sort((a, b) => b.diffPixelFraction - a.diffPixelFraction);

  const report = {
    schema: 'purelottie.pixel-sufficiency.v2',
    metricStatus: 'assumed',
    aaTolerance: AA_TOLERANCE,
    structuralFraction: STRUCTURAL_FRACTION,
    note: 'Composited over black and white (transparent pixels contribute nothing); '
      + 'a fixture violates numeric -> pixel sufficiency when more than structuralFraction '
      + 'of pixels diverge beyond aaTolerance, i.e. the numbers matched lottie-web but a '
      + 'render feature did not reach the raster. Cross-renderer AA has no portable bound, '
      + 'so the metric status is assumed.',
    framesChecked: results.length,
    fixturesChecked: Object.keys(byFixture).length,
    maxObservedDelta: results.reduce((m, r) => Math.max(m, r.maxChannelDelta), 0),
    sufficiencyViolations: violations,
    failures
  };
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (failures.length > 0) {
    process.stderr.write(`pixel-sufficiency: ${failures.length} numeric-eligible frame(s) diverged beyond the assumed tolerance.\n`);
    process.exit(1);
  }
}).catch((error) => {
  process.stderr.write(`pixel-sufficiency failed: ${error.message}\n`);
  process.exit(1);
});
