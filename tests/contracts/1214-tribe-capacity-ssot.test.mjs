// #1214 — Tribe capacity SSOT guard (static + DB-aware, padrão #1087 O2 / Pattern 47).
//
// Regressão: a landing exibia "Máx. 10" e o gate client de tribo-cheia só fechava aos 10,
// enquanto o SSOT vivo (platform_settings.max_researchers_per_tribe) e o gate server
// (select_tribe via tribe_capacity_limit()) usavam 7.
//
// Contrato:
//   Parte 1 (estática): a seção de linhas da home (ResearchLinesSection, #2553) mostra as vagas com a
//     capacidade que get_public_research_lines devolve (tribe_capacity_limit(), afirmado no guard
//     2553-linhas-de-pesquisa-publicas), nunca com a constante MAX_SLOTS.
//   Parte 2 (DB-aware, skip sem creds): o fallback MAX_SLOTS do frontend, o RPC
//     get_homepage_stats e o helper tribe_capacity_limit() batem com o SSOT
//     platform_settings.max_researchers_per_tribe.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(root, p), 'utf8');

const tribesData = read('src/data/tribes.ts');
// comentários mascarados: a asserção mede o código, não a explicação dele
const linesSection = maskJsComments(read('src/components/sections/ResearchLinesSection.astro'));
const homeData = maskJsComments(read('src/lib/publicHomeData.ts'));

const maxSlotsMatch = tribesData.match(/export const MAX_SLOTS = (\d+);/);

// ── Parte 1 — estática ───────────────────────────────────────────────────────
test('P1: a home mostra as vagas com a capacidade que a RPC devolve, não com a constante', () => {
  // #2553 PR-7: a TribesSection, que resolvia maxSlots de get_homepage_stats, saiu da home. A seção de linhas lê
  // members e capacity de get_public_research_lines, e a capacidade da RPC é tribe_capacity_limit().
  assert.match(homeData, /capacity: isNum\(r\.capacity\) \? r\.capacity : 0,/,
    'o loader deve ler capacity da linha da RPC');
  assert.match(linesSection, /const full = l\.capacity > 0 && l\.members >= l\.capacity;/,
    'linha cheia deve comparar com a capacidade da RPC');
  assert.match(linesSection, /t\('homeV2\.lines\.seats', lang\)\.replace\('\{n\}', String\(l\.members\)\)\.replace\('\{max\}', String\(l\.capacity\)\)/,
    'o contador X/max deve usar a capacidade da RPC');
  assert.doesNotMatch(linesSection, /\bMAX_SLOTS\b/, 'a seção não pode usar a constante MAX_SLOTS');
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

// #1950: a chave virou `max_members_per_tribe` porque o valor SEMPRE contou o líder
// (8 = 1 líder + 7 pesquisadores). O nome antigo NÃO é aceito aqui de propósito: no frontend os
// dois convivem durante a janela entre os deploys, mas o SSOT tem UM nome só — aceitar os dois no
// banco deixaria o rename passar pela metade sem ninguém notar.
async function fetchSetting() {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/platform_settings?key=eq.max_members_per_tribe&select=value`,
    { headers },
  );
  assert.ok(res.ok, `platform_settings HTTP ${res.status}`);
  const rows = await res.json();
  assert.equal(rows.length, 1, 'setting max_members_per_tribe deve existir');
  return Number(rows[0].value);
}

test(canRun ? 'P2: a chave ANTIGA nao existe mais (o rename foi ate o fim)' : skipMsg, { skip: !canRun }, async () => {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/platform_settings?key=eq.max_researchers_per_tribe&select=key`,
    { headers },
  );
  assert.ok(res.ok, `platform_settings HTTP ${res.status}`);
  assert.equal((await res.json()).length, 0,
    'max_researchers_per_tribe nao pode coexistir com a nova: duas chaves = duas verdades de capacidade');
});

test(canRun ? 'P2: fallback MAX_SLOTS do frontend bate com platform_settings' : skipMsg, { skip: !canRun }, async () => {
  const ssot = await fetchSetting();
  assert.ok(Number.isInteger(ssot) && ssot > 0, `SSOT inválido: ${ssot}`);
  assert.equal(Number(maxSlotsMatch[1]), ssot,
    `MAX_SLOTS fallback (${maxSlotsMatch[1]}) divergiu do SSOT platform_settings (${ssot}) — atualize src/data/tribes.ts`);
});

test(canRun ? 'P2: get_homepage_stats expõe max_members_per_tribe = SSOT' : skipMsg, { skip: !canRun }, async () => {
  const ssot = await fetchSetting();
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_homepage_stats`, {
    method: 'POST', headers, body: '{}',
  });
  assert.ok(res.ok, `get_homepage_stats HTTP ${res.status}`);
  const stats = await res.json();
  assert.equal(stats.max_members_per_tribe, ssot,
    'get_homepage_stats.max_members_per_tribe deve espelhar platform_settings');
  assert.equal(stats.max_researchers_per_tribe, undefined,
    'o campo antigo deve sumir da resposta: dois campos com o mesmo numero divergem no primeiro que alguem esquecer');
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
