/**
 * Carregadores do quadro seguem a política de leitura de board_items.
 *
 * A tabela board_items só deixa ler, pela API, membro com vínculo vigente: a política
 * board_items_read_members usa rls_is_authoritative_member() desde a migration 20260805000246.
 * get_board e list_board_items são SECURITY DEFINER, ignoram a RLS da tabela, e por isso precisam
 * aplicar a mesma regra a quem chama pela API (public._request_is_rest_caller(), #684). Chamadas
 * internas (service_role, cron) seguem iguais.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. A captura VIGENTE de cada carregador (latestFunctionCapture, #1932) aplica a regra antes de
 *      montar qualquer dado, e o portão de quadro confidencial continua no lugar.
 *   B. Paridade: a última definição de board_items_read_members nas migrations usa o mesmo
 *      predicado. Se a política da tabela mudar, este guard reprova e lembra dos carregadores.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = (name) => maskLineComments(latestFunctionCapture(ROOT, name).block);
const REGRA = 'public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member()';
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

test('A1: get_board aplica a regra da tabela antes de montar o quadro', () => {
  const b = cap('get_board');
  const gate = b.search(new RegExp(`IF ${esc(REGRA)} THEN\\s+RETURN NULL;\\s+END IF;`));
  assert.ok(gate >= 0, 'quem chama pela API sem vínculo vigente recebe NULL');
  assert.ok(gate < b.indexOf('SELECT jsonb_build_object('), 'a regra vem antes de qualquer leitura');
  assert.match(b, /IF NOT public\.rls_can_see_board\(p_board_id\) THEN\s+RETURN NULL;\s+END IF;/, 'o portão de quadro confidencial segue');
});

test('A2: list_board_items aplica a regra da tabela antes de devolver linhas', () => {
  const b = cap('list_board_items');
  const gate = b.search(new RegExp(`IF ${esc(REGRA)} THEN RETURN; END IF;`));
  assert.ok(gate >= 0, 'quem chama pela API sem vínculo vigente recebe zero linhas');
  assert.ok(gate < b.indexOf('RETURN QUERY'), 'a regra vem antes da consulta');
  assert.match(b, /IF NOT public\.rls_can_see_board\(p_board_id\) THEN RETURN; END IF;/, 'o portão de quadro confidencial segue');
});

test('B1: a política de leitura de board_items usa o mesmo predicado dos carregadores', () => {
  const dir = join(ROOT, 'supabase/migrations');
  let last = null;
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(dir, f), 'utf8'));
    const re = /(?:CREATE|ALTER)\s+POLICY\s+"?board_items_read_members"?\s+ON\s+public\.board_items\b[^;]*?USING\s*\(([^;]*)\)\s*;/gi;
    let m;
    while ((m = re.exec(sql)) !== null) last = { file: f, using: m[1] };
  }
  assert.ok(last, 'a política existe nas migrations');
  assert.match(last.using, /^\s*public\.rls_is_authoritative_member\(\)\s*$/, `a última definição (${last?.file}) usa rls_is_authoritative_member()`);
});
