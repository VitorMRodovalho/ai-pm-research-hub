// #1257 (Wave 3) — Leader-review hardening: 7d TTL on tribe requests, D-2 leader nudge + GP fallback
// cron, and the #1263 atomic tribe switch on approval. Static test over the migration (the DB is
// production; the body-drift Phase C gate covers live drift). See
// docs/specs/SPEC_TRIBE_SWITCH_AND_LEADER_REVIEW.md §Wave 3.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIG = join(
  __dirname,
  '../../supabase/migrations/20260805000395_1257_wave3_leader_review_hardening.sql',
);
const sql = readFileSync(MIG, 'utf8');

// ── TTL 7d (tribe path only) ──

test('#1257: request_tribe_assignment seta expires_at = now()+7d EXPLÍCITO no INSERT', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.request_tribe_assignment\(p_tribe_id integer, p_message text\)/,
  );
  // o INSERT passa expires_at na lista de colunas e o valor de 7 dias no VALUES
  assert.match(
    sql,
    /INSERT INTO public\.initiative_invitations\s*\n\s*\(initiative_id, invitee_member_id, inviter_member_id, kind_scope, message, expires_at\)/,
    'expires_at deve estar na lista de colunas do INSERT',
  );
  assert.match(sql, /'volunteer', p_message, now\(\) \+ interval '7 days'\)/, 'valor 7d no VALUES');
  assert.match(sql, /'expires_at', \(now\(\) \+ interval '7 days'\)/, 'RETURN reflete 7d');
});

test('#1257: NÃO altera o default da tabela (convites líder→pesquisador seguem 72h)', () => {
  // a migration não deve tocar no DEFAULT de initiative_invitations.expires_at
  assert.doesNotMatch(sql, /ALTER COLUMN expires_at SET DEFAULT/i, 'não pode mexer no default de 72h');
  assert.doesNotMatch(sql, /ALTER TABLE[^;]*expires_at[^;]*DEFAULT/i);
});

// ── #1263 atomic tribe switch ──

test('#1257/#1263: review_tribe_request demite a engagement de tribo anterior na admissão', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.review_tribe_request\(p_invitation_id uuid, p_decision text, p_note text DEFAULT NULL::text\)/,
  );
  // demote-block: offboarded, mesmo person, outra tribo, ANTES do INSERT da nova engagement
  assert.match(sql, /SET status = 'offboarded',/, "usa 'offboarded' (status válido)");
  assert.match(sql, /revoke_reason = 'tribe_switch_on_approval'/, 'marca a demissão como troca');
  assert.match(
    sql,
    /AND e\.initiative_id <> v_invitation\.initiative_id/,
    'só demite tribos DIFERENTES da alvo',
  );
});

test('#1257/#1263: a demissão NUNCA usa o status inválido revoked', () => {
  // 'revoked' não existe em engagements_status_check — o incidente da Wave 2 já provou isso.
  assert.doesNotMatch(sql, /status = 'revoked'/, "não pode usar 'revoked' em engagements");
});

test('#1257/#1263: a demissão precede o INSERT da nova engagement (troca atômica)', () => {
  const demoteIdx = sql.indexOf("revoke_reason = 'tribe_switch_on_approval'");
  const insertIdx = sql.indexOf("'source', 'tribe_request_approved'");
  assert.ok(demoteIdx > 0 && insertIdx > 0, 'ambos os blocos existem');
  assert.ok(demoteIdx < insertIdx, 'demite ANTES de inserir (bridge trigger nunca vê 2 ativas)');
});

test('#1257/#1263: revoked_by usa person_id do caller (FK -> persons)', () => {
  assert.match(sql, /revoked_by = v_caller_person_id/, 'revoked_by = caller person_id (FK persons)');
});

// ── D-2 nudge + GP fallback ──

test('#1257: coluna metadata (jsonb) adicionada em initiative_invitations (dedup do nudge)', () => {
  assert.match(
    sql,
    /ALTER TABLE public\.initiative_invitations\s*\n\s*ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '\{\}'::jsonb/,
  );
});

test('#1257: process_tribe_request_nudges — nudge D-2 ao líder com dedup por metadata', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.process_tribe_request_nudges\(p_dry_run boolean DEFAULT false\)/,
  );
  // janela D-2: pending, expira em <=2 dias, ainda não nudgeado
  assert.match(sql, /ii\.expires_at <= v_run_at \+ interval '2 days'/, 'janela D-2');
  assert.match(sql, /\(ii\.metadata->>'leader_nudged_at'\) IS NULL/, 'dedup do nudge por metadata');
  assert.match(sql, /'tribe_request_nudge'/, 'tipo de notificação do nudge ao líder');
});

test('#1257: GP fallback na expiração — fan-out por manager, dedup por metadata, bound de recência', () => {
  assert.match(sql, /'tribe_request_expired_gp'/, 'tipo de notificação do fallback ao GP');
  assert.match(sql, /\(ii\.metadata->>'gp_fallback_at'\) IS NULL/, 'dedup do fallback por metadata');
  assert.match(
    sql,
    /ii\.expires_at > v_run_at - interval '3 days'/,
    'bound de 3 dias evita blast de backfill',
  );
  assert.match(
    sql,
    /CROSS JOIN public\.members m\s*\n\s*WHERE m\.operational_role = 'manager'/,
    'fan-out 1 por GP (manager), espelha detect_stuck_selection_funnel',
  );
});

test('#1257: process_tribe_request_nudges é cron-only (REVOKE PUBLIC+anon+authenticated, mantém service_role)', () => {
  // Supabase concede EXECUTE a anon/authenticated EXPLICITAMENTE por default privileges; REVOKE só de
  // PUBLIC não basta (#965 forward-defense) — revogar dos três e manter service_role.
  assert.match(
    sql,
    /REVOKE EXECUTE ON FUNCTION public\.process_tribe_request_nudges\(boolean\) FROM PUBLIC, anon, authenticated/,
  );
  assert.match(
    sql,
    /GRANT\s+EXECUTE ON FUNCTION public\.process_tribe_request_nudges\(boolean\) TO service_role/,
  );
});

test('#1257: cron tribe-request-nudge-hourly agendado 15 min após o expire (:00)', () => {
  assert.match(
    sql,
    /cron\.schedule\('tribe-request-nudge-hourly', '15 \* \* \* \*', 'SELECT public\.process_tribe_request_nudges\(\);'\)/,
  );
  // idempotência: unschedule guardado antes do schedule
  assert.match(sql, /PERFORM cron\.unschedule\('tribe-request-nudge-hourly'\)/, 'unschedule idempotente');
});
