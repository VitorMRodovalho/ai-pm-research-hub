/**
 * Contract: #1477 — check_my_tcv_readiness isenta por label SÓ na ausência de engagement operacional.
 *
 * Bug: a isenção do TCV usava `operational_role IN (labels)` — o cache de EXIBIÇÃO single-valued que colapsa
 * multi-hat (antipadrão do arco #1476). Dois membros `chapter_liaison` que TAMBÉM têm tier operacional ativo
 * via engagement (v_member_operational_tiers, a junction canonical da Onda 2) escapavam do termo de voluntariado
 * mas devem assiná-lo.
 *
 * Fix (rota A, carve-out cirúrgico, ratificado owner 2026-07-24): o label só isenta quando NOT EXISTS em
 * v_member_operational_tiers. Corrige os 2 dual-hat com 0 ripple (os 45 alumni/guest/null seguem não-isentos).
 * Escolhido sobre isenção-pura-por-engagement (rota B) porque o TCV é gate contratual PMI-GO: over-inclusivo é
 * seguro, under-inclusivo seria lacuna de conformidade se a junction omitisse um voluntário operacional real.
 *
 * Travas:
 *  (1) static — o corpo capturado mantém a lista-rótulo E adiciona o carve-out `NOT EXISTS
 *      v_member_operational_tiers`.
 *  (2) DB — service_role (auth.uid()=null) recebe not_authenticated (RPC existe, fail-closed); e a superfície
 *      dual-hat (label + engagement) EXISTE nos dados (o carve-out é load-bearing).
 *
 * Comportamento (dual-hat -> applicable=true / label-sem-engagement -> role_exempt) verificado por impersonação
 * (set_config request.jwt.claims) em QA manual desta sessão -- supabase-js não seta jwt.claims + chama a RPC numa
 * transação (ver nota em 1326-my-meetings-audience-scope / 1474-wave5b-candidate-transparency-gate).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');

function latestBodyMatching(re) {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  let body = null;
  for (const f of files) {
    const sql = readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8');
    if (re.test(sql)) body = sql;
  }
  return body;
}

test('#1477 static: check_my_tcv_readiness keeps the label list AND carves out operational engagement', () => {
  const body = latestBodyMatching(/CREATE OR REPLACE FUNCTION public\.check_my_tcv_readiness\s*\(/);
  assert.ok(body, 'a migration must capture CREATE OR REPLACE FUNCTION public.check_my_tcv_readiness(');
  const norm = body.replace(/\s+/g, ' ');

  // The exempt label list is retained (route A keeps the labels as the base).
  for (const label of ['sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor']) {
    assert.match(norm, new RegExp(`'${label}'`), `exempt label ${label} must remain in the gate`);
  }

  // The carve-out: the label only exempts when there is NO operational engagement.
  assert.match(
    norm,
    /NOT EXISTS \( SELECT 1 FROM public\.v_member_operational_tiers t WHERE t\.member_id = v_member\.id \)/,
    'exemption must be carved out by NOT EXISTS over v_member_operational_tiers (#1477 route A)',
  );
  // Guard the coupling: the carve-out must gate the SAME role_exempt branch (AND, not a separate IF).
  assert.match(
    norm,
    /operational_role IN \('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor'\) AND NOT EXISTS/,
    'the label IN (...) and the NOT EXISTS carve-out must be ANDed in one condition',
  );
});

test('#1477 DB: RPC lives and is fail-closed for service-role (auth.uid null)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_my_tcv_readiness');
  assert.ifError(error);
  assert.equal(data?.error, 'not_authenticated', 'service-role (no auth.uid) must return not_authenticated');
});

test('#1477 DB: the dual-hat carve-out surface exists (label + operational engagement)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // Members carrying an exempt display label whose canonical junction still lists an operational tier.
  // Without the #1477 carve-out these would be wrongly exempted from the TCV. The guard is load-bearing:
  // if this surface is ever empty the behavioural fix cannot be exercised and the test should be revisited.
  const { data: tiers, error: e1 } = await sb.from('v_member_operational_tiers').select('member_id');
  assert.ifError(e1);
  const opMemberIds = new Set((tiers ?? []).map((r) => r.member_id));

  const { data: labeled, error: e2 } = await sb
    .from('members')
    .select('id, operational_role')
    .in('operational_role', ['sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor']);
  assert.ifError(e2);

  const dualHat = (labeled ?? []).filter((m) => opMemberIds.has(m.id));
  assert.ok(dualHat.length >= 1, `expected >=1 dual-hat member (exempt label + operational engagement), got ${dualHat.length}`);
});
