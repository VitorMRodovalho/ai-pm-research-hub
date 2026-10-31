/**
 * Contract: #2862 (G3) e #2621 (G1) — a curadoria responde pelo critério da RPC, e a tela pergunta à RPC.
 *
 * G3. As 4 leitoras da fila de curadoria aceitavam `write_board` em ALGUM lugar (#245, #1977), e
 * `write_board` vem de qualquer engajamento de tribo. Medido em 30/10/2026 com JWT de cada papel:
 * `list_curation_board` devolveu a fila inteira a pesquisador, líder de tribo e comunicação. A tela
 * de curadoria já pedia `curate_content` OU `participate_in_governance_review`. As 4 passam a pedir
 * o mesmo. Em 31/10, de 117 membros ativos: 86 passavam no portão antigo, 19 passam no novo, e os
 * 19 são exatamente os que a tela admite.
 *
 * G1. O botão de envio à curadoria aparecia para quem a `submit_for_curation` recusa (o atribuído
 * ao card). A tela passa a ler `can_submit_curation` de `get_artifact_classification`, calculado com
 * a MESMA regra de autoridade da RPC (mesmo desenho do `can_leader_review` da #2455). A RPC não muda.
 *
 * Camadas:
 *   G  estática sobre a captura vigente: o portão de cada leitora amarra as duas capacidades ao RAISE,
 *      antes da leitura, e a INVERSA (o ramo `write_board` não sobrou em lugar nenhum);
 *   C  o campo novo tem a regra da RPC, e a regra da RPC é a que o campo copia (paridade nos dois
 *      corpos: se a `submit_for_curation` mudar, este guard reprova e aponta o campo);
 *   V  corpo vivo igual à captura nas 6 funções.
 * O efeito por persona (quem perde, quem ganha, o campo igual à decisão da RPC) foi exercido no
 * pacote de banco, com impersonação em transação somente leitura, antes e depois do apply.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { normalizeBody, md5 } from '../helpers/rpc-body-drift-parser.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
/** Corpo vigente, sem comentário e com espaço colapsado: a asserção fala da regra, não da indentação. */
const corpo = (nome) => maskLineComments(latestFunctionCapture(ROOT, nome).body).replace(/\s+/g, ' ');

const PORTAO_LEITORA = new RegExp(
  "IF NOT \\( ?public\\.can_by_member\\(v_member_id, 'curate_content'\\) " +
  "OR public\\.can_by_member\\(v_member_id, 'participate_in_governance_review'\\) ?\\) " +
  "THEN RAISE EXCEPTION 'Curatorship access required'");
