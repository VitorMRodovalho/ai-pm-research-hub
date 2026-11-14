/**
 * Contract: #3067 — o MCP entrega o CV da candidatura por link assinado curto, sem chave administrativa.
 *
 * Decisão do GP em 14/11/2026: a lane de avaliação baixa o CV pelo MCP, com a conta dele, em vez de depender da
 * chave de serviço.
 *
 * Camadas:
 *   S  RPC get_application_resume_path:
 *      - recusa quem não tem view_pii ANTES de ler o caminho (o mesmo portão da política do bucket);
 *      - registra o acesso em pii_access_log antes de devolver;
 *      - fechada a anon; aberta a authenticated (o portão está dentro).
 *   S  MCP application_get scope 'cv': chama a RPC e cria o link com o cliente do PRÓPRIO usuário, 10 minutos.
 *   L  viva: anon recebe 42501 na RPC.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const RPC = 'get_application_resume_path';
const MCP = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');

function captura() {
  const cap = latestFunctionCapture(ROOT, RPC);
  assert.ok(cap, `${RPC}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}

test('#3067 S: sem view_pii, a RPC recusa antes de ler o caminho', () => {
  const { corpo } = captura();
  assert.match(corpo,
    /IF NOT public\.can_by_member\(v_caller_id, 'view_pii'::text\) THEN RAISE EXCEPTION 'Unauthorized: view_pii required' USING ERRCODE = 'insufficient_privilege'; END IF; SELECT sa\.resume_storage_path INTO v_path/,
    'o portão view_pii não vem antes da leitura do caminho');
  assert.match(corpo, /SELECT m\.id INTO v_caller_id FROM public\.members m WHERE m\.auth_id = auth\.uid\(\) AND m\.is_active = true; IF v_caller_id IS NULL THEN RAISE EXCEPTION/,
    'quem chama não é resolvido pelo auth.uid() de membro ativo');
});

test('#3067 S: a RPC registra o acesso antes de devolver o caminho', () => {
  const { corpo } = captura();
  assert.match(corpo,
    /PERFORM public\._log_application_pii_access\( p_application_id, v_caller_id, ARRAY\['resume_storage_path'\], 'get_application_resume_path' \); RETURN jsonb_build_object\('application_id', p_application_id, 'resume_storage_path', v_path\);/,
    'o caminho sai sem o registro em pii_access_log logo antes');
  assert.match(corpo, /SECURITY DEFINER SET search_path TO 'public', 'pg_temp'/, 'atributos da RPC mudaram');
});

test('#3067 S: a RPC é fechada a anon e aberta só a authenticated', () => {
  const { file } = captura();
  const sql = maskLineComments(readFileSync(resolve(ROOT, 'supabase/migrations', file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.get_application_resume_path\(uuid\) FROM PUBLIC, anon;/, 'o REVOKE de anon sumiu');
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.get_application_resume_path\(uuid\) TO authenticated;/, 'o GRANT a authenticated sumiu');
  assert.doesNotMatch(sql, /GRANT[^;]*get_application_resume_path[^;]*\banon\b/, 'a RPC foi aberta a anon');
});

test('#3067 S: o MCP cria o link com o cliente do usuário, só depois da RPC, e por 10 minutos', () => {
  const ef = maskJsComments(readFileSync(MCP, 'utf8')).replace(/\s+/g, ' ');
  assert.match(ef, /const CV_LINK_TTL_S = 600;/, 'a validade do link mudou');
  assert.match(ef,
    /case "cv": \{ source = "get_application_resume_path"; \(\{ data, error \} = await sb\.rpc\("get_application_resume_path", \{ p_application_id: params\.application_id \}\)\); if \(!error && data && \(data as any\)\.resume_storage_path\) \{ const path = String\(\(data as any\)\.resume_storage_path\); const signed = await sb\.storage\.from\("selection-resumes"\)\.createSignedUrl\(path, CV_LINK_TTL_S\);/,
    'o link não sai do cliente do usuário (sb), não depende da RPC ou não usa a validade curta');
  assert.match(ef, /scope: z\.enum\(\["scores", "interviews", "gate_attempts", "returning", "onboarding", "cv"\]\)/, 'o escopo cv não está no schema');
});

const URL_BASE = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

test('#3067 L: anon recebe 42501 na RPC (e não 404, que seria a função ausente)',
  { skip: URL_BASE && ANON ? false : 'sem credencial de banco' }, async () => {
    const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/${RPC}`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_application_id: '00000000-0000-0000-0000-000000000000' }),
    });
    const texto = await r.text();
    assert.ok([401, 403].includes(r.status), `anon recebeu ${r.status}: ${texto.slice(0, 160)}`);
    assert.match(texto, /"code":"42501"/, `a recusa a anon não é falta de permissão: ${texto.slice(0, 160)}`);
  });
