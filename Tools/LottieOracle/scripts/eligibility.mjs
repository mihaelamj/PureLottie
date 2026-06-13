export function backendEvidenceFindingCount(summary) {
  return (summary.renderIR ?? []).reduce(
    (count, frame) => count + Number(frame.backendEvidenceFindingCount ?? 0),
    0
  );
}

export function renderIRDiagnosticCount(summary) {
  return (summary.renderIR ?? []).reduce(
    (count, frame) => count + Number(frame.diagnosticCount ?? 0),
    0
  );
}

export function renderedArtifactManifestSummary(manifest) {
  const artifacts = Array.isArray(manifest?.artifacts) ? manifest.artifacts : [];
  return {
    present: manifest != null,
    schema: manifest?.schema ?? null,
    generatedFrameCount: manifest?.export?.generatedFrameCount ?? null,
    artifactCount: manifest == null ? null : artifacts.length,
    frameArtifactCount: manifest == null ? null : artifacts.filter((artifact) => artifact.kind === 'png-frame').length
  };
}

export function comparisonEligibility(input) {
  const evidence = normalizeEligibilityInput(input);
  const { summary, manifest, lottieWebIntent, frames } = evidence;
  const validationEligible = summary.validation?.eligible === true;
  const importClean = summary.importReport?.clean === true;
  const renderIRClean = renderIRDiagnosticCount(summary) === 0;
  const backendEvidenceClean = backendEvidenceFindingCount(summary) === 0;
  const evidenceResult = sourceIntentEvidenceEligibility(evidence);

  const reasons = [...evidenceResult.reasons];
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
  const allowed = validationEligible &&
    importClean &&
    renderIRClean &&
    backendEvidenceClean &&
    evidenceResult.sourceIntentEvidenceComplete &&
    reasons.length === 0;

  return {
    allowed,
    validationEligible,
    importClean,
    renderIRClean,
    backendEvidenceClean,
    semanticTraceComplete: evidenceResult.semanticTraceComplete,
    renderedArtifactManifestComplete: evidenceResult.renderedArtifactManifestComplete,
    lottieWebIntentComplete: evidenceResult.lottieWebIntentComplete,
    sourceIntentEvidenceComplete: evidenceResult.sourceIntentEvidenceComplete,
    selectedFrameCount: frames.length,
    renderIRDiagnosticCount: renderIRDiagnosticCount(summary),
    backendEvidenceFindingCount: backendEvidenceFindingCount(summary),
    reasons
  };
}

function normalizeEligibilityInput(input) {
  if (input?.summary) {
    const summary = input.summary;
    return {
      summary,
      manifest: input.manifest ?? input.renderedArtifactManifest ?? null,
      lottieWebIntent: input.lottieWebIntent ?? null,
      frames: selectedFrames(input.frames, summary, input.manifest ?? input.renderedArtifactManifest ?? null)
    };
  }
  const summary = input ?? {};
  return {
    summary,
    manifest: null,
    lottieWebIntent: null,
    frames: selectedFrames(null, summary, null)
  };
}

function selectedFrames(frames, summary, manifest) {
  if (Array.isArray(frames)) {
    return frames.map(Number);
  }
  if (Array.isArray(summary?.frameTiming?.samples)) {
    return summary.frameTiming.samples.map((sample) => Number(sample.sourceFrame));
  }
  if (Array.isArray(summary?.frames)) {
    return summary.frames.map((frame) => Number(frame.frame));
  }
  const artifacts = pngFrameArtifacts(manifest);
  if (artifacts.length > 0) {
    return artifacts.map((artifact) => Number(artifact.sourceFrame));
  }
  return [];
}

function sourceIntentEvidenceEligibility({ summary, manifest, lottieWebIntent, frames }) {
  const reasons = [];
  const summaryComplete = summaryFrameRowsComplete(summary, frames, reasons);
  const manifestComplete = manifestFrameRowsComplete(manifest, frames, reasons);
  const intentComplete = lottieWebIntentRowsComplete(lottieWebIntent, frames, reasons);
  return {
    semanticTraceComplete: summaryComplete,
    renderedArtifactManifestComplete: manifestComplete,
    lottieWebIntentComplete: intentComplete,
    sourceIntentEvidenceComplete: summaryComplete && manifestComplete && intentComplete,
    reasons
  };
}

