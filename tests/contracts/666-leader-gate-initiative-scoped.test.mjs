/**
 * #666 — _can_sign_gate('leader') escopado ao LÍDER DA INICIATIVA do documento
 *
 * Bug: `WHEN 'leader' THEN can_by_member(member,'sign_chain_leader')` deixava QUALQUER tribe_leader
 * elegível no gate 'leader' (role-based), não só o líder da iniciativa do doc. Fix (mig
 * 20260805000156): escopa a `v_initiative_roster` (role='leader') da iniciativa do documento, com
 * fallback p/ a capability quando o doc não tem iniciativa (back-compat). `leader_awareness` (ciência
 * ampla) fica INALTERADO.
 *
 * Source-contract (offline) trava a forma do predicado. O behavioural (DB) prova o comportamento
 * resolvendo a chain/iniciativa AO VIVO (skip se não houver chain com gate 'leader').
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000156_666_leader_gate_initiative_scoped.sql', import.meta.url)),
  'utf8',
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

function headers() {
  return { 'Content-Type': 'application/json', apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` };
}
async function rpc(fn, args) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers: headers(), body: JSON.stringify(args) });
  if (!res.ok) throw new Error(`rpc ${fn} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}
async function getRows(table, query) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, { headers: headers() });
  if (!res.ok) throw new Error(`${table} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

// ── Source contract (offline) ───────────────────────────────────────────────
test("666: doc lookup resolves initiative_id for the 'leader' scope", () => {
  assert.match(MIG, /SELECT gd\.doc_type, gd\.initiative_id INTO v_doc_type, v_doc_initiative_id/, 'must resolve the doc initiative');
  assert.match(MIG, /v_doc_initiative_id\s+uuid;/, 'declares the initiative var');
});

test("666: 'leader' gate is scoped to the doc's initiative roster leader (with NULL-initiative fallback)", () => {
  // capability still required
  assert.match(MIG, /WHEN 'leader' THEN\s*\n\s*public\.can_by_member\(v_member\.id, 'sign_chain_leader'\)/, 'capability still required');
  // scoped to v_initiative_roster role=leader of the doc initiative
  assert.match(MIG, /public\.v_initiative_roster r/, 'scope via initiative roster');
  assert.match(MIG, /r\.initiative_id = v_doc_initiative_id/, 'roster scoped to the doc initiative');
  assert.match(MIG, /r\.role = 'leader'/, 'roster role = leader');
  // back-compat fallback for NON-charter docs without an initiative; project_charter w/o initiative fails closed (F1)
  assert.match(MIG, /v_doc_initiative_id IS NULL AND v_doc_type IS DISTINCT FROM 'project_charter'/, 'NULL-initiative fallback EXCLUDES project_charter (#666 F1 fail-closed)');
});

test("666: 'leader_awareness' stays broad (unchanged)", () => {
  assert.match(MIG, /WHEN 'leader_awareness' THEN public\.can_by_member\(v_member\.id, 'sign_chain_leader'\)/, 'awareness gate unchanged');
});

// ── Behavioural (DB, guarded) ────────────────────────────────────────────────
test(canRun ? "666: initiative leader eligible, OTHER leader denied on a live 'leader' gate" : skipMsg, { skip: !canRun }, async () => {
  // find a review/approved chain that carries a 'leader' gate
  const chains = await getRows('approval_chains', 'status=in.(review,approved)&select=id,document_id,gates');
  const chain = chains.find(c => Array.isArray(c.gates) && c.gates.some(g => g?.kind === 'leader'));
  if (!chain) { console.log('  (skip: no review/approved chain with a leader gate live)'); return; }

  // the doc's initiative + its roster leader
  const docs = await getRows('governance_documents', `id=eq.${chain.document_id}&select=initiative_id`);
  const initiativeId = docs[0]?.initiative_id;
  if (!initiativeId) { console.log('  (skip: leader-gate doc has no initiative)'); return; }

  const rosterLeaders = await getRows('v_initiative_roster', `initiative_id=eq.${initiativeId}&role=eq.leader&select=member_id`);
  const leaderId = rosterLeaders[0]?.member_id;
  if (!leaderId) { console.log('  (skip: initiative has no roster leader)'); return; }

  // a DIFFERENT active tribe_leader (holds sign_chain_leader) who is NOT this initiative's leader
  const others = await getRows('members', `operational_role=eq.tribe_leader&is_active=eq.true&id=neq.${leaderId}&select=id&limit=1`);
  const otherLeaderId = others[0]?.id;

  const leaderCanSign = await rpc('_can_sign_gate', { p_member_id: leaderId, p_chain_id: chain.id, p_gate_kind: 'leader' });
  assert.equal(leaderCanSign, true, 'the initiative roster leader MUST be eligible on the leader gate');

  if (otherLeaderId) {
    const otherCanSign = await rpc('_can_sign_gate', { p_member_id: otherLeaderId, p_chain_id: chain.id, p_gate_kind: 'leader' });
    assert.equal(otherCanSign, false, 'a tribe_leader of a DIFFERENT initiative MUST be denied (fail-closed scope)');
  } else {
    console.log('  (partial: no other tribe_leader to assert the denial against)');
  }
});

test(canRun ? "666 F1: project_charter without an initiative fails closed on 'leader' (no 'any leader')" : skipMsg, { skip: !canRun }, async () => {
  const leaders = await getRows('members', 'operational_role=eq.tribe_leader&is_active=eq.true&select=id&limit=1');
  const leaderId = leaders[0]?.id;
  if (!leaderId) { console.log('  (skip: no active tribe_leader live)'); return; }
  // doc_type-only path (no chain) → v_doc_initiative_id stays NULL:
  const onCharter = await rpc('_can_sign_gate', { p_member_id: leaderId, p_chain_id: null, p_gate_kind: 'leader', p_doc_type: 'project_charter' });
  assert.equal(onCharter, false, 'a project_charter with no initiative MUST NOT be signable by any leader (F1 fail-closed)');
  const onPolicy = await rpc('_can_sign_gate', { p_member_id: leaderId, p_chain_id: null, p_gate_kind: 'leader', p_doc_type: 'policy' });
  assert.equal(onPolicy, true, 'a non-charter org doc with no initiative keeps the capability fallback (back-compat)');
});
