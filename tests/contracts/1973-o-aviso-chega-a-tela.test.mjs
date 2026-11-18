// tests/contracts/1973-o-aviso-chega-a-tela.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1973 — a mensagem de erro precisa CHEGAR à tela.
 *
 * O que aconteceu em 24/08/2026: um entrevistador conduziu a entrevista, clicou em concluir,
 * e a página recarregou no mesmo ponto sem dizer nada. O servidor tinha respondido
 * `Unauthorized: not an assigned interviewer` (causa na #1972), o handler tinha capturado o
 * erro corretamente e chamado `toast(e.message, 'error')` — e a mensagem morreu ali.
 *
 * O MECANISMO, e ele é banal: `src/components/ui/Toast.astro` renderiza `<div id="toast">` e
 * define `window.toast`. Mas `selection.astro` definia uma função `toast()` LOCAL procurando
 * `#toast-container`, id que não existe em lugar nenhum. A local SOMBREIA a global, cai num
 * `if (!el) return`, e **as 87 chamadas daquela tela evaporavam** — sucesso e erro.
 *
 * O portão funcionou. A superfície jogou a frase fora. É por isso que este guard existe:
 * um canal de feedback que falha em silêncio é indistinguível de um sistema que não faz nada.
 *
 * Cross-ref: #1973, #1972, #1838 (recusa no corpo lida como sucesso — a classe irmã).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();

function paginas(dir = 'src/pages', acc = []) {
  for (const e of readdirSync(resolve(ROOT, dir))) {
    const p = join(dir, e);
    if (statSync(resolve(ROOT, p)).isDirectory()) paginas(p, acc);
    else if (e.endsWith('.astro')) acc.push(p);
  }
  return acc;
}
const TODAS = paginas();
const ler = (p) => readFileSync(resolve(ROOT, p), 'utf8');

test('#1973: `toast-container` não é referenciado em lugar nenhum — o id nunca existiu', () => {
  // O componente canônico renderiza `id="toast"`. Qualquer busca por `toast-container` é
  // uma implementação local órfã, e ela falha em silêncio por construção.
  const ofensores = TODAS.filter((p) => {
    const src = ler(p);
    // ignora a citação em comentário (o histórico do defeito fica registrado de propósito)
    return /getElementById\(['"]toast-container['"]\)/.test(src);
  });
  assert.deepEqual(ofensores, [],
    `estas páginas procuram um id que não existe, então toda mensagem delas some:\n  ${ofensores.join('\n  ')}`);
});

test('#1973: quem define `toast()` local DELEGA ao global — não reimplementa contra um id', () => {
  const quebradas = [];
  for (const p of TODAS) {
    const src = ler(p);
    const m = src.match(/function toast\([^)]*\)\s*\{([\s\S]{0,400}?)\n\s*\}/);
    if (!m) continue;
    const corpo = m[1];
    const delega = /\(window as any\)\.toast\?\.|window\.toast\?\./.test(corpo);
    const alvoProprio = /getElementById\(['"]toast['"]\)/.test(corpo);
    if (!delega && !alvoProprio) quebradas.push(p);
  }
  assert.deepEqual(quebradas, [],
    'uma implementação local de toast contra um id próprio SOMBREIA a global e cala a tela:\n  ' +
    quebradas.join('\n  '));
});

// ── O Toast é montado UMA vez, no BaseLayout (17/11/2026) ────────────────────────────────────────────
// Até 17/11 cada página importava e renderizava o componente por conta própria, e o teste daqui só
// contava `toast(` sem ponto antes. A forma `(window as any).toast?.(...)` escapava dele: 15 páginas a
// chamavam sem montar o Toast (68 chamadas), e todas viravam no-op — inclusive o "Salvar" do modal
// de submissão em /publications, onde uma pesquisadora salvou três vezes o mesmo rascunho.
// Agora o BaseLayout monta o Toast, o AdminLayout envolve o BaseLayout, e a pergunta passa a ser:
// todo arquivo que chama toast é renderizado debaixo de um layout que o garante?

/** Arquivo sem comentário JS nem HTML, com offsets preservados. */
const semComentario = (src) => src
  .replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '))
  .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
  .replace(/^([ \t]*)\/\/[^\n]*/gm, (m, i) => i + ' '.repeat(m.length - i.length));

function arquivos(dir, exts, acc = []) {
  for (const e of readdirSync(resolve(ROOT, dir))) {
    const p = join(dir, e);
    if (statSync(resolve(ROOT, p)).isDirectory()) arquivos(p, exts, acc);
    else if (exts.some((x) => e.endsWith(x))) acc.push(p);
  }
  return acc;
}
const FONTES = arquivos('src', ['.astro', '.tsx', '.ts', '.jsx', '.js']);
const LAYOUTS = arquivos('src/layouts', ['.astro']);
const CANONICO = 'src/components/ui/Toast.astro';
// Chamada em qualquer forma: toast(, toast?.(, window.toast(, (window as any).toast?.(
const CHAMA = /(?<![A-Za-z0-9_$])toast\s*(?:\?\.)?\s*\(/g;
const RENDER = /^[ \t]*<Toast\s*\/>[ \t]*$/m;

/** Layouts que garantem o Toast: renderizam o componente, ou envolvem um layout que garante. */
function layoutsQueGarantem() {
  const ok = new Set();
  let mudou = true;
  while (mudou) {
    mudou = false;
    for (const l of LAYOUTS) {
      if (ok.has(l)) continue;
      const src = semComentario(ler(l));
      const nome = (x) => x.split('/').pop().replace('.astro', '');
      if ((RENDER.test(src) && /^import Toast from '\.\.\/components\/ui\/Toast\.astro';$/m.test(src))
          || [...ok].some((g) => new RegExp(`<${nome(g)}[\\s>]`).test(src))) {
        ok.add(l); mudou = true;
      }
    }
  }
  return ok;
}

/** Quem importa cada arquivo de src (import estático ou dinâmico, caminho relativo). */
function importadores() {
  const mapa = new Map();
  for (const f of FONTES) {
    const src = semComentario(ler(f));
    for (const m of src.matchAll(/(?:from\s+|import\s*\(\s*)['"](\.{1,2}\/[^'"]+)['"]/g)) {
      const base = join(f, '..', m[1]);
      const alvo = ['', '.astro', '.tsx', '.ts', '.jsx', '.js', '/index.ts', '/index.tsx', '/index.astro']
        .map((x) => base + x).find((c) => FONTES.includes(c));
      if (!alvo) continue;
      if (!mapa.has(alvo)) mapa.set(alvo, new Set());
      mapa.get(alvo).add(f);
    }
  }
  return mapa;
}

test('#1973: o BaseLayout importa e renderiza o Toast, fora de comentário', () => {
  const src = semComentario(ler('src/layouts/BaseLayout.astro'));
  assert.match(src, /^import Toast from '\.\.\/components\/ui\/Toast\.astro';$/m, 'import do componente');
  const corpo = src.slice(src.indexOf('<body'), src.indexOf('</body>'));
  assert.match(corpo, RENDER, '<Toast /> numa linha própria dentro do <body>');
});

test('#1973: todo layout garante o Toast', () => {
  const ok = layoutsQueGarantem();
  assert.deepEqual(LAYOUTS.filter((l) => !ok.has(l)), [], 'layout que nem monta o Toast nem envolve quem monta');
});

test('#1973: todo arquivo que chama toast é renderizado debaixo de um layout que o garante', () => {
  const ok = [...layoutsQueGarantem()];
  const imp = importadores();
  const nome = (x) => x.split('/').pop().replace('.astro', '');
  const usaLayout = (f) => ok.some((l) => new RegExp(`<${nome(l)}[\\s>]`).test(semComentario(ler(f))));
  const memo = new Map();
  /** Coberto: renderiza um layout que garante, ou TODOS os que o importam são cobertos. */
  function coberto(f, pilha = new Set()) {
    if (memo.has(f)) return memo.get(f);
    if (ok.includes(f) || usaLayout(f)) { memo.set(f, true); return true; }
    if (pilha.has(f)) return false;
    pilha.add(f);
    // Endpoint de servidor (.ts/.js em src/pages) importa para rodar no servidor, sem window e sem tela:
    // não é um caminho de renderização, então não entra no "todos os importadores".
    const de = [...(imp.get(f) || [])].filter((d) => !(d.startsWith('src/pages/') && /\.(ts|js)$/.test(d)));
    const r = de.length > 0 && de.every((d) => coberto(d, pilha));
    pilha.delete(f);
    memo.set(f, r);
    return r;
  }
  const chamadores = FONTES.filter((f) => f !== CANONICO && (semComentario(ler(f)).match(CHAMA) || []).length > 0);
  assert.ok(chamadores.length > 0, 'controle: a varredura encontra quem chama toast');
  const descobertos = chamadores.filter((f) => !coberto(f));
  assert.deepEqual(descobertos, [], 'chamam toast sem layout que monte o Toast (o aviso vira no-op):\n  ' + descobertos.join('\n  '));
});

test('#1973: só o BaseLayout renderiza o Toast — duas montagens duplicam id="toast"', () => {
  const outros = FONTES.filter((f) => f !== 'src/layouts/BaseLayout.astro' && RENDER.test(semComentario(ler(f))));
  assert.deepEqual(outros, [], 'montagem extra do Toast:\n  ' + outros.join('\n  '));
});

test('#1973: o componente canônico continua definindo o global e renderizando o alvo', () => {
  // Controle positivo: se o componente mudar de forma, os testes acima passam a validar nada.
  const c = ler('src/components/ui/Toast.astro');
  assert.match(c, /id="toast"/, 'renderiza o elemento alvo');
  assert.match(c, /\(window as any\)\.toast\s*=/, 'define o global que as páginas chamam');
  assert.match(c, /getElementById\('toast'\)/, 'e o global escreve NAQUELE elemento');
});
