#!/usr/bin/env node
// #2806: gera a marca a partir de scripts/brand/capitulo.mjs, o simbolo "Capitulo".
//
//   node scripts/generate-app-icons.mjs
//
// Saidas:
//   public/brand/nucleo-simbolo-{principal,reduzido}[-negativo].svg, para a comunicacao;
//   public/favicon.svg (versao reduzida; as sementes azuis ficam brancas no tema escuro) e public/favicon.ico (16, 32
//   e 48 px, para o navegador que nao le SVG);
//   public/icons/app-192.png e app-512.png (purpose any, cantos arredondados, simbolo principal em negativo);
//   public/icons/app-maskable-512.png (purpose maskable, fundo ate a borda, simbolo dentro da zona segura de 80%, que o
//   sistema recorta em circulo ou squircle);
//   public/icons/apple-touch-180.png (opaco e ate a borda: o iOS arredonda sozinho e pinta de preto o que e transparente).
import sharp from 'sharp';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { NAVY, symbol, svgDocument, faviconSvg, appIcons, FAVICON_ICO_SIZES } from './brand/capitulo.mjs';

const PUBLIC = resolve(process.cwd(), 'public');
const WHITE = '#FFFFFF';
mkdirSync(resolve(PUBLIC, 'brand'), { recursive: true });
mkdirSync(resolve(PUBLIC, 'icons'), { recursive: true });

for (const name of ['principal', 'reduzido']) {
  writeFileSync(resolve(PUBLIC, `brand/nucleo-simbolo-${name}.svg`), svgDocument(symbol(name)));
  writeFileSync(resolve(PUBLIC, `brand/nucleo-simbolo-${name}-negativo.svg`), svgDocument(symbol(name, { base: WHITE })));
}
writeFileSync(resolve(PUBLIC, 'favicon.svg'), faviconSvg());

// fundo azul (rx 0 = ate a borda) com o simbolo principal em negativo, centrado, com `mark` px de lado
async function tile(size, { radius, mark, opaque }) {
  const off = (size - mark) / 2;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">` +
    `<rect width="${size}" height="${size}" rx="${radius}" fill="${NAVY}"/>` +
    `<svg x="${off}" y="${off}" width="${mark}" height="${mark}" viewBox="0 0 100 100">${symbol('principal', { base: WHITE })}</svg></svg>`;
  let img = sharp(Buffer.from(svg));
  if (opaque) img = img.flatten({ background: NAVY });
  return img.png({ compressionLevel: 9 }).toBuffer();
}

// .ico com uma imagem PNG por tamanho (o formato aceita PNG dentro desde o Windows Vista)
async function ico(sizes) {
  const pngs = await Promise.all(sizes.map((s) => sharp(Buffer.from(svgDocument(symbol('reduzido'), { size: s }))).png({ compressionLevel: 9 }).toBuffer()));
  const head = Buffer.alloc(6 + 16 * sizes.length);
  head.writeUInt16LE(0, 0);
  head.writeUInt16LE(1, 2);
  head.writeUInt16LE(sizes.length, 4);
  let offset = head.length;
  sizes.forEach((s, i) => {
    const e = 6 + 16 * i;
    head.writeUInt8(s % 256, e);
    head.writeUInt8(s % 256, e + 1);
    head.writeUInt16LE(1, e + 4);
    head.writeUInt16LE(32, e + 6);
    head.writeUInt32LE(pngs[i].length, e + 8);
    head.writeUInt32LE(offset, e + 12);
    offset += pngs[i].length;
  });
  return Buffer.concat([head, ...pngs]);
}

const jobs = [...appIcons().map((i) => [i.file, tile(i.size, i)]), ['favicon.ico', ico(FAVICON_ICO_SIZES)]];
for (const [file, job] of jobs) {
  const buf = await job;
  writeFileSync(resolve(PUBLIC, file), buf);
  console.log(`${file} ${buf.length} bytes`);
}
