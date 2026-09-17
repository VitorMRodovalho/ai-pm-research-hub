/**
 * Contract: #1217 — the tribe/initiative members list derives from the engagement PRIMITIVE
 * (get_initiative_roster_members -> v_initiative_roster), NOT the single-slot members.initiative_id
 * cache. The fill-only cache dropped a C4 leader whose slot was held by a workgroup engagement
 * (leader + workgroup is the normal C4 case), so the leader vanished from their OWN tribe page.
 *
 * Migration: supabase/migrations/20260805000400_1217_initiative_roster_members_from_primitive.sql
 * Page:      src/pages/tribe/[id].astro (members Promise.all leg now calls the RPC)
 * Cross-ref: #1215 (same family), ADR-0100 (roster primitive), ADR-0105 (confidential gate).
 *
 * Static layer (always) + DB-gated ratchet: for every active tribe with a canonical leader_member_id,
 * the leader MUST appear in the roster of their own initiative — the regression the cache allowed.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
// ⚠️ #1932: este guard FIXAVA a migration de 05/08 e afirmava o corpo dela. Quando a #2334
// redefiniu `get_initiative_roster_members` (para unir os visitantes), o texto fixado continuou
// no disco e este guard seguiu VERDE descrevendo um corpo que a produção não executa mais — o
// modo de falha que o #1932 existe para pegar, e que ele pegou. Agora lê a captura VIGENTE.
const MIG_ORIGINAL = resolve(ROOT, 'supabase/migrations/20260805000400_1217_initiative_roster_members_from_primitive.sql');
const PAGE = resolve(ROOT, 'src/pages/tribe/[id].astro');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const captura = latestFunctionCapture(ROOT, 'get_initiative_roster_members');
// `block` inclui o cabeçalho (assinatura, SECURITY DEFINER); `body` traz só o miolo.
const mig = captura?.block ?? '';
const page = existsSync(PAGE) ? readFileSync(PAGE, 'utf8') : '';

test('#1217: migration defines get_initiative_roster_members from the roster primitive', () => {
  assert.ok(mig, 'nenhuma migration define get_initiative_roster_members — sem captura, este guard ' +
    'ficaria VERDE por não achar nada, que é o modo de falhar mais silencioso que existe');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.get_initiative_roster_members\(p_initiative_id uuid\)/);
  assert.match(mig, /FROM public\.v_initiative_roster r/, 'roster derives from the engagement primitive, not the cache');
  assert.ok(!/\.initiative_id\s*=\s*p_initiative_id[\s\S]*FROM public\.public_members\b(?![\s\S]*v_initiative_roster)/.test(mig) || /v_initiative_roster/.test(mig), 'primitive is the source');
});

test('#1217: RPC is confidential-gated and SECURITY DEFINER (LGPD/ADR-0105 parity)', () => {
  assert.match(mig, /SECURITY DEFINER/);
  assert.match(mig, /IF NOT public\.rls_can_see_initiative\(p_initiative_id\) THEN\s*RETURN '\[\]'::jsonb;/);
});

test('#1217: a concessão original revoga anon (a migration que CONCEDEU é a fonte do ACL)', () => {
  // ⚠️ O ACL não vive no corpo da função: `CREATE OR REPLACE` PRESERVA os grants. Afirmar o GRANT
  // contra a captura vigente reprovaria sobre estado correto toda vez que alguém redefinisse o
  // corpo sem repetir a concessão — que é o caminho normal. Então esta camada olha a migration que
  // de fato concedeu, e a camada viva abaixo confirma o efeito no catálogo.
  assert.ok(existsSync(MIG_ORIGINAL), 'a migration que concedeu o ACL sumiu do disco');
  const orig = readFileSync(MIG_ORIGINAL, 'utf8');
  assert.match(orig, /REVOKE ALL ON FUNCTION public\.get_initiative_roster_members\(uuid\) FROM PUBLIC, anon;/);
  assert.match(orig, /GRANT EXECUTE ON FUNCTION public\.get_initiative_roster_members\(uuid\) TO authenticated, service_role;/);
});

test('#1217 DB: anon NÃO alcança a RPC hoje (o ACL vigente, não o texto que o concedeu)',
  { skip: !dbGated && skipMsg }, async () => {
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
  if (!anonKey) return;
  const anon = createClient(SUPABASE_URL, anonKey, { auth: { persistSession: false } });
  const { error } = await anon.rpc('get_initiative_roster_members',
    { p_initiative_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(error, 'anon executou a RPC de roster: o REVOKE se perdeu em algum CREATE OR REPLACE');
  assert.notEqual(error.code, 'PGRST202',
    'anon foi barrado porque a função sumiu do schema cache, não porque o ACL a protege');
});

test('#1217: DISTINCT ON person keeps the highest-authority role (leader wins)', () => {
  // O alias deixou de ser fixo em `r` quando a #2334 passou a unir efetivos e visitantes numa
  // subconsulta (`u`). O que este guard protege é a PRECEDÊNCIA — uma pessoa aparece uma vez, com
  // o papel de maior autoridade —, não a letra do alias.
  assert.match(mig, /SELECT DISTINCT ON \(\w+\.person_id\)/,
    'a deduplicação por pessoa sumiu: a mesma pessoa passaria a aparecer duas vezes no roster');
  assert.match(mig, /WHEN 'leader' THEN 0/,
    'a prioridade de líder sumiu da ordenação: o DISTINCT ON poderia eleger um papel menor e o ' +
    'líder desapareceria da própria tribo — a regressão original do #1217');
});

test('#1217: tribe page loads the members list via the RPC (not public_members.initiative_id cache)', () => {
  assert.ok(existsSync(PAGE), 'tribe page present');
  assert.match(page, /sb\.rpc\('get_initiative_roster_members', \{ p_initiative_id: INITIATIVE_ID \}\)/);
  // forward-defense: the old cache-based leg (public_members filtered by initiative_id) must be gone
  assert.ok(
    !/\.from\('public_members'\)[\s\S]{0,240}\.eq\('initiative_id', INITIATIVE_ID\)/.test(page),
    'the public_members.initiative_id cache query must no longer feed the members list',
  );
});

// ── DB-gated: the regression guard — leader appears on their own page ────────────
test('#1217 DB: every active tribe leader appears in their own initiative roster', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: tribes, error } = await sb
    .from('tribes')
    .select('id, leader_member_id')
    .eq('is_active', true)
    .not('leader_member_id', 'is', null);
  assert.ok(!error, error?.message);

  for (const t of tribes) {
    const { data: initId, error: rErr } = await sb.rpc('resolve_initiative_id', { p_tribe_id: t.id });
    assert.ok(!rErr, rErr?.message);
    if (!initId) continue; // legacy tribe with no initiative bridge — RPC path does not apply
    const { data: roster, error: mErr } = await sb.rpc('get_initiative_roster_members', { p_initiative_id: initId });
    assert.ok(!mErr, mErr?.message);
    const ids = (Array.isArray(roster) ? roster : []).map((m) => m.id);
    assert.ok(
      ids.includes(t.leader_member_id),
      `tribe ${t.id}: leader_member_id ${t.leader_member_id} must appear in get_initiative_roster_members (found ${ids.length} members)`,
    );
  }
});
