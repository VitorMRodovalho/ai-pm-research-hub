/**
 * Contract: #568 — LGPD Art. 18 consent-record read surface (#564 council follow-up).
 *
 * consent_records was locked (rpc_only_deny_all) with the read RPCs deferred ("futuras") and never
 * created → export_my_data omitted consent history and there was no admin audit path. This migration
 * (20260805000130) adds:
 *   1. list_my_consents() — subject self-read (auth.uid()→member). Friendly fields, OMITS hashes,
 *      adds is_active = (revoked_at IS NULL).
 *   2. admin_list_member_consents(p_member_id) — view_pii-gated audit read WITH capture-evidence
 *      hashes; an explicit multi-tenant org fence (SECDEF bypasses the RESTRICTIVE org RLS, and
 *      can_by_member('view_pii') does not bound the TARGET → a cross-org read was possible); logs
 *      EVERY call (incl self) to pii_access_log (Art. 37 accountability).
 *   3. export_my_data() — adds 'consent_records' (explicit projection, not row_to_json) and FIXES a
 *      pre-existing latent bug: it referenced initiatives.name (V4 renamed to `title`) → the export
 *      RAISED "column i.name does not exist" for ANY member with engagements. Now i.title.
 *
 * Grant posture: new fns REVOKE FROM PUBLIC, anon + GRANT authenticated, service_role. export_my_data
 * is re-asserted to authenticated+service_role (anon dropped — CREATE OR REPLACE would otherwise let
 * the auto PUBLIC grant linger).
 *
 * Cross-ref: #568, #564/PR#565, GC-162, LGPD Art. 18 (II access / V confirmation) + Art. 37.
 *
 * ── #1932, lote PII/LGPD: as afirmacoes de INVARIANTE CORRENTE leem a captura VIGENTE ──────────
 * Este arquivo era a instancia provada do #1932. Ele fixava a migration 130 e afirmava
 * `can_by_member(v_caller_id, 'view_pii')` com a mensagem "admin read gated on view_pii" — linha
 * que a producao nao executa desde 20260822120649, que trocou o portao pelo `can_org_by_member`,
 * mais estrito. O guard seguia VERDE.
 *
 * Agora cada afirmacao de invariante corrente resolve `latestFunctionCapture(...)`. O que continua
 * fixado na 130 e so o que e ENTREGA HISTORICA daquela migration (a postura de GRANT que ela
 * estabeleceu), e esta rotulado como tal. A postura de GRANT VIGENTE quem prova sao os testes de
 * banco no fim do arquivo, que exercem o anon de verdade.
 *
 * ⚠️ `export_my_data` tambem estava desatualizada aqui (fixada na 130, vigente em 20260808000100) e
 * o scanner do #1932 NAO a via: o arquivo nunca escreve `CREATE OR REPLACE FUNCTION
 * public.export_my_data`, so afirma trechos do corpo. O ponto cego nao e apenas por arquivo, e por
 * FUNCAO dentro de arquivo visivel.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
// Fixado DE PROPOSITO: so para o que a migration 130 entregou (postura de GRANT).
const MIG = resolve(ROOT, 'supabase/migrations/20260805000130_p568_consent_records_lgpd_read_rpcs.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

// Captura VIGENTE de cada funcao. `latestFunctionCapture` lanca se a funcao sumir, em vez de
// devolver vazio — um `doesNotMatch('', ...)` seria verde para sempre, e as afirmacoes de PII aqui
// sao justamente dessa forma ("nao vaza hash").
const capLmc = latestFunctionCapture(ROOT, 'list_my_consents');
const capAdm = latestFunctionCapture(ROOT, 'admin_list_member_consents');
const capExp = latestFunctionCapture(ROOT, 'export_my_data');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);

// ── VIGENTE: list_my_consents (leitura do proprio titular) ──────────────────────────────
test('#568 vigente: list_my_consents e SECDEF + STABLE, omite os hashes e publica is_active', () => {
  assert.match(capLmc.block, /CREATE OR REPLACE FUNCTION public\.list_my_consents\(\)/);
  assert.match(capLmc.block, /STABLE/, 'leitura do titular e STABLE');
  assert.match(capLmc.block, /SECURITY DEFINER/);
  // A visao do TITULAR nao pode expor as evidencias de captura. Antes isto exigia fatiar a
  // migration entre CREATE e REVOKE porque o arquivo continha as duas funcoes; a captura vigente
  // ja e so esta funcao, entao a afirmacao vale sobre o bloco inteiro.
  assert.doesNotMatch(capLmc.block, /email_hash|ip_hash|user_agent_hash/,
    'list_my_consents (visao do titular) precisa omitir as evidencias de captura');
  assert.match(capLmc.block, /'is_active', \(cr\.revoked_at IS NULL\)/,
    'o titular ve um flag consolidado de vigencia');
});

// ── VIGENTE: admin_list_member_consents (portao + cerca de org + log de acesso) ─────────
test('#568 vigente: admin_list_member_consents e gateada em view_pii COM escopo de org e loga sempre', () => {
  assert.match(capAdm.block, /CREATE OR REPLACE FUNCTION public\.admin_list_member_consents\(p_member_id uuid\)/);

  // O portao vigente e o ESCOPADO. Afirmar o nome exato importa: `can_org_by_member` nao contem
  // `can_by_member`, entao a versao anterior desta linha reprovaria — foi assim que o #1932 achou
  // este arquivo. A negativa abaixo e o que impede a volta silenciosa ao portao mais fraco.
  assert.match(capAdm.block, /IF NOT public\.can_org_by_member\(v_caller_id, 'view_pii'\) THEN/,
    'leitura administrativa gateada em view_pii COM escopo de organizacao');
  assert.doesNotMatch(capAdm.block, /public\.can_by_member\(v_caller_id, 'view_pii'\)/,
    'nao pode reverter para o portao amplo can_by_member (perde o escopo de org)');

  // CRITICO: cerca multi-tenant — SECDEF contorna a RLS RESTRICTIVE, e o portao de capacidade nao
  // limita o ALVO.
  assert.match(capAdm.block, /v_target_org_id IS NULL OR v_caller_org_id IS NULL OR v_target_org_id <> v_caller_org_id/,
    'cerca de org: o alvo precisa ser membro da organizacao de quem chama');
  assert.match(capAdm.block, /RAISE EXCEPTION 'Access denied: target member not in caller organization'/);
  assert.match(capAdm.block, /AND cr\.organization_id = v_caller_org_id/, 'cerca de org tambem na query');

  // O caminho administrativo (view_pii) DEVE expor as evidencias — inverso da visao do titular.
  assert.match(capAdm.block, /email_hash[\s\S]*?ip_hash[\s\S]*?user_agent_hash/,
    'o caminho de auditoria expoe as evidencias de captura');
});

test('#568 vigente: o log de acesso do admin_list_member_consents nao fica atras de condicional (Art. 37)', () => {
  const ins = capAdm.block.indexOf('INSERT INTO public.pii_access_log');
  assert.ok(ins > 0, 'a funcao precisa registrar a leitura em pii_access_log');
  assert.match(capAdm.block.slice(ins), /'admin_list_member_consents'[\s\S]*?now\(\)/);

  // A versao anterior afirmava `doesNotMatch(body, /p_member_id <> v_caller_id/)` sobre o arquivo
  // INTEIRO, como proxy de "self-read nao e excluido do log". O proxy quebrou sem que o invariante
  // quebrasse: a captura vigente usa exatamente essa comparacao na cerca de CAPITULO ("self sempre
  // permitido"), que nao tem relacao com o log. Varredura de literal no corpo todo nao diz de QUAL
  // construcao o literal e.
  //
  // A afirmacao precisa e posicional: entre o ultimo `END IF;` e o INSERT nao pode abrir condicional.
  const antes = capAdm.block.slice(0, ins);
  const ultimoEndIf = antes.lastIndexOf('END IF;');
  assert.ok(ultimoEndIf > 0, 'esperado ao menos um bloco IF antes do log (os portoes)');
  const entre = antes.slice(ultimoEndIf + 'END IF;'.length);
  assert.doesNotMatch(entre, /\bIF\b/,
    'o log de acesso precisa ser incondicional: nenhuma leitura administrativa pode escapar do registro');
});

// ── VIGENTE: export_my_data ─────────────────────────────────────────────────────────────
test('#568 vigente: export_my_data leva consent_records por projecao explicita e usa i.title', () => {
  assert.match(capExp.block, /'consent_records', COALESCE\(\(/, 'o export inclui consent_records');
  // projecao explicita (NAO row_to_json), para coluna futura nao ser exportada por acidente
  const exBlock = capExp.block.slice(capExp.block.lastIndexOf("'consent_records'"));
  assert.doesNotMatch(exBlock, /row_to_json\(cr\)/, 'consent_records exporta por projecao explicita');
  // o bug pre-existente: initiatives.name deixou de existir (V4 renomeou para title)
  assert.doesNotMatch(capExp.block, /'initiative_name', i\.name\b/,
    'nao pode referenciar i.name (a coluna virou title no V4)');
  assert.match(capExp.block, /'initiative_name', i\.title\b/, 'engagements usam i.title');
});

// ── ENTREGA HISTORICA: a postura de ACL que a migration 130 estabeleceu ─────────────────
// Fixado de proposito. A pergunta aqui e "a 130 entregou isto?", nao "isto vale hoje" — quem
// responde a segunda sao os testes de banco abaixo, que exercem o anon de verdade. Manter as duas
// e o ponto: `CREATE OR REPLACE` reconcede EXECUTE a PUBLIC por padrao, entao a postura vigente
// precisa ser medida, nao deduzida do texto de uma migration.
test('#568 entrega da migration 130: revoga PUBLIC/anon e concede authenticated + service_role', () => {
  assert.ok(existsSync(MIG), 'migration 130 existe');
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.list_my_consents\(\) FROM PUBLIC, anon;/);
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.list_my_consents\(\) TO authenticated, service_role;/);
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.admin_list_member_consents\(uuid\) FROM PUBLIC, anon;/);
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.export_my_data\(\) FROM PUBLIC, anon;/,
    'CREATE OR REPLACE obriga a reafirmar a ACL (derruba o auto-grant de anon)');
});

// ── DB (gated): anon is revoked on all three; service_role fail-closes ───────────────────
test('#568 DB: anon CANNOT execute the consent read RPCs (revoke effective)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const r1 = await anon.rpc('list_my_consents');
  assert.ok(r1.error, 'anon rejected from list_my_consents');
  const r2 = await anon.rpc('admin_list_member_consents', { p_member_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(r2.error, 'anon rejected from admin_list_member_consents');
});

test('#568 DB: anon CANNOT execute export_my_data (anon grant dropped this migration)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc('export_my_data');
  assert.ok(error, 'anon must be rejected from export_my_data (permission denied for function)');
});

test('#568 DB: service_role (no auth.uid) fail-closes on all three', { skip: svcGated ? false : 'service key required' }, async () => {
  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  // list_my_consents + export_my_data raise 'Not authenticated' (no auth.uid → no member row)
  const r1 = await svc.rpc('list_my_consents');
  assert.ok(r1.error, 'list_my_consents fail-closes for null uid');
  const r2 = await svc.rpc('export_my_data');
  assert.ok(r2.error, 'export_my_data fail-closes for null uid');
  // admin_list_member_consents also fail-closes (Not authenticated before the view_pii gate)
  const r3 = await svc.rpc('admin_list_member_consents', { p_member_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(r3.error, 'admin_list_member_consents fail-closes for null uid');
});
