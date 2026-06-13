import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { chromium } from 'playwright';

const require = createRequire(import.meta.url);
const lottieBundle = require.resolve('lottie-web/build/player/lottie.js');
const lottiePackage = require('lottie-web/package.json');
const playwrightPackage = require('playwright/package.json');
const playwrightCorePath = require.resolve('playwright-core/package.json');
const browsersPath = path.join(path.dirname(playwrightCorePath), 'browsers.json');
const browsersData = JSON.parse(fs.readFileSync(browsersPath, 'utf8'));
const chromiumInfo = browsersData.browsers.find((b) => b.name === 'chromium');
const chromiumRevision = chromiumInfo ? chromiumInfo.revision : 'unknown';

const moduleDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(moduleDir, '../../..');

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

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

export async function extractLottieIntent({
  input,
  source = input,
  output = null,
  frames,
  scale = 1,
  renderer = 'svg',
  sampleCount = 1024
}) {
  const animationData = JSON.parse(fs.readFileSync(input, 'utf8'));
  const width = Math.max(1, Number(animationData.w) || 1);
  const height = Math.max(1, Number(animationData.h) || 1);

  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({
      viewport: { width: Math.ceil(width), height: Math.ceil(height) },
      deviceScaleFactor: scale
    });

    await page.setContent(`
      <!doctype html>
      <html>
        <head>
          <meta charset="utf-8">
          <style>
            html, body {
              width: ${width}px;
              height: ${height}px;
              margin: 0;
              padding: 0;
              overflow: hidden;
              background: transparent;
            }
            #stage {
              width: ${width}px;
              height: ${height}px;
              overflow: hidden;
              background: transparent;
            }
          </style>
        </head>
        <body>
          <div id="stage"></div>
        </body>
      </html>
    `);
    await page.addScriptTag({ path: lottieBundle });
    await page.evaluate(
      ({ animationData: data, rendererName }) => new Promise((resolve, reject) => {
        if (typeof window.lottie.setSubframe === 'function') {
          window.lottie.setSubframe(false);
        }
        const animation = window.lottie.loadAnimation({
          container: document.getElementById('stage'),
          renderer: rendererName,
          loop: false,
          autoplay: false,
          animationData: data,
          rendererSettings: {
            preserveAspectRatio: 'xMinYMin meet',
            progressiveLoad: false
          }
        });
        window.__purelottieOracleAnimation = animation;
        const timeout = window.setTimeout(() => reject(new Error('lottie-web DOMLoaded timeout')), 10000);
        animation.addEventListener('DOMLoaded', () => {
          window.clearTimeout(timeout);
          resolve();
        });
        animation.addEventListener('data_failed', () => {
          window.clearTimeout(timeout);
          reject(new Error('lottie-web failed to load animation data'));
        });
      }),
      { animationData, rendererName: renderer }
    );

    const extractedFrames = [];
    for (const frame of frames) {
      await page.evaluate(
        (selectedFrame) => new Promise((resolve) => {
          window.__purelottieOracleAnimation.goToAndStop(selectedFrame, true);
          window.requestAnimationFrame(() => window.requestAnimationFrame(resolve));
        }),
        frame
      );
      extractedFrames.push(await page.evaluate(collectFrameIntent, { frame, scale, sampleCount }));
    }

    const result = {
      schema: {
        name: 'purelottie.lottie-web-intent',
        version: 1
      },
      source,
      renderer,
      lottieWeb: {
        package: `npm:lottie-web@${lottiePackage.version}`,
        version: lottiePackage.version
      },
      width,
      height,
      scale,
      coordinateSemantics: [
        'stageBounds and svgBounds are CSS pixel coordinates with the stage origin at (0, 0).',
        'sampledOutputBounds equals sampledCompositionBounds multiplied by deviceScaleFactor.',
        'path.sampledCompositionBounds uses getTotalLength/getPointAtLength and getScreenCTM, not raster pixels.',
        'path.strokeExpandedCompositionBounds expands sampled path bounds by half the computed stroke width when a stroke is visible.',
        'layer.matrix is lottie-web finalTransform.mat.props and uses lottie-web internal matrix order.',
        'mask.pathD is lottie-web generated SVG mask path data in the target layer local coordinate space; mask opacity is normalized to 0...1.',
        'matte.sourceRenderElementIndex and matte.targetRenderElementIndex use lottie-web renderer element order; implicit mattes resolve to the previous renderer element.',
        'precomposition.renderedFrame is lottie-web precomp element renderedFrame after start-time, stretch, and time-remap handling in the child composition frame domain.',
        'trim.startFraction, trim.endFraction, and trim.offsetTurns are lottie-web shape modifier values after percentage and degree normalization.',
        'trim.selectedSegments are not exposed as stable lottie-web SVG runtime objects; compare normalized trim facts with the rendered SVG path records and diagnostics.'
      ],
      frames: extractedFrames
    };

    const canonicalString = JSON.stringify(result);
    const contentHash = crypto.createHash('sha256').update(canonicalString).digest('hex');

    const cleanedArgv = process.argv.map((arg, idx) => {
      if (idx === 0) return 'node';
      if (idx === 1) return path.relative(repoRoot, arg);
      if (path.isAbsolute(arg) && arg.startsWith(repoRoot)) {
        return path.relative(repoRoot, arg);
      }
      return arg;
    });

    result.provenance = {
      lottieWeb: `npm:lottie-web@${lottiePackage.version}`,
      playwright: `npm:playwright@${playwrightPackage.version}`,
      chromiumRevision: chromiumRevision,
      renderer,
      scale,
      sampleCount,
      frames,
      command: cleanedArgv.join(' '),
      contentHash: `sha256:${contentHash}`
    };

    if (output) {
      writeJson(output, result);
    }
    return result;
  } finally {
    await browser.close();
  }
}

