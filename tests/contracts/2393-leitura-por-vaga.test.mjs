/**
 * Contract: #2393, ADR-0134 §6, fatia 2 — leitura por vaga.
 *
 * `list_opening_applications` e `get_opening_application` dão a quem lidera a iniciativa de uma vaga
 * de linha a leitura das candidaturas dessa vaga, pela ação `view_opening_applications` (escopo
 * `initiative`). O que volta é o que o GP decidiu em 01/11/2026 (D2 (a)): dados do candidato,
 * respostas, status e etapa, sem nota de avaliador e sem IA.
 *
 * Camadas:
 *   S  estática, na captura vigente de cada função:
 *      - cada passo do portão amarrado à recusa que ele produz, na ordem: membro e organização; vaga
 *        geral recusada antes da autoridade; autoridade com a iniciativa da vaga e portão de
 *        iniciativa confidencial; conflito de interesse; registro OBRIGATÓRIO antes do retorno;
 *      - até a autoridade, toda recusa é 'Unauthorized' (sem oráculo de existência);
 *      - o registro estrito não tem tratador de exceção e grava mesmo sem e-mail;
 *      - as chaves do objeto devolvido são EXATAMENTE as decididas (a inversa da D2: nenhuma nota,
 *        avaliação ou IA);
 *      - VOLATILE, SECURITY DEFINER, search_path vazio, anon e PUBLIC sem EXECUTE;
 *      - as sementes da ação são só os 4 pares de liderança, e só em `initiative`;
 *      - o registro grava a candidatura lida (`target_application_id`), com FK ON DELETE SET NULL.
 *   L  viva: anon recebe 42501 nas duas (e não 404, que seria função ausente); as sementes vivas
 *      são as da migration; a coluna do registro existe.
 * O corpo vivo igual à captura é o Phase C de `rpc-migration-coverage`. A recusa por persona
 * (impersonação) é a verificação do pacote, que não cabe num teste sem SET ROLE.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');

const ACAO = 'view_opening_applications';
const SEMENTES = [
  'committee_member|leader|initiative',
  'study_group_owner|leader|initiative',
  'study_group_owner|owner|initiative',
  'volunteer|leader|initiative',
];

const CHAVES_LISTA = [
  'application_id', 'opportunity_id', 'opening_title', 'initiative_id', 'applicant_name', 'chapter',
  'role_applied', 'status', 'interview_status', 'application_date',
];
const CHAVES_DETALHE = [
  'application_id', 'opportunity_id', 'opening_title', 'initiative_id', 'cycle_code', 'essay_questions',
  'applicant_name', 'email', 'chapter', 'chapter_affiliation', 'applicant_city', 'state', 'country',
  'linkedin_url', 'credly_url', 'role_applied',
  'status', 'interview_status', 'application_date', 'certifications', 'academic_background',
  'motivation_letter', 'reason_for_applying', 'proposed_theme', 'areas_of_interest',
  'availability_declared', 'leadership_experience', 'non_pmi_experience',
];

/** Captura vigente, sem comentário de linha e com espaço colapsado. */
function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}

/** O trecho entre `de` e a primeira ocorrência de `ate` depois dele. */
function recorte(corpo, de, ate) {
  const i = corpo.indexOf(de);
  assert.ok(i >= 0, `recorte: início ausente: ${de}`);
  const j = corpo.indexOf(ate, i + de.length);
  assert.ok(j > i, `recorte: fim ausente depois de ${de}: ${ate}`);
  return corpo.slice(i, j + ate.length);
}

const chavesDe = (bloco, alias) =>
  [...bloco.matchAll(new RegExp(`'([a-z_]+)', (?:${alias}\\.|v_perguntas\\b)`, 'g'))].map((m) => m[1]);

const PORTAO_MEMBRO =
  /SELECT m\.id INTO v_caller_id FROM public\.members m WHERE m\.auth_id = auth\.uid\(\) AND m\.is_active = true; v_org := public\.auth_org\(\); IF v_caller_id IS NULL OR v_org IS NULL THEN RETURN jsonb_build_object\('error', 'Unauthorized'\);/;

const PROIBIDO = /\b(\w*score\w*|rank_\w+|\w*pert_\w+|ai_\w+|last_briefing\w*|cv_extracted_text|selection_evaluations|\w*evaluation\w*|feedback|phone|gender|age_band|profile_\w+|pmi_id|tags)\b/;

