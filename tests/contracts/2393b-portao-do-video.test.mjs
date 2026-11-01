/**
 * Contract: ADR-0134 §4 e §6 — portão provisório do vídeo do candidato (decisão do GP, 01/11/2026).
 *
 * `get_application_video_screenings` devolve link, arquivo e transcrição dos vídeos de uma
 * candidatura. Até existir a leitura por atribuição, só a vê quem tem `manage_platform` ou o assento
 * `lead`/`evaluator` do comitê do ciclo da candidatura. Antes bastava `view_internal_analytics`, que
 * patrocínio, ponto de contato de capítulo e curadoria também têm.
 *
 * Camadas:
 *   S  estática, na captura vigente:
 *      - membro ativo; candidatura da organização do caller e não anonimizada; o portão exato
 *        (manage_platform OU assento lead/evaluator NO CICLO da candidatura), amarrado à recusa; a
 *        INVERSA (nada de view_internal_analytics, nada de observer);
 *      - conflito de interesse, depois o registro estrito, depois a leitura dos vídeos, nessa ordem;
 *      - as chaves de cada vídeo são as de antes menos `failure_reason`, que a aba Vídeos não usa e
 *        pode trazer texto interno de erro;
 *      - VOLATILE, SECURITY DEFINER, search_path vazio, anon e PUBLIC sem EXECUTE.
 *   L  viva: anon recebe 42501 (e não 404).
 * Quem vê e quem é recusado por persona é a verificação do pacote (impersonação).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const NOME = 'get_application_video_screenings';

const CHAVES_DO_VIDEO = [
  'id', 'pillar', 'question_index', 'question_text', 'status', 'storage_provider', 'drive_folder_id',
  'drive_file_id', 'drive_file_name', 'youtube_url', 'duration_seconds', 'file_size_bytes', 'mime_type',
  'transcription', 'transcription_provider', 'transcription_model_version', 'transcription_at',
  'transcription_confidence', 'retry_count', 'uploaded_at', 'created_at', 'updated_at',
];

function captura() {
  const cap = latestFunctionCapture(ROOT, NOME);
  assert.ok(cap, `${NOME}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}

test('#2393b S: o vídeo é de manage_platform ou do assento lead/evaluator do ciclo da candidatura', () => {
  const { corpo } = captura();
  assert.match(corpo,
    /SELECT m\.id INTO v_caller_id FROM public\.members m WHERE m\.auth_id = auth\.uid\(\) AND m\.is_active = true; IF v_caller_id IS NULL THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; SELECT sa\.cycle_id INTO v_cycle_id FROM public\.selection_applications sa WHERE sa\.id = p_application_id AND sa\.organization_id = public\.auth_org\(\) AND sa\.anonymized_at IS NULL; IF v_cycle_id IS NULL THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; IF NOT \( public\.can_by_member\(v_caller_id, 'manage_platform'\) OR EXISTS \( SELECT 1 FROM public\.selection_committee sc WHERE sc\.cycle_id = v_cycle_id AND sc\.member_id = v_caller_id AND sc\.role IN \('lead', 'evaluator'\) \) \) THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF;/,
    'a sequência membro ativo → candidatura da organização e não anonimizada → portão manage_platform ou assento lead/evaluator do ciclo foi quebrada');
});

test('#2393b S (INVERSA): o vídeo não volta para view_internal_analytics nem para o observador', () => {
  const { corpo } = captura();
  assert.doesNotMatch(corpo, /view_internal_analytics/, 'o portão voltou a aceitar view_internal_analytics');
  assert.doesNotMatch(corpo, /'observer'/, 'o assento observer entrou no portão');
});

test('#2393b S: conflito de interesse, depois o registro estrito, depois os vídeos', () => {
  const { corpo } = captura();
  assert.match(corpo,
    /IF public\.selection_coi_recused\(v_caller_id, v_cycle_id\) THEN RETURN jsonb_build_object\('error', 'recused_conflict_of_interest',.*?\); END IF; PERFORM public\._log_opening_application_access\( p_application_id, v_caller_id, ARRAY\[[^\]]+\], 'get_application_video_screenings' \); SELECT jsonb_build_object\(/,
    'a ordem conflito de interesse → registro estrito → leitura dos vídeos foi quebrada');
  assert.doesNotMatch(corpo, /_log_application_pii_access\s*\(/, 'usa o registro fail-soft, que deixa a leitura sair sem registro');
});

test('#2393b S: cada vídeo sai com as chaves de antes, menos failure_reason', () => {
  const { corpo } = captura();
  const i = corpo.indexOf("'rows', COALESCE(jsonb_agg(jsonb_build_object(");
  assert.ok(i > 0, 'o agregado de vídeos sumiu');
  const bloco = corpo.slice(i, corpo.indexOf(') ORDER BY v.pillar', i));
  const chaves = [...bloco.matchAll(/'([a-z_]+)', v\./g)].map((m) => m[1]);
  assert.deepEqual(chaves, CHAVES_DO_VIDEO,
    'as chaves de cada vídeo mudaram: a aba Vídeos depende delas, e failure_reason não sai');
});

test('#2393b S: VOLATILE, SECURITY DEFINER, search_path vazio, e anon e PUBLIC não executam', () => {
  const { file, corpo } = captura();
  assert.match(corpo, /RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS/,
    'perdeu VOLATILE, SECURITY DEFINER ou o search_path vazio');
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.get_application_video_screenings\(uuid\) FROM PUBLIC, anon;/,
    'a migration não revoga PUBLIC e anon');
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.get_application_video_screenings\(uuid\) TO authenticated;/,
    'a migration não concede a authenticated');
  // a própria migration e as posteriores: um GRANT depois do REVOKE, no mesmo arquivo, também devolve o acesso
  const posteriores = readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql') && x >= file);
  for (const f of posteriores) {
    const outro = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8'));
    assert.doesNotMatch(outro, /GRANT[^;]*ON FUNCTION public\.get_application_video_screenings\b[^;]*\b(anon|PUBLIC)\b/i,
      `${f}: devolve o vídeo a anon ou PUBLIC`);
  }
});

test('#2393b S (tela): a recusa vira aviso na aba Vídeos, antes do ramo de erro, nos 3 idiomas', () => {
  const tela = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8')).replace(/\s+/g, ' ');
  const i = tela.indexOf('async function loadVideoScreenings(');
  assert.ok(i > 0, 'loadVideoScreenings sumiu da tela');
  const funcao = tela.slice(i, tela.indexOf('async function loadPmiProfile(', i));
  assert.match(funcao,
    /if \(error\) throw error; if \(data\?\.error === 'Unauthorized' \|\| data\?\.error === 'recused_conflict_of_interest'\) \{ const notice = data\.error === 'Unauthorized' \? T\.modal\.videosRestricted : T\.modal\.videosRecused; container\.innerHTML = `[^`]*\$\{esc\(notice\)\}[^`]*`; return; \} if \(data\?\.error\) throw new Error\(data\.error\);/,
    'a recusa do portão voltou a cair no ramo de erro (ou o aviso não é o da recusa)');
  for (const dic of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = readFileSync(resolve(ROOT, `src/i18n/${dic}.ts`), 'utf8');
    for (const chave of ['videosRestricted', 'videosRecused']) {
      assert.match(src, new RegExp(`'admin\\.selection\\.modal\\.${chave}': '[^']{20,}'`), `${dic}: falta ${chave}`);
    }
  }
});

// ─── L: vivo ──────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

test('#2393b L: anon recebe 42501 (e não 404, que seria a função ausente)',
  { skip: URL_BASE && KEY && ANON ? false : 'sem credencial de banco' }, async () => {
    const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/${NOME}`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_application_id: '00000000-0000-0000-0000-000000000000' }),
    });
    const texto = await r.text();
    assert.ok([401, 403].includes(r.status), `anon recebeu ${r.status}: ${texto.slice(0, 160)}`);
    assert.match(texto, /"code":"42501"/, `a recusa a anon não é falta de permissão: ${texto.slice(0, 160)}`);
  });
