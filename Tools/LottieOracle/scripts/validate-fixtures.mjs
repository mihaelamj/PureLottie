import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { extractLottieIntent } from './extract-intent.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultOracleRoot = path.dirname(scriptDirectory);

const validationStatus = {
  usable: 'usable'
};

export const evidenceRoleVocabulary = Object.freeze([
  'conformance',
  'regression',
  'unsupported-feature',
  'visual-inspection',
  'engine-divergence'
]);

const evidenceRoleSet = new Set(evidenceRoleVocabulary);

function readArgument(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) {
    return null;
  }
  const value = process.argv[index + 1];
  if (!value || value.startsWith('--')) {
    throw new Error(`Missing value for ${name}`);
  }
  return value;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function resolveFromOracleRoot(oracleRoot, relativePath) {
  return path.resolve(oracleRoot, relativePath);
}

function validation(description, check, when = () => true) {
  return { description, check, when };
}

function failure(description, fixture, path, details = null) {
  return {
    fixtureID: fixture?.id ?? '<unknown>',
    path,
    reason: `Failed to satisfy: ${description}`,
    details
  };
}

function applyValidations(validations, context) {
  return validations.flatMap((rule) => {
    if (!rule.when(context)) {
      return [];
    }
    const result = rule.check(context);
    return result === true ? [] : [failure(rule.description, context.fixture, context.path, result)];
  });
}

function frameList(fixture) {
  return (fixture.frames ?? []).map((entry) => Number(entry.frame));
}

function unknownEvidenceRoles(fixture) {
  if (!Array.isArray(fixture.evidenceRoles)) {
    return [];
  }
  return (fixture.evidenceRoles ?? []).filter((role) => !evidenceRoleSet.has(role));
}

function purposeMentionsCoverage(fixture) {
  return (fixture.coverage ?? []).some((item) => fixture.purpose.includes(item));
}

function hasVisiblePaint(pathRecord) {
  const style = pathRecord.style ?? {};
  const fillOpacity = Number(style.fillOpacity ?? 1);
  const strokeOpacity = Number(style.strokeOpacity ?? 1);
  const strokeWidth = Number(style.strokeWidth ?? 0);
  const fillVisible = style.fill && style.fill !== 'none' && fillOpacity > 0;
  const strokeVisible = style.stroke && style.stroke !== 'none' && strokeOpacity > 0 && strokeWidth > 0;
  return pathRecord.visible === true && (fillVisible || strokeVisible);
}

function visiblePaintPathCount(frame) {
  return (frame.paths ?? []).filter(hasVisiblePaint).length;
}

function manifestPath(index, field) {
  return `oracle-fixtures.json[${index}]${field ? `.${field}` : ''}`;
}

