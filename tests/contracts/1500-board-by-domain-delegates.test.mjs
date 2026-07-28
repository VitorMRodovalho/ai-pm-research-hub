/**
 * Contract: #1500 — `get_board_by_domain` resolve o id e DELEGA para `get_board`.
 *
 * O #1500 foi aberto sob a tese de que as duas RPCs serviam o mesmo board com payloads
 * diferentes, e que só `get_board` lia `board_item_assignments`. Medido em 2026-07-28 contra
 * o corpo VIVO: a tese é falsa. `get_board_by_domain` termina em `RETURN public.get_board(...)`
 * desde a migration 20260428180000 (28/04), e uma chamada ao board da tribo que reportou
 * devolveu `assignments` em 8 de 8 itens. O issue foi fechado como não-issue.
 *
 * O que sobra é a preocupação legítima: se alguém reescrever `get_board_by_domain` montando
 * o payload por conta própria, a divergência passa a EXISTIR, e o sintoma reaparece longe da
 * causa — uma feature que depende de participantes some só na rota de tribo. Este teste trava
 * a delegação para que isso falhe no CI em vez de virar bug de campo.
 *
 * Estático sobre a última captura da RPC em migrations. Comentários SQL são removidos antes de
 * qualquer asserção: o motivo da delegação é justamente o tipo de coisa que se escreve em
 * comentário, e a prosa não pode contar como código vivo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function stripSqlComments(sql) {
  return sql.replace(/\/\*[\s\S]*?\*\//g, '').replace(/--[^\n]*/g, '');
}

/** Última captura de uma função em migrations, já sem comentários. */
function lastCapture(fnName) {
  const re = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${fnName}\\s*\\([\\s\\S]*?\\$function\\$[\\s\\S]*?\\$function\\$`,
    'i',
  );
  let found = null;
  for (const file of readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort()) {
    const block = stripSqlComments(readFileSync(resolve(MIGRATIONS_DIR, file), 'utf8')).match(re)?.[0];
    if (block) found = { file, block };
  }
  return found;
}

test('1500: get_board_by_domain delega para get_board em vez de montar payload proprio', () => {
  const cap = lastCapture('get_board_by_domain');
  assert.ok(cap, 'get_board_by_domain deve estar capturada em alguma migration');

  assert.match(cap.block, /RETURN\s+public\.get_board\s*\(/i,
    `${cap.file}: a RPC deve delegar a get_board, senao os dois payloads divergem (#1500)`);
  assert.doesNotMatch(cap.block, /board_item_assignments/i,
    `${cap.file}: montar a juncao aqui recria a divergencia que o #1500 apurou como inexistente`);
  assert.doesNotMatch(cap.block, /jsonb_agg\s*\(/i,
    `${cap.file}: agregar itens aqui significa payload proprio, nao delegacao`);
});

test('1500: get_board (o payload unico) devolve assignments por item', () => {
  const cap = lastCapture('get_board');
  assert.ok(cap, 'get_board deve estar capturada em alguma migration');
  assert.match(cap.block, /'assignments'\s*,/i,
    `${cap.file}: get_board deve devolver a chave assignments — é dela que as duas rotas dependem`);
  assert.match(cap.block, /board_item_assignments/i,
    `${cap.file}: a juncao de participantes deve ser lida de board_item_assignments`);
});
