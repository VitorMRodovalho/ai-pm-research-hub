/**
 * Contract: #2393, fatia 3 (ADR-0134, decisão do GP em 02/11/2026) — marcador de piloto por vaga.
 *
 * `vep_opportunities.evaluation_track` separa a avaliação da importação: `is_active` segue governando só a
 * importação do VEP, e uma vaga `line_pilot` fica fora da avaliação geral do comitê do ciclo (ADR-0134 §3,
 * §4 e P2). Toda a avaliação geral se apoia em `cycle_id`, sem atribuição, então o marcador tem de valer em
 * cada leitor e em cada automação que leva uma candidatura até o comitê.
 *
 * Camadas:
 *   S  estática, na captura vigente:
 *      - a coluna, o CHECK e o helper `_na_avaliacao_geral(uuid)`, fechado para todo cliente;
 *      - cada uma das 14 funções chama o helper DENTRO do bloco que decide (a fila, a recusa, o WHERE da
 *        automação), não solto no corpo;
 *      - inventário simétrico: as funções que chamam o helper são exatamente as auditadas (as 14 da fila e das
 *        automações, e o trigger do token da D4).
 *   L  viva: anon recebe 42501 no helper, e a coluna existe.
 * Quem vê o quê por persona é a verificação do pacote (impersonação, com vaga sintética line_pilot).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { parseMigration } from '../helpers/rpc-body-drift-parser.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const HELPER = '_na_avaliacao_geral';
const RECUSA = "IF NOT public\\._na_avaliacao_geral\\(p_application_id\\) THEN RAISE EXCEPTION 'Unauthorized: pilot_track[^']*' USING ERRCODE = 'insufficient_privilege'; END IF;";

function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}

const conta = (s, re) => (s.match(re) || []).length;

// ─── S: coluna e helper ────────────────────────────────────────────────────────────

test('#2393c S: a coluna evaluation_track nasce com default general e só aceita general e line_pilot', () => {
  const { file } = captura(HELPER);
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, /ALTER TABLE public\.vep_opportunities ADD COLUMN IF NOT EXISTS evaluation_track text NOT NULL DEFAULT 'general';/,
    'a coluna não nasce NOT NULL com default general');
  assert.match(sql, /CHECK \(evaluation_track IN \('general', 'line_pilot'\)\);/, 'o CHECK da trilha não está na forma esperada');
});

test('#2393c S: o helper diz "não é de vaga line_pilot", pela vaga e não pelo ciclo', () => {
  const { corpo } = captura(HELPER);
  assert.match(corpo,
    /RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS \$function\$ SELECT NOT EXISTS \( SELECT 1 FROM public\.selection_applications sa JOIN public\.vep_opportunities vo ON vo\.opportunity_id = sa\.vep_opportunity_id WHERE sa\.id = p_application_id AND vo\.evaluation_track = 'line_pilot' \); \$function\$/,
    'o helper mudou a regra, os atributos ou passou a casar pelo ciclo');
});

// GRANT depois do REVOKE, no mesmo arquivo ou num posterior, também devolve o acesso.
function semGrantDepois(file, funcao, papeis) {
  const re = new RegExp(`GRANT[^;]*ON FUNCTION public\\.${funcao}\\b[^;]*\\b(${papeis})\\b`, 'i');
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql') && x >= file)) {
    assert.doesNotMatch(maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')), re, `${f}: devolve ${funcao} a ${papeis}`);
  }
}

test('#2393c S: nenhum cliente executa o helper', () => {
  const { file } = captura(HELPER);
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, /REVOKE ALL ON FUNCTION public\._na_avaliacao_geral\(uuid\) FROM PUBLIC, anon, authenticated;/,
    'a migration não revoga o helper de PUBLIC, anon e authenticated');
  semGrantDepois(file, HELPER, 'anon|PUBLIC|authenticated');
});

// ─── S: fila e avaliação do comitê ─────────────────────────────────────────────────

test('#2393c S: o painel só mostra a linha piloto à gestão, marcada pela trilha', () => {
  const { corpo } = captura('get_selection_dashboard');
  assert.equal(conta(corpo, /v_ve_piloto :=/g), 1, 'v_ve_piloto é atribuído mais de uma vez');
  const atrib = corpo.search(/v_ve_piloto := public\.can_by_member\(v_caller_id, 'manage_platform'\);/);
  assert.ok(atrib !== -1, 'v_ve_piloto não vem de manage_platform');
  assert.ok(atrib > corpo.indexOf("'recused_conflict_of_interest'"), 'v_ve_piloto é decidido antes da recusa por conflito');
  const lista = corpo.search(/FROM public\.selection_applications sa WHERE sa\.cycle_id = v_cycle_id AND \(v_ve_piloto OR public\._na_avaliacao_geral\(sa\.id\)\) \) a /);
  assert.ok(lista !== -1, 'a lista do painel não tira a linha piloto de quem não é da gestão');
  assert.ok(atrib < lista, 'v_ve_piloto é decidido depois da lista');
});

test('#2393c S: cada linha do painel leva a trilha, e a posição objetiva é separada por trilha', () => {
  const { corpo } = captura('get_selection_dashboard');
  assert.match(corpo, /\|\| jsonb_build_object\('evaluation_track', CASE WHEN public\._na_avaliacao_geral\(a\.id\) THEN 'general' ELSE 'line_pilot' END\) \|\| jsonb_build_object\('vep_opportunity_id', a\.vep_opportunity_id\) ORDER BY/,
    'a linha não leva evaluation_track antes da chave da vaga');
  assert.match(corpo, /PARTITION BY sa\.role_applied, public\._na_avaliacao_geral\(sa\.id\) ORDER BY sa\.objective_score_avg/,
    'a posição objetiva mistura piloto e avaliação geral');
  assert.match(corpo, /'line_pilot_total', CASE WHEN v_ve_piloto THEN \(SELECT count\(\*\) FROM public\.selection_applications WHERE cycle_id = v_cycle_id AND NOT public\._na_avaliacao_geral\(id\)\) END/,
    'a contagem do piloto não é só da gestão');
});

test('#2393c S: a fila do avaliador tira o piloto da fila, do concluído e do total', () => {
  const { corpo } = captura('get_my_pending_evaluations');
  assert.match(corpo, /INTO v_pending FROM public\.selection_applications sa WHERE sa\.cycle_id = v_cycle\.id AND public\._na_avaliacao_geral\(sa\.id\) AND sa\.status <> ALL \(v_terminal\)/,
    'a fila pendente não tira o piloto');
  assert.match(corpo, /INTO v_completed_count FROM public\.selection_applications sa JOIN public\.selection_evaluations se ON se\.application_id = sa\.id WHERE sa\.cycle_id = v_cycle\.id AND public\._na_avaliacao_geral\(sa\.id\) AND /,
    'o concluído não tira o piloto');
  assert.match(corpo, /SELECT count\(\*\) INTO v_total_count FROM public\.selection_applications WHERE cycle_id = v_cycle\.id AND public\._na_avaliacao_geral\(id\) AND status <> ALL \(v_terminal\);/,
    'o total não tira o piloto');
});

test('#2393c S: as atribuições do comitê tiram o piloto', () => {
  const { corpo } = captura('get_my_committee_assignments');
  assert.match(corpo, /WHERE a\.cycle_id = ANY\(v_committee_cycles\) AND a\.status NOT IN \('withdrawn','cancelled'\) AND public\._na_avaliacao_geral\(a\.id\) \) r;/,
    'as atribuições não tiram o piloto');
});

test('#2393c S (D1): o formulário recusa o piloto para todos, depois do portão e antes do registro de acesso', () => {
  const { corpo } = captura('get_evaluation_form');
  assert.match(corpo, new RegExp(`RAISE EXCEPTION 'Unauthorized: not a committee member'; END IF; ${RECUSA} PERFORM public\\._log_application_pii_access\\(`),
    'a recusa do piloto não está entre o portão do comitê e o registro de acesso');
});

test('#2393c S (D1): o envio de avaliação recusa o piloto para todos, antes de gravar', () => {
  const { corpo } = captura('submit_evaluation');
  const m = corpo.match(new RegExp(`RAISE EXCEPTION 'Unauthorized: observer role does not evaluate' USING ERRCODE = 'insufficient_privilege'; END IF; ${RECUSA} IF EXISTS \\(`));
  assert.ok(m, 'a recusa do piloto não está logo depois da recusa do observador');
  const grava = corpo.search(/INSERT INTO public\.selection_evaluations\b/);
  assert.ok(grava === -1 || m.index < grava, 'a recusa do piloto vem depois da gravação');
});

// ─── S: automações ──────────────────────────────────────────────────────────────────

test('#2393c S: a revisão por pares não tem elegível para o piloto', () => {
  const { corpo } = captura('_get_peer_review_eligibility');
  assert.match(corpo, /RAISE EXCEPTION 'Application not found: %', p_application_id; END IF; IF NOT public\._na_avaliacao_geral\(p_application_id\) THEN RETURN; END IF; RETURN QUERY/,
    'a elegibilidade não sai vazia para o piloto antes do RETURN QUERY');
});

test('#2393c S: o cron do convite à entrevista geral não pega o piloto', () => {
  const { corpo } = captura('_selection_cutoff_pending_cron');
  assert.match(corpo, /AND c\.status = 'open' AND public\._na_avaliacao_geral\(a\.id\) ORDER BY a\.objective_score_avg DESC LIMIT 50 LOOP/,
    'a seleção do cron não tira o piloto');
});

test('#2393c S: o convite à entrevista geral recusa o piloto por retorno, antes de emitir', () => {
  const { corpo } = captura('notify_selection_cutoff_approved');
  const m = corpo.match(/IF NOT public\._na_avaliacao_geral\(p_application_id\) THEN RETURN jsonb_build_object\( 'success', false, 'application_id', p_application_id, 'email_sent', false, 'reason', 'pilot_track' \); END IF; IF v_app\.cutoff_approved_email_sent_at IS NOT NULL THEN/);
  assert.ok(m, 'a recusa do piloto não vem antes da idempotência, ou não é por retorno');
  assert.ok(m.index < corpo.indexOf('_dispatch_interview_booking_link('), 'a recusa vem depois da emissão do token');
});

test('#2393c S (D2): o corte PERT tira o piloto da população e do carimbo', () => {
  const { corpo } = captura('_compute_pert_cutoff_core');
  assert.match(corpo, /WHERE sa\.cycle_id = p_cycle_id AND sa\.role_applied = p_role AND public\._na_avaliacao_geral\(sa\.id\) AND \(NOT p_filter_active_only/,
    'a população do corte inclui o piloto');
  const updates = conta(corpo, /UPDATE public\.selection_applications SET/g);
  assert.equal(updates, 3, `o corte tem ${updates} carimbos, e o guard espera 3`);
  assert.equal(conta(corpo, /WHERE cycle_id = p_cycle_id AND role_applied = p_role AND public\._na_avaliacao_geral\(id\);/g), 3,
    'algum carimbo do corte cai no piloto');
});

test('#2393c S: a mudança automática de status não move o piloto, e a mediana é só da avaliação geral', () => {
  const { corpo } = captura('recompute_application_status');
  assert.match(corpo, /WHERE objective_score_avg IS NOT NULL AND role_applied = 'researcher' AND public\._na_avaliacao_geral\(id\) GROUP BY cycle_id/,
    'a mediana do ciclo inclui o piloto');
  assert.match(corpo, /AND \(p_cycle_id IS NULL OR a\.cycle_id = p_cycle_id\) AND public\._na_avaliacao_geral\(a\.id\) \), canon AS/,
    'a base das transições inclui o piloto');
});

test('#2393c S (D2): calculate_rankings tira o piloto do ranking, da mediana, do p90 e da lista', () => {
  const { corpo } = captura('calculate_rankings');
  assert.match(corpo, /WITH scored AS \( SELECT id, chapter, final_score FROM public\.selection_applications WHERE cycle_id = p_cycle_id AND final_score IS NOT NULL AND status NOT IN \('withdrawn', 'cancelled'\) AND public\._na_avaliacao_geral\(id\) \)/, 'o ranking inclui o piloto');
  assert.match(corpo, /INTO v_median FROM public\.selection_applications WHERE cycle_id = p_cycle_id AND final_score IS NOT NULL AND status NOT IN \('withdrawn', 'cancelled'\) AND public\._na_avaliacao_geral\(id\);/, 'a mediana inclui o piloto');
  assert.match(corpo, /INTO v_p90 FROM public\.selection_applications WHERE cycle_id = p_cycle_id AND objective_score_avg IS NOT NULL AND role_applied = 'researcher' AND status NOT IN \('withdrawn', 'cancelled'\) AND public\._na_avaliacao_geral\(id\);/, 'o p90 inclui o piloto');
  assert.match(corpo, /INTO v_ranked FROM public\.selection_applications a WHERE a\.cycle_id = p_cycle_id AND a\.status NOT IN \('withdrawn', 'cancelled'\) AND public\._na_avaliacao_geral\(a\.id\);/, 'a lista inclui o piloto');
});

test('#2393c S (D2): recalculate_cycle_rankings tira o piloto das duas trilhas', () => {
  const { corpo } = captura('recalculate_cycle_rankings');
  assert.match(corpo, /AND a\.research_score IS NOT NULL AND a\.status NOT IN \('withdrawn','rejected','cancelled'\) AND public\._na_avaliacao_geral\(a\.id\) AND NOT EXISTS/, 'a trilha de pesquisador inclui o piloto');
  assert.match(corpo, /AND a\.leader_score IS NOT NULL AND a\.status NOT IN \('withdrawn','rejected','cancelled'\) AND public\._na_avaliacao_geral\(a\.id\) \) UPDATE selection_applications a SET rank_leader/, 'a trilha de líder inclui o piloto');
});

test('#2393c S (D2): get_selection_rankings tira o piloto das duas trilhas', () => {
  const { corpo } = captura('get_selection_rankings');
  assert.match(corpo, /AND a\.research_score IS NOT NULL AND a\.status NOT IN \('withdrawn','rejected','cancelled','merged'\) AND public\._na_avaliacao_geral\(a\.id\) AND NOT EXISTS/, 'a trilha de pesquisador inclui o piloto');
  assert.match(corpo, /AND a\.leader_score IS NOT NULL AND a\.status NOT IN \('withdrawn','rejected','cancelled','merged'\) AND public\._na_avaliacao_geral\(a\.id\) \) SELECT coalesce\(jsonb_agg/, 'a trilha de líder inclui o piloto');
});

test('#2393c S: o piloto não vira aviso de funil travado', () => {
  const { corpo } = captura('detect_stuck_selection_funnel');
  assert.match(corpo, /CROSS JOIN public\.members m WHERE m\.operational_role = 'manager' AND public\._na_avaliacao_geral\(s\.application_id\) \),/,
    'os avisos de funil travado incluem o piloto');
});

// ─── S: inventário simétrico ────────────────────────────────────────────────────────

const CHAMADORES = [
  'get_selection_dashboard', 'get_my_pending_evaluations', 'get_my_committee_assignments', 'get_evaluation_form',
  'submit_evaluation', '_get_peer_review_eligibility', '_selection_cutoff_pending_cron',
  'notify_selection_cutoff_approved', '_compute_pert_cutoff_core', 'recompute_application_status',
  'calculate_rankings', 'recalculate_cycle_rankings', 'get_selection_rankings', 'detect_stuck_selection_funnel',
  // #2393 fatia 3, D4: o trigger que tira o vídeo do token de candidatura de vaga piloto.
  '_token_de_candidatura_sem_video_no_piloto',
  // #2393 A1: as travas do piloto na decisão, na entrevista e no token de agendamento (guard 2393h).
  'admin_update_application', 'schedule_interview', '_issue_interview_booking_token_core',
  // #2393 A3 e A4: o link do portal do piloto vale o processo, e o líder não recebe o e-mail (guard 2393i).
  '_token_do_piloto_vale_o_processo', 'get_opening_application',
].sort();

test('#2393c S: as funções que chamam o helper são exatamente as auditadas', () => {
  const ultima = new Map();
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()) {
    for (const b of parseMigration(f, readFileSync(join(MIGRATIONS, f), 'utf8'))) ultima.set(`${b.name}@${b.args}`, b);
  }
  const achadas = [...new Set([...ultima.values()]
    .filter((b) => b.name !== HELPER && /\b_na_avaliacao_geral\s*\(/.test(maskLineComments(b.body)))
    .map((b) => b.name))].sort();
  assert.deepEqual(achadas, CHAMADORES, 'o conjunto de chamadores do marcador mudou: audite a função nova ou a que saiu');
});

// ─── L: vivo ──────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

test('#2393c L: anon recebe 42501 no helper (e não 404, que seria a função ausente), e a coluna existe',
  { skip: URL_BASE && KEY && ANON ? false : 'sem credencial de banco' }, async () => {
    const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/${HELPER}`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_application_id: '00000000-0000-0000-0000-000000000000' }),
    });
    const texto = await r.text();
    assert.ok([401, 403].includes(r.status), `anon recebeu ${r.status}: ${texto.slice(0, 160)}`);
    assert.match(texto, /"code":"42501"/, `a recusa a anon não é falta de permissão: ${texto.slice(0, 160)}`);
    const c = await dbFetch(`${URL_BASE}/rest/v1/vep_opportunities?select=evaluation_track&limit=1`, {
      headers: { apikey: KEY, Authorization: `Bearer ${KEY}` },
    });
    assert.equal(c.status, 200, `a leitura de evaluation_track devolveu ${c.status}: ${(await c.text()).slice(0, 160)}`);
  });