function validateManifestShape(fixture, index) {
  const context = { fixture, path: manifestPath(index) };
  return applyValidations([
    validation('Fixture ids are non-empty strings', ({ fixture }) => typeof fixture.id === 'string' && fixture.id.length > 0),
    validation('Fixture descriptions explain the case', ({ fixture }) => typeof fixture.description === 'string' && fixture.description.length > 30),
    validation('Fixture bug classes explain the protected failure', ({ fixture }) => typeof fixture.bugClass === 'string' && fixture.bugClass.length > 30),
    validation('Fixture evidence roles contain at least one role', ({ fixture }) => Array.isArray(fixture.evidenceRoles) && fixture.evidenceRoles.length > 0),
    validation('Fixture evidence roles use stable vocabulary', ({ fixture }) => unknownEvidenceRoles(fixture).length === 0 || unknownEvidenceRoles(fixture)),
    validation('Fixture purpose explains the evidence role', ({ fixture }) => typeof fixture.purpose === 'string' && fixture.purpose.length > 50),
    validation('Fixture semantic status is modeled or diagnosed', ({ fixture }) => ['modeled', 'diagnosed'].includes(fixture.semanticStatus)),
    validation('Fixture coverage contains at least one family', ({ fixture }) => Array.isArray(fixture.coverage) && fixture.coverage.length > 0),
    validation('Fixture purpose names at least one coverage family', ({ fixture }) => purposeMentionsCoverage(fixture), ({ fixture }) => Array.isArray(fixture.coverage) && typeof fixture.purpose === 'string'),
    validation('Fixture source path is recorded', ({ fixture }) => typeof fixture.lottie === 'string' && fixture.lottie.endsWith('.json')),
    validation('Fixture lottie-web intent path is recorded', ({ fixture }) => typeof fixture.lottieWebIntent === 'string' && fixture.lottieWebIntent.endsWith('.json')),
    validation('Fixture renderer is svg', ({ fixture }) => fixture.renderer === 'svg'),
    validation('Fixture selected frames carry rationale', ({ fixture }) => Array.isArray(fixture.frames) && fixture.frames.every((frame) => Number.isFinite(Number(frame.frame)) && typeof frame.rationale === 'string' && frame.rationale.length > 20)),
    validation('Fixture reference non-empty expectation is true', ({ fixture }) => fixture.expectReferenceNonEmpty === true),
    validation('Modeled fixtures are source-validation eligible', ({ fixture }) => fixture.expectedValidationEligible === true, ({ fixture }) => fixture.semanticStatus === 'modeled'),
    validation('Modeled fixtures carry conformance evidence', ({ fixture }) => fixture.evidenceRoles.includes('conformance'), ({ fixture }) => fixture.semanticStatus === 'modeled' && Array.isArray(fixture.evidenceRoles)),
    validation('Modeled fixtures do not carry unsupported-feature evidence', ({ fixture }) => !fixture.evidenceRoles.includes('unsupported-feature'), ({ fixture }) => fixture.semanticStatus === 'modeled' && Array.isArray(fixture.evidenceRoles)),
    validation('Diagnosed fixtures are not source-validation eligible', ({ fixture }) => fixture.expectedValidationEligible === false, ({ fixture }) => fixture.semanticStatus === 'diagnosed'),
    validation('Diagnosed fixtures carry unsupported-feature evidence', ({ fixture }) => fixture.evidenceRoles.includes('unsupported-feature'), ({ fixture }) => fixture.semanticStatus === 'diagnosed' && Array.isArray(fixture.evidenceRoles)),
    validation('Diagnosed fixtures do not carry conformance evidence', ({ fixture }) => !fixture.evidenceRoles.includes('conformance'), ({ fixture }) => fixture.semanticStatus === 'diagnosed' && Array.isArray(fixture.evidenceRoles)),
    validation('Visual-inspection fixtures require non-empty references', ({ fixture }) => fixture.expectReferenceNonEmpty === true, ({ fixture }) => Array.isArray(fixture.evidenceRoles) && fixture.evidenceRoles.includes('visual-inspection')),
    validation('Engine-divergence fixtures declare divergence ids', ({ fixture }) => Array.isArray(fixture.divergenceIDs) && fixture.divergenceIDs.length > 0 && fixture.divergenceIDs.every((id) => typeof id === 'string' && id.length > 0), ({ fixture }) => Array.isArray(fixture.evidenceRoles) && fixture.evidenceRoles.includes('engine-divergence'))
  ], context);
}

function validateRecordedUsability(fixture, index) {
  return applyValidations([
    validation('Fixture validation status is usable', ({ fixture }) => fixture.validation?.status === validationStatus.usable),
    validation('Usable fixtures have no failure reasons', ({ fixture }) => Array.isArray(fixture.validation?.failureReasons) && fixture.validation.failureReasons.length === 0, ({ fixture }) => fixture.validation?.status === validationStatus.usable),
    validation('Fixture source JSON parse status is parses', ({ fixture }) => fixture.validation?.sourceJSON === 'parses'),
    validation('Fixture lottie-web load status is loads', ({ fixture }) => fixture.validation?.lottieWeb === 'loads'),
    validation('Fixture numeric intent status is committed', ({ fixture }) => fixture.validation?.numericIntent === 'committed'),
    validation('Fixture reference non-empty status is passed', ({ fixture }) => fixture.validation?.referenceNonEmpty === 'passed')
  ], { fixture, path: manifestPath(index, 'validation') });
}

