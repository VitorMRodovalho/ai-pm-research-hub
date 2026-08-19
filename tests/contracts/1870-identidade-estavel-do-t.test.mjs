/**
 * #1870 — a identidade de `t` tem que ser estavel entre renders.
 *
 * O QUE ACONTECEU. `usePageI18n()` devolvia uma arrow nova a cada render. Componente que poe `t`
 * num array de dependencia (`useCallback(..., [t])`) alimentando um `useEffect(..., [cb])` que
 * grava estado fecha laco: efeito -> rede -> setState -> render -> `t` novo -> `cb` novo -> efeito.
 *
 * Medido em producao em 19/08/2026 pelo SealPanel: 15 de 15 backends ativos presos na mesma RPC,
 * pool esgotado, e o site PUBLICO devolvendo 504 em 1 de cada 3 requisicoes (61 s). Com o painel
 * fechado, os mesmos 3 pedidos voltaram em 0,27 s. Foi tambem o que fez o `validate` estourar o
 * teto de 95 min e ser cancelado (#1869), o que por sua vez deixou fixture de teste viva em
 * producao. Um defeito de memoizacao chegou ate ai.
 *
 * ESTE GUARD e estatico de proposito: nao ha runtime de React nesta suite, e o defeito e visivel
 * na FORMA do hook. Ele guarda a raiz (o hook) e mede a superficie (os consumidores), reportando
 * TODOS os examinados com um booleano em vez de so acusar o primeiro que falha.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const HOOK = 'src/i18n/usePageI18n.ts';

function varrerComponentes(dir, acc = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) varrerComponentes(p, acc);
    else if (e.name.endsWith('.tsx')) acc.push(p);
  }
  return acc;
}

/** Corpo de `const NOME = useX(` fechando por profundidade, e o array de dependencia final. */
function blocosMemoizados(src, hook) {
  const out = [];
  const re = new RegExp(`const\\s+(\\w+)\\s*=\\s*${hook}\\(`, 'g');
  let m;
  while ((m = re.exec(src))) {
    let i = m.index + m[0].length;
    let depth = 1;
    while (i < src.length && depth > 0) {
      const c = src[i];
      if (c === '(' || c === '[' || c === '{') depth++;
      else if (c === ')' || c === ']' || c === '}') depth--;
      i++;
    }
    const corpo = src.slice(m.index + m[0].length, i - 1);
    const dm = corpo.match(/,\s*(\[[^\]]*\])\s*$/);
    out.push({ nome: m[1], corpo, deps: dm ? dm[1] : '' });
  }
  return out;
}

const citaT = (deps) => /(?<![\w.])t(?![\w])/.test(deps || '');

test('#1870: usePageI18n devolve funcao MEMOIZADA', () => {
  const src = readFileSync(HOOK, 'utf8');
  const examinado = {
    arquivo: HOOK,
    retorna_useCallback: /return\s+useCallback\(/.test(src),
    importa_useCallback: /import\s*\{[^}]*\buseCallback\b[^}]*\}\s*from\s*'react'/.test(src),
    tem_deps_do_dict: /\[\s*dict\s*\]/.test(src),
    retorna_arrow_crua: /return\s*\(key/.test(src),
  };
  assert.equal(examinado.retorna_arrow_crua, false,
    'o hook voltou a devolver uma arrow crua: identidade nova a cada render, e o laco do #1870 '
    + `reabre em todo consumidor. Examinado: ${JSON.stringify(examinado)}`);
  assert.equal(examinado.retorna_useCallback, true, `Examinado: ${JSON.stringify(examinado)}`);
  assert.equal(examinado.importa_useCallback, true, `Examinado: ${JSON.stringify(examinado)}`);
  assert.equal(examinado.tem_deps_do_dict, true,
    'a memoizacao precisa depender de `dict`: com `[]` o dicionario carregado apos a montagem '
    + `nunca chegaria as traducoes. Examinado: ${JSON.stringify(examinado)}`);
});

/**
 * A superficie. Enquanto o hook estiver memoizado isto NAO fecha laco, mas a forma
 * `useEffect(..., [cb])` com `cb = useCallback(..., [t])` que grava estado continua sendo fragil:
 * qualquer outra dependencia instavel a reabre. O teste MEDE e publica em vez de proibir, porque
 * proibir quebraria codigo correto hoje.
 *
 * ⚠️ O detector so olha dependencia de `useEffect`. Contar tambem array de `useCallback` produz
 * falso positivo: `CohortHealthIsland` cita um callback dentro da dependencia de OUTRO callback e
 * consome o resultado por `useRef`, que e justamente o contorno correto. Um guard que nao separa
 * as duas coisas acusa quem se protegeu.
 */
function blocosDe(src, chamada) {
  const out = [];
  const re = new RegExp(`${chamada}\\(`, 'g');
  let m;
  while ((m = re.exec(src))) {
    let i = m.index + m[0].length;
    let depth = 1;
    while (i < src.length && depth > 0) {
      const c = src[i];
      if (c === '(' || c === '[' || c === '{') depth++;
      else if (c === ')' || c === ']' || c === '}') depth--;
      i++;
    }
    const corpo = src.slice(m.index + m[0].length, i - 1);
    const dm = corpo.match(/,\s*(\[[^\]]*\])\s*$/);
    out.push({ inicio: m.index, corpo, deps: dm ? dm[1] : '' });
  }
  return out;
}

test('#1870: a superficie fragil e medida e publicada, nao presumida', () => {
  const componentes = varrerComponentes('src/components')
    .filter((f) => readFileSync(f, 'utf8').includes('usePageI18n()'));

  const fragis = [];
  for (const f of componentes) {
    const src = readFileSync(f, 'utf8');
    // callbacks que dependem de `t` E gravam estado
    const suspeitos = blocosMemoizados(src, 'useCallback')
      .filter((b) => citaT(b.deps) && /\bset[A-Z]\w*\(/.test(b.corpo));
    // dependencias de useEffect, e SO delas
    const depsDeEfeito = blocosDe(src, 'useEffect').map((b) => b.deps);
    for (const b of suspeitos) {
      const consumidoPorEfeito = depsDeEfeito
        .some((d) => new RegExp(`(?<![\\w.])${b.nome}(?![\\w])`).test(d));
      if (consumidoPorEfeito) fragis.push(`${f.replace('src/components/', '')}:${b.nome}`);
    }
  }

  // Teto que so desce. Subiu, alguem introduziu forma fragil nova e deve olhar antes do numero.
  const TETO = 4;
  assert.ok(
    fragis.length <= TETO,
    `formas fragis passaram de ${TETO} para ${fragis.length}. Examinados: ${componentes.length} `
    + `componentes que usam usePageI18n(). Fragis: ${fragis.join(', ')}`,
  );
  assert.ok(componentes.length >= 40,
    `esperava 40+ consumidores do hook, achei ${componentes.length} — a varredura provavelmente quebrou`);
});
