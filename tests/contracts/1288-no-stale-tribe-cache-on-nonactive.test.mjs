/**
 * Contract: #1288 — tribos antigas NAO devem exibir quem saiu (higiene do cache dual-write).
 *
 * Diagnostico (2026-07-11): NAO era bug de renderizacao. Toda superficie de roster de tribo
 * filtra is_active / current_cycle_active / member_status, entao membros nao-ativos com
 * members.tribe_id stale NAO apareciam. Era DIVIDA DE DADO: 15 membros alumni/inactive
 * retinham members.tribe_id/initiative_id de offboards ANTERIORES ao fix de democao dual-write
 * (#1270, 2026-07-10 — [[reference-dual-write-demotion-clear-both-columns]]). Reconciliado ao vivo.
 *
 * Recorrencia ja prevenida: a ponte dual-write (#1270) re-deriva members.tribe_id das engagements
 * ATIVAS; ao offboardar, o engagement vai a 'offboarded' -> a ponte zera o cache (validado com
 * Cintia no primeiro uso real do #1020). Este teste e a rede de seguranca: falha se o invariante
 * regredir (ex.: um caminho de mudanca de status que nao feche a engagement).
 *
 * Invariante: nenhum member com member_status <> 'active' pode reter members.tribe_id
 * OU members.initiative_id (o cache single-slot da posse de tribo). O historico de tribo do
 * desligado vive em member_offboarding_records.tribe_id_at_offboard, nao no cache vivo.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1288 DB: no non-active member retains a live tribe_id/initiative_id cache', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('members')
    .select('id, name, member_status, tribe_id, initiative_id')
    .neq('member_status', 'active')
    .or('tribe_id.not.is.null,initiative_id.not.is.null');

  assert.ok(!error, `query must not error: ${error?.message}`);
  const offenders = (data || []).map((m) => ({
    id: m.id, name: m.name, status: m.member_status, tribe_id: m.tribe_id, initiative_id: m.initiative_id,
  }));
  assert.equal(
    offenders.length,
    0,
    `non-active members must not retain tribe_id/initiative_id (dual-write demotion #1270 clears both). ` +
      `Offenders: ${JSON.stringify(offenders)}`,
  );
});
