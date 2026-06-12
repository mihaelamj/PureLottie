import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { comparePngDirectories } from './compare-images.mjs';
import { backendEvidenceFindingCount, comparisonEligibility } from './eligibility.mjs';
import { extractLottieIntent } from './extract-intent.mjs';
import { renderReferenceFrames } from './render-reference.mjs';

const require = createRequire(import.meta.url);
const lottiePackage = require('lottie-web/package.json');
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const oracleRoot = path.dirname(scriptDirectory);
const repoRoot = path.dirname(path.dirname(oracleRoot));
const manifestPath = path.join(oracleRoot, 'oracle-fixtures.json');

function hasFlag(name) {
  return process.argv.includes(name);
}

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

function loadSelectedFixtures() {
  const fixtures = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (hasFlag('--all')) {
    return fixtures;
  }
  const selected = readArgument('--fixture') ?? fixtures[0]?.id;
  const fixture = fixtures.find((candidate) => candidate.id === selected);
  if (!fixture) {
    throw new Error(`Unknown fixture '${selected}'. Known fixtures: ${fixtures.map((entry) => entry.id).join(', ')}`);
  }
  return [fixture];
}

function frameList(fixture) {
  return fixture.frames.map((entry) => Number(entry.frame));
}

function resolveFromOracleRoot(relativePath) {
  return path.resolve(oracleRoot, relativePath);
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function markdownReport(report) {
  const frameRows = report.selectedFrames
    .map((entry) => `| ${entry.frame} | ${entry.rationale} |`)
    .join('\n');
  const comparisonRows = report.comparison.frames
    .map((entry) => `| ${entry.frame} | ${entry.status} | ${entry.changedPixels ?? 'n/a'} | ${entry.maxChannelDelta ?? 'n/a'} | ${entry.diffFile ?? 'n/a'} |`)
    .join('\n');
  const reasons = report.comparisonEligibility.reasons.length === 0
    ? 'Comparison allowed: validation, import report, and RenderIR diagnostics are clean.'
    : `Comparison skipped: ${report.comparisonEligibility.reasons.join('; ')}.`;

  return `# Lottie Oracle Report: ${report.id}

## Authority

- lottie-web: \`${report.lottieWeb.package}\`
- Renderer: \`${report.lottieWeb.renderer}\`
- Source fixture: \`${report.source.fixture}\`

## Frame Count

${report.frameCount.explanation}

## Selected Frames

| Frame | Rationale |
| ---: | --- |
${frameRows}

## Validation Eligibility

- Eligible: \`${report.validation.eligible}\`
- Validation errors: \`${report.validation.errorCount}\`
- Import findings: \`${report.importReport.findingCount}\`
- RenderIR diagnostics: \`${report.renderIRDiagnosticCount}\`
- RenderIR backend evidence findings: \`${report.backendEvidenceFindingCount}\`
- Reference non-empty check: \`${report.referenceIntegrity.status}\`

${reasons}

## Comparison

| Frame | Status | Changed pixels | Max channel delta | Diff artifact |
| ---: | --- | ---: | ---: | --- |
${comparisonRows || '| n/a | skipped | n/a | n/a | n/a |'}

## Trace Context

Numeric lottie-web intent is written to \`${path.basename(report.artifacts.lottieWebIntent)}\`. Semantic trace context is written to \`${path.basename(report.artifacts.semanticTraces)}\`. Mismatch-only trace context is written to \`${path.basename(report.artifacts.mismatchTraces)}\` when any frame differs.
`;
}

async function runFixture(fixture, options) {
  const fixturePath = resolveFromOracleRoot(fixture.lottie);
  const outputRoot = path.resolve(options.output, fixture.id);
  const pureLayerDir = path.join(outputRoot, 'purelayer');
  const referenceDir = path.join(outputRoot, 'reference');
  const diffDir = path.join(outputRoot, 'diff');
  const frames = frameList(fixture);
  const framesArgument = frames.join(',');
  const scale = Number(fixture.scale ?? 1);
  const renderer = fixture.renderer ?? 'svg';

  fs.mkdirSync(outputRoot, { recursive: true });
  execFileSync(
    'swift',
    [
      'run',
      'LottieFrameDump',
      '--input',
      fixturePath,
      '--output',
      pureLayerDir,
      '--frames',
      framesArgument,
      '--scale',
      String(scale)
    ],
    { cwd: repoRoot, stdio: 'inherit' }
  );

  const reference = await renderReferenceFrames({
    input: fixturePath,
    output: referenceDir,
    frames,
    scale,
    renderer
  });
  const lottieWebIntentFile = path.join(outputRoot, 'lottie-web-intent.json');
  const lottieWebIntent = await extractLottieIntent({
    input: fixturePath,
    output: lottieWebIntentFile,
    frames,
    scale,
    renderer
  });

  const summary = JSON.parse(fs.readFileSync(path.join(pureLayerDir, 'oracle-summary.json'), 'utf8'));
  const eligibility = comparisonEligibility(summary);
  const comparisons = eligibility.allowed
    ? comparePngDirectories({
      referenceDir,
      actualDir: pureLayerDir,
      diffDir,
      frames,
      tolerance: options.tolerance
    })
    : [];
  const emptyReferenceFrames = comparisons
    .filter((entry) => Number(entry.referenceAlphaPixels ?? 0) === 0)
    .map((entry) => entry.frame);
  const referenceIntegrity = {
    expectNonEmpty: fixture.expectReferenceNonEmpty === true,
    status: fixture.expectReferenceNonEmpty === true && emptyReferenceFrames.length > 0 ? 'failed' : 'passed',
    emptyReferenceFrames
  };

  const renderIRDiagnosticCount = (summary.renderIR ?? []).reduce(
    (count, frame) => count + Number(frame.diagnosticCount ?? 0),
    0
  );
  const backendEvidenceCount = backendEvidenceFindingCount(summary);
  const semanticTraces = {
    id: fixture.id,
    frames: summary.renderIR
  };
  const mismatchFrames = new Set(comparisons.filter((entry) => entry.status !== 'match').map((entry) => entry.frame));
  const mismatchTraces = {
    id: fixture.id,
    frames: (summary.renderIR ?? []).filter((frame) => mismatchFrames.has(frame.frame))
  };

  const semanticTraceFile = path.join(outputRoot, 'semantic-traces.json');
  const mismatchTraceFile = path.join(outputRoot, 'mismatch-traces.json');
  writeJson(semanticTraceFile, semanticTraces);
  writeJson(mismatchTraceFile, mismatchTraces);

  const report = {
    id: fixture.id,
    description: fixture.description,
    source: {
      fixture: path.relative(repoRoot, fixturePath)
    },
    lottieWeb: {
      package: `npm:lottie-web@${lottiePackage.version}`,
      renderer,
      version: lottiePackage.version
    },
    frameCount: {
      declared: summary.composition.sourceFrameCount,
      inPoint: summary.composition.inPoint,
      outPoint: summary.composition.outPoint,
      frameRate: summary.composition.frameRate,
      explanation: `The root declares ip=${summary.composition.inPoint}, op=${summary.composition.outPoint}, and Lottie's root frame window is half-open, so integer source frames satisfy ip <= frame < op. That yields ${summary.composition.sourceFrameCount} source frames; this oracle selects ${frames.length} diagnostic frames rather than every frame.`
    },
    selectedFrames: fixture.frames,
    validation: summary.validation,
    importReport: summary.importReport,
    renderIRDiagnosticCount,
    backendEvidenceFindingCount: backendEvidenceCount,
    referenceIntegrity,
    comparisonEligibility: eligibility,
    comparison: {
      tolerance: options.tolerance,
      frames: comparisons
    },
    reference,
    lottieWebIntent: {
      schema: lottieWebIntent.schema,
      lottieWeb: lottieWebIntent.lottieWeb,
      frameCount: lottieWebIntent.frames.length,
      layerCounts: lottieWebIntent.frames.map((entry) => entry.layerCount),
      pathCounts: lottieWebIntent.frames.map((entry) => entry.pathCount)
    },
    artifacts: {
      outputRoot,
      referenceDir,
      pureLayerDir,
      diffDir,
      lottieWebIntent: lottieWebIntentFile,
      semanticTraces: semanticTraceFile,
      mismatchTraces: mismatchTraceFile
    }
  };

  writeJson(path.join(outputRoot, 'comparison-report.json'), report);
  fs.writeFileSync(path.join(outputRoot, 'comparison-report.md'), markdownReport(report));
  return report;
}

const output = path.resolve(readArgument('--output') ?? path.join(oracleRoot, 'artifacts'));
const tolerance = Number(readArgument('--tolerance') ?? '0');
const failOnMismatch = hasFlag('--fail-on-mismatch');
const reports = [];

for (const fixture of loadSelectedFixtures()) {
  reports.push(await runFixture(fixture, { output, tolerance }));
}

const mismatches = reports.flatMap((report) => report.comparison.frames.filter((entry) => entry.status !== 'match'));
const referenceIntegrityFailures = reports.filter((report) => report.referenceIntegrity.status !== 'passed');
process.stdout.write(`${JSON.stringify({
  output,
  fixtureCount: reports.length,
  mismatches: mismatches.length,
  referenceIntegrityFailures: referenceIntegrityFailures.length
}, null, 2)}\n`);
if (referenceIntegrityFailures.length > 0) {
  process.exitCode = 1;
}
if (failOnMismatch && mismatches.length > 0) {
  process.exitCode = 1;
}
