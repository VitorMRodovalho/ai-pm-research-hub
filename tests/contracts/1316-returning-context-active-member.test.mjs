/**
 * Contract: #1316 (parte C) — get_application_returning_context deriva contexto do estado VIVO.
 *
 * Um membro ATIVO que re-candidata (ex. Luciana Dutra, Ciclo 1 Goiás via 62106) aparecia no pipeline
 * como "rejeitado" sem sinalizar que já é membro ativo, porque o painel de contexto era gated na coluna
 * gravada `selection_applications.is_returning_member` (false p/ quem entrou fora do fluxo de seleção —
 * 34/99 engagements ativos têm selection_application_id=null; 81 apps casam membro ativo, 7 rejected).
 *
 * Fix: a RPC deriva `already_active_member` (membro casado ativo e não offboarded) + `previous_cycles`
 * do mirror legado `volunteer_applications` (ao vivo). A UII sempre carrega o painel e mostra o callout
 * "já é membro ativo".
 *
 * Travas:
 *  (1) static — a migration deriva already_active_member + previous_cycles do volunteer_applications;
 *      o selection.astro sempre chama loadReturningContext (gate removido) + renderiza o callout;
 *      i18n nas 3 dicionárias.
 *  (2) DB — existe app rejeitada cujo candidato é membro ativo (a classe é load-bearing).
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
const SELECTION_PAGE = resolve(process.cwd(), 'src/pages/admin/selection.astro');

function latestBodyMatching(re) {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  let body = null;
  for (const f of files) {
    const sql = readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8');
    if (re.test(sql)) body = sql;
  }
  return body;
}

test('#1316(C) static: RPC derives already_active_member + previous_cycles from live sources', () => {
  const body = latestBodyMatching(/CREATE OR REPLACE FUNCTION public\.get_application_returning_context\s*\(/);
  assert.ok(body, 'a migration must capture get_application_returning_context');
  const norm = body.replace(/\s+/g, ' ');
  assert.match(norm, /'already_active_member'/, 'must expose already_active_member');
  assert.match(
    norm,
    /member_status = 'active' AND v_matched_member\.offboarded_at IS NULL/,
    'already_active_member must be derived from the live member state',
  );
  assert.match(
    norm,
    /FROM public\.volunteer_applications va WHERE va\.member_id = v_matched_member\.id/,
    'previous_cycles must be derived from the legacy volunteer_applications mirror',
  );
});

test('#1316(C) static: selection UI always loads the panel + renders the active-member callout', () => {
  const src = readFileSync(SELECTION_PAGE, 'utf8');
  // The panel container is no longer gated on row.is_returning_member.
  assert.doesNotMatch(
    src,
    /\$\{row\.is_returning_member \? `<div id="returning-context-panel"/,
    'the returning-context panel must not be gated on row.is_returning_member (#1316 C)',
  );
  // loadReturningContext is called unconditionally.
  assert.match(
    src,
    /\/\/ #91 G4 \+ #1316\(C\)[\s\S]*?loadReturningContext\(row\.id\);/,
    'loadReturningContext must be called unconditionally',
  );
  // Active-member callout branch present + i18n keys wired.
  assert.match(src, /alreadyActive = data\.already_active_member === true/, 'reads the derived flag');
  assert.match(src, /T\.modal\.activeMemberBadge/, 'renders the active-member badge');
  assert.match(src, /T\.modal\.activeMemberCycles/, 'renders participated cycles');
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const d = readFileSync(resolve(process.cwd(), `src/i18n/${dict}.ts`), 'utf8');
    for (const key of ['activeMemberBadge', 'activeMemberNote', 'activeMemberCycles']) {
      assert.ok(d.includes(`'admin.selection.modal.${key}'`), `i18n key ${key} missing in ${dict}`);
    }
  }
});

test('#1316(C) DB: a rejected application whose applicant is an active member exists (load-bearing)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // The class the fix targets: rejected in the pipeline but actually an active member.
  const { data: apps, error } = await sb
    .from('selection_applications')
    .select('email, status')
    .eq('status', 'rejected');
  assert.ok(!error, `query must not error: ${error?.message}`);
  const emails = [...new Set((apps || []).map((a) => (a.email || '').toLowerCase()).filter(Boolean))];
  assert.ok(emails.length > 0, 'expected some rejected applications');

  const { data: members, error: mErr } = await sb
    .from('members')
    .select('email')
    .eq('is_active', true);
  assert.ok(!mErr, `members query must not error: ${mErr?.message}`);
  const activeEmails = new Set((members || []).map((m) => (m.email || '').toLowerCase()).filter(Boolean));

  const rejectedButActive = emails.filter((e) => activeEmails.has(e));
  assert.ok(
    rejectedButActive.length > 0,
    'expected at least one rejected applicant who is an active member (the class #1316 C surfaces)',
  );
});
