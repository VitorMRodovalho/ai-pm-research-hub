// tests/contracts/2529-inscricao-de-competicao.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2529 / ADR-0133 — inscrição pública em competição (formulário sem login): as travas que a revisão
 * de segurança de 30/09 exigiu antes de aplicar.
 *
 *   C1  a inscrição nasce pendente e NÃO escreve em persons nem em consent_records; só a confirmação
 *       pelo link (e-mail provado) escreve, e só depois de conferir que ainda está pendente;
 *   H1  link não gira (reenviar não mexe nos links anteriores) e todo envio de e-mail passa por teto:
 *       o da edição ANTES de saber se o e-mail existe (para 'busy' não virar oráculo), o da inscrição
 *       antes de emitir link; anônimo sem IP é recusado, porque o limitador por IP falha aberto;
 *   H2/H3  corpo pequeno e objeto, e-mail estrito, sem caractere de controle, violação de CHECK vira
 *       resposta com código;
 *   e o resto que sustenta isso: link com validade, desistência que revoga o consentimento DESTA
 *   inscrição, lista de quem organiza sem as pendentes, search_path fechado, EXECUTE fechado no schema,
 *   limpeza agendada com o mesmo nome no cron e no registro de retenção, token só no fragmento.
 *
 * Cada asserção casa a CONDIÇÃO junto com o RESULTADO dentro do bloco que decide; comentários são
 * mascarados antes de medir. O comportamento vivo foi exercido no banco (anon com IP, sem IP, membro
 * com manage_platform) e está na PR; este arquivo segura o texto contra regressão.
 *
 * Cross-ref: #2529, ADR-0133, #1050 (limitador por IP), #1812 (registro de retenção).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const body = (name) => maskLineComments(latestFunctionCapture(ROOT, name).block);
// Funções do schema competition: o helper resolve por nome qualificado quando o nome traz o schema.
const inner = (name) => body(`competition\\.${name}`);

// A migration que cria a camada, achada pelo CONTEÚDO (não por nome de arquivo fixado, #1932).
const MIG_DIR = join(ROOT, 'supabase/migrations');
const layerFile = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort()
  .find((f) => /CREATE SCHEMA IF NOT EXISTS competition;/.test(readFileSync(join(MIG_DIR, f), 'utf8')));
const LAYER = layerFile ? maskLineComments(readFileSync(join(MIG_DIR, layerFile), 'utf8')) : '';

const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const idx = (text, re) => { const m = re.exec(text); return m ? m.index : -1; };

test('#2529: a migration da camada existe e é a que o guard lê', () => {
  assert.ok(layerFile, 'nenhuma migration cria o schema competition');
  // piso de denominador: se a extração parar de casar, o guard reprova em vez de ficar vazio
  assert.ok((LAYER.match(/\bCREATE FUNCTION\b/g) || []).length >= 22, 'a camada perdeu funções ou a extração parou de casar');
});

// ── C1: nada vai para persons nem consent_records antes do e-mail provado ─────────────────────
test('#2529 C1: a inscrição nasce pendente e sem pessoa', () => {
  assert.match(LAYER, /status\s+text NOT NULL DEFAULT 'pending_confirmation'/);
  assert.match(LAYER, /CHECK \(status = 'pending_confirmation' OR person_id IS NOT NULL\)/);
  assert.match(LAYER, /person_id\s+uuid REFERENCES public\.persons\(id\),/, 'person_id tem de aceitar NULL enquanto pende');
});

