import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const oracleRoot = path.resolve(import.meta.dirname, '..');

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(oracleRoot, relativePath), 'utf8'));
}

test('witness corpus manifest records lottie-web reference traces', () => {
  const manifest = readJson('witness-corpus.json');
  assert.deepEqual(manifest.schema, {
    name: 'purelottie.numeric-claim-witness-corpus',
    version: 1
  });
  assert.equal(manifest.entries.length, 5);
  assert.equal(new Set(manifest.entries.map((entry) => entry.id)).size, manifest.entries.length);

  for (const entry of manifest.entries) {
    assert.equal(entry.semanticStatus, 'witnessed-reference', entry.id);
    assert.equal(entry.witness.status, 'witnessed', entry.id);
    assert.ok(entry.witness.evidence.includes(entry.lottieWebIntent), entry.id);
    assert.ok(fs.existsSync(path.resolve(oracleRoot, entry.lottie)), `${entry.id} missing source`);
    assert.ok(fs.existsSync(path.resolve(oracleRoot, entry.lottieWebIntent)), `${entry.id} missing trace`);
  }
});

test('witness corpus trace identities match their manifest entries', () => {
  const manifest = readJson('witness-corpus.json');
  for (const entry of manifest.entries) {
    const trace = JSON.parse(fs.readFileSync(path.resolve(oracleRoot, entry.lottieWebIntent), 'utf8'));
    assert.equal(trace.schema.name, 'purelottie.lottie-web-intent', entry.id);
    assert.equal(trace.schema.version, 1, entry.id);
    assert.equal(trace.source, entry.lottie, entry.id);
    assert.equal(trace.lottieWeb.version, '5.13.0', entry.id);
    assert.deepEqual(
      trace.frames.map((frame) => frame.frame),
      entry.frames.map((frame) => frame.frame),
      entry.id
    );
  }
});