for (const nome of ['list_opening_applications', 'get_opening_application']) {
  test(`#2393 S: ${nome} é VOLATILE, SECURITY DEFINER, search_path vazio, e anon e PUBLIC não executam`, () => {
    const { file, corpo } = captura(nome);
    assert.match(corpo, /RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS/,
      `${nome}: perdeu VOLATILE, SECURITY DEFINER ou o search_path vazio`);
    const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
    const assinatura = nome === 'list_opening_applications' ? 'text' : 'uuid';
    assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.${nome}\\(${assinatura}\\) FROM PUBLIC, anon;`),
      `${nome}: a migration não revoga PUBLIC e anon`);
    assert.match(sql, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${nome}\\(${assinatura}\\) TO authenticated;`),
      `${nome}: a migration não concede a authenticated`);
    for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql'))) {
      const outro = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8'));
      assert.doesNotMatch(outro, new RegExp(`GRANT[^;]*ON FUNCTION public\\.${nome}\\b[^;]*\\b(anon|PUBLIC)\\b`, 'i'),
        `${f}: concede ${nome} a anon ou PUBLIC`);
    }
  });

  test(`#2393 S: ${nome} recusa quem não é membro ativo da organização, antes de tudo`, () => {
    const { corpo } = captura(nome);
    assert.match(corpo, PORTAO_MEMBRO, `${nome}: o portão de membro e organização não recusa`);
    const i = corpo.search(PORTAO_MEMBRO);
    for (const depois of ['public.can_by_member(', 'public._log_opening_application_access(', 'public.selection_applications ']) {
      assert.ok(corpo.indexOf(depois) > i, `${nome}: ${depois} aparece antes do portão de membro`);
    }
  });

  test(`#2393 S (INVERSA da D2): ${nome} não lê nota, avaliação, IA nem dado fora da minimização`, () => {
    const { corpo } = captura(nome);
    const achado = corpo.match(PROIBIDO);
    assert.equal(achado, null, `${nome}: cita ${achado && achado[0]}`);
  });

  test(`#2393 S: ${nome} registra pelo registro estrito, nunca pelo fail-soft, e não lê a linha inteira`, () => {
    const { corpo } = captura(nome);
    assert.match(corpo, /PERFORM public\._log_opening_application_access\(/, `${nome}: não chama o registro estrito`);
    assert.doesNotMatch(corpo, /_log_application_pii_access\s*\(/, `${nome}: chama o registro fail-soft, que deixa a leitura sair sem registro`);
    assert.doesNotMatch(corpo, /\b\w+\.\*/, `${nome}: lê uma linha inteira (x.*) em vez das colunas que devolve`);
  });

  test(`#2393 S: ${nome} não diz se a vaga ou a candidatura existem antes da autoridade`, () => {
    const { corpo } = captura(nome);
    const achado = corpo.match(/'(opening_not_found|opening_without_line|application_not_found)'/);
    assert.equal(achado, null, `${nome}: devolve ${achado && achado[1]}, que diferencia existência de autoridade`);
  });
}

test('#2393 S: o registro estrito não engole falha, grava mesmo sem e-mail, e é interno', () => {
  const { file, corpo } = captura('_log_opening_application_access');
  assert.match(corpo, /RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS/,
    'o registro estrito perdeu VOLATILE, SECURITY DEFINER ou o search_path vazio');
  assert.doesNotMatch(corpo, /EXCEPTION\s+WHEN/, 'o registro estrito ganhou tratador de exceção: a falha deixaria a leitura sair');
  assert.doesNotMatch(corpo, /\bRETURN\s*;/, 'o registro estrito ganhou uma saída antes de gravar');
  assert.match(corpo,
    /IF v_app_email IS NOT NULL THEN SELECT m\.id INTO v_target_member_id FROM public\.members m WHERE lower\(trim\(m\.email\)\) = lower\(trim\(v_app_email\)\) LIMIT 1; END IF; INSERT INTO public\.pii_access_log \( accessor_id, target_member_id, target_application_id, fields_accessed, context, accessed_at \) VALUES \( p_accessor_id, v_target_member_id, p_application_id, p_fields, p_context, now\(\) \); END;/,
    'o INSERT deixou de vir depois do bloco do e-mail, para todo caso, gravando a candidatura');
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, /REVOKE ALL ON FUNCTION public\._log_opening_application_access\(uuid, uuid, text\[\], text\) FROM PUBLIC, anon, authenticated;/,
    'o registro estrito não é revogado de PUBLIC, anon e authenticated');
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql'))) {
    const outro = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8'));
    assert.doesNotMatch(outro, /GRANT[^;]*ON FUNCTION public\._log_opening_application_access\b[^;]*\b(anon|PUBLIC|authenticated)\b/i,
      `${f}: concede o registro estrito a cliente`);
  }
});

