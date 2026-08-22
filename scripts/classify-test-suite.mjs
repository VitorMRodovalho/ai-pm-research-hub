#!/usr/bin/env node
/**
 * A1 (auditoria de CI, #1908) — classifica a suíte em ESTRUTURAL e COMPORTAMENTAL.
 *
 * Um arquivo é COMPORTAMENTAL se referencia `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
 * `SUPABASE_ANON_KEY` ou o helper `db-fetch` — ou seja, fala com o banco de produção
 * compartilhado e por isso pertence à faixa serializada. Caso contrário é ESTRUTURAL: lê
 * arquivo, catálogo ou código do repo, e não tem por que esperar na faixa de ninguém.
 *
 * Medido em 22/08/2026: 287 estruturais (3.588 testes, 12,58s com `--test-concurrency=4`,
 * **0 skipped**) contra 322 comportamentais (~11m35s). O `0 skipped` é a prova de que a metade
 * estrutural é mesmo hermética: nenhum arquivo dela está gated por credencial.
 *
 * ⚠️ A CLASSIFICAÇÃO É DERIVADA, NUNCA ESCRITA À MÃO. As listas em `package.json` são cópias
 * materializadas desta função, e `tests/contracts/1908-a1-particao-da-suite.test.mjs` reprova se
 * elas divergirem. Uma lista escrita à mão apodrece no primeiro teste novo, e o modo de falha é
 * silencioso nos dois sentidos: um teste de banco no balde estrutural roda FORA da faixa (dois
 * processos no mesmo banco, que é o estrago do #1509), e um teste hermético no balde
 * comportamental volta a esperar 14 min por nada.
 *
 * Uso:
 *   node scripts/classify-test-suite.mjs structural     # imprime a lista, separada por espaço
 *   node scripts/classify-test-suite.mjs behavioural
 *   node scripts/classify-test-suite.mjs --json         # {structural: [...], behavioural: [...]}
 *   node scripts/classify-test-suite.mjs --check        # confere o package.json e sai != 0 se divergir
 */

