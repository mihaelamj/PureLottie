import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { chromium } from 'playwright';
import { frameFileName } from './compare-images.mjs';

const require = createRequire(import.meta.url);
const lottieBundle = require.resolve('lottie-web/build/player/lottie.js');
const lottiePackage = require('lottie-web/package.json');

export async function renderReferenceFrames({ input, output, frames, scale = 1, renderer = 'svg' }) {
  const animationData = JSON.parse(fs.readFileSync(input, 'utf8'));
  const width = Math.max(1, Number(animationData.w) || 1);
  const height = Math.max(1, Number(animationData.h) || 1);
  fs.mkdirSync(output, { recursive: true });

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

    const written = [];
    for (const frame of frames) {
      await page.evaluate(
        (selectedFrame) => new Promise((resolve) => {
          window.__purelottieOracleAnimation.goToAndStop(selectedFrame, true);
          window.requestAnimationFrame(() => window.requestAnimationFrame(resolve));
        }),
        frame
      );
      const file = frameFileName(frame);
      await page.locator('#stage').screenshot({
        path: path.join(output, file),
        omitBackground: true
      });
      written.push({ frame, file });
    }

    return {
      renderer,
      lottieWebVersion: lottiePackage.version,
      width,
      height,
      scale,
      frames: written
    };
  } finally {
    await browser.close();
  }
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

if (import.meta.url === `file://${process.argv[1]}`) {
  const input = readArgument('--input');
  const output = readArgument('--output');
  const framesArgument = readArgument('--frames');
  const scale = Number(readArgument('--scale') ?? '1');
  const renderer = readArgument('--renderer') ?? 'svg';

  if (!input || !output || !framesArgument) {
    throw new Error('Usage: node scripts/render-reference.mjs --input <file> --output <dir> --frames 0,5,9 [--scale 1] [--renderer svg]');
  }

  const frames = framesArgument.split(',').map(Number);
  const summary = await renderReferenceFrames({ input, output, frames, scale, renderer });
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}
