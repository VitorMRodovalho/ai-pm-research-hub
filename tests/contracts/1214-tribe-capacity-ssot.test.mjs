// #1214 — Tribe capacity SSOT guard (static + DB-aware, padrão #1087 O2 / Pattern 47).
//
// Regressão: a landing exibia "Máx. 10" e o gate client de tribo-cheia só fechava aos 10,
// enquanto o SSOT vivo (platform_settings.max_researchers_per_tribe) e o gate server
// (select_tribe via tribe_capacity_limit()) usavam 7.
//
// Contrato:
//   Parte 1 (estática): TribesSection deriva maxSlots de get_homepage_stats
//     (max_researchers_per_tribe) com MAX_SLOTS como fallback, usa maxSlots no template
//     (dots + contador) e injeta o valor resolvido no client script via define:vars.
//   Parte 2 (DB-aware, skip sem creds): o fallback MAX_SLOTS do frontend, o RPC
//     get_homepage_stats e o helper tribe_capacity_limit() batem com o SSOT
//     platform_settings.max_researchers_per_tribe.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(root, p), 'utf8');

const tribesData = read('src/data/tribes.ts');
const tribesSection = read('src/components/sections/TribesSection.astro');

const maxSlotsMatch = tribesData.match(/export const MAX_SLOTS = (\d+);/);

// ── Parte 1 — estática ───────────────────────────────────────────────────────
test('P1: TribesSection deriva maxSlots de get_homepage_stats com fallback MAX_SLOTS', () => {
  assert.match(tribesSection, /let maxSlots = MAX_SLOTS;/,
    'maxSlots deve inicializar no fallback MAX_SLOTS');
  assert.match(tribesSection,
    /typeof data\.max_researchers_per_tribe === 'number' && data\.max_researchers_per_tribe > 0/,
    'maxSlots deve ser lido de get_homepage_stats.max_researchers_per_tribe (com type-guard)');
});

test('P1: template usa maxSlots (não a constante) para dots e contador', () => {
  assert.match(tribesSection, /Array\.from\(\{ length: maxSlots \}\)/,
    'dots de slot devem usar maxSlots');
  assert.doesNotMatch(tribesSection, /Array\.from\(\{ length: MAX_SLOTS \}\)/,
    'dots não podem usar a constante MAX_SLOTS diretamente');
  assert.match(tribesSection, /\{initialCounts\[tr\.id\] \|\| 0\}\/\{maxSlots\}/,
    'contador X/max deve usar maxSlots');
});

test('P1: client script recebe o valor resolvido via define:vars', () => {
  assert.match(tribesSection, /define:vars=\{\{[^}]*MAX_SLOTS: maxSlots/,
    'define:vars deve injetar MAX_SLOTS: maxSlots (gate client de tribo-cheia usa o SSOT resolvido)');
});

test('P1: MAX_SLOTS em data/tribes existe e está documentado como fallback', () => {
  assert.ok(maxSlotsMatch, 'tribes.ts deve exportar MAX_SLOTS numérico');
  assert.match(tribesData, /#1214[\s\S]{0,400}?export const MAX_SLOTS/,
    'MAX_SLOTS deve carregar o aviso #1214 de que é fallback do SSOT');
});

// ── Parte 2 — DB-aware (skip sem creds) ──────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';
const headers = {
  apikey: SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
  'Content-Type': 'application/json',
};

async function fetchSetting() {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/platform_settings?key=eq.max_researchers_per_tribe&select=value`,
    { headers },
  );
  assert.ok(res.ok, `platform_settings HTTP ${res.status}`);
  const rows = await res.json();
  assert.equal(rows.length, 1, 'setting max_researchers_per_tribe deve existir');
  return Number(rows[0].value);
}

test(canRun ? 'P2: fallback MAX_SLOTS do frontend bate com platform_settings' : skipMsg, { skip: !canRun }, async () => {
  const ssot = await fetchSetting();
  assert.ok(Number.isInteger(ssot) && ssot > 0, `SSOT inválido: ${ssot}`);
  assert.equal(Number(maxSlotsMatch[1]), ssot,
    `MAX_SLOTS fallback (${maxSlotsMatch[1]}) divergiu do SSOT platform_settings (${ssot}) — atualize src/data/tribes.ts`);
});

test(canRun ? 'P2: get_homepage_stats expõe max_researchers_per_tribe = SSOT' : skipMsg, { skip: !canRun }, async () => {
  const ssot = await fetchSetting();
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_homepage_stats`, {
    method: 'POST', headers, body: '{}',
  });
  assert.ok(res.ok, `get_homepage_stats HTTP ${res.status}`);
  const stats = await res.json();
  assert.equal(stats.max_researchers_per_tribe, ssot,
    'get_homepage_stats.max_researchers_per_tribe deve espelhar platform_settings');
});

test(canRun ? 'P2: gate server (tribe_capacity_limit) = SSOT' : skipMsg, { skip: !canRun }, async () => {
  const ssot = await fetchSetting();
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/tribe_capacity_limit`, {
    method: 'POST', headers, body: '{}',
  });
  assert.ok(res.ok, `tribe_capacity_limit HTTP ${res.status}`);
  assert.equal(await res.json(), ssot,
    'tribe_capacity_limit() (gate do select_tribe) deve espelhar platform_settings');
});