function validateSourceDocument({ fixture, index, sourcePath }) {
  let source;
  try {
    source = readJson(sourcePath);
  } catch (error) {
    return [failure('Fixture source JSON parses', fixture, manifestPath(index, 'lottie'), error.message)];
  }

  return applyValidations([
    validation('Fixture source has Lottie root keys', ({ source }) => ['v', 'fr', 'ip', 'op', 'w', 'h', 'layers'].every((key) => Object.hasOwn(source, key))),
    validation('Fixture frame rate is positive', ({ source }) => Number(source.fr) > 0),
    validation('Fixture root frame window is positive', ({ source }) => Number(source.op) > Number(source.ip)),
    validation('Fixture dimensions are positive', ({ source }) => Number(source.w) > 0 && Number(source.h) > 0),
    validation('Fixture layers are present', ({ source }) => Array.isArray(source.layers) && source.layers.length > 0)
  ], { fixture, source, path: manifestPath(index, 'lottie') });
}

function validateCommittedIntent({ fixture, index, intentPath, sourcePath }) {
  let intent;
  try {
    intent = readJson(intentPath);
  } catch (error) {
    return [failure('Committed lottie-web intent trace parses', fixture, manifestPath(index, 'lottieWebIntent'), error.message)];
  }

  const sourceRelativeToRepo = fixture.lottie;
  return applyValidations([
    validation('Committed intent trace has schema name purelottie.lottie-web-intent', ({ intent }) => intent.schema?.name === 'purelottie.lottie-web-intent'),
    validation('Committed intent trace has schema version 1', ({ intent }) => intent.schema?.version === 1),
    validation('Committed intent trace points at the manifest source path', ({ intent }) => intent.source === sourceRelativeToRepo),
    validation('Committed intent trace uses the manifest renderer', ({ intent }) => intent.renderer === fixture.renderer),
    validation('Committed intent trace uses lottie-web 5.13.0', ({ intent }) => intent.lottieWeb?.version === '5.13.0'),
    validation('Committed intent trace frame list matches the manifest', ({ intent }) => JSON.stringify((intent.frames ?? []).map((frame) => frame.frame)) === JSON.stringify(frameList(fixture))),
    validation('Committed intent trace has visible painted paths for every selected frame', ({ intent }) => (intent.frames ?? []).every((frame) => Number(frame.pathCount) > 0 && visiblePaintPathCount(frame) > 0))
  ], {
    fixture,
    intent,
    path: manifestPath(index, 'lottieWebIntent'),
    sourcePath
  });
}

async function validateLiveLottieWeb({ fixture, index, sourcePath, intentPath, sampleCount }) {
  let committedIntent;
  try {
    committedIntent = readJson(intentPath);
  } catch (error) {
    return [failure('Committed lottie-web intent trace parses before live validation', fixture, manifestPath(index, 'lottieWebIntent'), error.message)];
  }

  let liveIntent;
  try {
    liveIntent = await extractLottieIntent({
      input: sourcePath,
      frames: frameList(fixture),
      scale: Number(fixture.scale ?? 1),
      renderer: fixture.renderer ?? 'svg',
      sampleCount
    });
  } catch (error) {
    return [failure('Fixture loads in pinned lottie-web', fixture, manifestPath(index, 'lottie'), error.message)];
  }

  return applyValidations([
    validation('Live lottie-web version matches the pinned package', ({ liveIntent }) => liveIntent.lottieWeb?.version === '5.13.0'),
    validation('Live lottie-web frame list matches the manifest', ({ liveIntent }) => JSON.stringify(liveIntent.frames.map((frame) => frame.frame)) === JSON.stringify(frameList(fixture))),
    validation('Live lottie-web dimensions match the committed trace', ({ liveIntent }) => liveIntent.width === committedIntent.width && liveIntent.height === committedIntent.height),
    validation('Live lottie-web layer counts match committed trace', ({ liveIntent }) => JSON.stringify(liveIntent.frames.map((frame) => frame.layerCount)) === JSON.stringify(committedIntent.frames.map((frame) => frame.layerCount))),
    validation('Live lottie-web path counts match committed trace', ({ liveIntent }) => JSON.stringify(liveIntent.frames.map((frame) => frame.pathCount)) === JSON.stringify(committedIntent.frames.map((frame) => frame.pathCount))),
    validation('Live lottie-web selected frames have visible painted paths when required', ({ liveIntent }) => liveIntent.frames.every((frame) => Number(frame.pathCount) > 0 && visiblePaintPathCount(frame) > 0), ({ fixture }) => fixture.expectReferenceNonEmpty === true)
  ], { fixture, liveIntent, path: manifestPath(index, 'lottie') });
}

