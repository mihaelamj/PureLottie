import test from 'node:test';
import assert from 'node:assert/strict';
import { backendEvidenceFindingCount, comparisonEligibility } from '../scripts/eligibility.mjs';

test('comparison eligibility blocks RenderIR backend evidence', () => {
  const summary = {
    validation: { eligible: true },
    importReport: { clean: true },
    renderIR: [
      {
        diagnosticCount: 0,
        backendEvidenceFindingCount: 2
      }
    ]
  };

  const eligibility = comparisonEligibility(summary);
  assert.equal(backendEvidenceFindingCount(summary), 2);
  assert.equal(eligibility.allowed, false);
  assert.equal(eligibility.backendEvidenceClean, false);
  assert.equal(eligibility.backendEvidenceFindingCount, 2);
  assert.deepEqual(eligibility.reasons, ['RenderIR-to-PureLayer lowering produced backend gap evidence']);
});

test('comparison eligibility allows clean validation import RenderIR and backend evidence', () => {
  const summary = {
    validation: { eligible: true },
    importReport: { clean: true },
    renderIR: [
      {
        diagnosticCount: 0,
        backendEvidenceFindingCount: 0
      }
    ]
  };

  const eligibility = comparisonEligibility(summary);
  assert.equal(eligibility.allowed, true);
  assert.equal(eligibility.backendEvidenceClean, true);
  assert.equal(eligibility.reasons.length, 0);
});
