/**
 * #2621 (decisao do GP de 09/10/2026: "no card, ja"): prazo do destino no card.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. set_curation_target: card invisivel responde como item ausente (mesma mensagem); so autoria,
 *      lideranca da iniciativa ou governanca gravam; so antes da publicacao; sem EXECUTE para anon;
 *   B. as duas listas da curadoria devolvem destino, data-alvo e o alerta (prazo da curadoria, no fuso de
 *      Brasilia, depois da data-alvo);
 *   C. o card edita o prazo so para quem pode enviar e alerta pelo mesmo criterio; a tela da curadoria
 *      mostra o destino; toda mensagem nova da RPC chega traduzida;
 *   D. o MCP grava o destino ANTES de enviar, campo omitido nao apaga o gravado, data invalida e
 *      entrada invalida, e o card_write grava sem enviar;
 *   E. todo texto novo existe nas 3 linguas.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const setFn = maskLineComments(latestFunctionCapture(ROOT, 'set_curation_target').body);
const listFn = maskLineComments(latestFunctionCapture(ROOT, 'list_curation_pending_board_items').body);
const queueFn = maskLineComments(latestFunctionCapture(ROOT, 'get_curation_queue_state').body);
const card = maskJsComments(readFileSync(resolve(ROOT, 'src/components/board/CardDetail.tsx'), 'utf8'));
const cur = maskJsComments(readFileSync(resolve(ROOT, 'src/components/boards/CuratorshipBoardIsland.tsx'), 'utf8'));
const mcp = maskJsComments(readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8'));
const engine = readFileSync(resolve(ROOT, 'src/components/islands/BoardEngine.tsx'), 'utf8');
const curPage = readFileSync(resolve(ROOT, 'src/pages/admin/curatorship.astro'), 'utf8');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8'));
const DIR = resolve(ROOT, 'supabase/migrations');
const allSql = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort().map((f) => maskLineComments(readFileSync(join(DIR, f), 'utf8'))).join('\n');
const RISK = /\(bi\.curation_target_date IS NOT NULL AND bi\.curation_due_at IS NOT NULL AND \(bi\.curation_due_at AT TIME ZONE 'America\/Sao_Paulo'\)::date > bi\.curation_target_date\) AS target_at_risk/;

test('A. set_curation_target: visibilidade, autoridade, etapa e grants antes de gravar', () => {
  assert.match(setFn, /IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;\s+IF NOT public\.rls_can_see_board\(v_item\.board_id\) THEN\s+RAISE EXCEPTION 'Item not found: %', p_item_id;\s+END IF;/);
  const write = setFn.indexOf('UPDATE public.board_items');
  const stage = setFn.indexOf("IF v_item.curation_status NOT IN ('draft', 'peer_review', 'leader_review', 'curation_pending') THEN");
  const auth = setFn.indexOf('IF NOT v_is_authorized THEN');
  assert.ok(write !== -1 && stage !== -1 && auth !== -1 && stage < write && auth < write, 'etapa e autoridade antes da escrita');
  assert.match(setFn, /IF v_item\.assignee_id = v_caller\.id THEN\s+v_is_authorized := true;\s+ELSIF EXISTS \([\s\S]*?bia\.role IN \('author', 'contributor'\)[\s\S]*?ELSIF v_initiative_id IS NOT NULL AND EXISTS \([\s\S]*?e\.role = 'leader'[\s\S]*?ELSIF public\.can_by_member\(v_caller\.id, 'participate_in_governance_review'\) THEN\s+v_is_authorized := true;\s+END IF;\s+IF NOT v_is_authorized THEN\s+RAISE EXCEPTION 'Requires /);
  assert.match(setFn, /SET curation_target_venue = v_venue,\s+curation_target_date\s+= p_date,/);
  assert.match(allSql, /REVOKE ALL ON FUNCTION public\.set_curation_target\(uuid, text, date\) FROM PUBLIC, anon;/);
  assert.match(allSql, /ADD COLUMN IF NOT EXISTS curation_target_venue text NULL,\s+ADD COLUMN IF NOT EXISTS curation_target_date date NULL;/);
  assert.match(allSql, /ADD CONSTRAINT board_items_curation_target_venue_len\s+CHECK \(curation_target_venue IS NULL OR char_length\(curation_target_venue\) BETWEEN 1 AND 200\);/, 'o teto vale na tabela');
  assert.match(setFn, /IF length\(v_venue\) > 200 THEN\s+RAISE EXCEPTION 'Target venue too long/, 'e na RPC, com mensagem');
  assert.match(card, /<input type="text" maxLength=\{200\}/, 'e na tela, com o mesmo numero');
});

test('A. a mudanca do destino fica no historico do card, e o CHECK das acoes nao perde valor', () => {
  assert.match(setFn, /IF v_item\.curation_target_venue IS DISTINCT FROM v_venue OR v_item\.curation_target_date IS DISTINCT FROM p_date THEN\s+INSERT INTO public\.board_lifecycle_events \(board_id, item_id, action, reason, actor_member_id\)\s+VALUES \(\s+v_item\.board_id,\s+p_item_id,\s+'curation_target_set',/);
  const mig = maskLineComments(readFileSync(join(DIR, readdirSync(DIR).filter((x) => x.includes('_2621_prazo_do_destino')).sort().pop()), 'utf8'));
  assert.match(mig, /IF v_old IS NULL OR cardinality\(v_old\) < 37 THEN\s+RAISE EXCEPTION/, 'leitura curta aborta antes do DROP');
  assert.ok(mig.indexOf('cardinality(v_old) < 37') < mig.indexOf('DROP CONSTRAINT board_lifecycle_events_action_check'), 'o piso vem antes do DROP');
  assert.match(mig, /CHECK \(action = ANY \(ARRAY\[%s\]\)\)',\s+\(SELECT string_agg\(quote_literal\(x\), ', '\) FROM unnest\(array_append\(v_old, 'curation_target_set'\)\) AS x\)\);/, 'remonta com os valores vivos mais o novo');
  assert.match(mig, /IF NOT \(v_new @> v_old AND 'curation_target_set' = ANY \(v_new\) AND cardinality\(v_new\) = cardinality\(v_old\) \+ 1\) THEN\s+RAISE EXCEPTION/, 'pos-condicao: nenhum valor antigo caiu');
});

test('B. as listas da curadoria devolvem destino, data-alvo e alerta', () => {
  assert.match(listFn, /bi\.curation_target_venue, bi\.curation_target_date,/);
  assert.match(listFn, RISK);
  assert.match(queueFn, RISK);
  assert.match(queueFn, /'target_venue', q\.curation_target_venue,\s+'target_date', q\.curation_target_date,\s+'target_at_risk', q\.target_at_risk,/);
});

test('C. o card edita so para quem pode enviar e alerta pelo mesmo criterio', () => {
  assert.match(card, /const canEditTarget = isLeader \|\| isCardAssignee;/);
  const edit = (card.match(/\{canEditTarget \? \(([\s\S]*?)\n {18}\) : \(/) || [])[1] || '';
  assert.match(edit, /<button type="button" onClick=\{saveTarget\}\s+disabled=\{!targetLoaded \|\| savingTarget \|\| !dirty\}/, 'salvar so para quem pode, e so depois de ler o gravado');
  assert.match(card, /if \(!alive \|\| error \|\| !data\) return;[\s\S]{0,200}setTargetLoaded\(true\);/, 'leitura que falhou nao libera os campos');
  assert.match(card, /if \(error\) throw error;\s+if \(targetItemRef\.current !== savingFor\) return;\s+setTargetVenue\(sent\.venue\); setTargetSaved\(sent\);/, 'trocar de card durante o salvamento nao contamina o card novo');
  assert.match(card, /sb\.rpc\('set_curation_target', \{ p_item_id: savingFor, p_venue: sent\.venue \|\| null, p_date: sent\.date \|\| null \}\)/);
  assert.match(card, /toLocaleDateString\('en-CA', \{ timeZone: 'America\/Sao_Paulo' \}\)[\s\S]*?const atRisk = !!\(targetSaved\.date && dueLocal && dueLocal > targetSaved\.date\);/, 'mesmo criterio do banco');
  assert.match(card, /\{atRisk \? \(\s+<p role="alert"/, 'o alerta e anunciado');
  assert.match(cur, /<TargetBadge item=\{item\} ui=\{ui\} \/>[\s\S]*<TargetBadge item=\{item\} ui=\{ui\} \/>/, 'a curadoria ve o destino nos dois lugares');
});

test('C. toda mensagem da RPC nova chega traduzida', () => {
  const bloco = (card.match(/const REVIEW_ERRORS: Array<\[RegExp, string\]> = \[([\s\S]*?)\n\];/) || [])[1] || '';
  const pads = [...bloco.matchAll(/\[\/(.+?)\/([a-z]*), '([A-Za-z]+)'\]/g)].map((m) => new RegExp(m[1], m[2]));
  const msgs = [...setFn.matchAll(/RAISE EXCEPTION '((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'").replace(/%/g, 'x'));
  assert.ok(msgs.length >= 5, `so ${msgs.length} mensagens lidas`);
  assert.deepEqual(msgs.filter((m) => !pads.some((re) => re.test(m))), []);
});

test('D. o MCP grava o destino antes de enviar, e campo omitido nao apaga o gravado', () => {
  const h = (mcp.match(/async function setCurationTargetIfGiven\([\s\S]*?\n\}\n/) || [''])[0];
  assert.match(h, /if \(venue === undefined && date === undefined\) return null;\s+if \(date && !isCalendarDate\(date\)\) return \{ error: [^}]*errorCode: "invalid_input" \};/, 'sem campos nada e chamado; data invalida e entrada invalida');
  assert.match(h, /if \(v === undefined \|\| d === undefined\) \{[\s\S]*?if \(v === undefined\) v = cur\?\.curation_target_venue \?\? null;\s+if \(d === undefined\) d = cur\?\.curation_target_date \?\? null;\s+\}\s+const \{ data, error \} = await sb\.rpc\("set_curation_target", \{ p_item_id: itemId, p_venue: v \|\| null, p_date: d \|\| null \}\);/, 'o omitido e relido antes de gravar');
  assert.match(mcp, /const tgt = await setCurationTargetIfGiven\(sb, params\.item_id, params\.target_venue, params\.target_date\);\s+if \(tgt\?\.error\) \{[^\n]*return err\([^\n]*\}\s+const res = await submitForCurationAndReadState\(sb, params\.item_id\);/, 'ferramenta crua: recusa do destino para antes do envio');
  assert.match(mcp, /return err\(tgt\?\.saved \? `\$\{res\.error\} \(target_venue\/target_date WERE saved/, 'envio recusado diz que o destino ficou gravado');
  assert.match(mcp, /const RPC_DECIDES = new Set\(\[\.\.\.ROLE_ACTIONS, "submit_for_curation", "set_curation_target"\]\);/, 'a RPC decide quem grava, sem write_board');
  assert.match(mcp, /if \(hasTarget && !TARGET_ACTIONS\.has\(params\.action\)\) return invalid\(/, 'destino em outra acao e recusado, nao ignorado');
  const br = (mcp.match(/if \(params\.action === "set_curation_target"\) \{([\s\S]*?)\n {6}\}\n/) || [])[1] || '';
  assert.match(br, /^\s+const tgt = await setCurationTargetIfGiven\(sb, params\.card_id, params\.target_venue, params\.target_date\);\s+if \(tgt\?\.error\) \{[\s\S]*?return ok\(buildSemanticError/, 'card_write grava sem enviar');
  assert.doesNotMatch(br, /submitForCurationAndReadState|canV4\(/, 'gravar o destino nao envia nem tem portao proprio');
});

test('E. todo texto novo existe nas 3 linguas', () => {
  for (const k of ['targetTitle', 'targetVenueLabel', 'targetDateLabel', 'targetSave', 'targetNoVenue', 'targetAtRisk', 'targetSaved', 'targetHelp', 'targetNoDueYet', 'targetReadOnly', 'targetNoDate', 'targetClearDate']) {
    for (const d of DICTS) assert.match(d, new RegExp(`'comp\\.board\\.${k}': '`), `${k}`);
    assert.match(engine, new RegExp(`${k}: t\\('comp\\.board\\.${k}', DEFAULT_I18N\\.${k}\\),`));
  }
  for (const k of ['targetLabel', 'targetAtRisk']) {
    for (const d of DICTS) assert.match(d, new RegExp(`'admin\\.curatorship\\.${k}': '`), `admin.curatorship.${k}`);
    assert.match(curPage, new RegExp(`${k}: t\\('admin\\.curatorship\\.${k}', lang\\),`));
  }
});
