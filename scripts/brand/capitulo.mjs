// #2806: o simbolo do Nucleo, "Capitulo". Na botanica, a cabeca do girassol se chama capitulo. As sementes ficam no
// angulo de ouro (137,5 graus) umas das outras, e por isso as espirais aparecem sozinhas. O nucleo e um braco da
// espiral sao laranja. Duas versoes do mesmo desenho: a principal, de 48 px para cima, e a reduzida, de 16 a 32 px,
// com menos sementes e mais respiro entre as pecas para nao grudarem em 16 px.
//
// Este arquivo e a fonte da marca: scripts/generate-app-icons.mjs gera daqui os SVG de public/brand, o favicon e os
// icones do app. Mudou o desenho, rode o gerador; o guard 2806-simbolo-capitulo compara os arquivos com esta fonte.

export const NAVY = '#003B5C';
export const ORANGE = '#FF610F';
const GOLDEN_ANGLE = 137.50776405;
const ARM = 5; // o braco laranja e a familia de espiral n % 5 === 1, que comeca na semente mais perto do nucleo
const ARM_PHASE = 1;
const ROUND = 0.35; // traco da cor da semente que arredonda a ponta da cauda, em unidades da semente

// semente: cabeca de raio 1 na origem e cauda curva; as duas bordas saem da cabeca na tangente
const SEED = { tip: [2.4, 1.7], b1: [1, 1], b2: [2.04, 2.3], t1: [2.22, 0.44], t2: [1.2, -1] };

// raios em unidades de um quadro de 100; s0 e s1 sao o raio da cabeca da primeira e da ultima semente
export const VERSIONS = {
  principal: { seeds: 14, rIn: 18, rOut: 41.5, core: 11, s0: 3.598, s1: 5.14, tilt: 70, turn: 90 },
  reduzido: { seeds: 7, rIn: 28, rOut: 39, core: 14, s0: 5.79, s1: 5.79, tilt: 40, turn: 90 },
};

const f = (n) => Math.round(n * 1000) / 1000;
const pt = (p) => p.map(f).join(' ');
const SEED_PATH = `M0 -1A1 1 0 0 0 0 1C${pt(SEED.b1)} ${pt(SEED.b2)} ${pt(SEED.tip)}C${pt(SEED.t1)} ${pt(SEED.t2)} 0 -1Z`;

// densidade de area uniforme no anel entre rIn e rOut, a semente n girada n vezes o angulo de ouro
export function seeds(name) {
  const v = VERSIONS[name];
  const out = [];
  for (let n = 1; n <= v.seeds; n++) {
    const t = (n - 0.5) / (v.seeds - 0.5);
    const r = Math.sqrt(v.rIn * v.rIn + (v.rOut * v.rOut - v.rIn * v.rIn) * t);
    const th = n * GOLDEN_ANGLE + v.turn;
    const rad = (th * Math.PI) / 180;
    out.push({ n, x: 50 + r * Math.cos(rad), y: 50 + r * Math.sin(rad), rot: th + v.tilt, s: v.s0 + (v.s1 - v.s0) * t, orange: n % ARM === ARM_PHASE });
  }
  return out;
}

// baseClass troca o fill/stroke das sementes azuis por uma classe (o favicon muda de cor no tema escuro)
export function symbol(name, { base = NAVY, accent = ORANGE, baseClass = null } = {}) {
  const v = VERSIONS[name];
  let out = `<circle cx="50" cy="50" r="${f(v.core)}" fill="${accent}"/>`;
  for (const s of seeds(name)) {
    const paint = s.orange ? `fill="${accent}" stroke="${accent}"` : baseClass ? `class="${baseClass}"` : `fill="${base}" stroke="${base}"`;
    out += `<path d="${SEED_PATH}" transform="translate(${f(s.x)} ${f(s.y)}) rotate(${f(s.rot)}) scale(${f(s.s)})" ${paint} stroke-width="${ROUND}" stroke-linejoin="round"/>`;
  }
  return out;
}

export function svgDocument(inner, { size = null } = {}) {
  const dims = size ? ` width="${size}" height="${size}"` : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"${dims} role="img" aria-label="Núcleo">${inner}</svg>\n`;
}

// os PNG do app: fundo azul (rx 0 = ate a borda) com o simbolo principal em negativo, `mark` px de lado, centrado.
// O maskable cabe na zona segura de 80% (raio 40%) com folga: o ponto mais distante do centro fica a 38%.
export function appIcons() {
  const maskable = Math.floor((0.38 * 512 * 100) / measure('principal').reach);
  return [
    { file: 'icons/app-192.png', size: 192, radius: 36, mark: 138, opaque: false },
    { file: 'icons/app-512.png', size: 512, radius: 96, mark: 368, opaque: false },
    { file: 'icons/app-maskable-512.png', size: 512, radius: 0, mark: maskable, opaque: true },
    { file: 'icons/apple-touch-180.png', size: 180, radius: 0, mark: 130, opaque: true },
  ];
}
export const FAVICON_ICO_SIZES = [16, 32, 48];

export function faviconSvg() {
  const style = `<style>.b{fill:${NAVY};stroke:${NAVY}}@media (prefers-color-scheme:dark){.b{fill:#FFFFFF;stroke:#FFFFFF}}</style>`;
  return svgDocument(style + symbol('reduzido', { baseClass: 'b' }));
}

// contorno de cada semente no quadro de 100, para medir respiro e o raio ocupado
function cubic(p0, p1, p2, p3, t) {
  const u = 1 - t;
  return [0, 1].map((i) => u * u * u * p0[i] + 3 * u * u * t * p1[i] + 3 * u * t * t * p2[i] + t * t * t * p3[i]);
}
const OUTLINE = (() => {
  const pts = [];
  for (let i = 0; i <= 24; i++) { const a = -Math.PI / 2 - (Math.PI * i) / 24; pts.push([Math.cos(a), Math.sin(a)]); }
  for (let i = 1; i <= 24; i++) pts.push(cubic([0, 1], SEED.b1, SEED.b2, SEED.tip, i / 24));
  for (let i = 1; i < 24; i++) pts.push(cubic(SEED.tip, SEED.t1, SEED.t2, [0, -1], i / 24));
  return pts;
})();

function outlines(name) {
  return seeds(name).map((s) => {
    const a = (s.rot * Math.PI) / 180, c = Math.cos(a), si = Math.sin(a);
    return { pad: (ROUND / 2) * s.s, pts: OUTLINE.map(([px, py]) => [s.x + s.s * (px * c - py * si), s.y + s.s * (px * si + py * c)]) };
  });
}

// menor respiro entre duas sementes, entre semente e nucleo, e o raio mais distante do centro, no quadro de 100
export function measure(name) {
  const v = VERSIONS[name];
  const polys = outlines(name);
  let pair = Infinity, core = Infinity, reach = 0;
  for (let i = 0; i < polys.length; i++) {
    for (const p of polys[i].pts) {
      const d = Math.hypot(p[0] - 50, p[1] - 50);
      core = Math.min(core, d - v.core - polys[i].pad);
      reach = Math.max(reach, d + polys[i].pad);
    }
    for (let j = i + 1; j < polys.length; j++) {
      const pad = polys[i].pad + polys[j].pad;
      for (const p of polys[i].pts) for (const q of polys[j].pts) pair = Math.min(pair, Math.hypot(p[0] - q[0], p[1] - q[1]) - pad);
    }
  }
  return { pair, core, reach };
}
