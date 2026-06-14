import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG = 'supabase/migrations/20260805000165_676_recurring_meeting_admin_list_rpc.sql';
const PAGE = 'src/pages/admin/agenda-recorrente.astro';
const PAGE_EN = 'src/pages/en/admin/agenda-recorrente.astro';
const PAGE_ES = 'src/pages/es/admin/agenda-recorrente.astro';
const ISLAND = 'src/components/admin/RecurringAgendaIsland.tsx';
const SIDEBAR = 'src/components/admin/AdminSidebar.tsx';
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  : null;

test('#676 slice2 static: admin-list RPC migration exists, gated, read-only', () => {
  const body = read(MIG);
  assert.ok(body, 'migration file present');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_recurring_meeting_admin_list/);
  assert.match(body, /Unauthorized: requires manage_platform/, 'gated to manage_platform');
  assert.match(body, /REVOKE ALL ON FUNCTION public\.get_recurring_meeting_admin_list\(date\) FROM PUBLIC, anon/);
  assert.match(body, /scope_name/, 'returns human-readable scope name');
  assert.match(body, /last_reconciled_at/, 'surfaces last reconcile');
  // read-only: must not INSERT/UPDATE/DELETE events or rules
  assert.ok(!/\bINSERT\s+INTO\b|\bUPDATE\s+public\.|\bDELETE\s+FROM\b/i.test(body), 'admin list RPC is read-only');
});

test('#676 slice2 static: page + locale redirects exist', () => {
  assert.ok(existsSync(PAGE), 'pt-BR page exists');
  assert.ok(existsSync(PAGE_EN), '/en redirect exists');
  assert.ok(existsSync(PAGE_ES), '/es redirect exists');
  const en = read(PAGE_EN), es = read(PAGE_ES);
  assert.match(en, /url=\/admin\/agenda-recorrente\?lang=en-US/);
  assert.match(es, /url=\/admin\/agenda-recorrente\?lang=es-LATAM/);
  const page = read(PAGE);
  assert.match(page, /RecurringAgendaIsland/, 'page mounts the island');
  assert.match(page, /buildPageI18n\(\['comp\.recurringAgenda'/, 'page bundles its i18n namespace');
  // UX gate mirrors manage_platform (server RPC is the real boundary)
  assert.match(page, /operational_role === 'manager'/, 'UX gate mirrors GP');
});

test('#676 slice2 static: nav entry registered in operations section', () => {
  const nav = read(SIDEBAR);
  assert.match(nav, /href: '\/admin\/agenda-recorrente'/, 'sidebar item present');
  assert.match(nav, /permission: 'system\.global_config'/, 'gated to platform managers');
  assert.match(nav, /icon: 'CalendarClock'/, 'icon wired');
  assert.match(nav, /CalendarClock,?\s*\n?\s*\} from 'lucide-react'/, 'icon imported from lucide');
});

test('#676 slice2 static: island reads the admin-list RPC (uses React className)', () => {
  const isl = read(ISLAND);
  assert.match(isl, /rpc\('get_recurring_meeting_admin_list'\)/, 'reads the admin-list RPC');
  assert.ok(!/\bclass=/.test(isl), 'uses className (React), not class');
  // NOTE: write RPCs (update/create/reconcile) were added in Slice 3 — see
  // 676-recurring-agenda-write-path.test.mjs. The island is no longer read-only.
});

test('#676 slice2 static: i18n parity across all 3 dictionaries', () => {
  const KEYS = [
    'admin.breadcrumb.recurringAgenda',
    'comp.recurringAgenda.heading', 'comp.recurringAgenda.subtitle', 'comp.recurringAgenda.loading',
    'comp.recurringAgenda.loadError', 'comp.recurringAgenda.retry', 'comp.recurringAgenda.rulesCount',
    'comp.recurringAgenda.withDrift', 'comp.recurringAgenda.colScope', 'comp.recurringAgenda.colCadence',
    'comp.recurringAgenda.colNext', 'comp.recurringAgenda.colStatus', 'comp.recurringAgenda.colDrift',
    'comp.recurringAgenda.colLink', 'comp.recurringAgenda.weekly', 'comp.recurringAgenda.biweekly',
    'comp.recurringAgenda.statusActive', 'comp.recurringAgenda.statusPaused', 'comp.recurringAgenda.statusArchived',
    'comp.recurringAgenda.missing', 'comp.recurringAgenda.timeOff', 'comp.recurringAgenda.linkOff',
    'comp.recurringAgenda.inSync', 'comp.recurringAgenda.readonlyNote',
    'comp.recurringAgenda.dow1', 'comp.recurringAgenda.dow2', 'comp.recurringAgenda.dow3',
    'comp.recurringAgenda.dow4', 'comp.recurringAgenda.dow5', 'comp.recurringAgenda.dow6', 'comp.recurringAgenda.dow7',
  ];
  for (const dict of DICTS) {
    const body = read(dict);
    for (const k of KEYS) {
      assert.ok(body.includes(`'${k}'`), `${dict} missing key ${k}`);
    }
  }
});

test('#676 slice2 live: admin-list RPC returns rules with scope name + drift', { skip: sb ? false : 'Supabase env required' }, async () => {
  const { data, error } = await sb.rpc('get_recurring_meeting_admin_list');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length >= 9, 'returns all backfilled rules');
  for (const row of data) {
    assert.ok(typeof row.scope_name === 'string' && row.scope_name.length > 0, 'has scope_name');
    assert.ok(['active', 'paused', 'archived'].includes(row.status), 'valid status');
    assert.ok(row.day_of_week >= 1 && row.day_of_week <= 7, 'ISO weekday');
    assert.equal(row.missing_future, Math.max(row.expected_future - row.future_events, 0));
  }
});
