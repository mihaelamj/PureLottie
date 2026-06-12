import fs from 'node:fs';
import path from 'node:path';
import { PNG } from 'pngjs';

export function frameFileName(frame) {
  const value = Number(frame).toFixed(2);
  const [whole, fraction] = value.split('.');
  return `frame_${whole.padStart(4, '0')}.${fraction}.png`;
}

export function alphaStats(png) {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -1;
  let maxY = -1;
  let alphaPixels = 0;

  for (let y = 0; y < png.height; y += 1) {
    for (let x = 0; x < png.width; x += 1) {
      const index = (y * png.width + x) * 4;
      if (png.data[index + 3] > 0) {
        alphaPixels += 1;
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      }
    }
  }

  return {
    alphaPixels,
    bounds: alphaPixels === 0 ? null : { minX, minY, maxX, maxY }
  };
}

export function comparePngFiles(referenceFile, actualFile, diffFile, tolerance = 0) {
  const reference = PNG.sync.read(fs.readFileSync(referenceFile));
  const actual = PNG.sync.read(fs.readFileSync(actualFile));
  const referenceAlpha = alphaStats(reference);
  const actualAlpha = alphaStats(actual);

  if (reference.width !== actual.width || reference.height !== actual.height) {
    return {
      status: 'dimension-mismatch',
      referenceFile,
      actualFile,
      diffFile: null,
      width: reference.width,
      height: reference.height,
      actualWidth: actual.width,
      actualHeight: actual.height,
      referenceAlphaPixels: referenceAlpha.alphaPixels,
      actualAlphaPixels: actualAlpha.alphaPixels,
      referenceBounds: referenceAlpha.bounds,
      actualBounds: actualAlpha.bounds,
      changedPixels: null,
      totalPixels: null,
      maxChannelDelta: null,
      meanChannelDelta: null
    };
  }

  const diff = new PNG({ width: reference.width, height: reference.height });
  let changedPixels = 0;
  let maxChannelDelta = 0;
  let totalChannelDelta = 0;

  for (let index = 0; index < reference.data.length; index += 4) {
    const dr = Math.abs(reference.data[index] - actual.data[index]);
    const dg = Math.abs(reference.data[index + 1] - actual.data[index + 1]);
    const db = Math.abs(reference.data[index + 2] - actual.data[index + 2]);
    const da = Math.abs(reference.data[index + 3] - actual.data[index + 3]);
    const pixelMax = Math.max(dr, dg, db, da);
    maxChannelDelta = Math.max(maxChannelDelta, pixelMax);
    totalChannelDelta += dr + dg + db + da;

    if (pixelMax > tolerance) {
      changedPixels += 1;
      diff.data[index] = 255;
      diff.data[index + 1] = 0;
      diff.data[index + 2] = 255;
      diff.data[index + 3] = 255;
    } else {
      const gray = Math.round((reference.data[index] + reference.data[index + 1] + reference.data[index + 2]) / 3);
      diff.data[index] = gray;
      diff.data[index + 1] = gray;
      diff.data[index + 2] = gray;
      diff.data[index + 3] = Math.max(48, reference.data[index + 3]);
    }
  }

  fs.mkdirSync(path.dirname(diffFile), { recursive: true });
  fs.writeFileSync(diffFile, PNG.sync.write(diff));

  const totalPixels = reference.width * reference.height;
  return {
    status: changedPixels === 0 ? 'match' : 'mismatch',
    referenceFile,
    actualFile,
    diffFile,
    width: reference.width,
    height: reference.height,
    actualWidth: actual.width,
    actualHeight: actual.height,
    referenceAlphaPixels: referenceAlpha.alphaPixels,
    actualAlphaPixels: actualAlpha.alphaPixels,
    referenceBounds: referenceAlpha.bounds,
    actualBounds: actualAlpha.bounds,
    changedPixels,
    totalPixels,
    maxChannelDelta,
    meanChannelDelta: totalChannelDelta / (totalPixels * 4)
  };
}

export function comparePngDirectories({ referenceDir, actualDir, diffDir, frames, tolerance = 0 }) {
  return frames.map((frame) => {
    const fileName = frameFileName(frame);
    return {
      frame,
      ...comparePngFiles(
        path.join(referenceDir, fileName),
        path.join(actualDir, fileName),
        path.join(diffDir, fileName),
        tolerance
      )
    };
  });
}

function readArgument(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) {
    return null;
  }
  const value = process.argv[index + 1];
  if (!value || value.startsWith('--')) {
    throw new Error(`Missing value for ${name}`);
  }
  return value;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const referenceDir = readArgument('--reference');
  const actualDir = readArgument('--actual');
  const diffDir = readArgument('--diff');
  const framesArgument = readArgument('--frames');
  const tolerance = Number(readArgument('--tolerance') ?? '0');

  if (!referenceDir || !actualDir || !diffDir || !framesArgument) {
    throw new Error('Usage: node scripts/compare-images.mjs --reference <dir> --actual <dir> --diff <dir> --frames 0,5,9 [--tolerance 0]');
  }

  const frames = framesArgument.split(',').map(Number);
  const comparisons = comparePngDirectories({ referenceDir, actualDir, diffDir, frames, tolerance });
  process.stdout.write(`${JSON.stringify(comparisons, null, 2)}\n`);
}
