/**
 * #2624 (decisao do GP de 09/10/2026): publicacao e categoria, e todo artefato do tipo 'publicacao'
 * precisa de exatamente um formato (subtipo), na MARCACAO e no ENVIO a curadoria. O predicado
 * _board_item_needs_curation fica como esta ate o backfill dos lideres.
 *
 * Medido em 09/10: 35 artefatos do tipo publicacao, 23 sem formato. A comunicacao nao planeja canal,
 * formato nem esforco a partir da 'publicacao' generica.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. marcar 'publicacao' sem formato e recusado, antes de trocar o tipo;
 *   B. a entrada em curadoria (TRANSICAO para curation_pending, por qualquer caminho) recusa
 *      publicacao com zero ou mais de um formato;
 *   C. o predicado de artefato publicavel nao mudou (decisao do GP);
 *   D. toda mensagem nova chega traduzida a tela, nas 3 linguas;
 *   E. a tela nao grava 'publicacao' sem formato: escolher o tipo abre o formato, e "sem formato"
 *      deixou de ser opcao.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const setType = maskLineComments(latestFunctionCapture(ROOT, 'set_board_item_artifact_type').body);
const entry = maskLineComments(latestFunctionCapture(ROOT, 'trg_curation_entry_requires_subtype').body);
const predicate = maskLineComments(latestFunctionCapture(ROOT, '_board_item_needs_curation').body);
const card = maskJsComments(readFileSync(resolve(ROOT, 'src/components/board/CardDetail.tsx'), 'utf8'));
const engine = readFileSync(resolve(ROOT, 'src/components/islands/BoardEngine.tsx'), 'utf8');
const types = readFileSync(resolve(ROOT, 'src/types/board.ts'), 'utf8');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8'));
const MSG_PREFIX = 'Publicação precisa de exatamente um formato';

/** A definicao MAIS NOVA do gatilho, com comentarios mascarados. */
function latestTriggerDdl() {
  let hit = '';
  for (const f of readdirSync(DIR).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(DIR, f), 'utf8'));
    const m = sql.match(/CREATE TRIGGER trg_curation_entry_requires_subtype[\s\S]*?;/);
    if (m) hit = sql;
  }
  return hit;
}

test('A. marcar publicacao sem formato e recusado, antes de trocar o tipo', () => {
  const m = setType.match(new RegExp(`IF p_type = 'publicacao' AND p_subtype IS NULL THEN\\s+RAISE EXCEPTION '${MSG_PREFIX}`));
  assert.ok(m, 'publicacao sem formato e recusada');
  const del = setType.indexOf('DELETE FROM public.board_item_tag_assignments');
  assert.ok(del !== -1 && m.index < del, 'a recusa vem antes de apagar o tipo atual');
});

test('B. a entrada em curadoria recusa publicacao com zero ou mais de um formato', () => {
  assert.match(entry,
    /SELECT coalesce\(bool_or\(g\.tier = 'system' AND g\.name = 'publicacao'\), false\),\s+count\(\*\) FILTER \(WHERE g\.tier = 'administrative' AND g\.requires_curation IS TRUE\)\s+INTO v_is_pub, v_formats\s+FROM public\.board_item_tag_assignments a\s+JOIN public\.tags g ON g\.id = a\.tag_id\s+WHERE a\.board_item_id = NEW\.id/,
    'conta os formatos do proprio card');
  assert.match(entry, new RegExp(`IF v_is_pub AND v_formats <> 1 THEN\\s+RAISE EXCEPTION '${MSG_PREFIX}`),
    'zero ou mais de um formato recusa');

  const ddl = latestTriggerDdl();
  assert.match(ddl,
    /CREATE TRIGGER trg_curation_entry_requires_subtype\s+BEFORE UPDATE OF curation_status ON public\.board_items\s+FOR EACH ROW\s+WHEN \(NEW\.curation_status = 'curation_pending' AND OLD\.curation_status IS DISTINCT FROM 'curation_pending'\)\s+EXECUTE FUNCTION public\.trg_curation_entry_requires_subtype\(\);/,
    'BEFORE (a recusa aborta a escrita), so na TRANSICAO de entrada');
  assert.match(ddl, /REVOKE ALL ON FUNCTION public\.trg_curation_entry_requires_subtype\(\) FROM PUBLIC, anon, authenticated;/,
    'funcao de gatilho sem EXECUTE para a borda');
});

