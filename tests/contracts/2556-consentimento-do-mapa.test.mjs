/**
 * #2556: o consentimento de localizacao precisa no mapa publico e pedido na home do membro e deixa prova.
 *
 * Medido em 08/10/2026: o consentimento era so um booleano em members, sem data nem texto exibido, e so podia ser
 * dado no /profile; 25 de 80 da equipe de pesquisa nao tinham nenhum. Decisao do GP (opcao C): cartao na home,
 * "agora nao" no banco e cada autorizacao/revogacao no ledger consent_records (LGPD art. 8, par. 2).
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. o CHECK de policy_type ganha public_map_location e mantem todos os tipos anteriores;
 *   B. grant_public_map_consent: SECDEF, resolve o membro pela sessao, liga a flag E grava a linha no ledger
 *      (idempotente sobre a linha ativa), com evidencia por lista fechada de chaves;
 *   C. revoke_public_map_consent: desliga a flag E marca revoked_at na linha ativa, sem DELETE;
 *   D. get_my_public_map_prompt so mostra o cartao a quem esta na equipe, sem o consentimento e sem ter dispensado;
 *   E. update_my_profile (ultima captura) nao aceita mais allow_precise_location_in_public_map;
 *   F. as quatro funcoes sao negadas a PUBLIC/anon e concedidas a authenticated;
 *   G. a tela: o /profile chama grant/revoke e nao manda o campo ao update_my_profile; as tres homes passam ao
 *      cartao o rotulo aprovado (profile.allowPreciseLocationMapLabel); o cartao chama as RPCs;
 *   H. (banco) anon nao executa nenhuma das quatro; controle: anon executa uma RPC publica (o instrumento diz sim).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2556_consentimento_do_mapa\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
const fn = (name) => (SQL.match(new RegExp(String.raw`CREATE OR REPLACE FUNCTION public\.${name}\([\s\S]*?\$function\$[\s\S]*?\$function\$`)) || [''])[0];
const read = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));

test('a migration existe', () => {
  assert.equal(files.length, 1, `esperava 1 migration da #2556, achei ${files.length}`);
});

test('A. policy_type ganha public_map_location e mantem os anteriores', () => {
  const chk = (SQL.match(/ADD CONSTRAINT consent_records_policy_type_check[\s\S]*?\]\)\);/) || [''])[0];
  assert.match(SQL, /DROP CONSTRAINT consent_records_policy_type_check;/);
  for (const t of ['privacy_policy', 'volunteer_term', 'ai_analysis', 'communication_preferences', 'cookies', 'image_voice_publicity', 'public_map_location', 'other']) {
    assert.match(chk, new RegExp(`'${t}'::text`), `policy_type '${t}' ausente do CHECK`);
  }
});

test('B. grant liga a flag e grava a prova, idempotente, evidencia fechada', () => {
  const g = fn('grant_public_map_consent');
  assert.match(g, /SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
  assert.match(g, /FROM public\.members WHERE auth_id = auth\.uid\(\);\s+IF v_member_id IS NULL THEN\s+RAISE EXCEPTION 'Not authenticated'/);
  assert.match(g, /UPDATE public\.members SET allow_precise_location_in_public_map = true WHERE id = v_member_id;/);
  assert.match(g, /policy_type = 'public_map_location' AND revoked_at IS NULL[\s\S]*?IF v_active_id IS NOT NULL THEN\s+RETURN/, 'sem idempotencia sobre a linha ativa');
  assert.match(g, /INSERT INTO public\.consent_records \([\s\S]*?\) VALUES \(\s*v_member_id, 'public_map_location', v_version, now\(\), 'platform_action', v_evidence, v_org_id\s*\)/);
  const ev = (g.match(/v_evidence := jsonb_strip_nulls\(jsonb_build_object\(([\s\S]*?)\)\);/) || ['', ''])[1];
  const chaves = [...ev.matchAll(/^\s*'([a-z_]+)',/gm)].map((m) => m[1]).sort();
  assert.deepEqual(chaves, ['label_key', 'lang', 'surface']);
  assert.doesNotMatch(g, /evidence, v_org_id[\s\S]*p_evidence\s*[,)]/, 'p_evidence nao pode ir inteiro para o ledger');
});

test('C. revoke desliga a flag e marca revoked_at, sem DELETE', () => {
  const r = fn('revoke_public_map_consent');
  assert.match(r, /UPDATE public\.members SET allow_precise_location_in_public_map = false WHERE id = v_member_id;/);
  assert.match(r, /UPDATE public\.consent_records\s+SET revoked_at = now\(\),[\s\S]*?WHERE member_id = v_member_id AND policy_type = 'public_map_location' AND revoked_at IS NULL/);
  assert.doesNotMatch(r, /DELETE/i);
});

test('D. o cartao so aparece para a equipe, sem consentimento e sem dispensa', () => {
  const p = fn('get_my_public_map_prompt');
  assert.match(p, /'show', EXISTS \(SELECT 1 FROM public\.v_operational_members o WHERE o\.id = v_m\.id\)\s+AND NOT COALESCE\(v_m\.allow_precise_location_in_public_map, false\)\s+AND v_m\.public_map_prompt_dismissed_at IS NULL,/);
  const d = fn('dismiss_public_map_prompt');
  assert.match(d, /UPDATE public\.members SET public_map_prompt_dismissed_at = now\(\) WHERE id = v_member_id;/);
});

test('E. update_my_profile nao aceita mais o consentimento preciso', () => {
  const cap = latestFunctionCapture(ROOT, 'update_my_profile');
  const corpo = maskLineComments(cap.body);
  const lista = (corpo.match(/v_allowed_fields text\[\] := ARRAY\[([^\]]*)\]/) || ['', ''])[1];
  assert.ok(lista.includes("'allow_state_in_public_map'"), `${cap.file}: lista de campos nao encontrada`);
  assert.doesNotMatch(lista, /allow_precise_location_in_public_map/, `${cap.file}: update_my_profile ainda aceita o campo`);
  assert.doesNotMatch(corpo, /allow_precise_location_in_public_map\s*=/, `${cap.file}: update_my_profile ainda grava o campo`);
});

test('F. as quatro funcoes negadas a PUBLIC/anon e concedidas a authenticated', () => {
  for (const sig of ['get_my_public_map_prompt\\(\\)', 'grant_public_map_consent\\(jsonb\\)', 'revoke_public_map_consent\\(text\\)', 'dismiss_public_map_prompt\\(\\)']) {
    assert.match(SQL, new RegExp(`REVOKE ALL ON FUNCTION public\\.${sig} FROM PUBLIC, anon;`), `${sig} sem REVOKE`);
    assert.match(SQL, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${sig} TO authenticated, service_role;`), `${sig} sem GRANT`);
    assert.doesNotMatch(SQL, new RegExp(`GRANT[^;]*${sig}[^;]*\\banon\\b`), `${sig} concedida a anon`);
  }
});

test('G. a tela usa as RPCs e o rotulo aprovado', () => {
  const profile = read('src/pages/profile.astro');
  assert.match(profile, /allowPreciseMap\s*\?\s*await sb\.rpc\('grant_public_map_consent'[\s\S]{0,120}?:\s*await sb\.rpc\('revoke_public_map_consent'/);
  assert.doesNotMatch(profile, /fields\.allow_precise_location_in_public_map\s*=/, 'o /profile ainda manda o campo ao update_my_profile');
  for (const page of ['src/pages/index.astro', 'src/pages/en/index.astro', 'src/pages/es/index.astro']) {
    assert.match(read(page), /<MapConsentNudge client:load lang=\{lang\}\s+consentText=\{t\('profile\.allowPreciseLocationMapLabel', lang\)\}/, `${page}: cartao sem o rotulo aprovado`);
  }
  const card = read('src/components/onboarding/MapConsentNudge.tsx');
  assert.match(card, /sb\.rpc\('get_my_public_map_prompt'\)/);
  assert.match(card, /rpc === 'grant_public_map_consent' \? \{ p_evidence: \{ surface: 'home_card', lang \} \}/);
  assert.match(card, /act\('dismiss_public_map_prompt'\)/);
  assert.match(card, /if \(!prompt\?\.show\) return null;/, 'o cartao precisa obedecer ao show do servidor');
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(URL && ANON);

async function anonRpc(name, body = {}) {
  const r = await fetch(`${URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return r.status;
}

test('H. (banco) anon nao executa as quatro; controle: executa uma RPC publica', { skip: dbGated ? false : 'SUPABASE_URL + anon key required' }, async () => {
  for (const [name, body] of [['get_my_public_map_prompt', {}], ['grant_public_map_consent', {}], ['revoke_public_map_consent', {}], ['dismiss_public_map_prompt', {}]]) {
    const status = await anonRpc(name, body);
    assert.ok(status === 401 || status === 403 || status === 404, `${name} como anon voltou ${status}`);
  }
  assert.equal(await anonRpc('get_public_cpmai_course'), 200, 'controle: anon deveria executar a RPC publica');
});
