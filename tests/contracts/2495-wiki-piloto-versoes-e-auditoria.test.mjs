/**
 * Contract #2495 — piloto do wiki vivo, camada de banco (ADR-0129, emendas 1 e 2).
 *
 * A liderança da tribo publica na hora e o Comitê de Curadoria audita em até 14 dias. O comitê
 * aprova ANTES quando há aviso de dado pessoal, quando o autor é a liderança ou do comitê, ou quando
 * a tribo não tem liderança ativa. Quem escreveu nunca decide nem audita a própria versão.
 *
 * Cada asserção amarra a CONDIÇÃO ao RESULTADO dentro da função vigente (latestFunctionCapture),
 * com comentários mascarados. A camada viva foi exercida por impersonação em transação abortada na PR.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const body = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);
const migFile = (name) => maskLineComments(readFileSync(join(DIR, latestFunctionCapture(ROOT, name).file), 'utf8'));
const allMigrations = () => readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => maskLineComments(readFileSync(join(DIR, f), 'utf8'))).join('\n');
const catalog = JSON.parse(readFileSync(resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json'), 'utf8'));
const NEW_TYPES = ['wiki_review_requested', 'wiki_page_decision', 'wiki_audit_requested', 'wiki_audit_overdue'];

// ── rota e filtro ───────────────────────────────────────────────────────────────────────────────
test('#2495: wiki_submit manda ao comitê nos 4 casos de risco, e à liderança nos demais', () => {
  assert.match(body('wiki_submit'),
    /v_route := CASE\s+WHEN v_pii IS NOT NULL\s+OR public\._wiki_is_initiative_leader\(v_caller, v_ver\.initiative_id\)\s+OR public\.can_by_member\(v_caller, 'curate_content'\)\s+OR NOT EXISTS \(SELECT 1 FROM public\._wiki_initiative_leader_ids\(v_ver\.initiative_id\)\)\s+THEN 'committee' ELSE 'leader' END;/);
});

test('#2495: wiki_submit barra envio sem resumo, tipo ou fontes', () => {
  const b = body('wiki_submit');
  assert.match(b, /IF coalesce\(btrim\(v_ver\.summary\), ''\) = '' THEN v_missing := v_missing \|\| 'resumo'::text; END IF;/);
  assert.match(b, /IF v_ver\.doc_type IS NULL THEN v_missing := v_missing \|\| 'tipo'::text; END IF;/);
  assert.match(b, /IF jsonb_array_length\(v_ver\.sources\) = 0 THEN v_missing := v_missing \|\| 'fontes'::text; END IF;/);
  assert.match(b, /IF cardinality\(v_missing\) > 0 THEN\s+RAISE EXCEPTION/);
});

test('#2495: o filtro de dado pessoal usa as três regras do relatório de saúde', () => {
  const b = body('_wiki_pii_detail');
  assert.match(b, /THEN 'e-mail' END/);
  assert.match(b, /\\\+\?55\\s\?\\d\{2\}\\s\?\\d\{4,5\}\[\\s-\]\?\\d\{4\}' THEN 'telefone' END/);
  assert.match(b, /\\d\{3\}\\\.\\d\{3\}\\\.\\d\{3\}-\\d\{2\}' THEN 'CPF' END/);
});

// ── decisão ─────────────────────────────────────────────────────────────────────────────────────
test('#2495: wiki_decide aplica quatro olhos e o portão por rota', () => {
  const b = body('wiki_decide');
  assert.match(b, /IF v_ver\.author_id = v_caller THEN\s+RAISE EXCEPTION 'wiki: quem escreveu não aprova a própria versão'/);
  assert.match(b, /IF v_ver\.status = 'pending_committee' AND NOT v_is_committee THEN\s+RAISE EXCEPTION/);
  assert.match(b, /IF v_ver\.status = 'pending_leader' AND NOT \(v_is_leader OR v_is_committee\) THEN\s+RAISE EXCEPTION/);
});

test('#2495: publicar pela liderança abre 14 dias de auditoria; pelo comitê já nasce auditada', () => {
  const b = body('wiki_decide');
  assert.match(b, /v_due := CASE WHEN v_is_committee THEN NULL ELSE now\(\) \+ interval '14 days' END;/);
  assert.match(b, /audit_outcome = CASE WHEN v_is_committee THEN 'kept' END/);
  assert.match(b, /IF NOT v_is_committee THEN\s+PERFORM public\._wiki_notify\(array_remove\(ARRAY\(SELECT public\._wiki_committee_ids\(\)\), v_caller\),\s+'wiki_audit_requested'/);
});

test('#2495: a publicação grava no espaço da plataforma e nunca sobrescreve página do repositório', () => {
  const b = body('wiki_decide');
  assert.match(b, /'plataforma', p_version_id::text, now\(\), now\(\), v_audit_status, p_version_id\)\s+ON CONFLICT \(path\) DO UPDATE[\s\S]*?WHERE public\.wiki_pages\.source_repo = 'plataforma';/);
  assert.match(allMigrations(),
    /ADD CONSTRAINT wiki_pages_platform_namespace_check\s+CHECK \(\(source_repo = 'plataforma'\) = \(path LIKE 'nucleo\/%'\)\);/);
});

// ── auditoria ───────────────────────────────────────────────────────────────────────────────────
test('#2495: wiki_audit é do comitê, nunca de quem escreveu, e exige motivo para alterar ou despublicar', () => {
  const b = body('wiki_audit');
  assert.match(b, /OR NOT public\.can_by_member\(v_caller, 'curate_content'\) THEN\s+RAISE EXCEPTION 'wiki: auditoria é do comitê de curadoria'/);
  assert.match(b, /IF v_ver\.author_id = v_caller THEN\s+RAISE EXCEPTION 'wiki: quem escreveu não audita a própria versão'/);
  assert.match(b, /IF p_outcome IN \('altered', 'unpublished'\) AND coalesce\(btrim\(p_reason\), ''\) = '' THEN\s+RAISE EXCEPTION/);
  assert.match(b, /DELETE FROM public\.wiki_pages WHERE path = v_ver\.page_path AND source_repo = 'plataforma';/);
  assert.match(b, /IF v_pii IS NOT NULL THEN\s+RAISE EXCEPTION 'wiki: o texto novo tem possível dado pessoal/);
});

// ── escrita e leitura ───────────────────────────────────────────────────────────────────────────
test('#2495: wiki_save_draft restringe a escrita aos tipos com página e a quem participa ou cura (emenda 3)', () => {
  const b = body('wiki_save_draft');
  assert.match(b, /IF v_domain IS NULL THEN\s+RAISE EXCEPTION[^;]*;\s+END IF;\s+IF p_domain IS DISTINCT FROM v_domain THEN\s+RAISE EXCEPTION/);
  assert.match(b, /IF NOT public\.rls_can_see_initiative\(p_initiative_id\) THEN\s+RAISE EXCEPTION/);
  assert.match(b, /IF NOT public\._wiki_can_author\(v_caller, p_initiative_id\) THEN\s+RAISE EXCEPTION/);
  assert.match(body('_wiki_can_author'), /e\.status = 'active' AND e\.role = ANY \(public\._wiki_writer_roles\(\)\)\)\s+OR public\.can_by_member\(p_member, 'curate_content'\)/);
});

test('#2495: as leituras aplicam o portão de iniciativa confidencial', () => {
  assert.match(body('wiki_review_queue'), /WHERE public\.rls_can_see_initiative\(v\.initiative_id\)\s+AND v\.author_id IS DISTINCT FROM v_caller/);
  assert.match(body('wiki_get_version'), /IF NOT FOUND OR NOT public\.rls_can_see_initiative\(v_ver\.initiative_id\)/);
});

// 29/09/2026, no piloto em uso: duas lideranças salvaram um rascunho e, 21 s depois, abriram e enviaram uma
// segunda versão da mesma página; a primeira ficou órfã. Uma versão aberta por pessoa e por página.
test('#2495: criar com versão aberta da mesma pessoa na mesma página reaproveita o rascunho, ou recusa se aguarda decisão', () => {
  const b = body('wiki_save_draft');
  const trava = b.indexOf("PERFORM pg_advisory_xact_lock(hashtext('wiki_page_versions:' || p_page_path));");
  const aberta = b.indexOf('SELECT * INTO v_ver FROM public.wiki_page_versions\n   WHERE page_path = p_page_path AND author_id = v_caller');
  const insere = b.indexOf('INSERT INTO public.wiki_page_versions');
  assert.ok(trava > 0 && aberta > trava && insere > aberta, 'a checagem vem depois da trava por página e antes do INSERT');
  const bloco = b.slice(aberta, insere);
  assert.match(bloco, /AND status IN \('draft', 'returned', 'pending_leader', 'pending_committee'\)/);
  assert.match(bloco, /IF v_ver\.status IN \('pending_leader', 'pending_committee'\) THEN\s+RAISE EXCEPTION 'wiki: você já tem uma versão desta página aguardando decisão/);
  assert.match(bloco, /UPDATE public\.wiki_page_versions\s+SET title = p_title,[\s\S]*?status = 'draft', updated_at = now\(\)\s+WHERE id = v_ver\.id;\s+RETURN v_ver\.id;/);
});

test('#2495: a tela não deixa o Voltar reabrir um editor já preenchido', () => {
  const page = readFileSync(resolve(ROOT, 'src/pages/wiki.astro'), 'utf8');
  const salvar = page.slice(page.indexOf('async function save(andSubmit'), page.indexOf("bind('w-save'"));
  assert.match(salvar, /location\.replace\(href\(\{ version: vid \}\)\);/);
  assert.doesNotMatch(salvar, /location\.href = href\(\{ version: vid \}\)/);
  assert.match(page, /window\.addEventListener\('pageshow', \(e\) => \{ if \(\(e as PageTransitionEvent\)\.persisted\) location\.reload\(\); \}\);/);
});

test('#2495: eventos são só de acréscimo (nenhuma migration os altera ou apaga)', () => {
  assert.doesNotMatch(allMigrations(), /\b(UPDATE|DELETE\s+FROM)\s+(public\.)?wiki_page_events\b/i);
});

test('#2495: auxiliares e varredura sem EXECUTE de cliente; RPCs de usuário sem anon', () => {
  const m = migFile('wiki_submit');
  for (const fn of ['_wiki_pii_detail\\(text\\)', '_wiki_is_initiative_leader\\(uuid, uuid\\)', '_wiki_can_author\\(uuid, uuid\\)',
    '_wiki_initiative_leader_ids\\(uuid\\)', '_wiki_committee_ids\\(\\)', '_wiki_notify\\(uuid\\[\\], text, text, text, uuid\\)',
    'wiki_audit_sla_sweep\\(\\)']) {
    assert.match(m, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM PUBLIC, anon, authenticated;`), fn);
  }
  for (const fn of ['wiki_save_draft\\(text, uuid, text, text, text, text, jsonb, text, uuid\\)', 'wiki_submit\\(uuid\\)',
    'wiki_decide\\(uuid, text, text\\)', 'wiki_audit\\(uuid, text, text, text, text, text\\)', 'wiki_review_queue\\(\\)',
    'wiki_get_version\\(uuid\\)']) {
    assert.match(m, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM PUBLIC, anon;`), fn);
  }
  assert.match(m, /REVOKE ALL ON public\.wiki_page_versions FROM PUBLIC, anon, authenticated;/);
  assert.match(m, /REVOKE ALL ON public\.wiki_page_events\s+FROM PUBLIC, anon, authenticated;/);
  assert.match(m, /cron\.schedule\(\s*'wiki-audit-sla-daily',\s*'27 12 \* \* \*',\s*\$cron\$SELECT public\.wiki_audit_sla_sweep\(\);\$cron\$/);
});

test('#2495: os 4 avisos novos são imediatos no mapa de entrega e no catálogo', () => {
  const d = body('_delivery_mode_for');
  for (const t of NEW_TYPES) {
    assert.match(d, new RegExp(`WHEN '${t}'\\s+THEN 'transactional_immediate'`), t);
    assert.equal(catalog.types[t]?.delivery_mode, 'transactional_immediate', t);
  }
});

// ── banco vivo ──────────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);

test('#2495 db: os 4 avisos são imediatos e a fila recusa quem não é membro',
  { skip: dbGated ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required' }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    for (const t of NEW_TYPES) {
      const { data, error } = await sb.rpc('_delivery_mode_for', { p_type: t });
      assert.ifError(error);
      assert.equal(data, 'transactional_immediate', t);
    }
    // service_role não tem auth.uid(): o portão de membro tem de recusar, e não devolver fila vazia
    const q = await sb.rpc('wiki_review_queue');
    assert.ok(q.error, 'sem membro autenticado a fila precisa falhar');
    assert.match(q.error.message, /requer membro ativo/);
  });