function summaryFrameRowsComplete(summary, frames, reasons) {
  let complete = true;
  if (frames.length === 0) {
    reasons.push('selected frame list is missing');
    return false;
  }
  if (!Array.isArray(summary?.frameTiming?.samples) || summary.frameTiming.samples.length !== frames.length) {
    reasons.push('oracle-summary frameTiming samples do not match selected frames');
    complete = false;
  } else {
    summary.frameTiming.samples.forEach((sample, index) => {
      if (Number(sample.index) !== index || !numbersMatch(sample.sourceFrame, frames[index])) {
        reasons.push(`oracle-summary frameTiming row ${index} does not match selected frame ${frames[index]}`);
        complete = false;
      }
    });
  }
  if (!Array.isArray(summary?.renderIR) || summary.renderIR.length !== frames.length) {
    reasons.push('RenderIR semantic trace rows do not match selected frames');
    complete = false;
  } else {
    summary.renderIR.forEach((frame, index) => {
      if (!numbersMatch(frame.frame, frames[index])) {
        reasons.push(`RenderIR semantic trace row ${index} does not match selected frame ${frames[index]}`);
        complete = false;
      }
    });
  }
  return complete;
}

function manifestFrameRowsComplete(manifest, frames, reasons) {
  let complete = true;
  if (!manifest) {
    reasons.push('rendered artifact manifest is missing');
    return false;
  }
  if (manifest.schema?.name !== 'purelottie.rendered-artifact-manifest' || Number(manifest.schema?.version) !== 1) {
    reasons.push('rendered artifact manifest schema is unsupported');
    complete = false;
  }
  const artifacts = pngFrameArtifacts(manifest);
  if (Number(manifest.export?.generatedFrameCount) !== frames.length || artifacts.length !== frames.length) {
    reasons.push('rendered artifact manifest frame count does not match selected frames');
    complete = false;
  }
  artifacts.forEach((artifact, index) => {
    if (Number(artifact.frameIndex) !== index || !numbersMatch(artifact.sourceFrame, frames[index])) {
      reasons.push(`rendered artifact manifest artifact ${index} does not match selected frame ${frames[index]}`);
      complete = false;
    }
    const links = Array.isArray(artifact.evidenceLinks) ? artifact.evidenceLinks : [];
    if (!links.some((link) => evidenceLinkMatches(link, 'lottie-web-intent', index, frames[index]))) {
      reasons.push(`rendered artifact manifest artifact ${index} lacks matching lottie-web intent evidence`);
      complete = false;
    }
    if (!links.some((link) => (link.kind === 'geometry-json' || link.kind === 'geometry-csv') && evidenceLinkMatches(link, link.kind, index, frames[index]))) {
      reasons.push(`rendered artifact manifest artifact ${index} lacks matching geometry evidence`);
      complete = false;
    }
  });
  return complete;
}

function lottieWebIntentRowsComplete(lottieWebIntent, frames, reasons) {
  let complete = true;
  if (!lottieWebIntent) {
    reasons.push('lottie-web intent trace is missing');
    return false;
  }
  if (lottieWebIntent.schema?.name !== 'purelottie.lottie-web-intent' || Number(lottieWebIntent.schema?.version) !== 1) {
    reasons.push('lottie-web intent trace schema is unsupported');
    complete = false;
  }
  if (!Array.isArray(lottieWebIntent.frames) || lottieWebIntent.frames.length !== frames.length) {
    reasons.push('lottie-web intent trace rows do not match selected frames');
    return false;
  }
  lottieWebIntent.frames.forEach((row, index) => {
    if (!numbersMatch(row.frame, frames[index])) {
      reasons.push(`lottie-web intent trace row ${index} does not match selected frame ${frames[index]}`);
      complete = false;
    }
  });
  return complete;
}

function pngFrameArtifacts(manifest) {
  return (Array.isArray(manifest?.artifacts) ? manifest.artifacts : [])
    .filter((artifact) => artifact.kind === 'png-frame');
}

function evidenceLinkMatches(link, kind, frameIndex, sourceFrame) {
  return link?.kind === kind &&
    Number(link.frameIndex) === frameIndex &&
    numbersMatch(link.sourceFrame, sourceFrame) &&
    typeof link.rowAddress === 'string' &&
    link.rowAddress === `$.frames[${frameIndex}]`;
}

function numbersMatch(lhs, rhs) {
  return Number.isFinite(Number(lhs)) &&
    Number.isFinite(Number(rhs)) &&
    Math.abs(Number(lhs) - Number(rhs)) <= 0.000001;
}
