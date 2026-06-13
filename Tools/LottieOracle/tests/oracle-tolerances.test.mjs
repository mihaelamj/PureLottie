import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const oracleRoot = path.resolve(import.meta.dirname, '..');
const ledgerPath = path.join(oracleRoot, 'oracle-tolerances.json');

function loadLedger() {
  return JSON.parse(fs.readFileSync(ledgerPath, 'utf8'));
}

test('oracle tolerance ledger records required numeric comparison families', () => {
  const ledger = loadLedger();
  assert.deepEqual(ledger.schema, {
    name: 'purelottie.oracle-tolerances',
    version: 1
  });

  const byID = new Map(ledger.tolerances.map((entry) => [entry.id, entry]));
  assert.deepEqual([...byID.keys()].sort(), [
    'bounds.css-pixel.absolute',
    'frame.source-frame.absolute',
    'matrix.translation.css-pixel.absolute',
    'opacity.unit-interval.absolute',
    'path-length.css-pixel.absolute',
    'pixel.max-channel.exact',
    'trim.segment.unit-interval.absolute'
  ]);

  const pixel = byID.get('pixel.max-channel.exact');
  assert.equal(pixel.feature, 'pixel-diff');
  assert.equal(pixel.unit, 'rgbaChannelValue');
  assert.equal(pixel.comparison, 'max-channel-difference');
  assert.equal(pixel.threshold, 0);
  assert.match(pixel.reason, /exact RGBA channel equality/);

  const trim = byID.get('trim.segment.unit-interval.absolute');
  assert.equal(trim.feature, 'trim-segment');
  assert.equal(trim.unit, 'unitInterval');
  assert.equal(trim.comparison, 'absolute-difference');
  assert.equal(trim.threshold, 0.000001);
  assert.match(trim.reason, /normalized start and end fractions/);

  const frame = byID.get('frame.source-frame.absolute');
  assert.equal(frame.feature, 'frame');
  assert.equal(frame.unit, 'sourceFrame');
  assert.equal(frame.comparison, 'absolute-difference');
  assert.equal(frame.threshold, 0.000001);
  assert.match(frame.reason, /Lottie source-frame coordinates/);
});
