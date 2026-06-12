export function backendEvidenceFindingCount(summary) {
  return (summary.renderIR ?? []).reduce(
    (count, frame) => count + Number(frame.backendEvidenceFindingCount ?? 0),
    0
  );
}

export function comparisonEligibility(summary) {
  const validationEligible = summary.validation?.eligible === true;
  const importClean = summary.importReport?.clean === true;
  const renderIRClean = (summary.renderIR ?? []).every((frame) => frame.diagnosticCount === 0);
  const backendEvidenceClean = backendEvidenceFindingCount(summary) === 0;

  const reasons = [];
  if (!validationEligible) {
    reasons.push('validation reported silent-risk or invalid source features');
  }
  if (!importClean) {
    reasons.push('PureLayer import report contains skipped or approximated features');
  }
  if (!renderIRClean) {
    reasons.push('RenderIR contains semantic diagnostics for selected frames');
  }
  if (!backendEvidenceClean) {
    reasons.push('RenderIR-to-PureLayer lowering produced backend gap evidence');
  }

  return {
    allowed: reasons.length === 0,
    validationEligible,
    importClean,
    renderIRClean,
    backendEvidenceClean,
    backendEvidenceFindingCount: backendEvidenceFindingCount(summary),
    reasons
  };
}
