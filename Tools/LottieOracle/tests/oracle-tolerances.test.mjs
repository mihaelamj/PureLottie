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
    version: 2
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
  assert.equal(pixel.derivation.status, 'derived');
  assert.equal(pixel.derivation.derivedBound, pixel.threshold);
  assert.equal(pixel.derivation.counterexampleOffset, 1);

  const trim = byID.get('trim.segment.unit-interval.absolute');
  assert.equal(trim.feature, 'trim-segment');
  assert.equal(trim.unit, 'unitInterval');
  assert.equal(trim.comparison, 'absolute-difference');
  assert.equal(trim.threshold, 0.000000000001);
  assert.match(trim.reason, /normalized start, end, and offset-turn values/);
  assert.equal(trim.derivation.status, 'derived');
  assert.equal(trim.derivation.derivedBound, trim.threshold);

  const frame = byID.get('frame.source-frame.absolute');
  assert.equal(frame.feature, 'frame');
  assert.equal(frame.unit, 'sourceFrame');
  assert.equal(frame.comparison, 'absolute-difference');
  assert.equal(frame.threshold, 0.000000000001);
  assert.match(frame.reason, /Lottie source-frame units/);
  assert.equal(frame.derivation.status, 'derived');
  assert.equal(frame.derivation.derivedBound, frame.threshold);

  const translation = byID.get('matrix.translation.css-pixel.absolute');
  assert.equal(translation.threshold, 0.000003814697265625);
  assert.equal(translation.derivation.status, 'derived');
  assert.equal(translation.derivation.derivedBound, translation.threshold);

  const assumed = ['bounds.css-pixel.absolute', 'path-length.css-pixel.absolute'];
  for (const id of assumed) {
    const tolerance = byID.get(id);
    assert.equal(tolerance.derivation.status, 'assumed', id);
    assert.equal(tolerance.witness.status, 'asserted', id);
    assert.match(tolerance.derivation.assumption, /Missing portable Chromium SVG/, id);
  }

  for (const tolerance of ledger.tolerances) {
    assert.ok(tolerance.derivation.counterexampleOffset > tolerance.threshold, tolerance.id);
    assert.ok(tolerance.derivation.evidence.length > 0, tolerance.id);
    if (tolerance.derivation.status === 'derived') {
      assert.equal(tolerance.witness.status, 'witnessed', tolerance.id);
      assert.equal(tolerance.derivation.derivedBound, tolerance.threshold, tolerance.id);
    }
  }
});