test('#2393 S: list_opening_applications, uma vaga só: geral recusada antes da autoridade, e cada passo recusa', () => {
  const { corpo } = captura('list_opening_applications');
  const bloco = recorte(corpo, 'IF p_opportunity_id IS NOT NULL THEN', 'END IF; FOR v_app IN');
  assert.match(bloco,
    /IF v_opp\.opportunity_id IS NULL OR v_opp\.organization_id IS DISTINCT FROM v_org THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; IF v_opp\.initiative_id IS NULL THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; IF NOT public\.can_by_member\(v_caller_id, 'view_opening_applications', 'initiative', v_opp\.initiative_id\) OR NOT public\.rls_can_see_initiative\(v_opp\.initiative_id\) THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; IF public\.selection_coi_recused\(v_caller_id, v_opp\.cycle_id\) THEN RETURN jsonb_build_object\('error', 'recused_conflict_of_interest'/,
    'a sequência organização → vaga geral → autoridade com a iniciativa → conflito de interesse foi quebrada');
});

test('#2393 S: list_opening_applications, a varredura: só vaga de linha, mesma organização e ciclo, autoridade por vaga', () => {
  const { corpo } = captura('list_opening_applications');
  const consulta = recorte(corpo, 'FOR v_app IN', 'LOOP');
  assert.match(consulta,
    /FROM public\.vep_opportunities vo JOIN public\.selection_applications sa ON sa\.vep_opportunity_id = vo\.opportunity_id AND sa\.cycle_id = vo\.cycle_id WHERE vo\.initiative_id IS NOT NULL AND vo\.organization_id = v_org AND sa\.organization_id = v_org AND sa\.anonymized_at IS NULL AND \(p_opportunity_id IS NULL OR vo\.opportunity_id = p_opportunity_id\) AND public\.can_by_member\(v_caller_id, 'view_opening_applications', 'initiative', vo\.initiative_id\) AND public\.rls_can_see_initiative\(vo\.initiative_id\) ORDER BY/,
    'a varredura deixou de filtrar vaga de linha, organização, ciclo, anonimizada, autoridade ou iniciativa confidencial');
});

test('#2393 S: list_opening_applications, por candidatura: conflito de interesse pula, e o registro vem antes da linha', () => {
  const { corpo } = captura('list_opening_applications');
  const laco = recorte(corpo, 'LOOP', 'END LOOP;');
  assert.match(laco,
    /^LOOP IF public\.selection_coi_recused\(v_caller_id, v_app\.cycle_id\) THEN v_omitidas_coi := v_omitidas_coi \+ 1; CONTINUE; END IF; PERFORM public\._log_opening_application_access\( v_app\.id, v_caller_id, ARRAY\[[^\]]+\], 'list_opening_applications' \); v_rows := v_rows \|\| jsonb_build_array\(jsonb_build_object\(/,
    'o laço deixou de pular o conflito de interesse ou de registrar antes de acrescentar a linha');
  assert.deepEqual(chavesDe(laco, 'v_app'), CHAVES_LISTA, 'as chaves da lista não são as decididas (D2)');
});

test('#2393 S: get_opening_application: cada passo recusa, na ordem, e o registro vem antes do retorno', () => {
  const { corpo } = captura('get_opening_application');
  assert.match(corpo,
    /WHERE sa\.id = p_application_id AND sa\.anonymized_at IS NULL; IF v_app\.id IS NULL OR v_app\.organization_id IS DISTINCT FROM v_org THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; IF v_app\.vo_opportunity_id IS NULL OR v_app\.vo_organization_id IS DISTINCT FROM v_org THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; IF v_app\.vo_initiative_id IS NULL THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; IF NOT public\.can_by_member\(v_caller_id, 'view_opening_applications', 'initiative', v_app\.vo_initiative_id\) OR NOT public\.rls_can_see_initiative\(v_app\.vo_initiative_id\) THEN RETURN jsonb_build_object\('error', 'Unauthorized'\); END IF; IF public\.selection_coi_recused\(v_caller_id, v_app\.cycle_id\) THEN RETURN jsonb_build_object\('error', 'recused_conflict_of_interest'.*?\); END IF; PERFORM public\._log_opening_application_access\( v_app\.id, v_caller_id, ARRAY\[[^\]]+\], 'get_opening_application' \); v_perguntas := \( SELECT .*? END\) q \); RETURN jsonb_build_object\(/,
    'a sequência candidatura → vaga → vaga geral → autoridade → conflito de interesse → registro → retorno foi quebrada');
  assert.match(corpo,
    /LEFT JOIN public\.vep_opportunities vo ON vo\.opportunity_id = sa\.vep_opportunity_id AND vo\.cycle_id = sa\.cycle_id/,
    'a vaga deixou de ser a do mesmo ciclo da candidatura');
  const retorno = recorte(corpo, 'END) q ); RETURN jsonb_build_object(', '); END;');
  assert.deepEqual(chavesDe(retorno, 'v_app'), CHAVES_DETALHE, 'as chaves do detalhe não são as decididas (D2)');
});

test('#2393 S: get_opening_application devolve das perguntas da vaga só o campo e o texto', () => {
  const { corpo } = captura('get_opening_application');
  assert.match(corpo,
    /v_perguntas := \( SELECT jsonb_object_agg\(q\.key, jsonb_build_object\('field', q\.value->>'field', 'question', q\.value->>'question'\)\) FROM jsonb_each\(CASE WHEN jsonb_typeof\(v_app\.vo_essay_mapping\) = 'object' THEN v_app\.vo_essay_mapping ELSE '\{\}'::jsonb END\) q \);/,
    'as perguntas deixaram de ser montadas só com field e question');
  const retorno = recorte(corpo, 'END) q ); RETURN jsonb_build_object(', '); END;');
  assert.doesNotMatch(retorno, /vo_essay_mapping/, 'o essay_mapping inteiro voltou a sair no detalhe');
  assert.match(retorno, /'essay_questions', v_perguntas,/, 'essay_questions deixou de vir da lista filtrada');
});

test('#2393 S: as sementes da ação são só os 4 pares de liderança, só em initiative', () => {
  const achadas = new Set();
  let confere4 = false;
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8'));
    for (const m of sql.matchAll(new RegExp(`\\(\\s*'([a-z_]+)',\\s*'([a-z_]+)',\\s*'${ACAO}',\\s*'([a-z_]+)'`, 'g'))) {
      achadas.add(`${m[1]}|${m[2]}|${m[3]}`);
    }
    if (/IF v_inseridas <> 4 THEN\s+RAISE EXCEPTION 'view_opening_applications/.test(sql)) confere4 = true;
  }
  assert.deepEqual([...achadas].sort(), SEMENTES, 'as sementes de view_opening_applications não são as decididas');
  assert.ok(confere4, 'a migration das sementes deixou de parar quando não entram exatamente 4');
});

test('#2393 S: o registro grava a candidatura lida, e a FK não prende candidatura apagada', () => {
  const { corpo } = captura('_log_application_pii_access');
  assert.match(corpo,
    /INSERT INTO public\.pii_access_log \( accessor_id, target_member_id, target_application_id, fields_accessed, context, accessed_at \) VALUES \( p_accessor_id, v_target_member_id, p_application_id, p_fields, p_context, now\(\) \)/,
    '_log_application_pii_access deixou de gravar p_application_id em target_application_id');
  let fk = false;
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql'))) {
    const sql = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')).replace(/\s+/g, ' ');
    if (/ALTER TABLE public\.pii_access_log ADD COLUMN target_application_id uuid REFERENCES public\.selection_applications\(id\) ON DELETE SET NULL;/.test(sql)) fk = true;
  }
  assert.ok(fk, 'nenhuma migration cria target_application_id com FK ON DELETE SET NULL');
});