function collectFrameIntent({ frame, scale, sampleCount }) {
  function numberOrNull(value) {
    const number = Number(value);
    if (Number.isFinite(number)) {
      return number;
    }
    if (typeof value === 'string') {
      const parsed = Number.parseFloat(value);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  }

  function matrixRecord(matrix) {
    if (!matrix) {
      return null;
    }
    return {
      a: numberOrNull(matrix.a),
      b: numberOrNull(matrix.b),
      c: numberOrNull(matrix.c),
      d: numberOrNull(matrix.d),
      e: numberOrNull(matrix.e),
      f: numberOrNull(matrix.f)
    };
  }

  function pointByMatrix(matrix, point) {
    if (!matrix) {
      return point;
    }
    return {
      x: matrix.a * point.x + matrix.c * point.y + matrix.e,
      y: matrix.b * point.x + matrix.d * point.y + matrix.f
    };
  }

  function boundsFromPoints(points) {
    if (!points.length) {
      return null;
    }
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const point of points) {
      minX = Math.min(minX, point.x);
      minY = Math.min(minY, point.y);
      maxX = Math.max(maxX, point.x);
      maxY = Math.max(maxY, point.y);
    }
    return { minX, minY, maxX, maxY, width: maxX - minX, height: maxY - minY };
  }

  function scaleBounds(bounds, factor) {
    if (!bounds) {
      return null;
    }
    return {
      minX: bounds.minX * factor,
      minY: bounds.minY * factor,
      maxX: bounds.maxX * factor,
      maxY: bounds.maxY * factor,
      width: bounds.width * factor,
      height: bounds.height * factor
    };
  }

  function expandBounds(bounds, radius) {
    if (!bounds || !Number.isFinite(radius) || radius <= 0) {
      return bounds;
    }
    return {
      minX: bounds.minX - radius,
      minY: bounds.minY - radius,
      maxX: bounds.maxX + radius,
      maxY: bounds.maxY + radius,
      width: bounds.width + radius * 2,
      height: bounds.height + radius * 2
    };
  }

  function safeBBox(element) {
    try {
      const box = element.getBBox();
      return {
        minX: box.x,
        minY: box.y,
        maxX: box.x + box.width,
        maxY: box.y + box.height,
        width: box.width,
        height: box.height
      };
    } catch {
      return null;
    }
  }

  function safeClientBounds(element) {
    try {
      const rect = element.getBoundingClientRect();
      return {
        minX: rect.left,
        minY: rect.top,
        maxX: rect.right,
        maxY: rect.bottom,
        width: rect.width,
        height: rect.height
      };
    } catch {
      return null;
    }
  }

  function safeTotalLength(element) {
    try {
      return element.getTotalLength();
    } catch {
      return null;
    }
  }

  function transformScale(matrix) {
    if (!matrix) {
      return 1;
    }
    const xScale = Math.hypot(matrix.a, matrix.b);
    const yScale = Math.hypot(matrix.c, matrix.d);
    return Math.max(xScale, yScale);
  }

  function ancestorChain(element) {
    const chain = [];
    let current = element;
    while (current && current.id !== 'stage') {
      chain.push({
        tag: current.tagName,
        id: current.id || null,
        className: typeof current.className === 'object' ? current.className.baseVal : current.className || null,
        transform: current.getAttribute('transform'),
        opacity: current.getAttribute('opacity'),
        style: current.getAttribute('style')
      });
      current = current.parentElement;
    }
    return chain;
  }

  function collectPath(element, index) {
    const style = window.getComputedStyle(element);
    const ctm = element.getScreenCTM();
    const bbox = safeBBox(element);
    const length = safeTotalLength(element);
    const localSamples = [];

    if (Number.isFinite(length) && length > 0) {
      const steps = Math.max(1, Number(sampleCount));
      for (let index = 0; index <= steps; index += 1) {
        const point = element.getPointAtLength((length * index) / steps);
        localSamples.push({ x: point.x, y: point.y });
      }
    }

    if (bbox) {
      localSamples.push(
        { x: bbox.minX, y: bbox.minY },
        { x: bbox.maxX, y: bbox.minY },
        { x: bbox.maxX, y: bbox.maxY },
        { x: bbox.minX, y: bbox.maxY }
      );
    }

    const compositionSamples = localSamples.map((point) => pointByMatrix(ctm, point));
    const sampledCompositionBounds = boundsFromPoints(compositionSamples);
    const strokeWidth = numberOrNull(style.strokeWidth);
    const strokeOpacity = numberOrNull(style.strokeOpacity) ?? 1;
    const hasStroke = style.stroke !== 'none' && strokeOpacity > 0 && Number(strokeWidth || 0) > 0;
    const strokeRadius = hasStroke ? (strokeWidth * transformScale(ctm)) / 2 : 0;
    const strokeExpandedCompositionBounds = expandBounds(sampledCompositionBounds, strokeRadius);

    return {
      index,
      tag: element.tagName,
      id: element.id || null,
      className: typeof element.className === 'object' ? element.className.baseVal : element.className || null,
      visible: style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity) > 0,
      d: element.getAttribute('d') || '',
      transform: element.getAttribute('transform'),
      pathLength: length,
      localBBox: bbox,
      clientBounds: safeClientBounds(element),
      ctm: matrixRecord(ctm),
      sampledLocalBounds: boundsFromPoints(localSamples),
      sampledCompositionBounds,
      sampledOutputBounds: scaleBounds(sampledCompositionBounds, scale),
      strokeExpandedCompositionBounds,
      strokeExpandedOutputBounds: scaleBounds(strokeExpandedCompositionBounds, scale),
      style: {
        fill: style.fill,
        fillOpacity: numberOrNull(style.fillOpacity),
        fillRule: style.fillRule,
        opacity: numberOrNull(style.opacity),
        stroke: style.stroke,
        strokeOpacity: numberOrNull(style.strokeOpacity),
        strokeWidth,
        strokeLinecap: style.strokeLinecap,
        strokeLinejoin: style.strokeLinejoin,
        strokeMiterlimit: numberOrNull(style.strokeMiterlimit),
        strokeDasharray: style.strokeDasharray,
        strokeDashoffset: style.strokeDashoffset,
        display: style.display,
        visibility: style.visibility
      },
      ancestors: ancestorChain(element)
    };
  }

  function collectLayer(element, index) {
    const data = element?.data || {};
    const matrix = element?.finalTransform?.mat?.props;
    return {
      index,
      name: data.nm || null,
      type: data.ty ?? null,
      ind: data.ind ?? null,
      inPoint: data.ip ?? null,
      outPoint: data.op ?? null,
      startTime: data.st ?? null,
      renderedFrame: element?.comp?.renderedFrame ?? null,
      opacity: element?.finalTransform?.mProp?.o?.v ?? null,
      matrix: matrix ? Array.from(matrix) : null,
      layerElementBounds: element?.layerElement ? safeClientBounds(element.layerElement) : null
    };
  }

  function collectMasks(element, renderElementIndex) {
    const manager = element?.maskManager;
    if (!manager) {
      return [];
    }
    return Array.from(manager.masksProperties || []).map((mask, maskIndex) => {
      const view = manager.viewData?.[maskIndex];
      const pathValue = view?.prop?.v;
      return {
        renderElementIndex,
        layerInd: element?.data?.ind ?? null,
        layerName: element?.data?.nm ?? null,
        maskIndex,
        name: mask?.nm ?? null,
        mode: mask?.mode ?? null,
        inverted: Boolean(mask?.inv),
        closed: pathValue?.c ?? null,
        opacity: numberOrNull(view?.op?.v),
        expansion: numberOrNull(view?.x?.v ?? mask?.x?.k ?? 0),
        pathD: view?.elem?.getAttribute?.('d') ?? null,
        localBBox: view?.elem ? safeBBox(view.elem) : null,
        vertexCount: pathValue?._length ?? null
      };
    });
  }

  function collectMattes(elements) {
    return elements.flatMap((element, targetRenderElementIndex) => {
      const matteMode = element?.data?.tt;
      if (matteMode === undefined || matteMode === null) {
        return [];
      }
      const explicitSourceLayerIndex = element?.data?.tp ?? null;
      const sourceRenderElementIndex = explicitSourceLayerIndex === null
        ? targetRenderElementIndex - 1
        : elements.findIndex((candidate) => candidate?.data?.ind === explicitSourceLayerIndex);
      const source = sourceRenderElementIndex >= 0 ? elements[sourceRenderElementIndex] : null;
      return [{
        targetRenderElementIndex,
        targetLayerInd: element?.data?.ind ?? null,
        targetLayerName: element?.data?.nm ?? null,
        mode: matteMode,
        explicitSourceLayerIndex,
        sourceRenderElementIndex: sourceRenderElementIndex >= 0 ? sourceRenderElementIndex : null,
        sourceLayerInd: source?.data?.ind ?? null,
        sourceLayerName: source?.data?.nm ?? null,
        sourceLayerType: source?.data?.ty ?? null,
        sourceHidden: Boolean(source?.data?.hd),
        sourceResolved: Boolean(source),
        sourceIsMarker: Boolean(source?.data?.td)
      }];
    });
  }

  function collectPrecompositions(element, renderElementIndex) {
    if (element?.data?.ty !== 0) {
      return [];
    }
    return [{
      renderElementIndex,
      layerInd: element?.data?.ind ?? null,
      layerName: element?.data?.nm ?? null,
      refId: element?.data?.refId ?? null,
      startTime: numberOrNull(element?.data?.st),
      stretch: numberOrNull(element?.data?.sr),
      inPoint: numberOrNull(element?.data?.ip),
      outPoint: numberOrNull(element?.data?.op),
      renderedFrame: numberOrNull(element?.renderedFrame),
      timeRemapped: Boolean(element?.data?.tm),
      timeRemapValue: numberOrNull(element?.tm?.v),
      childLayerCount: Array.isArray(element?.layers) ? element.layers.length : null,
      builtChildElementCount: Array.isArray(element?.elements) ? element.elements.filter(Boolean).length : null
    }];
  }

  function collectTrims(element, renderElementIndex) {
    return Array.from(element?.shapeModifiers || []).flatMap((modifier, trimIndex) => {
      if (modifier?.s === undefined || modifier?.e === undefined || modifier?.o === undefined) {
        return [];
      }
      return [{
        renderElementIndex,
        layerInd: element?.data?.ind ?? null,
        layerName: element?.data?.nm ?? null,
        trimIndex,
        startFraction: numberOrNull(modifier.s?.v),
        endFraction: numberOrNull(modifier.e?.v),
        offsetTurns: numberOrNull(modifier.o?.v),
        mode: modifier.m ?? null,
        shapeCount: Array.isArray(modifier.shapes) ? modifier.shapes.length : null,
        animated: Boolean(modifier._isAnimated)
      }];
    });
  }

  function collectTrimDiagnostics(trims) {
    return trims.map((trim) => ({
      feature: 'trim.selectedSegments',
      reason: 'lottie-web SVG exposes normalized trim values and rendered path output, but not stable per-cubic selected segment internals.',
      renderElementIndex: trim.renderElementIndex,
      layerInd: trim.layerInd
    }));
  }

  const animation = window.__purelottieOracleAnimation;
  const svg = document.querySelector('#stage svg');
  const paths = Array.from(document.querySelectorAll('#stage svg path'))
    .map((element, index) => collectPath(element, index));
  const rendererElements = Array.from(animation?.renderer?.elements || []).filter(Boolean);
  const layers = rendererElements.map((element, index) => collectLayer(element, index));
  const masks = rendererElements.flatMap((element, index) => collectMasks(element, index));
  const mattes = collectMattes(rendererElements);
  const precompositions = rendererElements.flatMap((element, index) => collectPrecompositions(element, index));
  const trims = rendererElements.flatMap((element, index) => collectTrims(element, index));
  const diagnostics = collectTrimDiagnostics(trims);

  return {
    frame,
    currentFrame: animation?.currentFrame ?? null,
    renderedFrame: animation?.renderer?.renderedFrame ?? null,
    firstFrame: animation?.firstFrame ?? null,
    frameRate: animation?.frameRate ?? null,
    stageBounds: safeClientBounds(document.getElementById('stage')),
    svgBounds: svg ? safeClientBounds(svg) : null,
    svgViewBox: svg?.getAttribute('viewBox') ?? null,
    layerCount: layers.length,
    pathCount: paths.length,
    maskCount: masks.length,
    matteCount: mattes.length,
    precompositionCount: precompositions.length,
    trimCount: trims.length,
    layers,
    paths,
    masks,
    mattes,
    precompositions,
    trims,
    diagnostics
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const input = readArgument('--input');
  const output = readArgument('--output');
  const framesArgument = readArgument('--frames');
  const scale = Number(readArgument('--scale') ?? '1');
  const renderer = readArgument('--renderer') ?? 'svg';
  const sampleCount = Number(readArgument('--sample-count') ?? '1024');

  if (!input || !framesArgument) {
    throw new Error('Usage: node scripts/extract-intent.mjs --input <file> --frames 0,5,9 [--output intent.json] [--scale 1] [--renderer svg] [--sample-count 1024]');
  }

  const frames = framesArgument.split(',').map(Number);
  const summary = await extractLottieIntent({ input, output, frames, scale, renderer, sampleCount });
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}
