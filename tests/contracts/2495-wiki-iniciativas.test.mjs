/**
 * Contract #2495 — o wiki para todas as iniciativas (ADR-0129, emenda 3, decisão do GP em 28/09/2026).
 *
 * Medido em 28/09: 14 tribos (12 ativas, a 2 e a 3 arquivadas), 10 grupos de trabalho, 5 verticais e 1
 * grupo de estudos; o início listava só as 7 tribos com página, e só tribo escrevia.
 *
 *   - os papéis moram em dois auxiliares (quem publica, quem escreve) e nenhuma função do wiki repete
 *     papel literal: um papel novo entra em um lugar só;
 *   - o domínio da página vem do tipo da iniciativa (tribes ou initiatives; congresso e comitê não têm);
 *   - os CHECKs de domínio das duas tabelas, o mapa de tipos e a tela concordam;
 *   - o rascunho confere o domínio antes de gravar;
 *   - a lista do início sai do cadastro (wiki_initiatives_overview), com o portão de membro ativo e o de
 *     iniciativa confidencial, e não das páginas que já existem.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const cap = (name) => latestFunctionCapture(ROOT, name);
const body = (name) => maskLineComments(cap(name).body);
const migFile = (name) => maskLineComments(readFileSync(join(DIR, cap(name).file), 'utf8'));
const allMigrations = () => readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => maskLineComments(readFileSync(join(DIR, f), 'utf8'))).join('\n');
const PAGE_RAW = readFileSync(resolve(ROOT, 'src/pages/wiki.astro'), 'utf8');
const SCRIPT = maskJsComments(PAGE_RAW.slice(PAGE_RAW.indexOf('<script>')));
const arr = (sql) => [...sql.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);

// Toda função do wiki (nome com "wiki") capturada em alguma migration: a enumeração vem da FONTE.
function wikiFunctions() {
  const names = new Set();
  for (const m of allMigrations().matchAll(/CREATE (?:OR REPLACE )?FUNCTION public\.([a-z_]*wiki[a-z_]*)\(/g)) names.add(m[1]);
  return [...names];
}

// ── papéis ─────────────────────────────────────────────────────────────────────────────────────
test('#2495 iniciativas: quem publica é leader ou coordinator; quem escreve inclui participant, researcher e reviewer', () => {
  const lead = arr(body('_wiki_leadership_roles'));
  const write = arr(body('_wiki_writer_roles'));
  assert.deepEqual(lead, ['leader', 'coordinator']);
  assert.deepEqual(write, ['leader', 'coordinator', 'researcher', 'participant', 'reviewer']);
  for (const r of lead) assert.ok(write.includes(r), `${r} publica e por isso também escreve`);
  assert.ok(!write.includes('observer'), 'observer só lê');
});

test('#2495 iniciativas: os auxiliares perguntam pelos papéis centrais, e nenhuma função do wiki repete papel literal', () => {
  assert.match(body('_wiki_is_initiative_leader'), /AND e\.status = 'active' AND e\.role = ANY \(public\._wiki_leadership_roles\(\)\)\);/);
  assert.match(body('_wiki_initiative_leader_ids'), /AND e\.status = 'active' AND e\.role = ANY \(public\._wiki_leadership_roles\(\)\)\s+AND m\.is_active/);
  assert.match(body('_wiki_can_author'), /AND e\.status = 'active' AND e\.role = ANY \(public\._wiki_writer_roles\(\)\)\)\s+OR public\.can_by_member\(p_member, 'curate_content'\)/);
  const fns = wikiFunctions();
  assert.ok(fns.length >= 20, `esperava ao menos 20 funções do wiki, achou ${fns.length}`);
  for (const f of fns) {
    assert.doesNotMatch(body(f), /\be\.role\s*(=\s*'|IN\s*\()/, `${f} repete papel literal`);
  }
});

// ── domínio ────────────────────────────────────────────────────────────────────────────────────
test('#2495 iniciativas: o domínio vem do tipo, e congresso e comitê não têm página', () => {
  const b = body('_wiki_domain_for_kind');
  const map = Object.fromEntries([...b.matchAll(/WHEN '([a-z_]+)'\s+THEN '([a-z_]+)'/g)].map((m) => [m[1], m[2]]));
  assert.deepEqual(map, { research_tribe: 'tribes', workgroup: 'initiatives', community_vertical: 'initiatives', study_group: 'initiatives' });
  assert.doesNotMatch(b, /\bELSE\b/, 'tipo fora do mapa devolve NULL, nunca um domínio por omissão');
});

test('#2495 iniciativas: os CHECKs das duas tabelas, o mapa de tipos e a tela concordam no domínio', () => {
  const all = allMigrations();
  const lists = ['wiki_pages_domain_check', 'wiki_page_versions_domain_check'].map((c) => {
    const found = [...all.matchAll(new RegExp(`ADD CONSTRAINT ${c}\\s+CHECK \\(domain = ANY \\(ARRAY\\[([^\\]]*)\\]\\)\\)`, 'g'))];
    assert.ok(found.length, c);
    return arr(found.at(-1)[1]).sort();
  });
  assert.deepEqual(lists[0], lists[1], 'as duas tabelas aceitam os mesmos domínios');
  const mapped = [...body('_wiki_domain_for_kind').matchAll(/THEN '([a-z_]+)'/g)].map((m) => m[1]);
  for (const d of mapped) assert.ok(lists[0].includes(d), `o CHECK aceita ${d}`);
  const order = SCRIPT.match(/const DOMAIN_ORDER = \[([^\]]*)\]/);
  assert.ok(order, 'DOMAIN_ORDER na tela');
  assert.deepEqual(arr(order[1]).sort(), lists[0], 'a tela ordena exatamente os domínios que o banco aceita');
});

test('#2495 iniciativas: o rascunho confere o domínio da iniciativa antes de gravar', () => {
  const b = body('wiki_save_draft');
  const derive = b.indexOf('SELECT public._wiki_domain_for_kind(i.kind) INTO v_domain FROM public.initiatives i WHERE i.id = p_initiative_id;');
  assert.ok(derive > 0, 'o domínio vem do tipo da iniciativa');
  assert.match(b.slice(derive), /^[^;]*;\s+IF v_domain IS NULL THEN\s+RAISE EXCEPTION[^;]*;\s+END IF;\s+IF p_domain IS DISTINCT FROM v_domain THEN\s+RAISE EXCEPTION/);
  assert.ok(derive < b.indexOf('INSERT INTO public.wiki_page_versions'), 'antes do INSERT');
  assert.ok(derive < b.indexOf('public._wiki_can_author(v_caller, p_initiative_id)'), 'antes da checagem de autoria');
});

test('#2495 iniciativas: fora das tribos a página fica em nucleo/iniciativas/<id>', () => {
  assert.match(body('_wiki_initiative_path_prefix'),
    /WHEN i\.kind = 'research_tribe' THEN 'nucleo\/tribes\/' \|\| i\.id::text\s+ELSE 'nucleo\/iniciativas\/' \|\| i\.id::text END/);
});

// ── lista do início ────────────────────────────────────────────────────────────────────────────
test('#2495 iniciativas: a lista sai do cadastro, com os portões de membro ativo e de iniciativa confidencial', () => {
  const b = body('wiki_initiatives_overview');
  assert.ok(b.indexOf("RAISE EXCEPTION 'wiki: requer membro ativo'") < b.indexOf('RETURN'), 'o portão vem antes da resposta');
  assert.match(b, /WHERE public\._wiki_domain_for_kind\(i\.kind\) IS NOT NULL\s+AND \(i\.status = 'active' OR i\.kind = 'research_tribe'\)\s+AND public\.rls_can_see_initiative\(i\.id\)\) x\)/);
  assert.match(b, /AS domain,[\s\S]*e\.role = ANY \(public\._wiki_writer_roles\(\)\)\) AS has_team/);
  assert.match(b, /WHERE w\.source_repo <> 'plataforma' AND w\.path ~ \('\^tribes\/tribo-' \|\| x\.legacy_tribe_id \|\| '-'\)/);
  assert.match(b, /'can_author', public\._wiki_can_author\(v_caller, x\.id\)\)/);
  const m = migFile('wiki_initiatives_overview');
  assert.match(m, /REVOKE ALL ON FUNCTION public\.wiki_initiatives_overview\(\) FROM PUBLIC, anon;/);
  assert.match(m, /GRANT EXECUTE ON FUNCTION public\.wiki_initiatives_overview\(\) TO authenticated, service_role;/);
  for (const f of ['_wiki_leadership_roles\\(\\)', '_wiki_writer_roles\\(\\)', '_wiki_domain_for_kind\\(text\\)']) {
    assert.match(m, new RegExp(`REVOKE ALL ON FUNCTION public\\.${f} FROM PUBLIC, anon, authenticated;`), f);
  }
});

test('#2495 iniciativas: a tela monta a lista pelo cadastro, e não pelas páginas que existem', () => {
  assert.match(SCRIPT, /sb\.rpc\('wiki_initiatives_overview'\),\s+\]\);\s+const err = c\.error \|\| q\.error \|\| p\.error \|\| o\.error;/);
  assert.match(SCRIPT, /const tribes = overview\.filter\(\(x\) => x\.kind === 'research_tribe'\);\s+const others = overview\.filter\(\(x\) => x\.kind !== 'research_tribe'\);/);
  assert.doesNotMatch(SCRIPT, /pages\.filter\(\(p\) => p\.domain === 'tribes'\)/, 'a lista de tribos não sai mais das páginas');
  const row = SCRIPT.slice(SCRIPT.indexOf('function initiativeRow('), SCRIPT.indexOf('function viewHome('));
  assert.match(row, /x\.status !== 'active' \? muted\('wiki\.frozen'\)/);
  assert.match(row, /: x\.repo_page \? `<span class="wk-chip wk-chip-old">[^`]*` : muted\('wiki\.noPageYet'\)/);
  assert.match(row, /x\.status === 'active' && x\.can_author && !x\.platform_page\s+\? `<a class="wk-chip wk-chip-type" href="\$\{E\(href\(\{ new: x\.id, path: x\.path_prefix \}\)\)\}">/);
  assert.match(SCRIPT, /p_sources: f\.sources, p_domain: tribe!\.domain,/);
  assert.doesNotMatch(SCRIPT, /p_domain: 'tribes'/);
});

// ── banco vivo ──────────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);

test('#2495 iniciativas db: o mapa de tipos e os papéis vivos batem com a regra, e a lista recusa quem não é membro',
  { skip: dbGated ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required' }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const expected = { research_tribe: 'tribes', workgroup: 'initiatives', community_vertical: 'initiatives',
      study_group: 'initiatives', congress: null, committee: null };
    for (const [kind, domain] of Object.entries(expected)) {
      const { data, error } = await sb.rpc('_wiki_domain_for_kind', { p_kind: kind });
      assert.ifError(error);
      assert.equal(data, domain, kind);
    }
    const w = await sb.rpc('_wiki_writer_roles');
    assert.ifError(w.error);
    assert.deepEqual(w.data, ['leader', 'coordinator', 'researcher', 'participant', 'reviewer']);
    const o = await sb.rpc('wiki_initiatives_overview');
    assert.ok(o.error, 'sem membro autenticado a lista precisa falhar');
    assert.match(o.error.message, /requer membro ativo/);
  });