// ─── L: vivo ──────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const temCredencial = Boolean(URL_BASE && KEY);
const cabecalho = (chave) => ({ apikey: chave, Authorization: `Bearer ${chave}`, 'Content-Type': 'application/json' });

test('#2393 L: anon recebe 42501 nas duas leituras (e não 404, que seria a função ausente)',
  { skip: temCredencial && ANON ? false : 'sem credencial de banco' }, async () => {
    const chamadas = {
      list_opening_applications: {},
      get_opening_application: { p_application_id: '00000000-0000-0000-0000-000000000000' },
    };
    for (const [nome, corpo] of Object.entries(chamadas)) {
      const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/${nome}`, {
        method: 'POST', headers: cabecalho(ANON), body: JSON.stringify(corpo),
      });
      const texto = await r.text();
      assert.ok([401, 403].includes(r.status), `${nome}: anon recebeu ${r.status}: ${texto.slice(0, 160)}`);
      assert.match(texto, /"code":"42501"/, `${nome}: a recusa a anon não é falta de permissão: ${texto.slice(0, 160)}`);
    }
  });

test('#2393 L: as sementes vivas de view_opening_applications são as da migration',
  { skip: temCredencial ? false : 'sem credencial de banco' }, async () => {
    const r = await dbFetch(
      `${URL_BASE}/rest/v1/engagement_kind_permissions?select=kind,role,scope&action=eq.${ACAO}`,
      { headers: cabecalho(KEY) });
    assert.equal(r.status, 200, `engagement_kind_permissions respondeu ${r.status}`);
    const vivas = (await r.json()).map((x) => `${x.kind}|${x.role}|${x.scope}`).sort();
    assert.deepEqual(vivas, SEMENTES, 'as sementes vivas divergem das decididas');
  });

test('#2393 L: a coluna target_application_id existe no registro',
  { skip: temCredencial ? false : 'sem credencial de banco' }, async () => {
    const r = await dbFetch(`${URL_BASE}/rest/v1/pii_access_log?select=target_application_id&limit=0`,
      { headers: cabecalho(KEY) });
    assert.equal(r.status, 200, `pii_access_log.target_application_id: ${r.status} ${(await r.text()).slice(0, 160)}`);
  });
