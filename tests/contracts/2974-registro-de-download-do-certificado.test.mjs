/**
 * #2974 (d): record_certificate_download registra o primeiro download do certificado, e só pela própria pessoa.
 *
 * As páginas /certificates e /gamification chamavam a função antes de gerar o PDF, e ela não existia: a chamada
 * voltava erro calada e certificates.downloaded_at nunca era escrita. Decisão do GP em 04/11/2026: criar a função;
 * só a própria pessoa registra, e só o primeiro download.
 *
 * O corpo é lido pela captura MAIS NOVA (#1932), com comentários mascarados, e cada asserção amarra a condição ao
 * resultado:
 *   - sem membro na sessão, recusa antes de ler ou gravar certificates;
 *   - certificado de outra pessoa ou inexistente dá a mesma resposta, antes de gravar;
 *   - o UPDATE grava só downloaded_at, com dono e "ainda nula" na própria condição;
 *   - `recorded` vem da contagem de linhas do UPDATE;
 *   - anon não executa, authenticated executa, e a pós-condição da migration mede isso;
 *   - as duas páginas chamam com o nome de parâmetro da função, leem a recusa do corpo e geram o PDF depois, sem
 *     bloquear; em /gamification pela ação delegada, porque o onclick inline não enxergava o sb do script.
 * Com banco (CI), a função viva recusa a chamada sem sessão de membro.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const FN = 'record_certificate_download';
const migName = readdirSync(resolve(ROOT, 'supabase/migrations'))
  .filter((f) => f.endsWith('_2974_registro_de_download_do_certificado.sql'));
const MIG = migName.length ? maskLineComments(read(`supabase/migrations/${migName[0]}`)) : '';
const corpo = () => maskLineComments(latestFunctionCapture(ROOT, FN).body).replace(/\s+/g, ' ');
const bloco = () => maskLineComments(latestFunctionCapture(ROOT, FN).block).replace(/\s+/g, ' ');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);

test('(d) há exatamente uma migration do registro de download', () => {
  assert.equal(migName.length, 1, `esperava 1 migration *_2974_registro_de_download_do_certificado.sql, achei ${migName.length}`);
});

test('(d) a assinatura é a que as páginas chamam', () => {
  assert.match(bloco(), /^CREATE OR REPLACE FUNCTION public\.record_certificate_download\(p_cert_id uuid\) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'/);
});

test('(d) sem membro na sessão, recusa antes de ler ou gravar certificates', () => {
  const f = corpo();
  const antes = f.slice(0, f.indexOf('public.certificates'));
  assert.ok(antes.length > 0 && f.includes('public.certificates'), 'a função não lê certificates');
  assert.match(antes, /SELECT m\.id INTO v_caller_id FROM public\.members m WHERE m\.auth_id = auth\.uid\(\); IF v_caller_id IS NULL THEN RETURN jsonb_build_object\('error', 'not_authenticated'\); END IF;/);
});

test('(d) certificado de outra pessoa ou inexistente: a mesma resposta, antes de gravar', () => {
  const f = corpo();
  const antes = f.slice(0, f.indexOf('UPDATE public.certificates'));
  assert.ok(antes.length > 0 && f.includes('UPDATE public.certificates'), 'a função não grava em certificates');
  assert.match(antes, /SELECT c\.member_id INTO v_owner_id FROM public\.certificates c WHERE c\.id = p_cert_id; IF v_owner_id IS NULL OR v_owner_id IS DISTINCT FROM v_caller_id THEN RETURN jsonb_build_object\('error', 'not_found'\); END IF;/);
});

test('(d) o UPDATE grava só downloaded_at, do dono, e só se ainda nula; recorded vem da contagem', () => {
  const f = corpo();
  assert.match(f, /UPDATE public\.certificates SET downloaded_at = now\(\) WHERE id = p_cert_id AND member_id = v_caller_id AND downloaded_at IS NULL; GET DIAGNOSTICS v_rows = ROW_COUNT; RETURN jsonb_build_object\('success', true, 'recorded', v_rows = 1\);/);
  assert.equal((f.match(/UPDATE public\.certificates/g) || []).length, 1, 'a função grava em certificates mais de uma vez');
});

test('(d) anon não executa, authenticated executa, e a pós-condição mede os dois', () => {
  const m = MIG.replace(/\s+/g, ' ');
  assert.match(m, /REVOKE ALL ON FUNCTION public\.record_certificate_download\(uuid\) FROM PUBLIC, anon;/);
  assert.match(m, /GRANT EXECUTE ON FUNCTION public\.record_certificate_download\(uuid\) TO authenticated;/);
  assert.doesNotMatch(m, /GRANT [^;]*record_certificate_download[^;]* TO [^;]*\banon\b/, 'a migration concede a anon');
  assert.match(m, /IF has_function_privilege\('anon', 'public\.record_certificate_download\(uuid\)', 'EXECUTE'\) OR NOT has_function_privilege\('authenticated', 'public\.record_certificate_download\(uuid\)', 'EXECUTE'\) THEN RAISE EXCEPTION/);
  assert.match(m, /IF \(public\.record_certificate_download\(gen_random_uuid\(\)\)->>'error'\) IS DISTINCT FROM 'not_authenticated' THEN RAISE EXCEPTION/);
});

test('(d) /certificates registra com p_cert_id, lê a recusa do corpo e gera o PDF depois, sem bloquear', () => {
  const c = maskJsComments(read('src/pages/certificates.astro')).replace(/\s+/g, ' ');
  assert.match(c, /if \(certData\.id\) \{ const \{ data: reg, error: regErr \} = await sb\.rpc\('record_certificate_download', \{ p_cert_id: certData\.id \}\); if \(regErr \|\| reg\?\.error\) console\.warn\('record_certificate_download', regErr\?\.message \|\| reg\?\.error\); \} await downloadCertificatePDF\(certData, sb\);/);
});

test('(d) /gamification: Meus certificados usa a ação delegada, que registra e gera o PDF sem bloquear', () => {
  const g = maskJsComments(read('src/pages/gamification.astro'));
  assert.doesNotMatch(g, /onclick="[^"]*\bsb\./, 'onclick inline não enxerga o sb do script de módulo');
  const ini = g.indexOf('async function loadMyCertificates()');
  const fim = g.indexOf('\n  }\n', ini);
  assert.ok(ini !== -1 && fim !== -1, 'loadMyCertificates não encontrada');
  assert.match(g.slice(ini, fim), /data-action="download-my-cert" data-cert-id="\$\{c\.id\}" data-cert='\$\{JSON\.stringify\(\{member_name:MEMBER\.name,/,
    'o botão de Meus certificados não usa a ação delegada');
  const caso = g.slice(g.indexOf("case 'download-my-cert': {"), g.indexOf('break;', g.indexOf("case 'download-my-cert': {")));
  assert.ok(caso.length > 0, "case 'download-my-cert' ausente");
  assert.match(caso.replace(/\s+/g, ' '), /const certId = target\.dataset\.certId \|\| ''; if \(certId && sb\) \{ const \{ data: reg, error: regErr \} = await sb\.rpc\('record_certificate_download', \{ p_cert_id: certId \}\); if \(regErr \|\| reg\?\.error\) console\.warn\('record_certificate_download', regErr\?\.message \|\| reg\?\.error\); \} try \{ const d = JSON\.parse\(target\.dataset\.cert \|\| '\{\}'\); await \(window as any\)\.downloadCertificatePDF\(d\); \}/);
});

test('(d) ao vivo: a função existe e recusa chamada sem sessão de membro', { skip: !dbGated && 'sem SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY' }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc(FN, { p_cert_id: '00000000-0000-0000-0000-000000000000' });
  assert.equal(error, null, `a função viva não respondeu: ${error?.message}`);
  assert.deepEqual(data, { error: 'not_authenticated' });
});
