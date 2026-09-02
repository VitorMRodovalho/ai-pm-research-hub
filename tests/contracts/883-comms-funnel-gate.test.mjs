/**
 * #883 Onda A - get_comms_to_adoption_funnel security hygiene.
 *
 * Audit: docs/strategy/883_comms_audit_and_spec.md. Migration 20260805000331:
 *   A1. REVOKE anon (the body already fail-closes on auth.uid() NULL; the anon grant was noise).
 *   A2. Add can_view_comms_analytics() to the gate so the comms team sees its own funnel.
 *
 * REESCRITO EM 02/09/2026 (#2142), E O MOTIVO IMPORTA.
 *
 * A versao anterior fixava o arquivo `20260805000331_883_onda_a_comms_funnel_gate.sql` e afirmava
 * sobre o TEXTO dele. Quando a #2142 reescreveu a funcao, o guard passou a descrever um corpo que
 * producao nao executa mais, e o ratchet do #1932 o pegou. Agora ele resolve pela captura MAIS
 * RECENTE, entao reescrever a funcao move o guard junto.
 *
 * ENDURECIDO EM 02/09/2026 (#2149): A LINHA DE ACL AGORA AFIRMA O EFEITO, NAO O TEXTO.
 *
 * O guard original afirmava que a linha `REVOKE EXECUTE ... FROM anon` existia no arquivo. Ela
 * existia, e era INUTIL: a ACL viva era `=X/postgres`, isto e, PUBLIC mantinha EXECUTE e `anon`
 * herdava de PUBLIC. Revogar de `anon` nao tira o que PUBLIC concede. Aquele guard media a
 * PRESENCA DE UMA LINHA, nao o EFEITO dela, e por isso ficou verde por um mes sobre uma falsidade.
 *
 * A #2142 fez a coisa honesta no meio do caminho: parou de afirmar o que nao era verdade, e
 * deixou registrado que fechar a lacuna mudava permissao em producao e estava com o dono. O dono
 * decidiu em 02/09. A migration `20260902203143` revogou de PUBLIC e de anon nas DUAS funcoes, e
 * agora este guard afirma o estado vivo do PRIVILEGIO, via `_audit_function_execute_acl()`.
 *
 * POR QUE `resolve_default_gates` ENTRA NUM ARQUIVO CHAMADO 883: as duas foram apertadas pela
 * mesma migration e pela mesma razao, e a segunda so precisou existir porque tinha um GRANT
 * EXPLICITO a anon alem do PUBLIC — `REVOKE FROM PUBLIC` sozinho nao a fecharia. Separar os dois
 * casos em arquivos diferentes esconderia exatamente a assimetria que fez a #2149 nao ser um
 * one-liner.
 *
 * Contrato estatico (captura mais recente) + estado vivo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const FN = latestFunctionCapture(ROOT, 'get_comms_to_adoption_funnel');

const URL_ = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(URL_ && KEY);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';

test('#883 A2: o portao mantem os tres niveis mais o de comms', () => {
  assert.match(FN.body, /OR public\.can_view_comms_analytics\(\)\) THEN/,
    'o nivel de comms-analytics tem de continuar no OR');
  assert.match(FN.body, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/,
    'nivel internal-analytics preservado');
  assert.match(FN.body, /can_by_member\(v_caller_id, 'view_aggregate_analytics'\)/,
    'nivel aggregate preservado');
  assert.match(FN.body, /can_by_member\(v_caller_id, 'manage_platform'\)/,
    'nivel manage_platform preservado');
});

test('#883 A1: o corpo continua fail-closed antes de qualquer leitura', () => {
  assert.match(FN.body, /IF v_caller_id IS NULL THEN\s*\n\s*RETURN jsonb_build_object\('error', 'Unauthorized'\)/,
    'auth.uid() NULL tem de sair por Unauthorized ANTES de tocar em dado');
  // O portao de autoridade tem de vir antes da primeira agregacao, senao ele decora em vez de barrar.
  const posGate = FN.body.indexOf('can_view_comms_analytics');
  const posDado = FN.body.indexOf('FROM public.comms_metrics_daily');
  assert.ok(posGate > -1 && posDado > -1, 'ancoras nao encontradas no corpo');
  assert.ok(posGate < posDado, 'o portao tem de preceder a primeira leitura de dado');
});

test('#883: a assinatura nao muda de forma (DROP+CREATE mudaria o contrato)', () => {
  assert.match(FN.block, /CREATE OR REPLACE FUNCTION public\.get_comms_to_adoption_funnel\(p_period_days integer DEFAULT 30\)/);
  assert.doesNotMatch(FN.block, /DROP FUNCTION/);
  assert.match(FN.block, /RETURNS jsonb/);
});

test(dbGated ? '#883 vivo: a ACL de escrita/leitura confere, e o controle discrimina' : `SKIP: ${skipMsg}`,
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(URL_, KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
  assert.equal(error, null, error?.message);
  // CONTROLE POSITIVO: a funcao existe entre as vivas. Sem isto, tudo acima valeria sobre arquivo.
  const viva = (data ?? []).find((r) => r.proname === 'get_comms_to_adoption_funnel');
  assert.ok(viva, `funcao ausente entre as ${data?.length ?? 0} vivas`);
  assert.equal(viva.is_secdef, true, 'a funcao tem de seguir SECURITY DEFINER');
});

/**
 * #2149: O PRIVILEGIO, NAO O TEXTO.
 *
 * Este e o teste que o guard textual nao conseguia escrever. Ele pergunta ao catalogo
 * (`has_function_privilege`, via `_audit_function_execute_acl`) e nao ao arquivo de migration.
 * Se alguem reabrir a funcao para PUBLIC — por um `GRANT ... TO PUBLIC`, ou recriando a funcao
 * com CREATE em vez de CREATE OR REPLACE, que nasce aberta — este teste fica vermelho, e o
 * anterior nao ficaria.
 */