/** Onde a leitura começa em cada uma: o portão tem de vir antes. */
const LEITURA = /RETURN QUERY|SELECT jsonb_build_object\(/;

const LEITORAS = ['list_curation_board', 'list_curation_pending_board_items', 'get_curation_dashboard'];

test('#2862 controle positivo: as 6 funções têm captura não vazia', () => {
  for (const n of [...LEITORAS, 'get_curation_queue_state', 'get_artifact_classification', 'submit_for_curation']) {
    assert.ok(corpo(n).length > 200, `${n} resolveu para captura vazia: toda asserção abaixo passaria por vácuo`);
  }
});

test('#2862 G: as 3 leitoras exigem curate_content OU governança, antes de ler', () => {
  for (const n of LEITORAS) {
    const c = corpo(n);
    const portao = c.search(PORTAO_LEITORA);
    assert.ok(portao >= 0, `${n}: o portão não é curate_content OU participate_in_governance_review terminando no RAISE`);
    const leitura = c.search(LEITURA);
    assert.ok(leitura > portao, `${n}: a leitura começa antes do portão (portão em ${portao}, leitura em ${leitura})`);
  }
});

test('#2862 G (INVERSA): nenhuma das 3 pergunta por write_board', () => {
  for (const n of LEITORAS) {
    assert.doesNotMatch(corpo(n), /'write_board'/,
      `${n}: write_board voltou ao corpo. Um segundo ramo reabriria a fila a todo membro de tribo com este teste verde`);
  }
});

test('#2862 G: get_curation_queue_state abre só para curate_content OU governança', () => {
  const c = corpo('get_curation_queue_state');
  assert.match(c, /v_can_curate := public\.can_by_member\(v_member_id, 'curate_content'\);/,
    'v_can_curate deixou de ser curate_content');
  assert.match(c, /v_can_govern := public\.can_by_member\(v_member_id, 'participate_in_governance_review'\);/,
    'v_can_govern deixou de ser participate_in_governance_review');
  const portao = c.search(/IF NOT \(v_can_curate OR v_can_govern\) THEN RAISE EXCEPTION 'Curatorship access required'/);
  assert.ok(portao >= 0, 'o portão não é (v_can_curate OR v_can_govern) terminando no RAISE');
  assert.ok(c.search(/WITH q AS \(/) > portao, 'a fila é lida antes do portão');
  // INVERSA: v_can_write_board fica só no bloco `caller` da resposta, nunca num IF.
  assert.doesNotMatch(c, /IF NOT \([^)]*v_can_write_board/, 'v_can_write_board voltou a abrir o portão');
});

// ─── C: o campo da tela tem a regra da RPC ────────────────────────────────────────

/** O valor de `can_submit_curation`, até a chave seguinte do jsonb_build_object. */
function campoCanSubmit() {
  const c = corpo('get_artifact_classification');
  const m = c.match(/'can_submit_curation', ([\s\S]*?), 'types',/);
  assert.ok(m, "get_artifact_classification não devolve 'can_submit_curation' antes de 'types'");
  return m[1];
}

test('#2621 C: can_submit_curation = governança OU (tribe_leader E líder ativo da iniciativa do quadro)', () => {
  const v = campoCanSubmit();
  assert.match(v, new RegExp(
    "^public\\.can_by_member\\(v_caller, 'participate_in_governance_review'\\) " +
    "OR \\(v_init IS NOT NULL " +
    "AND EXISTS \\(SELECT 1 FROM public\\.members m WHERE m\\.id = v_caller AND m\\.operational_role = 'tribe_leader'\\) " +
    "AND EXISTS \\(SELECT 1 FROM public\\.engagements e JOIN public\\.persons p ON p\\.id = e\\.person_id " +
    "WHERE e\\.initiative_id = v_init AND e\\.status = 'active' AND e\\.role = 'leader' AND p\\.auth_id = auth\\.uid\\(\\)\\)\\)$"),
    `can_submit_curation não tem a regra de autoridade da submit_for_curation: ${v}`);
});

test('#2621 C (paridade): a submit_for_curation tem a regra que o campo copia', () => {
  // Se esta falhar, a RPC mudou de regra: atualize can_submit_curation junto, nunca só este teste.
  const c = corpo('submit_for_curation');
  assert.match(c, /v_is_gov := public\.can_by_member\(v_caller\.id, 'participate_in_governance_review'\);/,
    'a submit_for_curation deixou de pedir governança como a primeira via');
  assert.match(c, /IF NOT \( v_is_gov OR v_caller\.operational_role = 'tribe_leader' \) THEN RAISE EXCEPTION/,
    'a submit_for_curation deixou de aceitar governança OU tribe_leader no primeiro portão');
  assert.match(c, new RegExp(
    "IF NOT v_is_gov AND NOT EXISTS \\( SELECT 1 FROM project_boards pb JOIN engagements e ON e\\.initiative_id = pb\\.initiative_id " +
    "JOIN persons p ON p\\.id = e\\.person_id WHERE pb\\.id = v_item\\.board_id AND e\\.status = 'active' " +
    "AND e\\.role = 'leader' AND p\\.auth_id = auth\\.uid\\(\\) \\) THEN RAISE EXCEPTION"),
    'a submit_for_curation deixou de exigir liderança ativa na iniciativa do quadro de quem não é governança');
});

// ─── V: vivo ──────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const temCredencial = Boolean(URL_BASE && KEY);

test('#2862 V: o corpo VIVO das 6 é igual à captura', { skip: temCredencial ? false : 'sem credencial de banco' }, async () => {
  for (const n of [...LEITORAS, 'get_curation_queue_state', 'get_artifact_classification', 'submit_for_curation']) {
    const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/_audit_function_source`, {
      method: 'POST',
      headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_proname: n }),
    });
    assert.equal(r.status, 200, `_audit_function_source falhou para ${n}`);
    const linhas = await r.json();
    assert.equal(linhas.length, 1, `${n}: esperava 1 assinatura viva, vieram ${linhas.length}`);
    const cap = latestFunctionCapture(ROOT, n);
    assert.equal(md5(normalizeBody(linhas[0].prosrc)), md5(normalizeBody(cap.body)),
      `${n}: corpo vivo diverge da captura ${cap.version}`);
  }
});
