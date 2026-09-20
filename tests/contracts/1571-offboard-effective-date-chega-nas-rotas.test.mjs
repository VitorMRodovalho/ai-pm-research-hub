/**
 * #1571 - a data efetiva do offboard tem de CHEGAR, nas tres rotas que escrevem.
 *
 * Origem (#1570, 03/08/2026): `offboard_member` declarava `p_effective_date` e o corpo era um
 * wrapper que chamava `admin_offboard_member` SEM repassa-lo. O valor era aceito, ignorado, e a
 * funcao devolvia `success: true`. O destino mais grave e o TEXTO do certificado alumni, que e
 * documento entregue ao voluntario e usado em perfil profissional.
 *
 * Medido em 20/09/2026: a correcao do banco funciona (tres registros de 11/09 com data efetiva
 * distinta da data de registro, um retroagido 58 dias), mas TRES rotas ainda carimbavam hoje:
 * as duas superficies MCP (`offboard_member` raw e `member_lifecycle action='offboard'`) e
 * `offboard_member_with_handoffs`.
 *
 * FORMA DA ASSERCAO: cada afirmacao recorta o BLOCO que decide e amarra a condicao ao resultado.
 * Um `includes('p_effective_date')` sobre o arquivo inteiro ficaria verde com o parametro removido
 * da chamada, porque a string sobrevive no schema e nos comentarios - que e exatamente o defeito
 * que #2335/#2286/#2341 documentaram. Comentarios sao mascarados antes de medir.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const R = (p) => { const f = join(__dirname, p); return existsSync(f) ? readFileSync(f, 'utf8') : ''; };

const MCP = maskJsComments(R('../../supabase/functions/nucleo-mcp/index.ts'));

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = url && key ? createClient(url, key) : null;

/** Recorta o objeto rpcArgs/params de uma chamada, a partir de uma ancora unica. */
function blocoApos(src, ancora, chars = 400) {
  const i = src.indexOf(ancora);
  assert.ok(i >= 0, `ancora nao encontrada no fonte: ${ancora}`);
  return src.slice(i, i + chars);
}

test('#1571 estatico: o tool RAW offboard_member repassa p_effective_date NA CHAMADA', () => {
  const bloco = blocoApos(MCP, 'await sb.rpc("admin_offboard_member", {');
  assert.match(
    bloco,
    /p_reassign_to:[^}]*?p_effective_date:\s*efd\.value/s,
    'o tool raw chama admin_offboard_member sem p_effective_date: a data volta a ser hoje, ' +
      'inclusive no texto do certificado alumni.',
  );
});

test('#1571 estatico: member_lifecycle action=offboard repassa p_effective_date NOS rpcArgs', () => {
  const bloco = blocoApos(MCP, 'rpc = "admin_offboard_member"; rpcArgs = {');
  assert.match(
    bloco,
    /p_reassign_to:[^}]*?p_effective_date:\s*efd\.ok\s*\?\s*efd\.value\s*:\s*null/s,
    'a rota semantica monta rpcArgs sem p_effective_date.',
  );
});

test('#1571 estatico: data invalida e RECUSADA, nao silenciosamente virada em NULL', () => {
  assert.match(MCP, /function parseEffectiveDate\(/, 'o validador nao existe');
  const bloco = blocoApos(MCP, 'function parseEffectiveDate(', 1200);
  assert.match(bloco, /ok:\s*false[^}]*must be an ISO date/s, 'formato invalido tem de falhar');
  assert.match(bloco, /is in the future/, 'data futura tem de falhar');
  assert.match(bloco, /return\s*\{\s*ok:\s*true,\s*value:\s*null\s*\}/,
    'ausencia (undefined/null/"") continua valida e significa "hoje"');
});

test('#1571 estatico: a migration da rota com handoffs repassa a data NA CHAMADA', () => {
  const mig = R('../../supabase/migrations/20260920143732_1571_offboard_com_handoffs_repassa_data_efetiva.sql');
  assert.ok(mig.length > 0, 'a migration do #1571 nao esta na arvore');
  const corpo = mig.replace(/--[^\n]*/g, ''); // mascara comentario de linha SQL
  assert.match(
    corpo,
    /admin_offboard_member\([^)]*p_reason_detail,\s*NULL,\s*p_effective_date\)/s,
    'a rota com handoffs chama admin_offboard_member sem a data efetiva',
  );
  // DROP + CREATE, e nao CREATE OR REPLACE: mudar a contagem de parametros com REPLACE cria
  // SOBRECARGA em vez de substituir, e duas versoes da mesma funcao e o defeito a evitar.
  assert.match(corpo, /DROP FUNCTION IF EXISTS public\.offboard_member_with_handoffs\(/,
    'mudanca de contagem de parametro exige DROP + CREATE');
  // O DROP leva os grants junto, e CREATE FUNCTION nasce com EXECUTE para PUBLIC.
  const revoke = R('../../supabase/migrations/20260920143750_1571_revoga_public_anon_que_o_create_function_reintroduziu.sql');
  assert.match(revoke, /REVOKE EXECUTE ON FUNCTION public\.offboard_member_with_handoffs\([^)]*\) FROM PUBLIC/,
    'sem o REVOKE, o DROP + CREATE deixa a funcao executavel por PUBLIC/anon');
});

test('#1571 vivo: as tres rotas declaram p_effective_date na assinatura', { skip: !sb }, async () => {
  // Sem .catch() encadeado: PostgrestBuilder e thenable, nao Promise, e .catch() lanca.
  // O catalogo devolve proname/identity_args/body_md5 - NAO devolve corpo. Por isso a afirmacao
  // viva e sobre a ASSINATURA, e a afirmacao sobre o corpo fica no teste estatico acima, sobre a
  // migration. O drift entre migration e corpo vivo e coberto pelo gate de Fase C.
  const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
  assert.equal(error, null, `nao consegui ler o catalogo: ${error?.message}`);
  assert.ok(Array.isArray(data) && data.length > 0,
    'catalogo vazio - o teste nao pode passar por vacuidade');

  const args = (nome) => {
    const fn = data.find((r) => r.proname === nome);
    assert.ok(fn, `${nome} nao esta no catalogo`);
    return String(fn.identity_args ?? '');
  };

  for (const nome of ['offboard_member', 'admin_offboard_member', 'offboard_member_with_handoffs']) {
    assert.match(args(nome), /p_effective_date date/,
      `${nome} nao declara p_effective_date: esta rota volta a carimbar a data de hoje`);
  }

  // CONTROLE NEGATIVO do instrumento: nome inventado tem de estar ausente, senao o find mente.
  assert.equal(data.find((r) => r.proname === 'funcao_que_nao_existe_1571'), undefined,
    'o catalogo respondeu por uma funcao inventada - o instrumento nao discrimina');
});
