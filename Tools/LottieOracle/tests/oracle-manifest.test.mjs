import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const oracleRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const repoRoot = path.dirname(path.dirname(oracleRoot));

const evidenceRoleVocabulary = [
  'conformance',
  'regression',
  'unsupported-feature',
  'visual-inspection',
  'engine-divergence'
];

function committedIntent(name) {
  return JSON.parse(fs.readFileSync(
    path.join(repoRoot, 'Tests/Fixtures/LottieOracle/lottie-web-intent', `${name}.json`),
    'utf8'
  ));
}

function committedFrame(name, sourceFrame) {
  const intent = committedIntent(name);
  const frame = intent.frames.find((candidate) => candidate.frame === sourceFrame);
  assert.ok(frame, `missing frame ${sourceFrame} in ${name}`);
  return frame;
}

test('oracle dependencies are exact external pins', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(oracleRoot, 'package.json'), 'utf8'));
  assert.equal(packageJson.dependencies['lottie-web'], '5.13.0');
  assert.equal(packageJson.dependencies.playwright, '1.60.0');
  assert.equal(packageJson.dependencies.pngjs, '7.0.0');
  assert.equal(packageJson.scripts['build-corpus'], 'node scripts/build-curated-corpus.mjs');
  assert.equal(packageJson.scripts['extract-intent'], 'node scripts/extract-intent.mjs');
  assert.equal(packageJson.scripts['validate-fixtures'], 'node scripts/validate-fixtures.mjs --check-lottie-web');

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
    assert.ok(fixture.purpose.length > 50);
    assert.ok(['modeled', 'diagnosed'].includes(fixture.semanticStatus));
    assert.ok(Array.isArray(fixture.evidenceRoles));
    assert.ok(fixture.evidenceRoles.length > 0);
    for (const role of fixture.evidenceRoles) {
      assert.ok(evidenceRoleVocabulary.includes(role), `${fixture.id} has unknown role ${role}`);
    }
    assert.ok(Array.isArray(fixture.coverage));
    assert.ok(fixture.coverage.length > 0);
    assert.ok(fixture.coverage.some((coverage) => fixture.purpose.includes(coverage)));
    if (fixture.semanticStatus === 'modeled') {
      assert.ok(fixture.evidenceRoles.includes('conformance'));
    }
    if (fixture.semanticStatus === 'diagnosed') {
      assert.ok(fixture.evidenceRoles.includes('unsupported-feature'));
    }
    assert.equal(typeof fixture.expectedValidationEligible, 'boolean');
    assert.equal(fixture.expectReferenceNonEmpty, true);
    assert.deepEqual(fixture.validation, {
      status: 'usable',
      sourceJSON: 'parses',
      lottieWeb: 'loads',
      numericIntent: 'committed',
      referenceNonEmpty: 'passed',
      failureReasons: []
    });
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

test('committed lottie-web traces expose feature reference facts', () => {
  const maskFrame = committedFrame('mask-add-rectangle', 5);
  assert.equal(maskFrame.maskCount, 1);
  assert.equal(maskFrame.masks[0].layerName, 'Masked Box');
  assert.equal(maskFrame.masks[0].mode, 'a');
  assert.equal(maskFrame.masks[0].opacity, 1);
  assert.equal(maskFrame.masks[0].vertexCount, 4);
  assert.ok(maskFrame.masks[0].pathD.length > 0);

  const matteFrame = committedFrame('alpha-matte-rectangle', 5);
  assert.equal(matteFrame.matteCount, 1);
  assert.equal(matteFrame.mattes[0].targetLayerName, 'Matted Box');
  assert.equal(matteFrame.mattes[0].sourceLayerName, 'Matte Circle');
  assert.equal(matteFrame.mattes[0].sourceResolved, true);
  assert.equal(matteFrame.mattes[0].sourceIsMarker, true);

  const precompFrames = committedIntent('precomp-static-child').frames;
  assert.deepEqual(precompFrames.map((frame) => frame.precompositions[0].renderedFrame), [0, 5, 9]);
  assert.equal(precompFrames[1].precompositions[0].refId, 'box_precomp');

  const remappedFrames = committedIntent('time-remap-precomp-diagnosed').frames;
  assert.deepEqual(remappedFrames.map((frame) => frame.precompositions[0].renderedFrame), [5, 5, 5]);
  assert.ok(remappedFrames.every((frame) => frame.precompositions[0].timeRemapped === true));
  assert.ok(remappedFrames.every((frame) => frame.precompositions[0].timeRemapValue === 5));

  const trimFrame = committedFrame('trim-rectangle-half', 5);
  assert.equal(trimFrame.trimCount, 1);
  assert.equal(trimFrame.trims[0].startFraction, 0);
  assert.equal(trimFrame.trims[0].endFraction, 0.5);
  assert.equal(trimFrame.trims[0].mode, 1);
  assert.ok(trimFrame.diagnostics.some((diagnostic) => diagnostic.feature === 'trim.selectedSegments'));

  const animatedTrimFrames = committedIntent('animated-trim-path').frames;
  assert.deepEqual(animatedTrimFrames.map((frame) => frame.trims[0].endFraction), [0, 5 / 9, 1]);
  assert.ok(animatedTrimFrames.every((frame) => {
    return frame.diagnostics.some((diagnostic) => diagnostic.feature === 'trim.selectedSegments');
  }));
});

test('evidence role vocabulary is documented and exercised', () => {
  const roleDoc = fs.readFileSync(path.join(repoRoot, 'docs/lottie-format/fixture-evidence-roles.md'), 'utf8');
  const fixtures = JSON.parse(fs.readFileSync(path.join(oracleRoot, 'oracle-fixtures.json'), 'utf8'));
  const usedRoles = new Set(fixtures.flatMap((fixture) => fixture.evidenceRoles));

  for (const role of evidenceRoleVocabulary) {
    assert.match(roleDoc, new RegExp(`\\| \`${role}\` \\|`));
    assert.ok(usedRoles.has(role), `missing fixture with evidence role ${role}`);
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
