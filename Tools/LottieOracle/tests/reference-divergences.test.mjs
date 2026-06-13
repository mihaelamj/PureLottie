import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const oracleRoot = path.resolve(import.meta.dirname, '..');
const repoRoot = path.resolve(oracleRoot, '..', '..');

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
}

test('reference divergence ledger records measured engine divergence facts', () => {
  const ledger = readJson('Tools/LottieOracle/reference-divergences.json');

  assert.deepEqual(ledger.schema, {
    name: 'purelottie.reference-divergences',
    version: 1
  });
  assert.equal(ledger.divergences.length, 17);
  assert.equal(new Set(ledger.divergences.map((entry) => entry.id)).size, ledger.divergences.length);

  for (const divergence of ledger.divergences) {
    assert.match(divergence.id, /^[a-z0-9]+(?:[.-][a-z0-9]+)+$/);
    assert.ok(divergence.title.length >= 20, divergence.id);
    assert.ok(['measured', 'diagnosed-boundary'].includes(divergence.status), divergence.id);
    assert.ok(divergence.engines.includes('lottie-web'), divergence.id);
    assert.ok(divergence.affectedFields.length > 0, divergence.id);
    assert.ok(divergence.fixtures.length > 0, divergence.id);
    assert.ok(divergence.observedBehavior.length >= 80, divergence.id);
    assert.ok(divergence.comparisonEvidence.length > 0, divergence.id);
    assert.ok(divergence.sourcePointers.length > 0, divergence.id);
  }
});

test('engine-divergence fixtures link to reference divergence ids', () => {
  const manifest = readJson('Tools/LottieOracle/oracle-fixtures.json');
  const ledger = readJson('Tools/LottieOracle/reference-divergences.json');
  const divergenceIDs = new Set(ledger.divergences.map((entry) => entry.id));
  const fixtureIDs = new Set(manifest.map((entry) => entry.id));
  const engineFixtures = manifest.filter((entry) => entry.evidenceRoles.includes('engine-divergence'));
  const ledgerFixtures = new Set(ledger.divergences.flatMap((entry) => entry.fixtures));

  assert.equal(engineFixtures.length, 24);
  for (const fixture of engineFixtures) {
    assert.ok(Array.isArray(fixture.divergenceIDs), `${fixture.id} lacks divergenceIDs`);
    assert.ok(fixture.divergenceIDs.length > 0, `${fixture.id} lacks ledger-backed reasons`);
    for (const id of fixture.divergenceIDs) {
      assert.ok(divergenceIDs.has(id), `${fixture.id} references unknown divergence id ${id}`);
      const divergence = ledger.divergences.find((entry) => entry.id === id);
      assert.ok(divergence.fixtures.includes(fixture.id), `${id} does not back-reference ${fixture.id}`);
    }
  }

  for (const fixtureID of ledgerFixtures) {
    assert.ok(fixtureIDs.has(fixtureID), `ledger references unknown fixture ${fixtureID}`);
    const fixture = engineFixtures.find((entry) => entry.id === fixtureID);
    assert.ok(fixture, `${fixtureID} is not tagged engine-divergence`);
  }

  for (const divergence of ledger.divergences) {
    for (const fixtureID of divergence.fixtures) {
      const fixture = engineFixtures.find((entry) => entry.id === fixtureID);
      assert.ok(fixture.divergenceIDs.includes(divergence.id), `${fixtureID} does not link back to ${divergence.id}`);
    }
  }
});

test('reference divergence source pointers resolve to repository files', () => {
  const ledger = readJson('Tools/LottieOracle/reference-divergences.json');
  const pointerKinds = new Set(['fixture', 'lottie-web-intent', 'local-source', 'local-test', 'oracle-tool']);

  for (const divergence of ledger.divergences) {
    for (const evidencePath of divergence.comparisonEvidence) {
      assert.ok(fs.existsSync(path.join(repoRoot, evidencePath)), `${divergence.id} missing evidence ${evidencePath}`);
    }
    for (const pointer of divergence.sourcePointers) {
      assert.ok(pointerKinds.has(pointer.kind), `${divergence.id} unknown pointer kind ${pointer.kind}`);
      assert.ok(fs.existsSync(path.join(repoRoot, pointer.path)), `${divergence.id} missing pointer ${pointer.path}`);
      assert.ok(pointer.note.length >= 20, `${divergence.id} pointer note too short`);
    }
  }
});
