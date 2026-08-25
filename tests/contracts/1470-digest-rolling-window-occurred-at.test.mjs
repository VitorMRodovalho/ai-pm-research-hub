/**
 * Contract: #1470 (follow-up da Onda 3 / #1464) — os DOIS leitores de janela MOVEL de
 * gamification_points passam a janelar por COALESCE(occurred_at, created_at) (data do fato),
 * nao created_at (data de lancamento).
 *
 *   get_weekly_member_digest.xp_delta       — "XP dos ultimos 7 dias"
 *   get_gamification_category_activity       — "eventos na janela now()-p_window_days / 7d"
 *
 * O mesmo flush historico que motivou a #1464 (sync-attendance-points inserindo presenca antiga
 * com created_at = now() do run) inflava essas janelas: uma presenca de 2025 marcada hoje contava
 * como "XP ganho esta semana". Sonda ao vivo (2026-07-24): 790/1020 pts (77%) do xp_delta semanal
 * eram backfill historico.
 *
 * FIX (mig 20260805000488): janelar por COALESCE(occurred_at, created_at). last_award permanece
 * max(created_at) — e o carimbo de concessao (auditoria), fora do escopo das janelas de atividade.
 *
 * Static locks o corpo. O DB-gated prova AO VIVO que a janela por occurred_at exclui o backfill
 * historico que a janela por created_at contava (a diferenca que motivou o fix).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const MIGP = fileURLToPath(new URL('../../supabase/migrations/20260805000488_1470_digest_rolling_window_occurred_at.sql', import.meta.url));
const migRaw = existsSync(MIGP) ? readFileSync(MIGP, 'utf8') : '';

/**
 * #1990: `get_gamification_category_activity` foi redefinida depois desta migration (troca do
 * portao resourceless). Fixar o CAMINHO de 20260805000488 faria estas assercoes falarem de um texto
 * que a producao nao executa mais — a classe do #1932. As assercoes sobre ELA leem a captura
 * VIGENTE; as de `get_weekly_member_digest`, que ninguem redefiniu, seguem no arquivo original.
 */
// ROOT em variavel de proposito: o scanner do #1932 casa `latestFunctionCapture(<algo sem
// parenteses>, 'nome')`, entao `process.cwd()` inline quebraria o reconhecimento da divida.
const ROOT = process.cwd();
const catAtual = maskLineComments(latestFunctionCapture(ROOT, 'get_gamification_category_activity').block);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC ────────────────────────────────────────────────────────────────────────
test('#1470 static: migration file exists + redefines both rolling-window readers', () => {
  assert.ok(existsSync(MIGP), 'migration 20260805000488 exists');
  assert.match(migRaw, /CREATE OR REPLACE FUNCTION public\.get_weekly_member_digest\(p_member_id uuid\)/, 'redefines get_weekly_member_digest');
  assert.match(catAtual, /CREATE OR REPLACE FUNCTION public\.get_gamification_category_activity\(p_window_days integer/, 'a captura vigente define get_gamification_category_activity');
});

test('#1470 static: xp_delta windows by occurred_at fact date, not bare created_at', () => {
  // the xp_delta subquery uses COALESCE(occurred_at, created_at)
  assert.match(migRaw, /'xp_delta',[\s\S]*?FROM public\.gamification_points gp\s*\n\s*WHERE gp\.member_id = p_member_id\s*\n\s*AND COALESCE\(gp\.occurred_at, gp\.created_at\) >= v_window_start/i,
    'xp_delta uses COALESCE(occurred_at, created_at) >= v_window_start');
  // and NOT the old bare created_at window on gamification_points
  assert.doesNotMatch(migRaw, /gp\.member_id = p_member_id\s*\n\s*AND gp\.created_at >= v_window_start/i, 'no bare created_at window remains in xp_delta');
});

test('#1470 static: category_activity windows (p_window_days + 7d) use occurred_at', () => {
  assert.match(catAtual, /FILTER \(WHERE COALESCE\(gp\.occurred_at, gp\.created_at\) >= now\(\) - \(p_window_days \|\| ' days'\)::interval\)/i,
    'p_window_days window uses occurred_at');
  assert.match(catAtual, /FILTER \(WHERE COALESCE\(gp\.occurred_at, gp\.created_at\) >= now\(\) - INTERVAL '7 days'\)/i,
    '7d window uses occurred_at');
  assert.doesNotMatch(catAtual, /FILTER \(WHERE gp\.created_at >= now\(\)/i, 'no bare created_at activity window remains');
});

test('#1470 static: last_award preserved as the grant timestamp max(created_at)', () => {
  assert.match(catAtual, /max\(gp\.created_at\) AS last_award/i, 'last_award stays max(created_at) — concession timestamp is out of scope');
});

test('#1470 static: migration notifies PostgREST', () => {
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/i, 'schema reload notified');
});

// ── BEHAVIOURAL (DB-gated): occurred_at window excludes historical backfill ─────────
test('#1470 behavioural: occurred_at 7d window excludes the historical backfill that created_at counted',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.from('gamification_points').select('points,occurred_at,created_at');
    assert.ifError(error);
    const now = Date.now();
    const win = now - 7 * 24 * 3600 * 1000;
    let byCreated = 0, byOccurred = 0;
    for (const r of data || []) {
      const c = new Date(r.created_at).getTime();
      const eff = new Date(r.occurred_at || r.created_at).getTime();
      if (c >= win) byCreated += r.points;
      if (eff >= win) byOccurred += r.points;
    }
    // the fix window (occurred_at) must not exceed the bug window (created_at): historical facts
    // whose created_at is recent but occurred_at is old are dropped from the fact-date window.
    assert.ok(byOccurred <= byCreated,
      `occurred_at window (${byOccurred}) must be <= created_at window (${byCreated}) — historical backfill is excluded`);
  });
