// tests/contracts/2806-simbolo-capitulo-nos-icones.test.mjs
/**
 * #2806: o app instalavel e a aba do navegador usam o simbolo do Nucleo ("Capitulo"), gerado por
 * scripts/generate-app-icons.mjs a partir de scripts/brand/capitulo.mjs. Antes, favicon.svg e favicon.ico eram o logo
 * padrao do Astro e os icones do app eram provisorios. Prende:
 *
 *   1. favicon.svg e o simbolo reduzido que a fonte gera, nunca o do Astro; favicon.ico e um .ico com 16, 32 e 48 px;
 *   2. os SVG de public/brand sao os que a fonte gera, byte a byte;
 *   3. o manifest aponta para PNG que existem, do tamanho declarado, com any e maskable; o apple-touch do layout e o
 *      PNG de 180 px opaco, so no host instalavel;
 *   4. os PNG desenham o simbolo da fonte (o nucleo e a cabeca de cada semente na cor certa, na posicao calculada), e
 *      o maskable nao tem nada do simbolo fora da zona segura de 80%. So o pixel do centro nao bastava: o icone
 *      provisorio "IA & GP" tambem tinha laranja ali, e a mutacao que o trazia de volta passava;
 *   5. a regra do desenho: respiro de 1 px a 16 px na reduzida, nucleo livre, nada cortado pela borda, e o braco
 *      laranja comeca na semente mais perto do nucleo.
 *
 * (4) e (5) medem o resultado (pixels e geometria), nao o texto do gerador.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import sharp from 'sharp';
import { NAVY, ORANGE, symbol, svgDocument, faviconSvg, measure, seeds, appIcons } from '../../scripts/brand/capitulo.mjs';

const path = (p) => resolve(process.cwd(), p);
const read = (p) => readFileSync(path(p), 'utf8');
const ASTRO_FAVICON = 'M50.4 78.5a75.1 75.1 0 0 0-28.5 6.9l24.2-65.7';

// IHDR do PNG: largura, altura e tipo de cor (2 = RGB sem alfa, 6 = RGBA)
function png(buf) {
  assert.equal(buf.subarray(1, 4).toString('latin1'), 'PNG', 'nao e PNG');
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20), colorType: buf.readUInt8(25) };
}

function icoEntries(ico) {
  return Array.from({ length: ico.readUInt16LE(4) }, (_, i) => {
    const e = 6 + 16 * i;
    return { declared: ico.readUInt8(e), data: ico.subarray(ico.readUInt32LE(e + 12), ico.readUInt32LE(e + 12) + ico.readUInt32LE(e + 8)) };
  });
}

const hex = (d, i) => '#' + [d[i], d[i + 1], d[i + 2]].map((x) => x.toString(16).padStart(2, '0')).join('').toUpperCase();
async function pixels(buf) {
  const { data, info } = await sharp(buf).raw().toBuffer({ resolveWithObject: true });
  return { at: (x, y) => hex(data, (y * info.width + x) * info.channels), info };
}

test('#2806 (1) o favicon e o simbolo reduzido, nunca o do Astro', () => {
  const svg = read('public/favicon.svg');
  assert.ok(!svg.includes(ASTRO_FAVICON), 'public/favicon.svg voltou a ser o logo do Astro');
  assert.equal(svg, faviconSvg(), 'public/favicon.svg difere do que scripts/brand/capitulo.mjs gera: rode o gerador');

  const ico = readFileSync(path('public/favicon.ico'));
  assert.deepEqual([ico.readUInt16LE(0), ico.readUInt16LE(2)], [0, 1], 'public/favicon.ico nao e um .ico (o do Astro era um PNG)');
  const entries = icoEntries(ico);
  assert.deepEqual(entries.map((e) => png(e.data).width), [16, 32, 48], 'favicon.ico sem os tamanhos 16, 32 e 48');
  for (const e of entries) assert.equal(png(e.data).width, e.declared, 'a entrada do .ico declara um tamanho e traz outro');
});

test('#2806 (2) os SVG da marca sao os que a fonte gera', () => {
  for (const name of ['principal', 'reduzido']) {
    assert.equal(read(`public/brand/nucleo-simbolo-${name}.svg`), svgDocument(symbol(name)), `${name}.svg: rode o gerador`);
    assert.equal(read(`public/brand/nucleo-simbolo-${name}-negativo.svg`), svgDocument(symbol(name, { base: '#FFFFFF' })), `${name}-negativo.svg: rode o gerador`);
  }
});

test('#2806 (3) manifest e apple-touch apontam para PNG do tamanho declarado', () => {
  const manifest = JSON.parse(read('public/manifest.webmanifest'));
  for (const icon of manifest.icons) {
    const file = path(`public${icon.src}`);
    assert.ok(existsSync(file), `${icon.src} nao existe`);
    const img = png(readFileSync(file));
    assert.equal(`${img.width}x${img.height}`, icon.sizes, `${icon.src}: o tamanho real difere do manifest`);
  }
  assert.deepEqual([...new Set(manifest.icons.map((i) => i.purpose))].sort(), ['any', 'maskable'], 'o manifest precisa de icone any e maskable');

  const layout = read('src/layouts/BaseLayout.astro');
  assert.match(layout, /<link rel="icon" type="image\/svg\+xml" href="\/favicon\.svg" \/>/);
  assert.match(layout, /\{isInstallHost && <link rel="apple-touch-icon" href="\/icons\/apple-touch-180\.png" \/>\}/);
  const touch = png(readFileSync(path('public/icons/apple-touch-180.png')));
  assert.deepEqual([touch.width, touch.height, touch.colorType], [180, 180, 2], 'apple-touch: 180 px e opaco (o iOS pinta o transparente de preto)');
});

// a cabeca de cada semente, na posicao que a fonte calcula, tem de estar na cor da semente; o centro, no nucleo
function paintedLikeTheSource(name, { at, off, mark, base }) {
  const px = (u) => Math.floor(off + (u * mark) / 100);
  const wrong = [];
  if (at(px(50), px(50)) !== ORANGE) wrong.push('nucleo');
  for (const s of seeds(name)) {
    if (at(px(s.x), px(s.y)) !== (s.orange ? ORANGE : base)) wrong.push(`semente ${s.n}`);
  }
  return wrong;
}

test('#2806 (4) os PNG desenham o simbolo da fonte e o maskable respeita a zona segura', async () => {
  for (const icon of appIcons()) {
    const { at } = await pixels(readFileSync(path(`public/${icon.file}`)));
    const wrong = paintedLikeTheSource('principal', { at, off: (icon.size - icon.mark) / 2, mark: icon.mark, base: '#FFFFFF' });
    assert.deepEqual(wrong, [], `${icon.file}: fora da cor da fonte em ${wrong.join(', ')}`);
  }
  const ico48 = icoEntries(readFileSync(path('public/favicon.ico'))).find((e) => e.declared === 48);
  const favicon = await pixels(ico48.data);
  const wrongIco = paintedLikeTheSource('reduzido', { at: favicon.at, off: 0, mark: 48, base: NAVY });
  assert.deepEqual(wrongIco, [], `favicon.ico 48 px: fora da cor da fonte em ${wrongIco.join(', ')}`);

  // fora do circulo de raio 40% (a zona segura de 80% do maskable) so pode haver o fundo azul
  const mask = await pixels(readFileSync(path('public/icons/app-maskable-512.png')));
  const { width, height } = mask.info, r0 = 0.4 * width;
  let outside = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (Math.hypot(x + 0.5 - width / 2, y + 0.5 - height / 2) > r0 && mask.at(x, y) !== NAVY) outside++;
    }
  }
  assert.equal(outside, 0, `${outside} pixels do simbolo fora da zona segura do maskable`);
});

test('#2806 (5) a regra do desenho: respiro, nucleo livre, nada cortado e o braco laranja', () => {
  const reduzido = measure('reduzido');
  const principal = measure('principal');
  assert.ok(reduzido.pair >= 6, `reduzida: respiro de ${reduzido.pair.toFixed(2)} < 6 em 100 (1 px a 16 px)`);
  assert.ok(principal.pair >= 2.3, `principal: respiro de ${principal.pair.toFixed(2)} < 2,3 em 100`);
  assert.ok(reduzido.core > 0 && principal.core > 0, 'semente encostando no nucleo');
  assert.ok(reduzido.reach < 50 && principal.reach < 50, 'semente cortada pela borda do quadro');
  assert.deepEqual(seeds('principal').filter((s) => s.orange).map((s) => s.n), [1, 6, 11], 'principal: o braco laranja mudou');
  assert.deepEqual(seeds('reduzido').filter((s) => s.orange).map((s) => s.n), [1, 6], 'reduzida: o braco laranja mudou');
});
