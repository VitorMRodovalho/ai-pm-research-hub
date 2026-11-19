/**
 * Toda chamada a move_board_item usa os nomes de parâmetro da assinatura.
 *
 * TribeKanbanIsland e PublicationsBoardIsland chamavam move_board_item com `p_position`. A
 * assinatura é (p_item_id, p_new_status, p_new_position, p_reason), conferida no pg_proc vivo em
 * 19/11/2026. O PostgREST resolve a função pelos NOMES dos argumentos, então a chamada não achava
 * função nenhuma e falhava para qualquer pessoa com PGRST202 ("Could not find the function
 * public.move_board_item(p_item_id, p_new_status, p_position)"), medido como consumidor no
 * astro dev com um id inexistente. Todo movimento de card nesses dois quadros terminava em
 * "Falha ao mover".
 *
 * O guard lê a assinatura em src/lib/database.gen.ts (Args) e, para cada chamada em src/, exige
 * que as chaves do objeto de argumentos estejam na assinatura e que as obrigatórias estejam na
 * chamada. A contagem de chamadas recortadas tem de bater com a de ocorrências do nome, para o
 * guard não passar no vazio se o recorte quebrar.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const RPCS = ['move_board_item'];
const GEN = 'src/lib/database.gen.ts';

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(tsx?|astro|mjs|js)$/.test(name) && p !== GEN) out.push(p);
  }
  return out;
}

/** Args de uma função no database.gen.ts: { keys, required }. */
function signature(fn) {
  const gen = readFileSync(GEN, 'utf8');
  const start = gen.search(new RegExp(`^      ${fn}: \\{$`, 'm'));
  assert.ok(start >= 0, `${fn} presente em ${GEN}`);
  const args = gen.slice(start).match(/Args:\s*(\{[\s\S]*?\}|never)\s*\n\s*Returns:/);
  assert.ok(args, `${fn}: bloco Args legível`);
  const keys = new Set(), required = new Set();
  for (const m of args[1].matchAll(/\b(p_\w+)(\??):/g)) {
    keys.add(m[1]);
    if (m[2] !== '?') required.add(m[1]);
  }
  assert.ok(keys.size > 0, `${fn}: assinatura com parâmetros`);
  return { keys, required };
}

/** Objetos literais passados a sb.rpc('<fn>', { ... }), com o arquivo e a linha. */
function calls(fn) {
  const found = [];
  let occurrences = 0;
  for (const file of walk('src')) {
    const src = maskJsComments(readFileSync(file, 'utf8'));
    occurrences += (src.match(new RegExp(`rpc\\(\\s*'${fn}'`, 'g')) || []).length;
    for (const m of src.matchAll(new RegExp(`rpc\\(\\s*'${fn}'\\s*,\\s*\\{([^{}]*)\\}`, 'g'))) {
      const keys = [...m[1].matchAll(/\b(p_\w+)\s*:/g)].map((k) => k[1]);
      found.push({ where: `${file}:${src.slice(0, m.index).split('\n').length}`, keys });
    }
  }
  return { found, occurrences };
}

for (const fn of RPCS) {
  test(`${fn}: cada chamada em src/ usa só parâmetros da assinatura e passa os obrigatórios`, () => {
    const { keys, required } = signature(fn);
    const { found, occurrences } = calls(fn);
    assert.ok(occurrences > 0, `há chamadas a ${fn} em src/`);
    assert.equal(found.length, occurrences, `toda ocorrência de rpc('${fn}') foi recortada com seu objeto de argumentos`);
    for (const c of found) {
      for (const k of c.keys) {
        assert.ok(keys.has(k), `${c.where}: ${k} não existe na assinatura de ${fn} (${[...keys].join(', ')}); o PostgREST não acha a função`);
      }
      for (const r of required) {
        assert.ok(c.keys.includes(r), `${c.where}: falta o parâmetro obrigatório ${r} de ${fn}`);
      }
    }
  });
}
