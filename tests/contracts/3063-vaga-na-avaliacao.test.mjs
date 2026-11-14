/**
 * Contract: #3063 — a fila e o formulário de avaliação dizem a VAGA do VEP da candidatura.
 *
 * `role_applied` não diz a vaga: Onboarding, Comunicação, Curadoria e Publicações chegam como 'researcher'. O GP
 * decidiu em 14/11/2026 que cada candidatura é avaliada pela régua da própria vaga, e o avaliador só aplica a
 * régua certa se a tela disser qual é.
 *
 * Camadas:
 *   S  estática, na captura vigente:
 *      - o helper `_vaga_da_candidatura` lê a vaga PELA candidatura (vep_opportunity_id), e só com
 *        p_com_perguntas entrega o essay_mapping; fechado para todo cliente;
 *      - a fila põe 'vaga' DENTRO do objeto de cada candidatura, na geral e na do piloto;
 *      - o formulário devolve 'vaga' com as perguntas, e o pert_cutoff diz que a coorte é ciclo + função.
 *   L  viva: anon recebe 42501 no helper.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const HELPER = '_vaga_da_candidatura';

function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}

// ─── S: helper ─────────────────────────────────────────────────────────────────────

test('#3063 S: o helper acha a vaga pela candidatura e só entrega as perguntas com p_com_perguntas', () => {
  const { corpo } = captura(HELPER);
  assert.match(corpo, /RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''/,
    'o helper mudou os atributos (tipo, volatilidade, definer ou search_path)');
  assert.match(corpo,
    /FROM public\.selection_applications sa LEFT JOIN public\.vep_opportunities vo ON vo\.opportunity_id = sa\.vep_opportunity_id WHERE sa\.id = p_application_id/,
    'o helper não acha mais a vaga pela vep_opportunity_id da própria candidatura');
  assert.match(corpo,
    /CASE WHEN p_com_perguntas THEN jsonb_build_object\( 'vep_url', vo\.vep_url, 'time_commitment', vo\.time_commitment, 'essay_mapping', vo\.essay_mapping \) ELSE '\{\}'::jsonb END/,
    'as perguntas da vaga saem sem depender de p_com_perguntas');
  assert.match(corpo, /jsonb_build_object\( 'opportunity_id', vo\.opportunity_id, 'title', vo\.title,/,
    'o helper não devolve mais o id e o título da vaga');
});

test('#3063 S: o helper é fechado para PUBLIC, anon e authenticated, sem GRANT depois', () => {
  const { file } = captura(HELPER);
  const arquivos = readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort();
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, /REVOKE ALL ON FUNCTION public\._vaga_da_candidatura\(uuid, boolean\) FROM PUBLIC, anon, authenticated;/,
    'o REVOKE do helper sumiu');
  for (const f of arquivos.slice(arquivos.indexOf(file))) {
    const s = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8'));
    assert.doesNotMatch(s, /GRANT[^;]*_vaga_da_candidatura/i, `${f} devolve acesso ao helper`);
  }
});

// ─── S: fila ───────────────────────────────────────────────────────────────────────

test('#3063 S: a fila põe a vaga dentro do objeto de cada candidatura, na geral e no piloto', () => {
  const { corpo } = captura('get_my_pending_evaluations');
  // geral: dentro do jsonb_build_object que vira 'pending', antes do flag de rascunho
  assert.match(corpo,
    /'created_at', sa\.created_at, 'vaga', public\._vaga_da_candidatura\(sa\.id, false\), 'has_my_evaluation_in_progress', EXISTS \(SELECT 1 FROM public\.selection_evaluations se WHERE se\.application_id = sa\.id AND se\.evaluator_id = v_caller_member_id AND se\.submitted_at IS NULL\) \) ORDER BY sa\.created_at\) INTO v_pending/,
    'a fila geral não leva a vaga no objeto de cada candidatura');
  // piloto: dentro do objeto que vira v_piloto
  assert.match(corpo,
    /'evaluation_track', 'line_pilot', 'vaga', public\._vaga_da_candidatura\(sa\.id, false\), 'part', a\.part,/,
    'a fila do piloto não leva a vaga');
  assert.match(corpo, /\) ORDER BY a\.due_at NULLS LAST, sa\.created_at\) INTO v_piloto/,
    'o objeto do piloto não é mais o que vira v_piloto');
});

// ─── S: formulário ─────────────────────────────────────────────────────────────────

test('#3063 S: o formulário devolve a vaga com as perguntas, e o corte diz que a coorte é ciclo + função', () => {
  const { corpo } = captura('get_evaluation_form');
  assert.match(corpo,
    /'calc_at', v_app\.pert_calc_at, 'cohort_scope', 'ciclo_e_funcao' \), 'vaga', public\._vaga_da_candidatura\(p_application_id, true\), 'evaluation_type', p_evaluation_type,/,
    'o formulário não devolve a vaga com as perguntas no RETURN, ou o corte não diz o escopo da coorte');
});

// ─── L: viva ───────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

test('#3063 L: anon recebe 42501 no helper (e não 404, que seria a função ausente)',
  { skip: URL_BASE && ANON ? false : 'sem credencial de banco' }, async () => {
    const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/${HELPER}`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_application_id: '00000000-0000-0000-0000-000000000000', p_com_perguntas: true }),
    });
    const texto = await r.text();
    assert.ok([401, 403].includes(r.status), `anon recebeu ${r.status}: ${texto.slice(0, 160)}`);
    assert.match(texto, /"code":"42501"/, `a recusa a anon não é falta de permissão: ${texto.slice(0, 160)}`);
  });
