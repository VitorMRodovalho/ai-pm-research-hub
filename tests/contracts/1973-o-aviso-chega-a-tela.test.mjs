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

test('#1973: toda página que chama `toast(` RENDERIZA o componente, não só importa', () => {
  // Importar sem renderizar deixa `window.toast` indefinido, e `window.toast?.(...)` vira
  // no-op silencioso — mesmo desfecho, outro caminho.
  const semRender = [];
  for (const p of TODAS) {
    const src = ler(p);
    const chama = (src.match(/(?<![A-Za-z.])toast\(/g) || []).length;
    if (chama === 0) continue;
    // delegação a `window.toast` só funciona se o componente estiver na página
    const renderiza = /<Toast\s*\/>/.test(src);
    if (!renderiza) semRender.push(`${p} (${chama} chamadas)`);
  }
  assert.deepEqual(semRender, [],
    'páginas que avisam o usuário sem ter onde mostrar o aviso:\n  ' + semRender.join('\n  '));
});

test('#1973: o componente canônico continua definindo o global e renderizando o alvo', () => {
  // Controle positivo: se o componente mudar de forma, os testes acima passam a validar nada.
  const c = ler('src/components/ui/Toast.astro');
  assert.match(c, /id="toast"/, 'renderiza o elemento alvo');
  assert.match(c, /\(window as any\)\.toast\s*=/, 'define o global que as páginas chamam');
  assert.match(c, /getElementById\('toast'\)/, 'e o global escreve NAQUELE elemento');
});
