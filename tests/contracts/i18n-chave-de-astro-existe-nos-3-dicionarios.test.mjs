/**
 * Toda chave literal passada a t() num .astro existe nos 3 dicionários.
 *
 * t() devolve a PRÓPRIA CHAVE quando ela falta (src/i18n/utils.ts), e a chave nunca é vazia: a tela
 * mostra "publications.formTitle" no lugar do rótulo, e um `t('x', lang) || 'Texto'` não salva nada,
 * porque o || nunca dispara. Medido em 17/11/2026: 12 chaves cruas no modal de submissão de
 * /publications e mais 3 em componentes (EditEventModal, NewEventModal, Nav).
 *
 * Fora do alcance, de propósito: chave montada em tempo de execução (`t('x.' + v)`, template
 * literal). Para essas, o guard do próprio fluxo enumera os valores (ex.: publicacoes-minhas-submissoes).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const walk = (d, a = []) => {
  for (const e of readdirSync(resolve(ROOT, d))) {
    const p = join(d, e);
    if (statSync(resolve(ROOT, p)).isDirectory()) walk(p, a);
    else if (e.endsWith('.astro')) a.push(p);
  }
  return a;
};
const semComentario = (src) => src
  .replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '))
  .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
  .replace(/^([ \t]*)\/\/[^\n]*/gm, (m, i) => i + ' '.repeat(m.length - i.length));

const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => [l, readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8')]);
const tem = (d, k) => d.includes(`'${k}':`) || d.includes(`"${k}":`);
// Chave literal INTEIRA como argumento: depois da aspa vem `,` ou `)`. `t('x.' + v)` não casa.
const CHAMADA = /(?<![A-Za-z0-9_$.])t\(\s*'([^'\n]+)'\s*(?=[,)])/g;

test('toda chave literal de t() em .astro existe nos 3 dicionários', () => {
  const arquivos = walk('src');
  let vistas = 0;
  const faltam = [];
  for (const f of arquivos) {
    const src = semComentario(readFileSync(resolve(ROOT, f), 'utf8'));
    for (const m of src.matchAll(CHAMADA)) {
      vistas++;
      const sem = DICTS.filter(([, d]) => !tem(d, m[1])).map(([l]) => l);
      if (sem.length) faltam.push(`${f}: ${m[1]} (falta em ${sem.join(', ')})`);
    }
  }
  // Controle: a varredura precisa ver o universo, senão um regex quebrado lê como "nada falta".
  assert.ok(vistas > 1000, `a varredura viu só ${vistas} chamadas`);
  assert.deepEqual([...new Set(faltam)], [], 'chave ausente aparece crua na tela');
});
