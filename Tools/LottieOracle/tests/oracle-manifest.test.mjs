import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const oracleRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const repoRoot = path.dirname(path.dirname(oracleRoot));

test('oracle dependencies are exact external pins', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(oracleRoot, 'package.json'), 'utf8'));
  assert.equal(packageJson.dependencies['lottie-web'], '5.13.0');
  assert.equal(packageJson.dependencies.playwright, '1.60.0');
  assert.equal(packageJson.dependencies.pngjs, '7.0.0');
  assert.equal(packageJson.scripts['build-corpus'], 'node scripts/build-curated-corpus.mjs');
  assert.equal(packageJson.scripts['extract-intent'], 'node scripts/extract-intent.mjs');

  for (const version of Object.values(packageJson.dependencies)) {
    assert.match(version, /^\d+\.\d+\.\d+$/);
  }
});

test('curated fixtures declare frame rationale and resolve to committed traces', () => {
  const fixtures = JSON.parse(fs.readFileSync(path.join(oracleRoot, 'oracle-fixtures.json'), 'utf8'));
  assert.ok(fixtures.length >= 30);

  for (const fixture of fixtures) {
    assert.ok(fixture.id.length > 0);
    assert.ok(fixture.description.length > 30);
    assert.ok(fixture.bugClass.length > 30);
    assert.ok(['modeled', 'diagnosed'].includes(fixture.semanticStatus));
    assert.ok(Array.isArray(fixture.coverage));
    assert.ok(fixture.coverage.length > 0);
    assert.equal(typeof fixture.expectedValidationEligible, 'boolean');
    assert.equal(fixture.expectReferenceNonEmpty, true);
    assert.ok(fixture.frames.length >= 3);
    assert.ok(fs.existsSync(path.resolve(oracleRoot, fixture.lottie)));

    const intentPath = path.resolve(oracleRoot, fixture.lottieWebIntent);
    assert.ok(fs.existsSync(intentPath));
    const intent = JSON.parse(fs.readFileSync(intentPath, 'utf8'));
    assert.equal(intent.schema.name, 'purelottie.lottie-web-intent');
    assert.equal(intent.schema.version, 1);
    assert.equal(intent.source, fixture.lottie);
    assert.equal(intent.renderer, fixture.renderer);
    assert.equal(intent.lottieWeb.version, '5.13.0');
    assert.deepEqual(intent.frames.map((frame) => frame.frame), fixture.frames.map((frame) => frame.frame));
    assert.ok(intent.frames.some((frame) => frame.pathCount > 0));

    for (const frame of fixture.frames) {
      assert.equal(typeof frame.frame, 'number');
      assert.ok(frame.rationale.length > 20);
    }
  }
});

test('curated fixture corpus covers required source-intent feature families', () => {
  const fixtures = JSON.parse(fs.readFileSync(path.join(oracleRoot, 'oracle-fixtures.json'), 'utf8'));
  const coverage = new Set(fixtures.flatMap((fixture) => fixture.coverage));
  const required = [
    'animated-position',
    'anchor',
    'scale',
    'rotation',
    'parent-transform',
    'ellipse',
    'rectangle',
    'path',
    'polygon',
    'star',
    'fill',
    'stroke',
    'trim',
    'mask',
    'matte',
    'precomp',
    'time-remap'
  ];

  for (const item of required) {
    assert.ok(coverage.has(item), `missing coverage family ${item}`);
  }
});

test('lottie-web stays outside the Swift package graph', () => {
  const packageSwift = fs.readFileSync(path.join(repoRoot, 'Package.swift'), 'utf8');
  assert.equal(packageSwift.includes('lottie-web'), false);
  assert.equal(packageSwift.includes('playwright'), false);
  assert.equal(packageSwift.includes('pngjs'), false);
});