test(dbGated ? '#2149: anon NAO executa as duas RPCs, e authenticated continua executando' : `SKIP: ${skipMsg}`,
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(URL_, KEY, { auth: { persistSession: false } });

  const ALVOS = ['get_comms_to_adoption_funnel', 'resolve_default_gates'];
  // O terceiro nome e o CONTROLE: funcao de auditoria sabidamente ABERTA a anon, fora do escopo
  // da #2149. Sem ele, uma sonda que devolvesse `false` para tudo (nome errado, RPC quebrada,
  // array vazio) deixaria as duas afirmacoes de baixo passarem por vacuidade — que e a forma
  // exata como o defeito de origem sobreviveu um mes.
  const CONTROLE = '_audit_list_public_function_bodies';

  const { data, error } = await sb.rpc('_audit_function_execute_acl', {
    p_names: [...ALVOS, CONTROLE],
  });
  assert.equal(error, null, `_audit_function_execute_acl indisponivel: ${error?.message ?? ''}`);

  const porNome = new Map((data ?? []).map((r) => [r.proname, r]));

  // CONTROLE PRIMEIRO: se ele nao for TRUE, a sonda nao discrimina e nada abaixo vale.
  const ctl = porNome.get(CONTROLE);
  assert.ok(ctl, `controle ${CONTROLE} ausente: a sonda devolveu ${data?.length ?? 0} linhas`);
  assert.equal(ctl.anon_exec, true,
    'o controle deixou de ser executavel por anon: ou a sonda quebrou, ou a #2149 revogou fora do escopo');

  for (const nome of ALVOS) {
    const r = porNome.get(nome);
    assert.ok(r, `${nome} ausente na leitura de ACL`);
    assert.equal(r.anon_exec, false,
      `${nome} voltou a ser executavel por anon (ACL reaberta a PUBLIC ou a anon)`);
    // A outra ponta: apertar demais quebraria a tela de admin, e o sintoma seria "nada aparece",
    // que demora a ser lido como problema de permissao.
    assert.equal(r.authenticated_exec, true,
      `${nome} perdeu EXECUTE para authenticated: o REVOKE fechou alem do pretendido`);
  }
});
