/**
 * #3150: textos que não olham o papel nem o status da pessoa.
 *
 * S7 (parcerias): o botão de retroceder status chamava admin_update_partner_status com o status
 * anterior. O funil é só para a frente (ADR-0033), a função recusa a volta no corpo, e a tela, que lia
 * só o `error`, dizia "Status retrocedido." sem mudar nada. O botão sai enquanto a função recusar.
 *
 * Comentários JS e SQL saem antes do assert.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments as maskJs, maskLineComments as maskSql } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');

function latestSqlBody(name) {
  const dir = resolve(ROOT, 'supabase/migrations');
  const head = `CREATE OR REPLACE FUNCTION public.${name}(`;
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()
    .filter((f) => maskSql(readFileSync(resolve(dir, f), 'utf8')).includes(head));
  assert.ok(files.length, `alguma migration define ${name}`);
  const sql = maskSql(readFileSync(resolve(dir, files.at(-1)), 'utf8'));
  const a = sql.lastIndexOf(head);
  return { file: files.at(-1), body: sql.slice(a, sql.indexOf('$function$;', a)) };
}

test('#3150 S7: a tela de parcerias não oferece voltar status enquanto a função recusa a volta', () => {
  const { file, body } = latestSqlBody('admin_update_partner_status');
  const blocks = /IF[\s\S]{0,400}?THEN\s+RETURN jsonb_build_object\('success', false, 'error', 'backward_transition_blocked'/.test(body);
  const island = maskJs(read('src/components/islands/PartnerPipelineIsland.tsx'));
  const calls = [...island.matchAll(/sb\.rpc\('admin_update_partner_status', \{[^}]*p_new_status: ([a-zA-Z_.[\]]+)/g)].map((m) => m[1]);
  const rpcCheckedCalls = [...island.matchAll(/rpcChecked\(sb, 'admin_update_partner_status', \{[\s\S]*?p_new_status: ([a-zA-Z_.[\]]+)/g)].map((m) => m[1]);
  if (blocks) {
    assert.doesNotMatch(island, /PREV_STATUS|Retrocedido|retrocedido/, `${file} recusa a volta: a ilha não pode ter botão nem texto de retroceder`);
    for (const v of [...calls, ...rpcCheckedCalls]) {
      assert.doesNotMatch(v, /prev/i, `${file} recusa a volta: nenhuma chamada manda o status anterior`);
    }
  }
  assert.ok(blocks, `${file}: a recusa da volta continua; se a função passar a aceitar, reveja este guard`);
});
