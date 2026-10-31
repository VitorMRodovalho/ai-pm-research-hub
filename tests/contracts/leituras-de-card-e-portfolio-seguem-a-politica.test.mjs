/**
 * Leituras de card e do portfólio seguem a política de leitura das tabelas (membro com vínculo vigente).
 *
 * Mesma regra de leitura-secdef-segue-politica-das-tabelas e do lote 2a: a quem chama pela API
 * (_request_is_rest_caller(), #684), a leitura segue a política da tabela, rls_is_authoritative_member().
 *
 * O QUE ESTE GUARD AFIRMA, na captura VIGENTE:
 *   T. get_card_timeline devolve vazio a quem não tem vínculo vigente, num IF antes do RETURN QUERY.
 *   S. exec_portfolio_board_summary (função SQL) aplica a regra no WHERE do CTE dos quadros, e toda contagem sai
 *      desse CTE: o portão no lugar que decide o resultado, não numa leitura lateral.
 *   V. no banco, o corpo vivo das duas é a captura vigente.
 * Fora daqui, de propósito: get_item_curation_history já aplica a regra desde 05/10 (guard do lote 2a), e
 * exec_portfolio_health é leitura pública por decisão (Metas da home, lida como anon no guard pr3-decisoes-site).
 * O efeito, como anon, autenticado sem membro e membro, está na verificação do pacote.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const REGRA = String.raw`public\._request_is_rest_caller\(\) AND NOT public\.rls_is_authoritative_member\(\)`;

test('T. get_card_timeline: sem vínculo vigente pela API, vazio, antes do RETURN QUERY', () => {
  const b = maskLineComments(latestFunctionCapture(ROOT, 'get_card_timeline').block);
  const g = b.search(new RegExp(`IF ${REGRA} THEN RETURN; END IF;`));
  assert.ok(g >= 0, 'a regra devolve vazio (RETURN) no corpo vigente');
  const q = b.indexOf('RETURN QUERY');
  assert.ok(q > g, `a regra (${g}) vem antes do RETURN QUERY (${q})`);
});

test('S. exec_portfolio_board_summary: a regra fica no CTE dos quadros, de onde saem todas as contagens', () => {
  const b = maskLineComments(latestFunctionCapture(ROOT, 'exec_portfolio_board_summary').block);
  const ini = b.indexOf('WITH boards AS (');
  const fim = b.search(/\),\s+items AS \(/);
  assert.ok(ini >= 0 && fim > ini, 'o CTE dos quadros existe e termina antes de items');
  const boards = b.slice(ini, fim);
  assert.match(boards, /WHERE \(p_include_inactive OR pb\.is_active = true\) AND NOT public\.is_confidential_board\(pb\.id\)\s+AND \(NOT public\._request_is_rest_caller\(\) OR public\.rls_is_authoritative_member\(\)\)\s*$/,
    'a regra é a última condição do WHERE dos quadros');
  const resto = b.slice(fim);
  assert.match(resto, /items AS \(\s+SELECT[\s\S]*?FROM boards b\s+LEFT JOIN public\.board_items bi ON bi\.board_id = b\.board_id/,
    'as contagens de items saem dos quadros filtrados');
  assert.match(resto, /\)\s+FROM items i;\s*\$function\$/, 'o resultado sai só de items');
  assert.doesNotMatch(resto, /FROM public\.(project_boards|board_items)\b/, 'nenhuma leitura de quadro ou card fora do CTE');
});

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const skip = SUPABASE_URL && SUPABASE_KEY ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('V. o corpo vivo das duas é a captura vigente', { skip }, async () => {
  const { parseMigration } = await import('../helpers/rpc-body-drift-parser.mjs');
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_list_public_function_bodies`, {
    method: 'POST',
    headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, 'Content-Type': 'application/json' },
    body: '{}',
  });
  assert.equal(r.status, 200);
  const vivos = await r.json();
  for (const fn of ['get_card_timeline', 'exec_portfolio_board_summary']) {
    const cap = latestFunctionCapture(ROOT, fn);
    const [bloco] = parseMigration(cap.file, cap.block);
    const linhas = vivos.filter((x) => x.proname === fn);
    assert.equal(linhas.length, 1, `${fn}: ${linhas.length} assinaturas vivas`);
    assert.equal(linhas[0].body_md5, bloco.bodyHash, `${fn}: corpo vivo diferente da captura vigente`);
  }
});