test('#2529 C1: competition_register não escreve em persons nem em consent_records', () => {
  const reg = body('competition_register');
  assert.match(reg, /INSERT INTO competition\.registrations \(/, 'o bloco lido não é o da inscrição');
  assert.doesNotMatch(reg, /INSERT\s+INTO\s+public\.persons/i);
  assert.doesNotMatch(reg, /INSERT\s+INTO\s+public\.consent_records/i);
});

test('#2529 C1: a confirmação só escreve pessoa e consentimento DEPOIS de conferir que pende', () => {
  const conf = body('competition_registration_confirm');
  const guard = idx(conf, /IF r\.status <> 'pending_confirmation' THEN\s+RETURN jsonb_build_object\('ok', true, 'message', 'already_confirmed'\);/);
  const person = idx(conf, /INSERT INTO public\.persons \(/);
  const consent = idx(conf, /INSERT INTO public\.consent_records \(/);
  assert.ok(guard >= 0, 'a confirmação perdeu a checagem de pendência');
  assert.ok(person > guard && consent > guard, 'pessoa ou consentimento escritos antes da checagem de pendência');
  assert.match(conf, /FROM competition\.registrations WHERE id = competition\.registration_by_token\(p_token\) FOR UPDATE;/);
});

// ── H1: link não gira; tetos antes de cada envio ────────────────────────────────────────────
test('#2529 H1: reenviar não mexe nos links anteriores', () => {
  const reg = body('competition_register');
  assert.doesNotMatch(reg, /(UPDATE|DELETE\s+FROM)\s+competition\.registration_tokens/i, 'a inscrição voltou a girar/apagar link');
  assert.equal((reg.match(/competition\.issue_token\(/g) || []).length, 3, 'cada caminho de envio emite um link novo por issue_token');
  assert.match(inner('issue_token'), /INSERT INTO competition\.registration_tokens \(token_hash, registration_id, expires_at\)/);
});

test('#2529 H1: o teto da edição vem antes de saber se o e-mail existe, e o da inscrição antes de emitir link', () => {
  const reg = body('competition_register');
  const cap = idx(reg, /IF NOT competition\.may_email\(e, NULL\) THEN\s+RETURN jsonb_build_object\('error', 'busy'\);/);
  const lookup = idx(reg, /SELECT \* INTO r FROM competition\.registrations WHERE edition_id = e\.id AND email = v_ans->>'email' FOR UPDATE;/);
  const perReg = idx(reg, /IF NOT competition\.may_email\(e, r\.id\) THEN\s+RETURN v_generic;/);
  const firstLink = idx(reg, /competition\.issue_token\(/);
  assert.ok(cap >= 0 && lookup > cap, "o teto da edição tem de vir antes da busca pelo e-mail ('busy' viraria oráculo)");
  assert.ok(perReg > lookup && firstLink > perReg, 'o teto da inscrição tem de vir antes do primeiro link emitido');
});

test('#2529 H1: os tetos são 1 e-mail a cada 15 min, 3 em 24 h, e o limite por hora da edição', () => {
  const m = inner('may_email');
  assert.match(m, /WHERE r\.edition_id = p_edition\.id AND ev\.event = 'email_queued'\s+AND ev\.created_at > now\(\) - interval '1 hour'\) < p_edition\.email_hourly_cap/);
  assert.match(m, /NOT EXISTS \(SELECT 1 FROM competition\.registration_events ev\s+WHERE ev\.registration_id = p_registration_id AND ev\.event = 'email_queued'\s+AND ev\.created_at > now\(\) - interval '15 minutes'\)/);
  assert.match(m, /AND ev\.created_at > now\(\) - interval '24 hours'\) < 3/);
});

test('#2529 H1: anônimo sem IP é recusado, e toda função anônima passa pelo portão antes de ler dado', () => {
  assert.match(inner('gate'), /IF v_ip IS NULL AND coalesce\(auth\.role\(\), ''\) <> 'service_role' THEN\s+RETURN 'unavailable';/);
  for (const fn of ['competition_register', 'competition_registration_confirm', 'competition_registration_get',
                    'competition_registration_update', 'competition_registration_withdraw']) {
    const b = body(fn);
    const gate = idx(b, /v_err := [^;]*competition\.gate\('competition_[a-z_]+', \d+, \d+\)/);
    const stop = idx(b, /IF v_err IS NOT NULL THEN RETURN jsonb_build_object\('error', v_err\); END IF;/);
    const data = idx(b, /FROM competition\.(registrations|editions)/);
    assert.ok(gate >= 0 && stop > gate && data > stop, `${fn}: o portão (IP + limite) tem de vir antes de ler dado`);
  }
});

test('#2529: link só vale dentro da validade, e o conteúdo do e-mail só sai para link válido DESTA inscrição', () => {
  assert.match(inner('registration_by_token'), /t\.token_hash = competition\.token_hash\(p_token\) AND t\.expires_at > now\(\)/);
  assert.match(body('_competition_email_payload'), /WHERE r\.id = p_registration_id AND r\.id = competition\.registration_by_token\(p_token\)/);
});

// ── H2/H3: entrada ─────────────────────────────────────────────────────────────────────────
test('#2529 H2/H3: corpo pequeno, e-mail estrito, sem caractere de controle', () => {
  const n = inner('normalize_answers');
  assert.match(n, /IF jsonb_typeof\(p_payload\) IS DISTINCT FROM 'object' OR octet_length\(p_payload::text\) > 8192 THEN\s+RAISE EXCEPTION 'competition:payload_invalid';/);
  assert.match(n, /v_email_re constant text := '\^\[a-z0-9\._%\+-\]\{1,64\}@\(\[a-z0-9-\]\+\\\.\)\+\[a-z\]\{2,63\}\$';/);
  assert.match(n, /IF v_email IS NULL OR char_length\(v_email\) > 254 OR v_email !~ v_email_re THEN\s+RAISE EXCEPTION 'competition:email_invalid:email';/);
  assert.match(n, /IF v_val ~ '\[\[:cntrl:\]<>\]' THEN\s+RAISE EXCEPTION 'competition:text_invalid:%', v_key;/);
  // campo com lista (origem, canal) só aceita um dos valores da versão do formulário
  assert.match(n, /IF jsonb_typeof\(f->v_key->'options'\) = 'array'\s+AND NOT EXISTS \(SELECT 1 FROM jsonb_array_elements\(f->v_key->'options'\) o WHERE o->>'value' = v_val\) THEN\s+RAISE EXCEPTION 'competition:option_invalid:%', v_key;/);
});

test('#2529 H3: erro de validação e violação de CHECK viram resposta com código, nunca erro cru', () => {
  const reg = body('competition_register');
  assert.match(reg, /EXCEPTION WHEN raise_exception OR invalid_text_representation OR check_violation THEN\s+RETURN competition\.invalid_response\(SQLERRM\);/);
  assert.match(body('competition_registration_update'), /EXCEPTION WHEN raise_exception OR invalid_text_representation OR check_violation THEN\s+RETURN competition\.invalid_response\(SQLERRM\);/);
});

// ── desistência, lista, permissões, limpeza ────────────────────────────────────────────────
test('#2529 M3: desistir revoga o consentimento DESTA inscrição e mata os links', () => {
  const w = body('competition_registration_withdraw');
  assert.match(w, /UPDATE public\.consent_records SET revoked_at = now\(\), revocation_reason = 'competition_withdraw'\s+WHERE email_hash = competition\.email_hash\(r\.email\) AND revoked_at IS NULL\s+AND evidence->>'source' = 'competition' AND evidence->>'registration_id' = r\.id::text;/);
  assert.match(w, /DELETE FROM competition\.registration_tokens WHERE registration_id = r\.id;/);
});

test('#2529 M2: a lista de quem organiza exige manage_platform e deixa de fora a inscrição não confirmada', () => {
  const l = body('competition_registrations_list');
  assert.match(l, /IF v_member IS NULL OR NOT public\.can_by_member\(v_member, 'manage_platform'\) THEN\s+RAISE EXCEPTION/);
  assert.match(l, /FROM competition\.registrations r\s+WHERE r\.edition_id = e\.id AND r\.status <> 'pending_confirmation'\) x;/);
  assert.match(l, /WHERE r\.edition_id = e\.id AND r\.leader_email IS NOT NULL\s+AND r\.status IN \('submitted', 'valid', 'selected', 'waitlisted', 'not_selected'\)/);
  assert.match(l, /'competition_registrations_list', 'edition=' \|\| e\.slug \|\| ' rows=' \|\| v_n, 'human'\);/);
});

test('#2529 L1: toda função da camada fecha o search_path', () => {
  const heads = LAYER.split(/\bCREATE FUNCTION\b/).slice(1).map((s) => s.slice(0, s.indexOf('AS $function$')));
  assert.ok(heads.length >= 22);
  const open = heads.filter((h) => !/SET search_path TO 'pg_catalog', 'pg_temp'\s*$/.test(h));
  assert.deepEqual(open.map((h) => h.split('(')[0].trim()), [], 'função com search_path aberto');
});

test('#2529 L2: EXECUTE fechado em todo o schema, DEPOIS da última função criada', () => {
  const revoke = LAYER.lastIndexOf('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA competition FROM PUBLIC, anon, authenticated;');
  const lastFn = LAYER.lastIndexOf('CREATE FUNCTION competition.');
  assert.ok(revoke > lastFn && lastFn >= 0, 'a revogação tem de vir depois da última função do schema');
  assert.match(LAYER, /REVOKE ALL ON FUNCTION public\._competition_email_payload\(uuid, text\) FROM PUBLIC, anon, authenticated;\s+GRANT EXECUTE ON FUNCTION public\._competition_email_payload\(uuid, text\) TO service_role;/);
  assert.match(LAYER, /REVOKE ALL ON FUNCTION public\.competition_registrations_list\(text\) FROM PUBLIC, anon;\s+GRANT EXECUTE ON FUNCTION public\.competition_registrations_list\(text\) TO authenticated, service_role;/);
});

test('#2529: a limpeza tem o MESMO nome no cron e no registro de retenção, e só apaga fora do modo seco', () => {
  const cron = /SELECT cron\.schedule\('([a-z-]+)', '[^']+', 'SELECT competition\.purge\(p_dry_run := false\);'\);/.exec(LAYER);
  const pol = /INSERT INTO public\.data_retention_policy \(table_name, retention_days, cleanup_type, description, is_active, executor\)\s+VALUES \('competition\.registrations', 2, 'delete',[\s\S]*?true, '([a-z-]+)'\);/.exec(LAYER);
  assert.ok(cron && pol, 'cron ou registro de retenção ausente');
  assert.equal(pol[1], cron[1], 'o executor declarado não é o job agendado');
  assert.match(inner('purge'), /IF p_dry_run THEN\s+SELECT count\(\*\) INTO v_pending[\s\S]*?ELSE\s+DELETE FROM competition\.registrations\s+WHERE status = 'pending_confirmation' AND submitted_at < now\(\) - interval '48 hours';/);
});

// ── front e e-mail: o token só no fragmento ────────────────────────────────────────────────
test('#2529: o link do e-mail leva o token no fragmento, e a página o tira da barra de endereço', () => {
  const ef = maskJsComments(read('supabase/functions/send-competition-email/index.ts'));
  assert.match(ef, /\/minha-inscricao#t=\$\{encodeURIComponent\(token\)\}/);
  assert.doesNotMatch(ef, /[?&]t=\$\{/, 'token em query string vai para log de servidor e Referer');
  const page = maskJsComments(read('src/pages/competicoes/[slug]/minha-inscricao.astro'));
  assert.match(page, /if \(fromHash\) \{[\s\S]{0,200}?history\.replaceState\(null, '', location\.pathname \+ location\.search\);\s*\}/);
  assert.match(page, /<meta name="robots" content="noindex, nofollow" \/>/);
});
