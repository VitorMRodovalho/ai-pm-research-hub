// tests/contracts/3186b-drive-religa-revisao.test.mjs
/**
 * #3186b: o cron membership-drive-reconcile-daily volta a mandar a revisão da ACL (#3179), sem skip_acl_review,
 * depois do ensaio da EF da #3186 e da decisão da gestão.
 *
 *   G36 a volta do cron: o mesmo nome e horário, o corpo de antes da pausa, sem skip_acl_review no código.
 *   M   cada predicado reprova a mutação do seu defeito.
 *
 * O vivo se confere no apply: md5(command) do cron contra o DEPOIS anotado na migration.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, 'supabase/migrations');
const MIG_CRON = readdirSync(MIG_DIR).filter((f) => /_3186b_drive_religa_revisao_no_cron\.sql$/.test(f)).sort().pop();

/** Tira comentário de linha e colapsa espaço (a mesma forma do guard da #3179). */
function sql(b) {
  return b.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}
const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));
const ok = (o, msg) => assert.deepEqual(o, allTrue(o), msg);

/** G36: a volta do cron. */
export function cronReligado(cronMig) {
  const c = sql(cronMig);
  return {
    mesmoNomeEHorario: /SELECT cron\.schedule\( 'membership-drive-reconcile-daily', '0 4 \* \* \*', \$cron\$/.test(c),
    corpoSemPausa: /body := '\{"source":"pg_cron"\}'::jsonb,/.test(c),
    semSkip: !/skip_acl_review/.test(c),
  };
}

test('#3186b G36: o cron volta sem skip_acl_review', () => {
  assert.ok(MIG_CRON, 'migration *_3186b_drive_religa_revisao_no_cron.sql ausente');
  ok(cronReligado(readFileSync(join(MIG_DIR, MIG_CRON), 'utf8')), 'o cron mudou');
});

test('#3186b M: cada predicado reprova a mutação do seu defeito', () => {
  const mut = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutação não aplicou: ${a}`); return out; };
  const C = readFileSync(join(MIG_DIR, MIG_CRON), 'utf8');
  const pausa = mut(C, `'{"source":"pg_cron"}'::jsonb`, `'{"source":"pg_cron","skip_acl_review":true}'::jsonb`);
  assert.equal(cronReligado(pausa).semSkip, false);
  assert.equal(cronReligado(pausa).corpoSemPausa, false);
  assert.equal(cronReligado(mut(C, "  '0 4 * * *',", "  '0 5 * * *',")).mesmoNomeEHorario, false);
  // o comentário do ANTES cita skip_acl_review e não conta: o predicado lê o código
  assert.ok(/skip_acl_review/.test(C));
});
