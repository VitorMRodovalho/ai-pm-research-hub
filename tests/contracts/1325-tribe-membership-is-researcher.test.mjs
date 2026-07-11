/**
 * Contract: #1325 — a membresia numa research_tribe (via o picker) concede 'researcher', não 'participant'.
 *
 * Incidente (2026-07-11, reportado pela membra Ligia Ribeiro): sumiu do ranking público de trilha.
 * review_tribe_request(approve) inseria o engagement de entrada com role='participant'.
 * sync_operational_role_cache mapeia volunteer/participant para o fallback 'guest' (não casa nenhuma
 * regra de researcher/leader), e get_public_trail_ranking exclui operational_role IN (...,'guest').
 * Quem entrou por seleção (approve_selection_application) recebe volunteer/researcher e aparece; quem
 * entrou pelo picker só NÃO caía para guest se tivesse um SEGUNDO vínculo researcher concorrente.
 *
 * Fix (#1325, owner opção B): o approve passa a inserir role='researcher', alinhando o picker à seleção
 * e eliminando a classe "guest em tribo" de raiz.
 *
 * Duas travas:
 *  (1) static — o corpo capturado do RPC insere 'researcher' (não 'participant') no engagement de entrada.
 *  (2) DB invariante — nenhum membro ativo COM tribe_id tem operational_role='guest'.
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

test('#1325 static: review_tribe_request inserts role researcher (not participant) for the tribe-entry engagement', () => {
  const body = latestReviewTribeRequestBody();
  assert.ok(body, 'a migration must capture CREATE OR REPLACE FUNCTION public.review_tribe_request(');

  const norm = body.replace(/\s+/g, ' ');
  // The INSERT VALUES ordering is (person_id, initiative_id, kind, role, status, ...): the role literal
  // sits immediately before the 'active' status literal. Assert it is 'researcher', not 'participant'.
  assert.match(
    norm,
    /'researcher', 'active', 'consent'/,
    "the tribe-entry engagement must be inserted with role='researcher' (#1325)",
  );
  assert.doesNotMatch(
    norm,
    /'participant', 'active', 'consent'/,
    "the tribe-entry engagement must NOT be inserted with role='participant' (maps to operational_role=guest, #1325)",
  );
});

test('#1325 DB: no active member with a tribe_id has operational_role=guest', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('members')
    .select('id, tribe_id, operational_role')
    .not('tribe_id', 'is', null)
    .eq('is_active', true)
    .eq('operational_role', 'guest');
  assert.ok(!error, `query must not error: ${error?.message}`);

  assert.equal(
    (data || []).length,
    0,
    `A member sitting in a tribe (tribe_id not null) must never be operational_role='guest' — guest is ` +
      `excluded from get_public_trail_ranking, so a tribe member would silently vanish (#1325). ` +
      `Offenders (member ids): ${JSON.stringify((data || []).map((m) => m.id))}`,
  );
});
