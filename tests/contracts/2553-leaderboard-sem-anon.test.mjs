// #2553 D4: get_public_leaderboard fechada para anon (decisão do GP, 20/10/2026) e para o ghost (autenticado sem
// linha em members; decisão da orquestradora, 21/10/2026, pela regra 6 do CLAUDE.md).
//
// O /gamification do visitante passou ao agregado, mas esconder a lista não fecha a fonte. Este guard afirma:
//   (A) estático: a migration revoga EXECUTE de PUBLIC, anon e authenticated NA função certa e devolve o EXECUTE só
//       à service_role; nenhuma migration posterior volta a conceder a anon, authenticated ou PUBLIC, nem faz
//       DROP + CREATE (que nasce com o EXECUTE padrão de PUBLIC);
//   (B) efeito, com banco: como anon a chamada é RECUSADA (o ghost a orquestradora exercita por impersonação, porque
//       esta suíte não tem sessão de autenticado sem membro); o mesmo cliente anon ainda chama
//       get_public_gamification_summary (controle positivo: a recusa vem do REVOKE, e o substituto responde);
//       com a service role a antiga responde.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const DIR = 'supabase/migrations';
const files = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort();
const REVOKE_FILE = files.find((f) => /_2553_leaderboard_sem_anon\.sql$/.test(f));
// comentários de linha fora: a explicação cita GRANT, PUBLIC e anon e não pode decidir nada
const sqlOf = (f) => readFileSync(join(DIR, f), 'utf8').replace(/--[^\n]*/g, '');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const opts = { auth: { persistSession: false } };
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, opts) : null;
const svc = SUPABASE_URL && SRK ? createClient(SUPABASE_URL, SRK, opts) : null;

describe('#2553 get_public_leaderboard sem anon', () => {
  it('a migration revoga de PUBLIC, anon e authenticated e concede só à service_role', () => {
    assert.ok(REVOKE_FILE, 'migration *_2553_leaderboard_sem_anon.sql ausente');
    const sql = sqlOf(REVOKE_FILE);
    assert.match(sql, /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.get_public_leaderboard\(integer\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated\s*;/i);
    assert.match(sql, /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.get_public_leaderboard\(integer\)\s+TO\s+service_role\s*;/i);
    assert.doesNotMatch(sql, /GRANT[^;]*get_public_leaderboard[^;]*\bTO\b[^;]*\b(?:anon|authenticated|PUBLIC)\b/i);
  });

  it('nenhuma migration posterior volta a conceder EXECUTE a anon, authenticated ou PUBLIC', () => {
    const later = files.slice(files.indexOf(REVOKE_FILE) + 1);
    const regrant = /GRANT\s+(?:EXECUTE|ALL)[^;]*ON\s+FUNCTION\s+(?:public\.)?get_public_leaderboard\b[^;]*\bTO\b[^;]*\b(?:anon|authenticated|PUBLIC)\b/i;
    // CREATE OR REPLACE preserva o ACL; DROP + CREATE nasce com o EXECUTE padrão de PUBLIC, que alcança o anon
    const dropped = /DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(?:public\.)?get_public_leaderboard\b/i;
    const offenders = later.filter((f) => regrant.test(sqlOf(f)) || dropped.test(sqlOf(f)));
    assert.deepEqual(offenders, [], `regrant ou DROP + CREATE depois da #2553: ${offenders.join(', ')}`);
  });

  it('como anon a antiga é recusada e o agregado responde; com service role a antiga responde', { skip: !(anon && svc) && 'sem SUPABASE_URL + chaves' }, async () => {
    const ctrl = await anon.rpc('get_public_gamification_summary');
    assert.equal(ctrl.error, null, `controle positivo falhou: o anon não chama o agregado (${ctrl.error?.message})`);

    const denied = await anon.rpc('get_public_leaderboard', { p_limit: 1 });
    assert.ok(denied.error, 'anon ainda executa get_public_leaderboard');
    assert.match(`${denied.error.code} ${denied.error.message}`, /42501|permission denied/i);

    const ok = await svc.rpc('get_public_leaderboard', { p_limit: 1 });
    assert.equal(ok.error, null, `service role não executa: ${ok.error?.message}`);
  });
});
