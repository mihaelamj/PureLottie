import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { PNG } from 'pngjs';
import { comparePngFiles, frameFileName } from '../scripts/compare-images.mjs';

const oracleRoot = path.resolve(import.meta.dirname, '..');
const toleranceLedger = JSON.parse(fs.readFileSync(path.join(oracleRoot, 'oracle-tolerances.json'), 'utf8'));
const pixelTolerance = toleranceLedger.tolerances.find((entry) => entry.id === 'pixel.max-channel.exact');

function writePng(file, pixels) {
  const png = new PNG({ width: 1, height: 1 });
  png.data[0] = pixels[0];
  png.data[1] = pixels[1];
  png.data[2] = pixels[2];
  png.data[3] = pixels[3];
  fs.writeFileSync(file, PNG.sync.write(png));
}

test('frame file names match LottieFrameDump output', () => {
  assert.equal(frameFileName(0), 'frame_0000.00.png');
  assert.equal(frameFileName(5), 'frame_0005.00.png');
  assert.equal(frameFileName(120), 'frame_0120.00.png');
  assert.equal(frameFileName(0.5), 'frame_0000.50.png');
});

test('PNG comparison records exact matches and mismatches', () => {
  assert.equal(pixelTolerance.threshold, 0);
  assert.equal(pixelTolerance.derivation.status, 'derived');
  assert.equal(pixelTolerance.derivation.counterexampleOffset, 1);

  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'purelottie-oracle-'));
  const reference = path.join(directory, 'reference.png');
  const actual = path.join(directory, 'actual.png');
  const diff = path.join(directory, 'diff.png');

  writePng(reference, [10, 20, 30, 255]);
  writePng(actual, [10, 20, 30, 255]);
  assert.equal(comparePngFiles(reference, actual, diff, pixelTolerance.threshold).status, 'match');

  writePng(actual, [10 + pixelTolerance.derivation.counterexampleOffset, 20, 30, 255]);
  const result = comparePngFiles(reference, actual, diff, pixelTolerance.threshold);
  assert.equal(result.status, 'mismatch');
  assert.equal(result.referenceAlphaPixels, 1);
  assert.equal(result.actualAlphaPixels, 1);
  assert.deepEqual(result.referenceBounds, { minX: 0, minY: 0, maxX: 0, maxY: 0 });
  assert.equal(result.changedPixels, 1);
  assert.equal(result.maxChannelDelta, 1);
  assert.equal(fs.existsSync(diff), true);
});
