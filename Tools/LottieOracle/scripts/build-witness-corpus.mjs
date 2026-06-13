import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { extractLottieIntent } from './extract-intent.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const oracleRoot = path.dirname(scriptDirectory);
const manifestPath = path.join(oracleRoot, 'witness-corpus.json');

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function resolveFromOracleRoot(relativePath) {
  return path.resolve(oracleRoot, relativePath);
}

const manifest = readJson(manifestPath);
for (const entry of manifest.entries) {
  await extractLottieIntent({
    input: resolveFromOracleRoot(entry.lottie),
    source: entry.lottie,
    output: resolveFromOracleRoot(entry.lottieWebIntent),
    frames: entry.frames.map((frame) => Number(frame.frame)),
    scale: 1,
    renderer: 'svg'
  });
  process.stdout.write(`witness-corpus: wrote ${entry.id}\n`);
}