test('C. o predicado de artefato publicavel nao mudou (decisao do GP)', () => {
  assert.match(predicate, /bi\.is_portfolio_item IS TRUE\s+AND g\.domain = 'board_item'\s+AND g\.requires_curation IS TRUE/);
  assert.doesNotMatch(predicate, /administrative|count\(/, 'o formato nao entrou no predicado');
});

test('D. a mensagem nova chega traduzida, nas 3 linguas', () => {
  const bloco = (card.match(/const REVIEW_ERRORS: Array<\[RegExp, string\]> = \[([\s\S]*?)\n\];/) || [])[1] || '';
  const pads = [...bloco.matchAll(/\[\/(.+?)\/([a-z]*), '([A-Za-z]+)'\]/g)].map((m) => [new RegExp(m[1], m[2]), m[3]]);
  const msgs = [...(setType + entry).matchAll(/RAISE EXCEPTION '((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'").replace(/%/g, 'x'));
  assert.ok(msgs.length >= 7, `so ${msgs.length} mensagens lidas`);
  for (const msg of msgs) {
    const hit = pads.find(([re]) => re.test(msg));
    assert.ok(hit, `sem traducao: ${msg}`);
    if (msg.startsWith(MSG_PREFIX)) assert.equal(hit[1], 'reviewErrNoSubtype', `${msg} cai na chave certa`);
  }
  for (const d of DICTS) {
    assert.match(d, /'comp\.board\.reviewErrNoSubtype': '[^']+',/);
    assert.match(d, /'comp\.board\.artifactSubtypeMissing': '[^']+',/);
    assert.match(d, /'comp\.board\.artifactSubtypePending': '[^']+',/);
  }
  assert.match(engine, /artifactSubtypePending: t\('comp\.board\.artifactSubtypePending', DEFAULT_I18N\.artifactSubtypePending\),/);
  // designar parecerista em card concluido envia a curadoria (gatilho p197): o erro tambem traduz
  assert.match(card, /toast\?\.\(friendlyReviewError\(err\?\.message, 'Erro ao adicionar membro'\), 'error'\);/,
    'a designacao mostra a recusa traduzida');
  assert.match(engine, /reviewErrNoSubtype: t\('comp\.board\.reviewErrNoSubtype', DEFAULT_I18N\.reviewErrNoSubtype\),/);
  assert.match(engine, /artifactSubtypeMissing: t\('comp\.board\.artifactSubtypeMissing', DEFAULT_I18N\.artifactSubtypeMissing\),/);
  assert.match(types, /reviewErrNoSubtype\?: string;/);
});

test('E. a tela nao grava publicacao sem formato', () => {
  assert.match(card,
    /const chooseArtifactType = \(type: string \| null\) => \{\s+if \(type === 'publicacao' && classif\?\.type !== 'publicacao'\) \{ setPendingPublication\(true\); return; \}/,
    'escolher publicacao abre o formato em vez de gravar');
  assert.match(card, /onChange=\{\(e\) => chooseArtifactType\(e\.target\.value \|\| null\)\}/, 'o seletor de tipo passa por ela');
  assert.match(card, /onClick=\{\(\) => chooseArtifactType\(classif\.suggested\)\}/, 'a sugestao tambem');
  assert.doesNotMatch(card, /saveArtifactType\(e\.target\.value \|\| null, null\)/, 'nenhum seletor grava tipo direto');
  assert.match(card, /\{\(classif\.type === 'publicacao' \|\| pendingPublication\) && \(\s+<select\s+value=\{classif\.subtype \|\| ''\}/,
    'o formato aparece tambem na escolha pendente');
  assert.match(card, /<option value="" disabled>\{i18n\.artifactSubtypeNone/, '"sem formato" deixou de ser opcao');
  assert.match(card, /useEffect\(\(\) => \{ setClassif\(null\); setPendingPublication\(false\); loadClassif\(\); \}/,
    'trocar de card descarta a escolha pendente');
  assert.match(card, /toast\?\.\(i18n\.artifactTypeSaved \|\| 'Tipo de artefato salvo', 'success'\);\s+setPendingPublication\(false\);/,
    'gravar com sucesso encerra a escolha pendente');
  assert.match(card,
    /\{\(classif\.type === 'publicacao' \|\| pendingPublication\) && !classif\.subtype && classif\.can_edit && \(\s+<p id=\{`artifact-subtype-hint-\$\{item\.id\}`\} role="status"[^>]*>\s+\{'⚠ '\}\{pendingPublication\s+\? \(i18n\.artifactSubtypePending/,
    'o aviso so aparece para quem pode escolher, e diz quando nada foi salvo');
});
