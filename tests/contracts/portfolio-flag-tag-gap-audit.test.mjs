/**
 * Auditoria de flag/tag de portfólio — contract test.
 *
 * Contexto: `get_portfolio_dashboard()` só enxerga cards com
 * `board_items.is_portfolio_item = true`, e o filtro "Todos os Tipos" só
 * classifica os que carregam uma tag `tier='system' AND domain='board_item'`.
 * Cards de tribo que são entregáveis reais mas não satisfazem uma das duas
 * condições ficam invisíveis no /admin/portfolio. A migration
 * 20260820215416 adiciona a heurística + a RPC de auditoria que tornam esse
 * drift mensurável em vez de descoberto por acaso.
 *
 * (A) static  — migration, script e wiring do admin (sempre roda).
 * (B) DB-gated — a RPC está no ar, é fail-closed para service-role (sem
 *     auth.uid()), e a heurística devolve os tipos esperados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260820215416_portfolio_flag_tag_gap_audit.sql');
const SCRIPT = resolve(ROOT, 'scripts/audit-portfolio-flags-tags.mjs');
const ADMIN = resolve(ROOT, 'src/pages/admin/portfolio.astro');

const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const scriptRaw = existsSync(SCRIPT) ? readFileSync(SCRIPT, 'utf8') : '';
const adminRaw = existsSync(ADMIN) ? readFileSync(ADMIN, 'utf8') : '';

// ── (A) static ─────────────────────────────────────────────────────────────
test('static: a migration cria a heurística e a RPC de auditoria', () => {
  assert.ok(migRaw, 'migration 20260820215416 presente');
  assert.match(migRaw, /FUNCTION public\.portfolio_suggest_item_type\(/, 'helper de sugestão de tipo');
  assert.match(migRaw, /FUNCTION public\.audit_portfolio_flag_tag_gaps\(/, 'RPC de auditoria');
  assert.match(migRaw, /IMMUTABLE/, 'o helper é IMMUTABLE (determinístico)');
});

test('static: a RPC de auditoria é SECURITY DEFINER gated por manage_platform e nega anon', () => {
  assert.match(migRaw, /SECURITY DEFINER/, 'SECDEF');
  assert.match(migRaw, /can_by_member\(v_caller_id, 'manage_platform'\)/, 'gate manage_platform');
  assert.match(migRaw, /REVOKE ALL ON FUNCTION public\.audit_portfolio_flag_tag_gaps[\s\S]{0,80}anon/,
    'anon revogado (LGPD: sem PII/dados operacionais para anon)');
});

test('static: a auditoria é read-only — nada escreve em board_items', () => {
  // O output é sugestão para decisão do GP/líder. Um UPDATE aqui converteria a
  // heurística em verdade e reescreveria conteúdo dos líderes sem revisão.
  const gapFnStart = migRaw.indexOf('FUNCTION public.audit_portfolio_flag_tag_gaps(');
  const gapFnBody = migRaw.slice(gapFnStart, migRaw.indexOf('COMMENT ON FUNCTION public.audit_portfolio_flag_tag_gaps'));
  assert.ok(gapFnBody.length > 0, 'corpo da RPC localizado');
  assert.equal(/\b(UPDATE|INSERT INTO|DELETE FROM)\s+public\.board_item/i.test(gapFnBody), false,
    'a RPC de auditoria não pode escrever em board_items nem em board_item_tag_assignments');
});

test('static: a ordem dos ramos da heurística protege o caso Toolkit vs workshop', () => {
  const ferramenta = migRaw.indexOf("THEN 'ferramenta'");
  const workshop = migRaw.indexOf("THEN 'workshop_artifact'");
  assert.ok(ferramenta > 0 && workshop > 0, 'ambos os ramos existem');
  assert.ok(ferramenta < workshop,
    "'ferramenta' precisa vir antes de 'workshop_artifact': senão \"Toolkit … Gate B\" " +
    'com tag legada "workshop" é classificado como workshop (regressão calibrada em 2026-08-20)');
});

test('static: o sanity do admin expõe os dois contadores de gap', () => {
  assert.match(migRaw, /'tribe_cards_missing_portfolio_flag'/, 'contador do gap A');
  assert.match(migRaw, /'tribe_portfolio_items_missing_type_tag'/, 'contador do gap B');
  assert.ok(adminRaw, 'admin/portfolio.astro legível');
  assert.match(adminRaw, /tribe_cards_missing_portfolio_flag/, 'o toast lê o gap A');
  assert.match(adminRaw, /tribe_portfolio_items_missing_type_tag/, 'o toast lê o gap B');
});

test('static: as chaves i18n novas existem nos 3 dicionários', () => {
  const keys = ['portfolio.script.sanityMissingFlag', 'portfolio.script.sanityMissingTypeTag'];
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = readFileSync(resolve(ROOT, `src/i18n/${loc}.ts`), 'utf8');
    for (const k of keys) {
      assert.ok(dict.includes(`'${k}'`), `${loc} não tem ${k}`);
    }
  }
});

test('static: o script de auditoria chama a RPC (uma só fonte de verdade)', () => {
  assert.ok(scriptRaw, 'scripts/audit-portfolio-flags-tags.mjs presente');
  assert.match(scriptRaw, /rpc\/audit_portfolio_flag_tag_gaps/, 'o script consome a RPC');
  assert.equal(/is_portfolio_item\s*=/.test(scriptRaw), false,
    'o script não reimplementa a regra em JS — ela vive na RPC');
});

test('static: os readers SECDEF novos aplicam o gate confidencial (#785 / ADR-0105)', () => {
  // A regra 5 do CLAUDE.md não abre exceção: reader SECDEF sobre tabela ligada a
  // iniciativa precisa de rls_can_see_initiative(), mesmo com manage_platform na
  // entrada. O allowlist de 785-secdef-reader-confidential-gate.test.mjs é para
  // exceções justificadas — não é o caminho quando o gate simplesmente cabe.
  const GATE_MIG = resolve(ROOT, 'supabase/migrations/20260820224453_gate_785_confidential_on_new_secdef_readers.sql');
  assert.ok(existsSync(GATE_MIG), 'migration do gate presente');
  const gateRaw = readFileSync(GATE_MIG, 'utf8');
  for (const fn of ['audit_portfolio_flag_tag_gaps', 'tribe_journey_health']) {
    const i = gateRaw.indexOf(`FUNCTION public.${fn}(`);
    assert.ok(i > 0, `${fn} recriada na migration do gate`);
    const body = gateRaw.slice(i, gateRaw.indexOf('$fn$;', i));
    assert.match(body, /public\.rls_can_see_initiative\(i\.id\)/,
      `${fn} precisa aplicar rls_can_see_initiative sobre a iniciativa`);
  }
  // Nenhum dos dois pode ter sido allowlistado em vez de gated.
  const guardRaw = readFileSync(
    resolve(ROOT, 'tests/contracts/785-secdef-reader-confidential-gate.test.mjs'), 'utf8');
  const allowlist = guardRaw.slice(guardRaw.indexOf('const ALLOWLIST = {'), guardRaw.indexOf('};', guardRaw.indexOf('const ALLOWLIST = {')));
  for (const fn of ['audit_portfolio_flag_tag_gaps', 'tribe_journey_health']) {
    assert.equal(allowlist.includes(`${fn}:`), false,
      `${fn} está gated — não pode aparecer no ALLOWLIST (o guard reprova entradas obsoletas)`);
  }
});

// ── (B) DB-gated ────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('DB: audit_portfolio_flag_tag_gaps está no ar e é fail-closed sem auth.uid()',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { error } = await sb.rpc('audit_portfolio_flag_tag_gaps', {
      p_include_non_tribe: false, p_dashboard_cycle: 3,
    });
    // service-role não tem auth.uid() → a RPC levanta authentication_required.
    // Um "could not find function" aqui significaria que a assinatura não está deployada.
    assert.ok(error, 'service-role (sem auth.uid()) precisa ser rejeitado');
    assert.equal(/could not find the function/i.test(error.message), false,
      `a assinatura precisa estar deployada (erro: ${error.message})`);
    assert.match(String(error.message), /authentication_required/i, 'fail-closed');
  });

test('DB: portfolio_suggest_item_type devolve os tipos calibrados',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const cases = [
      // título, tags legadas, tipo esperado
      ['Toolkit v1.0 de Governança de IA — Gate B', ['workshop'], 'ferramenta'],
      ['Target Pilar III - Modelo de Alinhamento Cognitivo IA', null, 'framework'],
      ['Artigo LinkedIn Newsletter - Agosto', ['publicacao'], 'publicacao'],
      ['1ª webinar - Industria da Construção', null, 'webinar'],
      // cards de processo não podem virar entregável por acidente
      ['Rodízio Líder Reunião 12/8/26', null, null],
      // "recursos"/"percurso" contêm "curso": a fronteira de palavra evita o falso positivo
      ['Recursos e percursos da tribo', null, null],
    ];
    for (const [title, tags, expected] of cases) {
      const { data, error } = await sb.rpc('portfolio_suggest_item_type', {
        p_title: title, p_tags: tags,
      });
      assert.ok(!error, `heurística precisa resolver (erro: ${error?.message})`);
      assert.equal(data, expected, `"${title}" → esperado ${expected}, veio ${data}`);
    }
  });
