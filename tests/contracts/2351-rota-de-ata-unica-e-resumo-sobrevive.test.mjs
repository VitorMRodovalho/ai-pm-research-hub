/**
 * #2351 — a rota de ata: uma superficie so, e o resumo que para de evaporar.
 *
 * DOIS defeitos, medidos em 17/09 na fonte viva (pg_proc + index.ts), nao lidos de doc:
 *
 * 1. DADO — `meeting_close` so anexava `p_summary` dentro de `IF NOT v_already_closed`.
 *    Como `upsert_event_minutes` (rota `meeting_minutes action='write'`) carimba
 *    `minutes_posted_at` na PRIMEIRA ata, a sequencia natural write -> close caia sempre
 *    no ramo ELSE, que so gravava `suggested_champion_ids`. O resumo sumia retornando
 *    `success: true`.
 *
 *    Exercicio de 17/09 (impersonacao + BEGIN/ROLLBACK, os DOIS sentidos, ANTES do conserto):
 *      braco A (ja fechada)         -> summary_appended=false, notes=0 chars, canario AUSENTE
 *      braco B (mesma fn/evento/chamador, NAO fechada) -> summary_appended=true, notes=80 chars
 *    A unica diferenca entre os bracos era o estado fechado. Com o conserto, A passa a
 *    casar com B.
 *
 *    Isso bloqueava a reconciliacao de atas: 253 de 317 reunioes de tribo estao sem ata
 *    (medido 17/09, #2352) e a importacao e item a item, entao seria um resumo perdido
 *    por ata, em silencio.
 *
 * 2. AMBIGUIDADE — `meeting_minutes` declara na propria descricao que absorve
 *    `create_meeting_notes`, `meeting_close`, `get_meeting_notes` e `get_meeting_preparation`,
 *    e as QUATRO seguiam registradas. Eram 8 tools com `meeting` no nome e nenhuma forma de
 *    um agente saber qual e a canonica — e DUAS rotas para fechar significam DUAS superficies
 *    para o defeito 1. Precedente do repo: `get_agenda_smart` foi absorvida e REMOVIDA
 *    (migration 457), com guard em semantic-envelope-w3 impedindo que volte.
 *
 * FORMA DAS ASSERCOES (CLAUDE.md, secao de 17/09): asserção amarra CONDICAO ao RESULTADO
 * dentro do bloco que decide. Presenca de string num corpo de centenas de linhas fica verde
 * com o mecanismo removido — em 17/09 isso aconteceu tres vezes. Por isso aqui:
 *   - a lista de absorvidas e DERIVADA da descricao da propria tool, nunca uma lista de nomes
 *     escrita a mao (uma lista apodrece e passa a medir um universo menor do que existe);
 *   - o corpo de `meeting_close` e recortado no ramo ELSE (o que decide) antes de afirmar;
 *   - a prova de banco e EXERCIDA, com controle positivo, nao leitura de catalogo.
 *
 * Registrado em AMBAS as whitelists de package.json (test:behavioural + test:contracts) — #1109.
 *
 * Cross-ref: #2351, #2352 (inventario), ADR-0049, semantic-envelope-w3, #1383 W3.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const EF = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

/** Nomes registrados como tool MCP. A quebra de linha apos `mcp.tool(` e o estilo das semanticas. */
function registeredTools(src) {
  return new Set([...src.matchAll(/mcp\.tool\(\s*\n?\s*"([A-Za-z0-9_]+)"/g)].map((m) => m[1]));
}

/** Descricao declarada de uma tool (primeiro literal apos o nome). */
function toolDescription(src, name) {
  const re = new RegExp(`mcp\\.tool\\(\\s*\\n?\\s*"${name}"\\s*,\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = src.match(re);
  assert.ok(m, `tool ${name} nao encontrada, ou a descricao nao e um literal de string`);
  return m[1];
}

// ── Defeito 2: absorcao declarada tem de valer no registro, nao so na prosa ───────────────

test('#2351: as tools que `meeting_minutes` DECLARA absorver nao seguem registradas', () => {
  const desc = toolDescription(EF, 'meeting_minutes');
  const clause = desc.match(/absorbs\s+([^)—]+)/);
  assert.ok(clause, 'meeting_minutes deve declarar `absorbs ...` na descricao — e dela que esta lista sai');

  // Nomes snake_case completos; fragmentos de abreviacao com barra ("create/update_x") ficam de fora.
  const declared = [...new Set(clause[1].match(/\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b/g) || [])];
  assert.ok(
    declared.length >= 4,
    `a clausula de absorcao ficou com ${declared.length} nomes — se ela mudar de forma, este guard ` +
      'mede um universo vazio e passa sem afirmar nada (ver "gate por string fica vazio ou acusa todo mundo")',
  );

  const registered = registeredTools(EF);
  const aindaRegistradas = declared.filter((n) => n !== 'meeting_minutes' && registered.has(n));
  assert.deepEqual(
    aindaRegistradas,
    [],
    `absorcao tem de estar no REGISTRO, nao so na descricao. Seguem registradas: ${aindaRegistradas.join(', ')}`,
  );
});

test('#2351: absorver e ROTEAR, nao apagar — as 3 RPCs continuam despachadas por meeting_minutes', () => {
  // O oposto do teste acima, e o que o impede de ser satisfeito deletando a funcionalidade:
  // as rotas read/prepare/write/close precisam continuar chegando nas RPCs.
  //
  // ⚠️ A primeira versao usava uma JANELA FIXA (`{0,1200}`) entre o discriminador e o sb.rpc.
  // Isso quebrou no mesmo dia, ao portar a quarentena do #170 para o ramo de escrita: o
  // comentario que explica o porte empurrou o sb.rpc para fora da janela. Janela fixa mede
  // distancia, nao pertencimento — e, na direcao contraria, uma janela folgada acaba casando
  // a chamada do ramo VIZINHO. O recorte por ramo nao tem nenhum dos dois problemas.
  const start = EF.indexOf('"meeting_minutes"');
  assert.ok(start !== -1, 'meeting_minutes registrada');
  const end = EF.indexOf('mcp.tool(', start + 1);
  const bloco = maskJsComments(EF.slice(start, end === -1 ? EF.length : end));

  // Fronteiras reais: cada ramo vai do seu discriminador ate o proximo.
  const cortes = [...bloco.matchAll(/params\.action === "([a-z_]+)"/g)].map((m) => ({ acao: m[1], at: m.index }));
  assert.ok(cortes.length >= 4, `esperava os 4 ramos read/prepare/write/close, achei ${cortes.length}`);
  const ramo = (acao) => {
    const i = cortes.findIndex((c) => c.acao === acao);
    assert.ok(i !== -1, `ramo action='${acao}' nao encontrado`);
    return bloco.slice(cortes[i].at, i + 1 < cortes.length ? cortes[i + 1].at : bloco.length);
  };

  for (const [acao, rpc] of [
    ['prepare', 'get_meeting_preparation'],
    ['write', 'upsert_event_minutes'],
    ['close', 'meeting_close'],
  ]) {
    assert.match(
      ramo(acao),
      new RegExp(`sb\\.rpc\\(\\s*"${rpc}"`),
      `meeting_minutes action='${acao}' tem de despachar ${rpc} DENTRO do proprio ramo`,
    );
  }
});

// ── Defeito 1 (estatico): o ramo que DECIDE anexa o resumo ────────────────────────────────

test('#2351 estatico: no ramo de reuniao JA FECHADA, o close grava o resumo em notes', () => {
  const cap = latestFunctionCapture(ROOT, 'meeting_close');
  const body = maskLineComments(cap.body); // o anti-padrao sobrevive em comentario; mascare antes de medir

  // Recorta o bloco que decide: do ELSE do `IF NOT v_already_closed` ate o END IF.
  const ifIdx = body.search(/IF\s+NOT\s+v_already_closed\s+THEN/i);
  assert.ok(ifIdx !== -1, `o ramo IF NOT v_already_closed sumiu de ${cap.file}`);
  const elseIdx = body.indexOf('ELSE', ifIdx);
  const endIdx = body.indexOf('END IF;', elseIdx);
  assert.ok(elseIdx !== -1 && endIdx !== -1, 'ramo ELSE/END IF do fechamento nao encontrado');
  const ramoJaFechada = body.slice(elseIdx, endIdx);

  // CONDICAO amarrada ao RESULTADO, dentro do bloco, e CONTIGUAS.
  //
  // ⚠️ A primeira versao desta asserção era `SET\s+notes\s*=[\s\S]{0,300}?WHEN\s+v_summary_appended`,
  // com folga entre as duas metades — e a MUTACAO a pegou verde: neutralizar o append deixando
  // `SET notes = notes;` antes do CASE original satisfazia os dois pedacos em linhas diferentes.
  // A folga e que permitia isso, entao o `= CASE WHEN v_summary_appended` virou contiguo.
  assert.match(
    ramoJaFechada,
    /SET\s+notes\s*=\s*CASE\s+WHEN\s+v_summary_appended\b[\s\S]{0,400}?Meeting close summary/i,
    'o ramo de reuniao ja fechada tem de anexar o resumo em notes sob v_summary_appended — ' +
      'era exatamente isto que faltava e fazia o resumo evaporar (#2351)',
  );

  // Anti-duplicata: um close repetido com o MESMO texto nao pode reanexar o bloco.
  //
  // ⚠️ Mesma historia: com `[\s\S]{0,200}?` entre `v_summary_dup :=` e `position(`, a mutacao
  // `v_summary_dup := false AND (...)` passava VERDE — o `position(...)` sobrevivia adiante na
  // mesma expressao, ja sem efeito. A expressao inteira e afirmada de uma vez.
  assert.match(
    body,
    /v_summary_dup\s*:=\s*v_summary_in\s+IS\s+NOT\s+NULL\s+AND\s+position\s*\(\s*v_summary_in\s+in\s+COALESCE\s*\(\s*v_event\.notes\s*,\s*''\s*\)\s*\)\s*>\s*0\s*;/i,
    'a protecao anti-duplicata tem de comparar o resumo com notes ANTES de anexar',
  );
  assert.match(
    body,
    /v_summary_appended\s*:=\s*v_summary_in\s+IS\s+NOT\s+NULL\s+AND\s+NOT\s+v_summary_dup/i,
    'summary_appended tem de relatar o que ACONTECEU (resumo novo e nao-duplicado), nao em qual branch caiu',
  );
});

// ── Defeito 1 (exercido): camada VIVA, dois sentidos ──────────────────────────────────────

test('#2351 exercido: fechar reuniao JA FECHADA com resumo PRESERVA o resumo', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  // O helper roda os dois bracos sob impersonacao e desfaz tudo (sub-transacao que termina em RAISE).
  // Existe porque supabase-js nao consegue setar request.jwt.claims e chamar a RPC na MESMA transacao.
  const { data, error } = await sb.rpc('_test_meeting_close_summary_roundtrip');
  assert.equal(error, null, `exercicio falhou: ${error?.message}`);
  assert.ok(data, 'o helper de exercicio precisa devolver observacoes');

  // CONTROLE POSITIVO primeiro: se o braco B falhar, o instrumento esta quebrado e o braco A
  // nao prova nada — "nenhum resumo apareceu" leria como aprovacao.
  assert.equal(data.arm_b_control.already_closed, false, 'controle: o braco B tem de rodar com a reuniao ABERTA');
  assert.equal(data.arm_b_control.summary_appended, true, 'controle positivo: em reuniao aberta o resumo e anexado');
  assert.equal(data.arm_b_control.notes_has_canary, true, 'controle positivo: o canario B chega em events.notes');

  // O braco que a #2351 conserta.
  assert.equal(data.arm_a.already_closed, true, 'o braco A tem de rodar com a reuniao JA FECHADA');
  assert.equal(data.arm_a.summary_appended, true, 'reuniao ja fechada tem de ACEITAR o resumo (#2351)');
  assert.equal(
    data.arm_a.notes_has_canary,
    true,
    'o resumo tem de chegar em events.notes mesmo com a reuniao ja fechada — antes do conserto isto era false',
  );
});

test('#2351 exercido: o proprio exercicio nao deixa rastro em producao', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // Consulta NOVA (o helper ja retornou): a sub-transacao tem de ter voltado atras.
  const { count, error } = await sb
    .from('events')
    .select('id', { count: 'exact', head: true })
    .like('notes', '%__test_2351%');
  assert.equal(error, null, `contagem de canario falhou: ${error?.message}`);
  assert.equal(count, 0, 'o helper de exercicio escreveu em producao — a sub-transacao nao voltou atras');
});
