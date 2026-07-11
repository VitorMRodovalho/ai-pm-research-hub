/**
 * Contract: #1313 — members.tribe_id so pode vir de uma engagement de MEMBRESIA (volunteer).
 *
 * Bug (2026-07-11): a ponte dual-write `_sync_tribe_id_from_engagement()` era ASSIMETRICA.
 * O ramo de ATIVACAO setava members.tribe_id para QUALQUER kind ativo numa research_tribe
 * (inclusive observer/speaker/curador), mas o guard de DEMOCAO so reconhece kind='volunteer'
 * para reter o tribe_id. Resultado: Roberto Macedo (observer/curador da T8) tinha tribe_id=8
 * ("membro da tribo") enquanto o roster corretamente NAO o listava — drift dual-write semantico.
 *
 * Fix: o SET passou a exigir NEW.kind='volunteer', espelhando o predicado do guard de democao
 * (em research_tribe TODA membresia e kind='volunteer'; lider e role='leader' dentro de volunteer).
 *
 * Invariante: todo member com members.tribe_id != NULL deve ter ao menos UMA engagement
 * kind='volunteer' status='active' numa initiative research_tribe cujo legacy_tribe_id = tribe_id.
 * Um member cujas engagements de tribo sejam SO observer/speaker/etc NAO pode reter tribe_id.
 *
 * Rede de seguranca contra regressao da assimetria SET-vs-CLEAR (classe #1270 / dual-write).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1313 DB: every member.tribe_id is backed by an active volunteer engagement in that research_tribe', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  // Members carrying a live tribe_id cache.
  const { data: members, error: mErr } = await sb
    .from('members')
    .select('id, name, person_id, tribe_id')
    .not('tribe_id', 'is', null);
  assert.ok(!mErr, `members query must not error: ${mErr?.message}`);

  // Active volunteer engagements in research_tribe initiatives, with the legacy_tribe_id.
  const { data: engs, error: eErr } = await sb
    .from('engagements')
    .select('person_id, kind, status, initiatives!inner(kind, legacy_tribe_id)')
    .eq('kind', 'volunteer')
    .eq('status', 'active')
    .eq('initiatives.kind', 'research_tribe');
  assert.ok(!eErr, `engagements query must not error: ${eErr?.message}`);

  // Set of "person_id:legacy_tribe_id" that legitimately backs a tribe_id.
  const backed = new Set(
    (engs || [])
      .filter((e) => e.initiatives && e.initiatives.legacy_tribe_id != null)
      .map((e) => `${e.person_id}:${e.initiatives.legacy_tribe_id}`),
  );

  const offenders = (members || [])
    .filter((m) => m.person_id != null)
    .filter((m) => !backed.has(`${m.person_id}:${m.tribe_id}`))
    .map((m) => ({ id: m.id, name: m.name, tribe_id: m.tribe_id }));

  assert.equal(
    offenders.length,
    0,
    `members.tribe_id must be backed by an active volunteer engagement in that research_tribe ` +
      `(observer/speaker/etc must NOT populate the cache — #1313 SET/CLEAR symmetry). ` +
      `Offenders: ${JSON.stringify(offenders)}`,
  );
});
