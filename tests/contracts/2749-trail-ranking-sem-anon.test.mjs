// #2749: get_public_trail_ranking fechada para anon (decisão do GP, 19/10/2026).
//
// A home passou a mostrar o ranking da trilha só com sessão (#2748), mas esconder a seção não fecha a fonte. Este
// guard afirma as duas metades:
//   (A) estático: a migration da #2749 revoga EXECUTE de anon NA função certa, e nenhuma migration posterior volta a
//       conceder EXECUTE a anon ou a PUBLIC;
//   (B) efeito, com banco: como anon a chamada é RECUSADA; o mesmo cliente anon ainda chama uma RPC pública
//       (controle positivo: a recusa vem do REVOKE, não de um cliente quebrado); com a service role a RPC responde.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const DIR = 'supabase/migrations';
const files = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort();
const REVOKE_FILE = files.find((f) => /_2749_trail_ranking_sem_anon\.sql$/.test(f));
// comentários de linha fora: o texto da explicação cita GRANT e anon e não pode decidir nada
const sqlOf = (f) => readFileSync(join(DIR, f), 'utf8').replace(/--[^\n]*/g, '');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const opts = { auth: { persistSession: false } };
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, opts) : null;
const svc = SUPABASE_URL && SRK ? createClient(SUPABASE_URL, SRK, opts) : null;

describe('#2749 get_public_trail_ranking sem anon', () => {
  it('a migration existe e revoga EXECUTE de anon na função certa, num único comando', () => {
    assert.ok(REVOKE_FILE, 'migration *_2749_trail_ranking_sem_anon.sql ausente');
    assert.match(
      sqlOf(REVOKE_FILE),
      /REVOKE\s+EXECUTE\s+ON\s+FUNCTION\s+public\.get_public_trail_ranking\(\s*\)\s+FROM\s+anon\s*;/i,
    );
  });

  it('nenhuma migration posterior volta a conceder EXECUTE a anon ou PUBLIC', () => {
    const later = files.slice(files.indexOf(REVOKE_FILE) + 1);
    const regrant = /GRANT\s+(?:EXECUTE|ALL)[^;]*ON\s+FUNCTION\s+public\.get_public_trail_ranking\b[^;]*\bTO\b[^;]*\b(?:anon|PUBLIC)\b/i;
    const offenders = later.filter((f) => regrant.test(sqlOf(f)));
    assert.deepEqual(offenders, [], `regrant a anon/PUBLIC depois da #2749: ${offenders.join(', ')}`);
  });

  it('como anon, a chamada é recusada; o controle anon passa; com service role, responde', { skip: !(anon && svc) && 'sem SUPABASE_URL + chaves' }, async () => {
    const ctrl = await anon.rpc('get_homepage_stats');
    assert.equal(ctrl.error, null, `controle positivo falhou: o cliente anon não chama nem uma RPC pública (${ctrl.error?.message})`);

    const denied = await anon.rpc('get_public_trail_ranking');
    assert.ok(denied.error, 'anon ainda executa get_public_trail_ranking');
    assert.match(`${denied.error.code} ${denied.error.message}`, /42501|permission denied/i);

    const ok = await svc.rpc('get_public_trail_ranking');
    assert.equal(ok.error, null, `service role não executa: ${ok.error?.message}`);
    assert.ok(Array.isArray(ok.data), 'service role deveria receber a lista');
  });
});