export function loadFixtureManifest(oracleRoot = defaultOracleRoot) {
  return readJson(path.join(oracleRoot, 'oracle-fixtures.json'));
}

function loadReferenceDivergenceLedger(oracleRoot = defaultOracleRoot) {
  return readJson(path.join(oracleRoot, 'reference-divergences.json'));
}

export async function validateFixtureCorpus({
  oracleRoot = defaultOracleRoot,
  fixtures = null,
  checkLottieWeb = false,
  sampleCount = 128
} = {}) {
  const manifest = fixtures ?? loadFixtureManifest(oracleRoot);
  const divergenceLedger = loadReferenceDivergenceLedger(oracleRoot);
  const divergenceByID = new Map((divergenceLedger.divergences ?? []).map((entry) => [entry.id, entry]));
  const errors = [];
  const ids = new Set();
  const duplicateIDs = new Set();
  const statuses = {};

  for (const fixture of manifest) {
    if (ids.has(fixture.id)) {
      duplicateIDs.add(fixture.id);
    }
    ids.add(fixture.id);
    statuses[fixture.validation?.status ?? '<missing>'] = (statuses[fixture.validation?.status ?? '<missing>'] ?? 0) + 1;
  }

  for (const id of duplicateIDs) {
    errors.push(failure('Fixture ids are unique', { id }, 'oracle-fixtures.json', id));
  }

  for (const [index, fixture] of manifest.entries()) {
    const sourcePath = resolveFromOracleRoot(oracleRoot, fixture.lottie ?? '');
    const intentPath = resolveFromOracleRoot(oracleRoot, fixture.lottieWebIntent ?? '');

    errors.push(...validateManifestShape(fixture, index));
    errors.push(...validateRecordedUsability(fixture, index));
    if (Array.isArray(fixture.evidenceRoles) && fixture.evidenceRoles.includes('engine-divergence')) {
      for (const divergenceID of fixture.divergenceIDs ?? []) {
        const divergence = divergenceByID.get(divergenceID);
        if (!divergence) {
          errors.push(failure('Engine-divergence fixtures reference known divergence ids', fixture, manifestPath(index, 'divergenceIDs'), divergenceID));
        } else if (!(divergence.fixtures ?? []).includes(fixture.id)) {
          errors.push(failure('Engine-divergence fixtures are back-referenced by the divergence ledger', fixture, manifestPath(index, 'divergenceIDs'), divergenceID));
        }
      }
    }

    if (!fs.existsSync(sourcePath)) {
      errors.push(failure('Fixture source path exists', fixture, manifestPath(index, 'lottie'), path.relative(oracleRoot, sourcePath)));
    } else {
      errors.push(...validateSourceDocument({ fixture, index, sourcePath }));
    }

    if (!fs.existsSync(intentPath)) {
      errors.push(failure('Committed lottie-web intent path exists', fixture, manifestPath(index, 'lottieWebIntent'), path.relative(oracleRoot, intentPath)));
    } else {
      errors.push(...validateCommittedIntent({ fixture, index, intentPath, sourcePath }));
    }

    if (checkLottieWeb && fs.existsSync(sourcePath) && fs.existsSync(intentPath)) {
      errors.push(...await validateLiveLottieWeb({ fixture, index, sourcePath, intentPath, sampleCount }));
    }
  }

  return {
    ok: errors.length === 0,
    fixtureCount: manifest.length,
    lottieWebChecked: checkLottieWeb,
    statuses,
    errors
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const result = await validateFixtureCorpus({
    checkLottieWeb: hasFlag('--check-lottie-web'),
    sampleCount: Number(readArgument('--sample-count') ?? '128')
  });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.ok) {
    process.exitCode = 1;
  }
}
