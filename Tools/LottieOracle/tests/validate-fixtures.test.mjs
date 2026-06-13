import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { evidenceRoleVocabulary, loadFixtureManifest, validateFixtureCorpus } from '../scripts/validate-fixtures.mjs';

const oracleRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

test('curated fixture validation records parse lottie-web and intent usability', async () => {
  const result = await validateFixtureCorpus({ oracleRoot });

  assert.equal(result.ok, true);
  assert.equal(result.fixtureCount, 31);
  assert.equal(result.lottieWebChecked, false);
  assert.deepEqual(result.statuses, { usable: 31 });
  assert.deepEqual(result.errors, []);
});

test('fixture validation rejects missing evidence role and purpose', async () => {
  const [fixture] = loadFixtureManifest(oracleRoot);
  const { evidenceRoles, purpose, ...fixtureWithoutRolePurpose } = fixture;
  const result = await validateFixtureCorpus({
    oracleRoot,
    fixtures: [fixtureWithoutRolePurpose]
  });

  assert.equal(result.ok, false);
  assert.deepEqual(
    result.errors.map((error) => error.reason),
    [
      'Failed to satisfy: Fixture evidence roles contain at least one role',
      'Failed to satisfy: Fixture purpose explains the evidence role'
    ]
  );
  assert.deepEqual(result.errors.map((error) => error.path), [
    'oracle-fixtures.json[0]',
    'oracle-fixtures.json[0]'
  ]);
});

test('fixture validation rejects unknown evidence roles', async () => {
  const [fixture] = loadFixtureManifest(oracleRoot);
  const result = await validateFixtureCorpus({
    oracleRoot,
    fixtures: [
      {
        ...fixture,
        evidenceRoles: [...fixture.evidenceRoles, 'synthetic-role']
      }
    ]
  });

  assert.equal(result.ok, false);
  assert.equal(result.errors.length, 1);
  assert.deepEqual(result.errors[0], {
    fixtureID: fixture.id,
    path: 'oracle-fixtures.json[0]',
    reason: 'Failed to satisfy: Fixture evidence roles use stable vocabulary',
    details: ['synthetic-role']
  });
});

test('fixture validation rejects non-array evidence roles without throwing', async () => {
  const [fixture] = loadFixtureManifest(oracleRoot);
  const result = await validateFixtureCorpus({
    oracleRoot,
    fixtures: [
      {
        ...fixture,
        evidenceRoles: 'conformance'
      }
    ]
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.errors.map((error) => error.reason), [
    'Failed to satisfy: Fixture evidence roles contain at least one role'
  ]);
  assert.deepEqual(result.errors.map((error) => error.path), [
    'oracle-fixtures.json[0]'
  ]);
});

test('fixture validation rejects status role contradictions', async () => {
  const [fixture] = loadFixtureManifest(oracleRoot);
  const result = await validateFixtureCorpus({
    oracleRoot,
    fixtures: [
      {
        ...fixture,
        evidenceRoles: [...fixture.evidenceRoles, 'unsupported-feature']
      }
    ]
  });

  assert.equal(result.ok, false);
  assert.equal(result.errors.length, 1);
  assert.deepEqual(result.errors[0], {
    fixtureID: fixture.id,
    path: 'oracle-fixtures.json[0]',
    reason: 'Failed to satisfy: Modeled fixtures do not carry unsupported-feature evidence',
    details: false
  });
});

test('fixture validation rejects engine divergence fixtures without divergence ids', async () => {
  const [fixture] = loadFixtureManifest(oracleRoot);
  const { divergenceIDs, ...fixtureWithoutDivergenceIDs } = fixture;
  const result = await validateFixtureCorpus({
    oracleRoot,
    fixtures: [fixtureWithoutDivergenceIDs]
  });

  assert.equal(result.ok, false);
  assert.equal(result.errors.length, 1);
  assert.deepEqual(result.errors[0], {
    fixtureID: fixture.id,
    path: 'oracle-fixtures.json[0]',
    reason: 'Failed to satisfy: Engine-divergence fixtures declare divergence ids',
    details: false
  });
});

test('fixture validation rejects unknown reference divergence ids', async () => {
  const [fixture] = loadFixtureManifest(oracleRoot);
  const result = await validateFixtureCorpus({
    oracleRoot,
    fixtures: [
      {
        ...fixture,
        divergenceIDs: ['missing.divergence']
      }
    ]
  });

  assert.equal(result.ok, false);
  assert.equal(result.errors.length, 1);
  assert.deepEqual(result.errors[0], {
    fixtureID: fixture.id,
    path: 'oracle-fixtures.json[0].divergenceIDs',
    reason: 'Failed to satisfy: Engine-divergence fixtures reference known divergence ids',
    details: 'missing.divergence'
  });
});

test('fixture validation rejects divergence ids without matching ledger back-reference', async () => {
  const [fixture] = loadFixtureManifest(oracleRoot);
  const result = await validateFixtureCorpus({
    oracleRoot,
    fixtures: [
      {
        ...fixture,
        divergenceIDs: ['style.fill-rule-evenodd']
      }
    ]
  });

  assert.equal(result.ok, false);
  assert.equal(result.errors.length, 1);
  assert.deepEqual(result.errors[0], {
    fixtureID: fixture.id,
    path: 'oracle-fixtures.json[0].divergenceIDs',
    reason: 'Failed to satisfy: Engine-divergence fixtures are back-referenced by the divergence ledger',
    details: 'style.fill-rule-evenodd'
  });
});

test('fixture validation diagnostics include fixture id manifest path and positive rule reason', async () => {
  const [fixture] = loadFixtureManifest(oracleRoot);
  const result = await validateFixtureCorpus({
    oracleRoot,
    fixtures: [
      {
        ...fixture,
        validation: {
          ...fixture.validation,
          failureReasons: ['synthetic failure']
        }
      }
    ]
  });

  assert.equal(result.ok, false);
  assert.equal(result.errors.length, 1);
  assert.deepEqual(result.errors[0], {
    fixtureID: fixture.id,
    path: 'oracle-fixtures.json[0].validation',
    reason: 'Failed to satisfy: Usable fixtures have no failure reasons',
    details: false
  });
});
