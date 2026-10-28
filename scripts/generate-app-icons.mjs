#!/usr/bin/env node
// #2806: gera os icones do app instalavel (manifest) a partir de um SVG tipografico nas cores do site
// (--color-navy #003B5C, --color-orange #FF610F). Icone PROVISORIO: o Nucleo nao tem arquivo de logo no
// repositorio, e trocar e so substituir os PNG em public/icons/ (ou mudar o SVG abaixo e rodar de novo).
//
//   node scripts/generate-app-icons.mjs
//
// Saidas: app-192.png e app-512.png (purpose any, cantos arredondados) e app-maskable-512.png (purpose maskable,
// fundo ate a borda e o conteudo dentro da zona segura de 80%, que o sistema recorta em circulo ou squircle).
import sharp from 'sharp';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

const OUT = resolve(process.cwd(), 'public/icons');
const NAVY = '#003B5C';
const ORANGE = '#FF610F';

function svg({ size, radius, scale }) {
  const c = size / 2;
  const s = (n) => Math.round(n * scale * (size / 512));
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <rect width="${size}" height="${size}" rx="${radius}" fill="${NAVY}"/>
  <text x="${c}" y="${c + s(40)}" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-weight="700"
        font-size="${s(230)}" fill="${ORANGE}" letter-spacing="${s(-6)}">IA</text>
  <text x="${c}" y="${c + s(150)}" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-weight="700"
        font-size="${s(84)}" fill="#FFFFFF" letter-spacing="${s(4)}">&amp; GP</text>
</svg>`;
}

mkdirSync(OUT, { recursive: true });
const jobs = [
  { file: 'app-192.png', size: 192, radius: 36, scale: 1 },
  { file: 'app-512.png', size: 512, radius: 96, scale: 1 },
  { file: 'app-maskable-512.png', size: 512, radius: 0, scale: 0.78 },
];
for (const j of jobs) {
  await sharp(Buffer.from(svg(j))).png({ compressionLevel: 9 }).toFile(resolve(OUT, j.file));
  const meta = await sharp(resolve(OUT, j.file)).metadata();
  console.log(`${j.file} ${meta.width}x${meta.height}`);
}
