import test from 'node:test';
import assert from 'node:assert/strict';
import {
  backendEvidenceFindingCount,
  comparisonEligibility,
  renderedArtifactManifestSummary
} from '../scripts/eligibility.mjs';

test('comparison eligibility blocks RenderIR backend evidence', () => {
  const evidence = cleanEvidence();
  evidence.summary.renderIR[0].backendEvidenceFindingCount = 2;

  const eligibility = comparisonEligibility(evidence);
  assert.equal(backendEvidenceFindingCount(evidence.summary), 2);
  assert.equal(eligibility.allowed, false);
  assert.equal(eligibility.backendEvidenceClean, false);
  assert.equal(eligibility.backendEvidenceFindingCount, 2);
  assert.deepEqual(eligibility.reasons, ['RenderIR-to-PureLayer lowering produced backend gap evidence']);
});

test('comparison eligibility allows clean semantic and source-intent evidence', () => {
  const eligibility = comparisonEligibility(cleanEvidence());

  assert.equal(eligibility.allowed, true);
  assert.equal(eligibility.backendEvidenceClean, true);
  assert.equal(eligibility.semanticTraceComplete, true);
  assert.equal(eligibility.renderedArtifactManifestComplete, true);
  assert.equal(eligibility.lottieWebIntentComplete, true);
  assert.equal(eligibility.sourceIntentEvidenceComplete, true);
  assert.equal(eligibility.reasons.length, 0);
});

test('comparison eligibility rejects summary-only evidence even when PNG files would exist', () => {
  const evidence = cleanEvidence();

  const eligibility = comparisonEligibility(evidence.summary);

  assert.equal(eligibility.allowed, false);
  assert.equal(eligibility.sourceIntentEvidenceComplete, false);
  assert.deepEqual(eligibility.reasons, [
    'rendered artifact manifest is missing',
    'lottie-web intent trace is missing'
  ]);
});

test('comparison eligibility rejects manifest artifacts without source-intent links', () => {
  const evidence = cleanEvidence();
  evidence.manifest.artifacts[0].evidenceLinks = evidence.manifest.artifacts[0].evidenceLinks
    .filter((link) => link.kind !== 'lottie-web-intent');

  const eligibility = comparisonEligibility(evidence);

  assert.equal(eligibility.allowed, false);
  assert.equal(eligibility.renderedArtifactManifestComplete, false);
  assert.deepEqual(eligibility.reasons, [
    'rendered artifact manifest artifact 0 lacks matching lottie-web intent evidence'
  ]);
});

test('comparison eligibility rejects lottie-web intent row drift', () => {
  const evidence = cleanEvidence();
  evidence.lottieWebIntent.frames[1].frame = 6;

  const eligibility = comparisonEligibility(evidence);

  assert.equal(eligibility.allowed, false);
  assert.equal(eligibility.lottieWebIntentComplete, false);
  assert.deepEqual(eligibility.reasons, [
    'lottie-web intent trace row 1 does not match selected frame 5'
  ]);
});

test('comparison eligibility rejects incomplete RenderIR semantic trace coverage', () => {
  const evidence = cleanEvidence();
  evidence.summary.renderIR.pop();

  const eligibility = comparisonEligibility(evidence);

  assert.equal(eligibility.allowed, false);
  assert.equal(eligibility.semanticTraceComplete, false);
  assert.deepEqual(eligibility.reasons, [
    'RenderIR semantic trace rows do not match selected frames'
  ]);
});

test('rendered artifact manifest summary records missing evidence instead of throwing', () => {
  const summary = renderedArtifactManifestSummary(null);

  assert.deepEqual(summary, {
    present: false,
    schema: null,
    generatedFrameCount: null,
    artifactCount: null,
    frameArtifactCount: null
  });
});

test('rendered artifact manifest summary counts frame artifacts only when evidence exists', () => {
  const evidence = cleanEvidence();
  evidence.manifest.artifacts.push({ kind: 'oracle-summary' });

  const summary = renderedArtifactManifestSummary(evidence.manifest);

  assert.equal(summary.present, true);
  assert.deepEqual(summary.schema, {
    name: 'purelottie.rendered-artifact-manifest',
    version: 1
  });
  assert.equal(summary.generatedFrameCount, 2);
  assert.equal(summary.artifactCount, 3);
  assert.equal(summary.frameArtifactCount, 2);
});

function cleanEvidence() {
  const frames = [0, 5];
  return {
    frames,
    summary: {
      validation: { eligible: true },
      importReport: { clean: true },
      frameTiming: {
        samples: frames.map((frame, index) => ({
          index,
          sourceFrame: frame,
          timeSeconds: index * 0.5
        }))
      },
      renderIR: frames.map((frame) => ({
        frame,
        diagnosticCount: 0,
        backendEvidenceFindingCount: 0
      }))
    },
    manifest: {
      schema: {
        name: 'purelottie.rendered-artifact-manifest',
        version: 1
      },
      export: {
        generatedFrameCount: frames.length
      },
      artifacts: frames.map((frame, index) => ({
        kind: 'png-frame',
        path: `frame_000${index === 0 ? '0' : '5'}.00.png`,
        frameIndex: index,
        sourceFrame: frame,
        timeSeconds: index * 0.5,
        evidenceLinks: [
          {
            kind: 'lottie-web-intent',
            path: '../lottie-web-intent.json',
            frameIndex: index,
            sourceFrame: frame,
            timeSeconds: index * 0.5,
            rowAddress: `$.frames[${index}]`
          },
          {
            kind: 'geometry-json',
            path: 'purelayer-geometry.json',
            frameIndex: index,
            sourceFrame: frame,
            timeSeconds: index * 0.5,
            rowAddress: `$.frames[${index}]`
          }
        ]
      }))
    },
    lottieWebIntent: {
      schema: {
        name: 'purelottie.lottie-web-intent',
        version: 1
      },
      frames: frames.map((frame) => ({ frame }))
    }
  };
}
