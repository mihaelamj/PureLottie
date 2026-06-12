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
  assert.equal(packageJson.scripts['extract-intent'], 'node scripts/extract-intent.mjs');

  for (const version of Object.values(packageJson.dependencies)) {
    assert.match(version, /^\d+\.\d+\.\d+$/);
  }
});

test('selected fixtures declare frame rationale and resolve to files', () => {
  const fixtures = JSON.parse(fs.readFileSync(path.join(oracleRoot, 'oracle-fixtures.json'), 'utf8'));
  assert.ok(fixtures.length >= 1);

  for (const fixture of fixtures) {
    assert.ok(fixture.id.length > 0);
    assert.ok(fs.existsSync(path.resolve(oracleRoot, fixture.lottie)));
    assert.ok(fs.existsSync(path.resolve(oracleRoot, fixture.lottieWebIntent)));
    assert.equal(fixture.expectedValidationEligible, true);
    assert.equal(fixture.expectReferenceNonEmpty, true);
    assert.ok(fixture.frames.length > 0);
    for (const frame of fixture.frames) {
      assert.equal(typeof frame.frame, 'number');
      assert.ok(frame.rationale.length > 20);
    }
  }
});

test('lottie-web stays outside the Swift package graph', () => {
  const packageSwift = fs.readFileSync(path.join(repoRoot, 'Package.swift'), 'utf8');
  assert.equal(packageSwift.includes('lottie-web'), false);
  assert.equal(packageSwift.includes('playwright'), false);
  assert.equal(packageSwift.includes('pngjs'), false);
});
