/**
 * #2495 / ADR-0132: o rotulo epistemico da pagina do wiki.
 *
 * Cada versao leva um de quatro rotulos (fonte, observacao de membro, sintese de IA, pesquisa externa);
 * a pagina publicada leva o da versao que a publicou; a tela deixa escolher, com observacao de membro
 * como padrao, e mostra o selo. O MCP de escrita (a seguir) grava sintese de IA por padrao pela mesma
 * funcao.
 *
 * O que este guard amarra, sempre condicao junto do resultado:
 *   banco: o CHECK das duas colunas; wiki_save_draft recusa rotulo fora da lista, mantem o rotulo
 *            quando recebe NULL (nos dois caminhos de atualizacao) e usa o padrao ao criar; wiki_decide
 *            e wiki_audit levam o rotulo da versao para a pagina; as duas leituras o devolvem; o EXECUTE
 *            da assinatura nova e de authenticated, nunca de anon.
 *   tela: o seletor, o padrao, o bloqueio na alteracao do comite, o envio a funcao e o selo.
 *   i18n: as chaves dinamicas (T(`wiki.label.${l}`)) nos 3 dicionarios, que o guard generico de
 *            paridade nao enxerga.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const LABELS = ['fonte', 'observacao_membro', 'sintese_ia', 'pesquisa_externa'];
const LIST = LABELS.map((l) => `'${l}'`).join(',\\s*');
const body = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);
const allMigrations = () => readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => maskLineComments(readFileSync(join(DIR, f), 'utf8'))).join('\n');
const WIKI = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/wiki.astro'), 'utf8'));

// ── banco ───────────────────────────────────────────────────────────────────────────────────────
test('ADR-0132: as duas colunas so aceitam os 4 rotulos; a da versao e obrigatoria com padrao', () => {
  const all = allMigrations();
  assert.match(all, /ALTER TABLE public\.wiki_page_versions ADD COLUMN IF NOT EXISTS epistemic_label text NOT NULL DEFAULT 'observacao_membro';/);
  assert.match(all, new RegExp(`ADD CONSTRAINT wiki_page_versions_epistemic_label_check\\s+CHECK \\(epistemic_label = ANY \\(ARRAY\\[${LIST}\\]\\)\\);`));
  assert.match(all, new RegExp(`ADD CONSTRAINT wiki_pages_epistemic_label_check\\s+CHECK \\(epistemic_label IS NULL OR epistemic_label = ANY \\(ARRAY\\[${LIST}\\]\\)\\);`));
});

test('ADR-0132: wiki_save_draft recusa rotulo fora da lista', () => {
  assert.match(body('wiki_save_draft'),
    new RegExp(`IF p_epistemic_label IS NOT NULL AND p_epistemic_label <> ALL \\(ARRAY\\[${LIST}\\]\\) THEN\\s+RAISE EXCEPTION`));
});

test('ADR-0132: wiki_save_draft mantem o rotulo com NULL nos dois caminhos de atualizacao, e cria com o padrao', () => {
  const b = body('wiki_save_draft');
  const keeps = [...b.matchAll(/UPDATE public\.wiki_page_versions\s+SET [^;]*?epistemic_label = coalesce\(p_epistemic_label, epistemic_label\)[^;]*?WHERE id = (p_version_id|v_ver\.id);/g)].map((m) => m[1]);
  assert.deepEqual(keeps.sort(), ['p_version_id', 'v_ver.id'], 'edicao por id e reaproveitamento do rascunho aberto');
  assert.match(b, /INSERT INTO public\.wiki_page_versions\s+\([^)]*\bepistemic_label\)\s+VALUES\s+\([^;]*'draft', coalesce\(p_epistemic_label, 'observacao_membro'\)\)/);
});

test('ADR-0132: publicar leva o rotulo da versao para a pagina, tambem quando a pagina ja existe', () => {
  const b = body('wiki_decide');
  assert.match(b, /INSERT INTO public\.wiki_pages\s+\([^)]*platform_version_id, epistemic_label\)\s+VALUES\s+\([^;]*v_audit_status, p_version_id, v_ver\.epistemic_label\)\s+ON CONFLICT \(path\) DO UPDATE\s+SET [^;]*epistemic_label = EXCLUDED\.epistemic_label\s+WHERE public\.wiki_pages\.source_repo = 'plataforma';/);
});

test('ADR-0132: a versao alterada pelo comite herda o rotulo, e a pagina recebe o dela', () => {
  const b = body('wiki_audit');
  assert.match(b, /INSERT INTO public\.wiki_page_versions\s+\([^)]*audit_outcome, epistemic_label\)\s+VALUES\s+\([^;]*'kept', v_ver\.epistemic_label\)\s+RETURNING \* INTO v_new;/);
  assert.match(b, /UPDATE public\.wiki_pages\s+SET [^;]*platform_version_id = v_new\.id, epistemic_label = v_new\.epistemic_label\s+WHERE path = v_ver\.page_path AND source_repo = 'plataforma';/);
});

test('ADR-0132: as duas leituras devolvem o rotulo da pagina', () => {
  for (const name of ['get_wiki_page', 'search_wiki_pages']) {
    const cap = latestFunctionCapture(ROOT, name);
    const file = maskLineComments(readFileSync(join(DIR, cap.file), 'utf8'));
    assert.match(file, new RegExp(`CREATE FUNCTION public\\.${name}\\([^)]*\\)\\s+RETURNS TABLE\\([^)]*audit_status text, epistemic_label text\\)`), `${name}: retorno`);
    assert.match(body(name), /w\.audit_status, w\.epistemic_label\s+FROM wiki_pages w/, `${name}: a coluna vem da pagina`);
  }
});

test('ADR-0132: a assinatura nova de wiki_save_draft e de authenticated, nunca de anon', () => {
  const file = maskLineComments(readFileSync(join(DIR, latestFunctionCapture(ROOT, 'wiki_save_draft').file), 'utf8'));
  const sig = 'public\\.wiki_save_draft\\(text, uuid, text, text, text, text, jsonb, text, uuid, text\\)';
  assert.match(file, new RegExp(`REVOKE ALL ON FUNCTION ${sig} FROM PUBLIC, anon;`));
  assert.match(file, new RegExp(`GRANT EXECUTE ON FUNCTION ${sig} TO authenticated, service_role;`));
});

// ── tela ────────────────────────────────────────────────────────────────────────────────────────
test('ADR-0132: a tela conhece os mesmos 4 rotulos e propoe observacao de membro', () => {
  assert.match(WIKI, new RegExp(`const EPISTEMIC_LABELS = \\[${LIST}\\];\\s+const DEFAULT_LABEL = 'observacao_membro';`));
});

test('ADR-0132: o editor mostra o rotulo da versao-base (ou o padrao) e o trava na alteracao do comite', () => {
  assert.match(WIKI, /<select id="w-label" class="\$\{INPUT\} mt-1" \$\{alter \? 'disabled' : ''\}>\s+\$\{EPISTEMIC_LABELS\.map\(\(l\) => `<option value="\$\{l\}" \$\{\(base\?\.epistemic_label \|\| DEFAULT_LABEL\) === l \? 'selected' : ''\}>/);
});

test('ADR-0132: salvar manda o rotulo escolhido, validado contra a lista', () => {
  assert.match(WIKI, /label: EPISTEMIC_LABELS\.includes\(\$<HTMLSelectElement>\('w-label'\)\.value\) \? \$<HTMLSelectElement>\('w-label'\)\.value : DEFAULT_LABEL,/);
  assert.match(WIKI, /rpc\('wiki_save_draft', \{[^}]*p_epistemic_label: f\.label,\s*\}\)/);
});

test('ADR-0132: o selo aparece na pagina publicada e na versao, e so para rotulo conhecido', () => {
  assert.match(WIKI, /const labelChip = \(l: string \| null \| undefined\) => l && EPISTEMIC_LABELS\.includes\(l\)\s+\? `<span class="wk-chip wk-chip-label/);
  assert.match(WIKI, /const meta = row \? \[\s+typeChip\(typ\),\s+labelChip\(row\.epistemic_label\),/);
  assert.match(WIKI, /\$\{statusChip\(v\.status\)\}\$\{labelChip\(v\.epistemic_label\)\}/);
});

test('ADR-0132: as chaves dinamicas do rotulo existem nos 3 dicionarios', () => {
  const keys = ['wiki.fieldLabel', 'wiki.fieldLabelHint',
    ...LABELS.map((l) => `wiki.label.${l}`), ...LABELS.map((l) => `wiki.labelHint.${l}`)];
  for (const f of ['pt-BR', 'en-US', 'es-LATAM']) {
    const lines = readFileSync(resolve(ROOT, `src/i18n/${f}.ts`), 'utf8').split('\n').map((l) => l.trim());
    // Comparação de linha, sem montar regex a partir da chave: a chave com valor não vazio.
    const has = (k) => lines.some((l) => l.startsWith(`'${k}': '`) && l.endsWith("',") && l.length > `'${k}': '',`.length);
    const missing = keys.filter((k) => !has(k));
    assert.deepEqual(missing, [], `${f}: faltam chaves`);
  }
});