import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SKIP_LIST } from '../tests/helpers/contract-whitelist-skips.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/**
 * O sinal de "fala com o banco". Mantido junto da doc acima de propósito.
 *
 * ⚠️ É casamento TEXTUAL puro, sem entender se o nome aparece como leitura de `process.env` ou
 * apenas citado dentro de uma string. Isso produz falso positivo em arquivo que só DOCUMENTA o
 * critério — aconteceu com `1908-a1-particao-da-suite.test.mjs`, que é hermético e caiu no balde
 * comportamental por escrever os nomes por extenso.
 *
 * Mantido assim de propósito, porque **a assimetria é favorável**: um falso "comportamental" custa
 * LATÊNCIA (o arquivo espera a faixa à toa), e um falso "estrutural" custa CORREÇÃO (dois
 * processos escrevendo no mesmo banco de produção, que é o #1509). Reconhecer `process.env` tornaria
 * o critério mais esperto e mais frágil, e erraria para o lado caro. Prefira ajustar o arquivo que
 * cita os nomes — é o que o teste do #1908 faz, montando-os por pedaços.
 */
export const MARCA_DE_BANCO = /SUPABASE_URL|SUPABASE_SERVICE_ROLE_KEY|SUPABASE_ANON_KEY|db-fetch/;

/** Extrai os caminhos de teste de um script npm, ignorando flags e o binário. */
export function arquivosDoScript(script) {
  return (script || '')
    .split(/\s+/)
    .filter((tok) => /^tests\/.+\.(mjs|ts)$/.test(tok));
}

export function classificar(arquivos, root = ROOT) {
  const structural = [];
  const behavioural = [];
  const ausentes = [];
  for (const rel of arquivos) {
    const abs = resolve(root, rel);
    if (!existsSync(abs)) { ausentes.push(rel); continue; }
    (MARCA_DE_BANCO.test(readFileSync(abs, 'utf8')) ? behavioural : structural).push(rel);
  }
  return { structural, behavioural, ausentes };
}

/**
 * O DENOMINADOR VEM DO DISCO, não do `package.json`.
 *
 * Antes da A1, o script `test` era uma lista explícita de 609 caminhos, e um arquivo novo só
 * entrava se alguém o adicionasse à mão. Esquecer não produzia sinal: a suíte ficava verde com um
 * arquivo a menos, exatamente como ficaria com ele. Foi assim que
 * o repo já guarda isso para `tests/contracts/` desde o #1109 — e é de lá que vem a lista de
 * exclusões abaixo. O que faltava era o mesmo denominador para o resto de `tests/`.
 *
 * Depois da partição, `test` deixa de listar arquivo (virou `npm run test:structural && ...`),
 * então uma checagem de união contra ele seria VAZIA — pior que a de antes. Por isso o denominador
 * passa a ser `tests/**\/*.test.{mjs,ts}` em disco, e cada arquivo tem de estar em um de três
 * lugares: um dos dois baldes, ou a lista declarada de exclusões abaixo.
 */
export const EXCLUSOES_DECLARADAS = new Map([
  // Único fora de `tests/contracts/`, e por isso declarado aqui: o guard do #1109 só varre aquele
  // diretório.
  ['tests/browser-guards.test.mjs',
   'tem job próprio (`browser_guards`, required) e script próprio (`test:browser:guards`)'],

  // As de `tests/contracts/` vêm da MESMA lista que o guard do #1109 usa. Não duplicar aqui:
  // duas listas divergem, e a divergência se manifesta como "teste sumiu do CI".
  ...SKIP_LIST.map((e) => [`tests/contracts/${e.file}`, `${e.reason} (issue #${e.issue})`]),
]);

/** Baseline do ratchet: só pode DESCER. Subir significa novo teste esquecido. */
export const EXCLUSOES_BASELINE = 1 + SKIP_LIST.length;

export function testesEmDisco(root = ROOT) {
  const encontrados = [];
  const anda = (dir) => {
    for (const e of readdirSync(resolve(root, dir), { withFileTypes: true })) {
      const rel = `${dir}/${e.name}`;
      if (e.isDirectory()) anda(rel);
      else if (/\.test\.(mjs|ts)$/.test(e.name)) encontrados.push(rel);
    }
  };
  anda('tests');
  return encontrados.sort();
}

export function lerParticao(pkg) {
  return {
    structural: arquivosDoScript(pkg.scripts['test:structural']),
    behavioural: arquivosDoScript(pkg.scripts['test:behavioural']),
  };
}

function main() {
  const arg = process.argv[2] || '--json';
  const pkg = JSON.parse(readFileSync(resolve(ROOT, 'package.json'), 'utf8'));

  if (arg === '--check') {
    const p = lerParticao(pkg);
    const disco = testesEmDisco();
    const esperado = classificar([...p.structural, ...p.behavioural]);
    const problemas = [];

    if (esperado.ausentes.length) {
      problemas.push(`arquivos listados que não existem: ${esperado.ausentes.join(' ')}`);
    }

    // O denominador. Todo arquivo em disco tem de estar num balde ou declarado como exclusão.
    const cobertos = new Set([...p.structural, ...p.behavioural]);
    const descobertos = disco.filter((f) => !cobertos.has(f) && !EXCLUSOES_DECLARADAS.has(f));
    if (descobertos.length) {
      problemas.push(
        `teste em disco que NENHUM script roda e que não está declarado como exclusão: `
        + `${descobertos.join(' ')} — some em silêncio, é o defeito da #1926`,
      );
    }
    if (EXCLUSOES_DECLARADAS.size > EXCLUSOES_BASELINE) {
      problemas.push(
        `a lista de exclusões subiu de ${EXCLUSOES_BASELINE} para ${EXCLUSOES_DECLARADAS.size}: `
        + `o ratchet só desce`,
      );
    }
    for (const f of EXCLUSOES_DECLARADAS.keys()) {
      if (!disco.includes(f)) problemas.push(`exclusão declarada aponta arquivo inexistente: ${f}`);
      if (cobertos.has(f)) problemas.push(`${f} está declarado como exclusão E dentro de um balde`);
    }

    const noBaldeErrado = [
      ...p.structural.filter((f) => esperado.behavioural.includes(f))
        .map((f) => `${f} toca banco e está em test:structural (rodaria FORA da faixa — #1509)`),
      ...p.behavioural.filter((f) => esperado.structural.includes(f))
        .map((f) => `${f} é hermético e está em test:behavioural (espera a faixa por nada)`),
    ];
    problemas.push(...noBaldeErrado);

    if (problemas.length) {
      console.error('partição da suíte DIVERGE do critério (A1 / #1908):');
      for (const p2 of problemas) console.error(`  - ${p2}`);
      process.exit(1);
    }
    console.log(
      `partição OK: ${p.structural.length} estruturais + ${p.behavioural.length} comportamentais `
      + `= ${p.structural.length + p.behavioural.length}, mais ${EXCLUSOES_DECLARADAS.size} exclusões `
      + `declaradas, cobrindo ${disco.length} arquivos em disco`,
    );
    return;
  }

  const unicos = testesEmDisco().filter((f) => !EXCLUSOES_DECLARADAS.has(f));
  const r = classificar(unicos);

  if (arg === '--json') { console.log(JSON.stringify(r, null, 2)); return; }
  if (arg === 'structural' || arg === 'behavioural') { console.log(r[arg].join(' ')); return; }

  console.error(`uso: classify-test-suite.mjs [structural|behavioural|--json|--check]`);
  process.exit(2);
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) main();
