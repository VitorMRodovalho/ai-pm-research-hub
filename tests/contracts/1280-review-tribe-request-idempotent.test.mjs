/**
 * Contract: #1280 — review_tribe_request(approve) é idempotente contra engagement ativa pré-existente.
 *
 * Incidente (2026-07-10, pego pelo check-invariants): David Gentil ficou com DUAS engagements
 * volunteer/active na MESMA research_tribe initiative — um stub retroativo do backfill #1247 mais a
 * engagement canônica criada quando o líder aprovou o join-request pendente para a mesma tribo.
 * O approve demovia volunteer em OUTRAS tribos (tribe switch) mas INSERIA incondicionalmente na
 * tribo alvo, violando AH_research_tribe_single_active_engagement (a invariante só DETECTAVA pós-fato).
 *
 * Fix (#1280): antes do INSERT, o write-path checa se já existe engagement do mesmo kind_scope ativa
 * nesta MESMA initiative; se sim, reusa (no-op) em vez de inserir uma segunda. Classe dual-write.
 *
 * Duas travas:
 *  (1) static — o corpo capturado do RPC guarda o INSERT atrás do reuse-if-exists (SELECT ... INTO
 *      v_engagement_id ... ; IF v_engagement_id IS NULL THEN INSERT). Falha se um refactor remover.
 *  (2) DB invariante (AH) — nenhuma (person, initiative) research_tribe tem >1 volunteer/active.
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

// Latest migration capturing the review_tribe_request body.
function latestReviewTribeRequestBody() {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  let body = null;
  for (const f of files) {
    const sql = readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8');
    if (/CREATE OR REPLACE FUNCTION public\.review_tribe_request\s*\(/.test(sql)) {
      body = sql;
    }
  }
  return body;
}

test('#1280 static: review_tribe_request guards the engagement INSERT behind a reuse-if-exists check', () => {
  const body = latestReviewTribeRequestBody();
  assert.ok(body, 'a migration must capture CREATE OR REPLACE FUNCTION public.review_tribe_request(');

  // The idempotency guard: select an existing active engagement into v_engagement_id, then only
  // INSERT when none was found. Normalize whitespace for a resilient match.
  const norm = body.replace(/\s+/g, ' ');
  assert.match(
    norm,
    /SELECT e\.id INTO v_engagement_id[\s\S]*?e\.status = 'active'/,
    'must SELECT an existing active engagement into v_engagement_id before inserting',
  );
  assert.match(
    norm,
    /IF v_engagement_id IS NULL THEN INSERT INTO public\.engagements/,
    'the INSERT must be gated by IF v_engagement_id IS NULL (reuse when one already exists)',
  );
});

test('#1280 DB: no person holds >1 active volunteer engagement in the same research_tribe (AH baseline)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('engagements')
    .select('person_id, initiative_id, initiatives!inner(kind)')
    .eq('kind', 'volunteer')
    .eq('status', 'active')
    .eq('initiatives.kind', 'research_tribe');
  assert.ok(!error, `query must not error: ${error?.message}`);

  const counts = new Map();
  for (const e of data || []) {
    const key = `${e.person_id}:${e.initiative_id}`;
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  const offenders = [...counts.entries()].filter(([, n]) => n > 1).map(([k, n]) => ({ key: k, n }));
  assert.equal(
    offenders.length,
    0,
    `AH_research_tribe_single_active_engagement: no (person, tribe) may hold >1 active volunteer ` +
      `engagement (approval idempotency, #1280). Offenders: ${JSON.stringify(offenders)}`,
  );
});
