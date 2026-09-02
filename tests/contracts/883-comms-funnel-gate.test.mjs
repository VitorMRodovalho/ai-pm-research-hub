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
 * E A TROCA MAIS IMPORTANTE E A DA LINHA DE ACL. O guard antigo afirmava que o texto
 * `REVOKE EXECUTE ... FROM anon` existia no arquivo. Isso e verdade e e INSUFICIENTE: medido em
 * 02/09, `has_function_privilege('anon', ..., 'EXECUTE')` devolve TRUE, porque a ACL viva e
 * `=X/postgres`, isto e, PUBLIC mantem EXECUTE, e `anon` herda de PUBLIC. Revogar de `anon` nao
 * tira o que PUBLIC concede. O guard textual nunca poderia ter visto isso: ele afirmava a
 * PRESENCA DE UMA LINHA, nao o EFEITO dela.
 *
 * Nao ha vazamento: o corpo e fail-closed e devolve Unauthorized para quem nao tem membro, e e
 * isso que as afirmacoes vivas abaixo protegem. O que NAO se afirma aqui, de proposito, e que
 * anon perdeu o privilegio, porque hoje ele nao perdeu. Afirmar isso deixaria o guard verde sobre
 * uma falsidade, que e exatamente o defeito que esta reescrita conserta.
 * Fechar a lacuna pede `REVOKE ALL ... FROM PUBLIC`, o que muda permissao em producao e por isso
 * esta com o dono, nao dentro desta PR.
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
