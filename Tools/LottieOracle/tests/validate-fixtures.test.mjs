import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadFixtureManifest, validateFixtureCorpus } from '../scripts/validate-fixtures.mjs';

const oracleRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

test('curated fixture validation records parse lottie-web and intent usability', async () => {
  const result = await validateFixtureCorpus({ oracleRoot });

  assert.equal(result.ok, true);
  assert.equal(result.fixtureCount, 31);
  assert.equal(result.lottieWebChecked, false);
  assert.deepEqual(result.statuses, { usable: 31 });
  assert.deepEqual(result.errors, []);
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
