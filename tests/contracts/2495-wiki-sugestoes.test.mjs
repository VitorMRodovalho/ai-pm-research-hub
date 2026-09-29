/**
 * Contract #2495 fase B2 — "Sugerir melhoria" no wiki (decisões do GP em 28/09/2026).
 *
 *   - quem decide: a liderança ativa da iniciativa dona da página; o comitê quando a página não tem
 *     iniciativa, é de governança, a iniciativa não tem liderança ativa, ou quem sugere é da própria
 *     liderança (quatro olhos, como nas versões);
 *   - só quem sugeriu e quem decide enxergam a sugestão: a tabela não tem acesso direto de cliente, e o
 *     aviso não leva o texto (ele pode carregar dado pessoal, ADR-0010);
 *   - ninguém responde à própria sugestão; recusar exige motivo, e quem sugeriu recebe a resposta;
 *   - a página de tribo do repositório acha a tribo dona por legacy_tribe_id;
 *   - os dois tipos de aviso são imediatos, no catálogo da ADR-0022 e em _delivery_mode_for;
 *   - a tela pede o motivo antes de recusar e carrega a fila junto com o resto do wiki.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const cap = (name) => latestFunctionCapture(ROOT, name);
const body = (name) => maskLineComments(cap(name).body);
const migFile = (name) => maskLineComments(readFileSync(join(DIR, cap(name).file), 'utf8'));
const PAGE_RAW = readFileSync(resolve(ROOT, 'src/pages/wiki.astro'), 'utf8');
const SCRIPT = maskJsComments(PAGE_RAW.slice(PAGE_RAW.indexOf('<script>')));
const slice = (s, from, to) => {
  const a = s.indexOf(from);
  assert.ok(a >= 0, `não achei: ${from}`);
  const b = s.indexOf(to, a + from.length);
  assert.ok(b > a, `não achei o fim: ${to}`);
  return s.slice(a, b);
};

// ── tabela ─────────────────────────────────────────────────────────────────────────────────────
test('#2495 sugestões: a tabela não tem acesso direto de cliente, e recusar sem motivo não grava', () => {
  const m = migFile('wiki_suggest');
  assert.match(m, /ALTER TABLE public\.wiki_page_suggestions ENABLE ROW LEVEL SECURITY;/);
  assert.match(m, /REVOKE ALL ON public\.wiki_page_suggestions FROM PUBLIC, anon, authenticated;/);
  assert.doesNotMatch(m, /GRANT [A-Z, ]+ ON (TABLE )?public\.wiki_page_suggestions TO (anon|authenticated)/);
  assert.match(m, /CHECK \(status <> 'declined' OR length\(btrim\(coalesce\(decision_reason, ''\)\)\) > 0\)/);
  assert.match(m, /CHECK \(\(status = 'open'\) = \(decided_at IS NULL\)\)/);
});

// ── quem decide ────────────────────────────────────────────────────────────────────────────────
test('#2495 sugestões: vai ao comitê sem iniciativa dona, em governança, sem liderança ativa ou vinda da própria liderança', () => {
  const b = body('wiki_suggest');
  const rota = slice(b, 'v_route := CASE', 'END;');
  assert.match(rota, /WHEN v_initiative IS NULL\s+OR v_page\.domain = 'governance'\s+OR public\._wiki_is_initiative_leader\(v_caller, v_initiative\)\s+OR NOT EXISTS \(SELECT 1 FROM public\._wiki_initiative_leader_ids\(v_initiative\)\)\s+THEN 'committee' ELSE 'leader'/);
  const aviso = slice(b, 'v_recipients := CASE v_route', 'END LOOP;');
  assert.match(aviso, /WHEN 'committee' THEN ARRAY\(SELECT public\._wiki_committee_ids\(\)\)\s+ELSE ARRAY\(SELECT public\._wiki_initiative_leader_ids\(v_initiative\)\) END;/);
  assert.match(aviso, /unnest\(array_remove\(v_recipients, v_caller\)\)/, 'quem sugere não se avisa');
});

test('#2495 sugestões: o aviso vai sem o texto da sugestão', () => {
  const aviso = slice(body('wiki_suggest'), 'FOR v_r IN', 'END LOOP;');
  assert.match(aviso, /PERFORM public\.create_notification\(v_r, 'wiki_suggestion_received',/);
  assert.doesNotMatch(aviso, /\b(v_body|p_body)\b/, 'o corpo do aviso e do e-mail não pode levar o texto livre');
});

test('#2495 sugestões: página confidencial some para quem não vê a iniciativa', () => {
  assert.match(body('wiki_suggest'),
    /IF v_initiative IS NOT NULL AND NOT public\.rls_can_see_initiative\(v_initiative\) THEN\s+RAISE EXCEPTION 'wiki: página não encontrada' USING ERRCODE = '42501';/);
  assert.match(body('wiki_suggestion_decide'),
    /IF NOT FOUND OR \(v_s\.initiative_id IS NOT NULL AND NOT public\.rls_can_see_initiative\(v_s\.initiative_id\)\) THEN\s+RAISE EXCEPTION 'wiki: sugestão não encontrada'/);
});

test('#2495 sugestões: a página de tribo do repositório acha a tribo pela legacy_tribe_id', () => {
  const b = body('_wiki_page_initiative');
  assert.match(b, /WHEN p_page_path LIKE 'nucleo\/%' THEN\s+\(SELECT v\.initiative_id FROM public\.wiki_page_versions v WHERE v\.page_path = p_page_path LIMIT 1\)/);
  assert.match(b, /WHEN p_page_path ~ '\^tribes\/tribo-\[0-9\]\+-' THEN\s+\(SELECT i\.id FROM public\.initiatives i\s+WHERE i\.kind = 'research_tribe'\s+AND i\.legacy_tribe_id = substring\(p_page_path FROM '\^tribes\/tribo-\(\[0-9\]\+\)-'\)::integer\)/);
  assert.doesNotMatch(b, /\bELSE\b/, 'página sem dona devolve NULL e vai ao comitê');
});

// ── responder ──────────────────────────────────────────────────────────────────────────────────
test('#2495 sugestões: ninguém responde à própria, e só quem decide responde', () => {
  const b = body('wiki_suggestion_decide');
  assert.match(b, /IF v_s\.author_id = v_caller THEN\s+RAISE EXCEPTION 'wiki: quem sugeriu não responde à própria sugestão' USING ERRCODE = '42501';/);
  assert.match(b, /IF v_s\.route = 'committee' AND NOT v_is_committee THEN\s+RAISE EXCEPTION/);
  assert.match(b, /IF v_s\.route = 'leader' AND NOT \(v_is_committee OR public\._wiki_is_initiative_leader\(v_caller, v_s\.initiative_id\)\) THEN\s+RAISE EXCEPTION/);
  assert.match(b, /IF v_s\.status <> 'open' THEN\s+RAISE EXCEPTION/, 'uma sugestão é respondida uma vez');
});

test('#2495 sugestões: recusar exige motivo, e quem sugeriu recebe a resposta', () => {
  const b = body('wiki_suggestion_decide');
  assert.match(b, /IF p_decision = 'declined' AND v_reason IS NULL THEN\s+RAISE EXCEPTION 'wiki: recusar exige motivo'/);
  assert.match(b, /IF v_s\.author_id IS NOT NULL THEN\s+PERFORM public\.create_notification\(v_s\.author_id, 'wiki_suggestion_decision',/);
});

test('#2495 sugestões: a fila mostra a quem decide o que é dele, e a quem sugeriu só o que enviou', () => {
  const b = body('wiki_suggestion_queue');
  const decidir = slice(b, "'to_decide'", "'mine'");
  assert.match(decidir, /WHERE s\.status = 'open'\s+AND s\.author_id IS DISTINCT FROM v_caller\s+AND \(s\.initiative_id IS NULL OR public\.rls_can_see_initiative\(s\.initiative_id\)\)\s+AND \(\(s\.route = 'committee' AND v_is_committee\)\s+OR \(s\.route = 'leader' AND \(v_is_committee OR public\._wiki_is_initiative_leader\(v_caller, s\.initiative_id\)\)\)\)/);
  const minhas = b.slice(b.indexOf("'mine'"));
  assert.match(minhas, /WHERE s\.author_id = v_caller/);
});

// ── permissões e avisos ────────────────────────────────────────────────────────────────────────
test('#2495 sugestões: auxiliar sem EXECUTE de cliente; RPCs de usuário sem anon', () => {
  const m = migFile('wiki_suggest');
  assert.match(m, /REVOKE ALL ON FUNCTION public\._wiki_page_initiative\(text\) FROM PUBLIC, anon, authenticated;/);
  for (const fn of ['wiki_suggest\\(text, text\\)', 'wiki_suggestion_decide\\(uuid, text, text\\)', 'wiki_suggestion_queue\\(\\)']) {
    assert.match(m, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM PUBLIC, anon;`), fn);
    assert.match(m, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn} TO authenticated, service_role;`), fn);
  }
  for (const f of ['wiki_suggest', 'wiki_suggestion_decide', 'wiki_suggestion_queue']) {
    assert.match(body(f), /IF v_caller IS NULL OR NOT public\.rls_is_authoritative_member\(\) THEN\s+RAISE EXCEPTION 'wiki: requer membro ativo'/, f);
  }
});

test('#2495 sugestões: os dois avisos são imediatos no catálogo e no helper', () => {
  const catalog = JSON.parse(readFileSync(resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json'), 'utf8'));
  const flat = JSON.stringify(catalog);
  const helper = body('_delivery_mode_for');
  for (const t of ['wiki_suggestion_received', 'wiki_suggestion_decision']) {
    assert.match(flat, new RegExp(`"${t}":\\{"delivery_mode":"transactional_immediate"`), t);
    assert.match(helper, new RegExp(`WHEN '${t}'\\s+THEN 'transactional_immediate'`), t);
  }
});

// ── tela ───────────────────────────────────────────────────────────────────────────────────────
test('#2495 sugestões: a tela pede o motivo antes de recusar e carrega a fila com o resto do wiki', () => {
  const decidir = slice(SCRIPT, "view().querySelectorAll('[data-decide]')", "rpc('wiki_suggestion_decide'");
  assert.match(decidir, /if \(decision === 'declined' && !reason\) \{ toast\(T\('wiki\.suggestReasonRequired'\), 'error'\); return; \}/);
  assert.match(SCRIPT, /rpc\('wiki_suggest', \{ p_page_path: path, p_body: body \}\)/);
  assert.match(SCRIPT, /sb\.rpc\('wiki_suggestion_queue'\),\s+\]\);\s+const err = c\.error \|\| q\.error \|\| p\.error \|\| o\.error \|\| s\.error;/);
  assert.match(SCRIPT, /count: queue\.awaiting_my_decision\.length \+ sugg\.to_decide\.length/);
});

// ── banco vivo ──────────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);

test('#2495 sugestões db: a página de tribo acha a tribo, e a fila recusa quem não é membro',
  { skip: dbGated ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required' }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: tribe, error: te } = await sb.from('initiatives').select('id')
      .eq('kind', 'research_tribe').eq('legacy_tribe_id', 2).maybeSingle();
    assert.ifError(te);
    assert.ok(tribe?.id, 'a tribo 2 existe no cadastro');
    const own = await sb.rpc('_wiki_page_initiative', { p_page_path: 'tribes/tribo-2-agentes-autonomos.md' });
    assert.ifError(own.error);
    assert.equal(own.data, tribe.id);
    const none = await sb.rpc('_wiki_page_initiative', { p_page_path: 'platform/qualquer.md' });
    assert.ifError(none.error);
    assert.equal(none.data, null, 'página sem iniciativa dona vai ao comitê');
    const q = await sb.rpc('wiki_suggestion_queue');
    assert.ok(q.error, 'sem membro autenticado a fila precisa falhar');
    assert.match(q.error.message, /requer membro ativo/);
  });
