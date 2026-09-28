/**
 * Contract #2495 — fase B1 do wiki: o que quem lê e o assistente enxergam (ADR-0129, emenda 2, item 5).
 *
 *   - get_wiki_page e search_wiki_pages devolvem audit_status e continuam SECURITY INVOKER (a RLS de
 *     membro ativo de wiki_pages é o portão), com o mesmo EXECUTE;
 *   - publicar (wiki_decide) e alterar (wiki_audit) gravam a tag diataxis-<tipo>, que é por onde a tela
 *     e a busca leem o tipo; antes a página da plataforma nascia sem tag e sumia dos atalhos;
 *   - o MCP acrescenta audit_notice a toda página com auditoria pendente, em TODA leitura do wiki;
 *   - a tela mostra o trecho da busca sem markdown cru e tira o H1 que repete o título.
 *
 * As asserções de SQL amarram a coluna ao VALOR na mesma posição da tupla, e não a presença de "tags".
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { dropLeadingTitle, plainSnippet } from '../../src/lib/wiki-render.ts';
import { withWikiAuditNotice, WIKI_AUDIT_PENDING_NOTICE } from '../../supabase/functions/nucleo-mcp/wiki-audit.mjs';

const ROOT = process.cwd();
const cap = (name) => latestFunctionCapture(ROOT, name);
const body = (name) => maskLineComments(cap(name).body);
const migFile = (name) => maskLineComments(readFileSync(resolve(ROOT, 'supabase/migrations', cap(name).file), 'utf8'));
const PAGE_RAW = readFileSync(resolve(ROOT, 'src/pages/wiki.astro'), 'utf8');
const SCRIPT = maskJsComments(PAGE_RAW.slice(PAGE_RAW.indexOf('<script>')));
const MCP = maskJsComments(readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8'));

// Divide uma lista SQL pelas vírgulas do nível de fora (parênteses e aspas não quebram).
function splitTop(list) {
  const out = []; let depth = 0; let quoted = false; let cur = '';
  for (const ch of list) {
    if (ch === "'") quoted = !quoted;
    if (!quoted && ch === '(') depth++;
    if (!quoted && ch === ')') depth--;
    if (!quoted && depth === 0 && ch === ',') { out.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}
// Conteúdo entre o "(" em `from` e o ")" que o fecha.
function parenAt(s, from) {
  const open = s.indexOf('(', from);
  let depth = 0; let quoted = false;
  for (let i = open; i < s.length; i++) {
    const ch = s[i];
    if (ch === "'") quoted = !quoted;
    if (quoted) continue;
    if (ch === '(') depth++;
    if (ch === ')' && --depth === 0) return { text: s.slice(open + 1, i), end: i + 1 };
  }
  throw new Error('parêntese sem fechamento');
}

// ── tipo na publicação ──────────────────────────────────────────────────────────────────────────
test('#2495 B1: _wiki_type_tags grava diataxis-<tipo>, e a tela aceita exatamente os tipos do banco', () => {
  assert.match(body('_wiki_type_tags'),
    /CASE WHEN p_doc_type IS NULL THEN '\{\}'::text\[\] ELSE ARRAY\['diataxis-' \|\| p_doc_type\] END/);
  // os tipos que a versão aceita (CHECK da tabela) são os que a tela reconhece pela tag
  const all = readFileSync(resolve(ROOT, 'supabase/migrations', cap('wiki_submit').file), 'utf8');
  const check = all.match(/doc_type\s+text CHECK \(doc_type IN \(([^)]*)\)\)/);
  assert.ok(check, 'CHECK de doc_type em wiki_page_versions');
  const dbTypes = [...check[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort();
  const front = SCRIPT.match(/const DOC_TYPES = \[([^\]]*)\]/);
  assert.ok(front, 'DOC_TYPES na tela');
  assert.deepEqual([...front[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort(), dbTypes);
  assert.match(SCRIPT, /\.find\(\(x: string\) => \/\^diataxis-\/\.test\(String\(x\)\)\)/, 'a tela lê o tipo pela tag diataxis-');
});

test('#2495 B1: publicar grava a tag na MESMA posição da coluna tags, e o upsert a atualiza', () => {
  const b = body('wiki_decide');
  const at = b.indexOf('INSERT INTO public.wiki_pages');
  assert.ok(at > 0, 'wiki_decide grava em wiki_pages');
  const cols = parenAt(b, at);
  const vals = parenAt(b, b.indexOf('VALUES', cols.end));
  const c = splitTop(cols.text); const v = splitTop(vals.text);
  assert.equal(c.length, v.length, 'colunas e valores do INSERT');
  const i = c.indexOf('tags');
  assert.ok(i >= 0, 'a coluna tags está no INSERT');
  assert.equal(v[i], 'public._wiki_type_tags(v_ver.doc_type)', 'o valor de tags é o tipo da versão publicada');
  const conflict = b.slice(vals.end, b.indexOf('WHERE public.wiki_pages.source_repo', vals.end));
  assert.match(conflict, /ON CONFLICT \(path\) DO UPDATE[\s\S]*\btags = EXCLUDED\.tags\b/);
});

test('#2495 B1: alterar pelo comitê regrava a tag no UPDATE que troca a versão da página', () => {
  const b = body('wiki_audit');
  const upd = b.match(/UPDATE public\.wiki_pages\s+SET ([\s\S]*?)\s+WHERE path = v_ver\.page_path AND source_repo = 'plataforma';/g) || [];
  const alter = upd.filter((u) => /platform_version_id = v_new\.id/.test(u));
  assert.equal(alter.length, 1, 'um UPDATE da alteração');
  assert.match(alter[0], /\btags = public\._wiki_type_tags\(v_new\.doc_type\)/);
});

// ── leituras com o estado de auditoria ─────────────────────────────────────────────────────────
for (const [fn, sig] of [['get_wiki_page', 'text'], ['search_wiki_pages', 'text, integer, text, text']]) {
  test(`#2495 B1: ${fn} devolve audit_status no fim, segue SECURITY INVOKER e sem anon`, () => {
    const { file } = cap(fn);
    const sql = migFile(fn);
    const create = sql.slice(sql.indexOf(`CREATE FUNCTION public.${fn}(`));
    const header = create.slice(0, create.indexOf('AS $function$'));
    assert.match(header, /RETURNS TABLE\([^)]*, audit_status text\)\s/, 'audit_status é a última coluna');
    assert.doesNotMatch(header, /SECURITY DEFINER/, 'a RLS de wiki_pages é o portão: nada de DEFINER');
    assert.match(body(fn), /,\s*w\.audit_status\s+FROM wiki_pages w/, 'o SELECT devolve a coluna na última posição');
    assert.match(sql, new RegExp(`DROP FUNCTION public\\.${fn}\\(${sig.replace(/[()]/g, '\\$&')}\\);\\s+CREATE FUNCTION public\\.${fn}\\(`));
    assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\(${sig}\\) FROM PUBLIC, anon;`));
    assert.match(sql, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\(${sig}\\) TO authenticated, service_role;`));
    assert.ok(file, fn);
  });
}

test('#2495 B1: o auxiliar de tag não tem EXECUTE de cliente', () => {
  assert.match(migFile('_wiki_type_tags'), /REVOKE ALL ON FUNCTION public\._wiki_type_tags\(text\) FROM PUBLIC, anon, authenticated;/);
});

// ── assistente ─────────────────────────────────────────────────────────────────────────────────
test('#2495 B1: o aviso de auditoria pendente marca só a página pendente, em linha ou lista', () => {
  const pend = { path: 'nucleo/tribes/tribo-2', audit_status: 'pending' };
  assert.equal(withWikiAuditNotice(pend).audit_notice, WIKI_AUDIT_PENDING_NOTICE);
  assert.equal(pend.audit_notice, undefined, 'não altera a linha recebida');
  const list = withWikiAuditNotice([pend, { audit_status: 'audited' }, { audit_status: null }, null]);
  assert.deepEqual(list.map((r) => r?.audit_notice ?? null), [WIKI_AUDIT_PENDING_NOTICE, null, null, null]);
  assert.match(WIKI_AUDIT_PENDING_NOTICE, /auditoria do Comitê de Curadoria pendente/);
});

test('#2495 B1: toda leitura do wiki no MCP passa pelo aviso (conta as chamadas e os usos)', () => {
  const calls = [...MCP.matchAll(/sb\.rpc\("(get_wiki_page|search_wiki_pages)"/g)].map((m) => m.index);
  const uses = [...MCP.matchAll(/withWikiAuditNotice\(/g)].map((m) => m.index);
  assert.ok(calls.length >= 5, `esperava ao menos 5 leituras do wiki no MCP, achou ${calls.length}`);
  assert.equal(uses.length, calls.length, 'um aviso por leitura');
  // cada uso pertence à leitura imediatamente anterior, e nenhuma leitura fica sem uso
  const owner = uses.map((u) => Math.max(...calls.filter((c) => c < u)));
  assert.deepEqual([...new Set(owner)].sort((a, b) => a - b), [...calls].sort((a, b) => a - b));
  owner.forEach((c, k) => assert.ok(uses[k] - c < 1500, 'o aviso fica no mesmo tratador da leitura'));
  assert.match(MCP, /import \{ withWikiAuditNotice \} from "\.\/wiki-audit\.mjs";/);
});

// ── tela ───────────────────────────────────────────────────────────────────────────────────────
test('#2495 B1: o trecho da busca vira texto puro (o trecho real medido em 28/09)', () => {
  const h = '**Agentes** Autonomos\n\n**Quadrante:** 2 — The Augmented Practitioner\n**Lider:** Fulana\n'
    + '**Reuniao:** Segunda, 19:30–21:00\n\n## Objetivo\n\nPesquisa em **agentes**';
  const s = plainSnippet(h);
  assert.doesNotMatch(s, /\*|#|\n/);
  assert.match(s, /^Agentes Autonomos Quadrante: 2 — The Augmented Practitioner .* Objetivo Pesquisa em agentes$/);
  assert.equal(plainSnippet('[o guia](../x.md) e [[Radar|o radar]] `cod` 5 * 3 - 2'), 'o guia e o radar cod 5 * 3 - 2');
  assert.equal(plainSnippet(null), '');
});

test('#2495 B1: só o H1 de abertura sai; H1 no meio e #tag ficam', () => {
  assert.equal(dropLeadingTitle('# Tribo 2 — X\n\n## Objetivo\ntexto'), '\n## Objetivo\ntexto');
  assert.equal(dropLeadingTitle('\n\n  # T\ncorpo'), 'corpo');
  assert.equal(dropLeadingTitle('## Sem H1\ntexto'), '## Sem H1\ntexto');
  assert.equal(dropLeadingTitle('texto\n# no meio\n'), 'texto\n# no meio\n');
  assert.equal(dropLeadingTitle('#tag\nx'), '#tag\nx');
});

test('#2495 B1: a tela usa as duas regras onde renderiza e onde copia', () => {
  assert.match(SCRIPT, /const snippet = plainSnippet\(headline\);\s+const lead = snippet\s+\? `<p>\$\{highlight\(snippet, q\)\}<\/p>`/);
  assert.doesNotMatch(SCRIPT, /\$\{(sanitizeUserHtml\()?headline\)?\}/, 'o trecho nunca vai cru para o HTML');
  assert.match(SCRIPT, /return renderWikiMarkdown\(dropLeadingTitle\(md\), path, LINKS\);/);
  const at = SCRIPT.indexOf('function assistantMarkdown(');
  const copy = SCRIPT.slice(at, SCRIPT.indexOf('\n  }', at));
  assert.ok(at > 0, 'assistantMarkdown existe');
  assert.match(copy, /return `[\s\S]*\$\{dropLeadingTitle\(md\)\}/, 'o texto copiado também sai sem o H1 repetido');
  assert.doesNotMatch(copy, /\$\{md\b/, 'nenhum outro uso cru do markdown na cópia');
});

// ── banco vivo ──────────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);

test('#2495 B1 db: as leituras devolvem audit_status, seguem INVOKER, e a tag sai no formato da tela',
  { skip: dbGated ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required' }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: fns, error: e0 } = await sb.rpc('_audit_list_public_function_bodies');
    assert.ifError(e0);
    const secdef = (n) => fns.filter((f) => f.proname === n).map((f) => f.is_secdef);
    assert.deepEqual(secdef('get_wiki_page'), [false]);
    assert.deepEqual(secdef('search_wiki_pages'), [false]);
    assert.deepEqual(secdef('wiki_decide'), [true]);

    const { data: pages, error: e1 } = await sb.from('wiki_pages').select('path,title').limit(1);
    assert.ifError(e1);
    assert.equal(pages.length, 1, 'o wiki tem ao menos uma página para exercer a leitura');
    const got = await sb.rpc('get_wiki_page', { p_path: pages[0].path });
    assert.ifError(got.error);
    assert.ok(Object.hasOwn(got.data[0], 'audit_status'), 'get_wiki_page devolve audit_status');
    const term = pages[0].title.split(/\W+/u).find((w) => w.length >= 5) || pages[0].title;
    const found = await sb.rpc('search_wiki_pages', { p_query: term, p_limit: 5 });
    assert.ifError(found.error);
    assert.ok(found.data.length > 0, `a busca por "${term}" acha a página`);
    assert.ok(found.data.every((r) => Object.hasOwn(r, 'audit_status')), 'search_wiki_pages devolve audit_status');

    const t = await sb.rpc('_wiki_type_tags', { p_doc_type: 'how_to' });
    assert.ifError(t.error);
    assert.deepEqual(t.data, ['diataxis-how_to']);
  });
