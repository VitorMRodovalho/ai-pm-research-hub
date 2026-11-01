/**
 * Contract: #2905 (decisão do GP, 01/11/2026) — a sugestão de IA de tipo `video` só sai para quem passa no
 * portão do vídeo (ADR-0134).
 *
 * `selection_evaluation_ai_suggestions` guarda, no tipo `video`, o resumo, as notas por critério e a nota que
 * a IA tirou da transcrição. `get_ai_suggestion` e `list_ai_suggestions` aceitavam qualquer assento do comitê
 * do ciclo, observador incluído, e o portão do vídeo os recusa. A sugestão existente fica MANTIDA e
 * ESCONDIDA (nada é apagado).
 *
 * Camadas:
 *   S  estática, na captura vigente:
 *      - o portão mora em `_passa_no_portao_do_video(uuid)`, na ordem: membro ativo → candidatura da
 *        organização, não anonimizada → manage_platform OU assento lead/evaluator do ciclo → sem conflito de
 *        interesse; e a INVERSA (nada de view_internal_analytics, nada de observer);
 *      - o helper e `get_application_video_screenings` dizem a MESMA coisa, condição por condição;
 *      - `get_ai_suggestion` passa o tipo `video` pelo helper ANTES da recusa e da leitura;
 *      - `list_ai_suggestions` tira as linhas `video` de quem não passa, no WHERE da única leitura;
 *      - o helper não é executável por nenhum cliente; as duas leituras não são executáveis por anon e PUBLIC.
 *   L  viva: anon recebe 42501 nas duas leituras e no helper.
 * Quem vê e quem é recusado por persona é a verificação do pacote (impersonação).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const HELPER = '_passa_no_portao_do_video';

function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}

// As quatro condições do portão, recortadas do corpo que decide. Cada uma devolve o texto da condição, para
// comparar o helper com a função do vídeo.
function condicoes(corpo, nome) {
  const membro = corpo.match(/SELECT m\.id INTO v_caller_id FROM public\.members m WHERE (m\.auth_id = auth\.uid\(\) AND m\.is_active = true); IF v_caller_id IS NULL THEN RETURN /);
  const candidatura = corpo.match(/SELECT sa\.cycle_id INTO v_cycle_id FROM public\.selection_applications sa WHERE (sa\.id = p_application_id[^;]*); IF v_cycle_id IS NULL THEN RETURN /);
  const portao = corpo.match(/IF NOT \( (public\.can_by_member\(v_caller_id, 'manage_platform'\) OR EXISTS \( SELECT 1 FROM public\.selection_committee sc WHERE [^)]*\) \)) \) THEN RETURN /);
  assert.ok(membro && candidatura && portao, `${nome}: o portão do vídeo não está na forma esperada`);
  return { membro: membro[1], candidatura: candidatura[1], portao: portao[1] };
}

test('#2905 S: o portão do vídeo mora no helper, na ordem certa e fechado', () => {
  const { corpo } = captura(HELPER);
  assert.match(corpo,
    /SELECT m\.id INTO v_caller_id FROM public\.members m WHERE m\.auth_id = auth\.uid\(\) AND m\.is_active = true; IF v_caller_id IS NULL THEN RETURN false; END IF; SELECT sa\.cycle_id INTO v_cycle_id FROM public\.selection_applications sa WHERE sa\.id = p_application_id AND sa\.organization_id = public\.auth_org\(\) AND sa\.anonymized_at IS NULL; IF v_cycle_id IS NULL THEN RETURN false; END IF; IF NOT \( public\.can_by_member\(v_caller_id, 'manage_platform'\) OR EXISTS \( SELECT 1 FROM public\.selection_committee sc WHERE sc\.cycle_id = v_cycle_id AND sc\.member_id = v_caller_id AND sc\.role IN \('lead', 'evaluator'\) \) \) THEN RETURN false; END IF; RETURN NOT public\.selection_coi_recused\(v_caller_id, v_cycle_id\); END;/,
    'a sequência membro ativo → candidatura → manage_platform ou lead/evaluator do ciclo → conflito de interesse foi quebrada');
  assert.equal((corpo.match(/RETURN true/g) || []).length, 0, 'o helper tem um RETURN true que pula o portão');
});

test('#2905 S (INVERSA): o helper não aceita view_internal_analytics nem o observador', () => {
  const { corpo } = captura(HELPER);
  assert.doesNotMatch(corpo, /view_internal_analytics/, 'o helper aceita view_internal_analytics');
  assert.doesNotMatch(corpo, /'observer'/, 'o assento observer entrou no helper');
});

test('#2905 S: o helper e get_application_video_screenings dizem a mesma coisa', () => {
  const helper = captura(HELPER).corpo;
  const video = captura('get_application_video_screenings').corpo;
  assert.deepEqual(condicoes(helper, HELPER), condicoes(video, 'get_application_video_screenings'),
    'o portão do helper divergiu do portão do vídeo');
  assert.match(helper, /RETURN NOT public\.selection_coi_recused\(v_caller_id, v_cycle_id\); END;/,
    'o helper não recusa por conflito de interesse');
  assert.match(video, /IF public\.selection_coi_recused\(v_caller_id, v_cycle_id\) THEN RETURN jsonb_build_object\('error', 'recused_conflict_of_interest'/,
    'o vídeo não recusa por conflito de interesse');
});

test('#2905 S: get_ai_suggestion passa o tipo video pelo portão antes da recusa e da leitura', () => {
  const { corpo } = captura('get_ai_suggestion');
  assert.match(corpo,
    /\) INTO v_authorized; IF v_authorized AND p_evaluation_type = 'video' THEN v_authorized := public\._passa_no_portao_do_video\(p_application_id\); END IF; IF NOT v_authorized THEN RAISE EXCEPTION 'Not authorized to read AI suggestions for this application' USING ERRCODE = 'insufficient_privilege'; END IF; SELECT jsonb_build_object\(/,
    'o tipo video não passa pelo portão do vídeo antes da leitura');
  assert.equal((corpo.match(/v_authorized :=/g) || []).length, 1, 'v_authorized é reatribuído fora do portão do vídeo');
  assert.equal((corpo.match(/FROM selection_evaluation_ai_suggestions/g) || []).length, 1, 'há outra leitura das sugestões');
});

test('#2905 S: list_ai_suggestions tira o tipo video de quem não passa no portão', () => {
  const { corpo } = captura('list_ai_suggestions');
  assert.match(corpo,
    /RETURN jsonb_build_object\('error', 'access_denied', 'required', 'committee or manage_member'\); END IF; v_ve_video := public\._passa_no_portao_do_video\(p_application_id\);/,
    'o portão do vídeo não é avaliado logo depois do acesso à função');
  assert.match(corpo,
    /FROM public\.selection_evaluation_ai_suggestions s WHERE s\.application_id = p_application_id AND \(p_evaluation_type IS NULL OR s\.evaluation_type = p_evaluation_type\) AND \(s\.evaluation_type IS DISTINCT FROM 'video' OR v_ve_video\) AND /,
    'a leitura não tira o tipo video de quem não passa');
  assert.equal((corpo.match(/v_ve_video :=/g) || []).length, 1, 'v_ve_video é reatribuído fora do portão do vídeo');
  assert.equal((corpo.match(/FROM public\.selection_evaluation_ai_suggestions/g) || []).length, 1, 'há outra leitura das sugestões');
});

// GRANT depois do REVOKE, no mesmo arquivo ou num posterior, também devolve o acesso.
function semGrantDepois(file, funcao, papeis) {
  const re = new RegExp(`GRANT[^;]*ON FUNCTION public\\.${funcao}\\b[^;]*\\b(${papeis})\\b`, 'i');
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql') && x >= file)) {
    assert.doesNotMatch(maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')), re, `${f}: devolve ${funcao} a ${papeis}`);
  }
}

test('#2905 S: o helper é STABLE, SECURITY DEFINER, search_path vazio, e nenhum cliente o executa', () => {
  const { file, corpo } = captura(HELPER);
  assert.match(corpo, /RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS/,
    'o helper perdeu STABLE, SECURITY DEFINER ou o search_path vazio');
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, /REVOKE ALL ON FUNCTION public\._passa_no_portao_do_video\(uuid\) FROM PUBLIC, anon, authenticated;/,
    'a migration não revoga o helper de PUBLIC, anon e authenticated');
  semGrantDepois(file, HELPER, 'anon|PUBLIC|authenticated');
});

test('#2905 S: as duas leituras de sugestão não são executáveis por anon nem PUBLIC', () => {
  for (const [nome, assinatura] of [['get_ai_suggestion', 'uuid, text'], ['list_ai_suggestions', 'uuid, text, boolean']]) {
    const { file } = captura(nome);
    const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
    const sig = assinatura.replace(/[(),]/g, (c) => `\\${c}`);
    assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.${nome}\\(${sig}\\) FROM PUBLIC, anon;`), `${nome}: a migration não revoga PUBLIC e anon`);
    assert.match(sql, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${nome}\\(${sig}\\) TO authenticated;`), `${nome}: a migration não concede a authenticated`);
    semGrantDepois(file, nome, 'anon|PUBLIC');
  }
});

// ─── L: vivo ──────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

test('#2905 L: anon recebe 42501 nas duas leituras e no helper (e não 404, que seria a função ausente)',
  { skip: URL_BASE && KEY && ANON ? false : 'sem credencial de banco' }, async () => {
    const zero = '00000000-0000-0000-0000-000000000000';
    for (const [nome, corpo] of [
      ['get_ai_suggestion', { p_application_id: zero, p_evaluation_type: 'video' }],
      ['list_ai_suggestions', { p_application_id: zero, p_evaluation_type: null, p_only_pending: false }],
      [HELPER, { p_application_id: zero }],
    ]) {
      const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/${nome}`, {
        method: 'POST',
        headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(corpo),
      });
      const texto = await r.text();
      assert.ok([401, 403].includes(r.status), `${nome}: anon recebeu ${r.status}: ${texto.slice(0, 160)}`);
      assert.match(texto, /"code":"42501"/, `${nome}: a recusa a anon não é falta de permissão: ${texto.slice(0, 160)}`);
    }
  });
