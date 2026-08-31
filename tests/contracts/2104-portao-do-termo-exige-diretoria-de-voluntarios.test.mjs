// tests/contracts/2104-portao-do-termo-exige-diretoria-de-voluntarios.test.mjs
//
// #2104 itens 1 e 2. Regra do PM (30/08/2026): o Termo de Adesão ao Serviço Voluntário é
// contra-assinado pela diretoria de voluntários do capítulo contratante; a presidência entra SÓ
// quando precisa escalar.
//
// MEDIDO EM PRODUÇÃO ANTES DA MIGRATION:
//   portão de então .............. 9 pessoas (2 por manage_member + 7 por board do contratante)
//   diretoria de voluntários ..... 1 titular, do contratante
//   presidência do contratante ... 1 (chapter_board + legal_signer), 1 de 5 no país
//
// ⚠️ O QUE ESTE GUARD EXISTE PARA PEGAR, e é o oposto do óbvio.
// `counter_sign_certificate` contra-assina CINCO tipos (volunteer_agreement 96, participation 46,
// excellence 14, alumni_recognition 11, contribution 4) e não filtrava por nenhum. O risco desta
// mudança nunca foi "o Termo ficou frouxo": foi "o estreitamento derrubou os outros 75". Por isso
// a asserção de vizinho abaixo vale tanto quanto a de restrição.
//
// Este arquivo afirma o INVARIANTE CORRENTE, então resolve a captura mais nova via
// `latestFunctionCapture` em vez de fixar um arquivo de migration (#1932). Fixar aqui envelheceria
// no próximo `CREATE OR REPLACE` e o guard seguiria verde descrevendo um corpo que a produção não
// executa mais.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = new URL('../..', import.meta.url).pathname;
const FN = 'counter_sign_certificate';

const capture = latestFunctionCapture(ROOT, FN);
const body = capture?.block ?? '';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

describe('#2104 itens 1 e 2 — estático', () => {
  it('controle de vacuidade: a captura mais nova de counter_sign_certificate foi encontrada', () => {
    assert.ok(capture, `nenhuma captura de ${FN} nas migrations`);
    assert.ok(body.length > 1000, `captura suspeita de vazia: ${body.length} chars`);
  });

  it('item 1: o portão do Termo exige voluntariado_director', () => {
    assert.match(body, /'voluntariado_director'\s*=\s*ANY\(v_caller_designations\)/,
      'a via ordinária do Termo tem de exigir a designação da diretoria de voluntários');
  });

  it('item 1: o estreitamento é ESCOPADO ao Termo, senão derruba os outros 4 tipos', () => {
    assert.match(body, /IF\s+v_cert\.type\s*=\s*'volunteer_agreement'\s+THEN/,
      'sem o escopo por tipo, o estreitamento atinge participation/excellence/alumni_recognition/contribution');
  });

  it('item 1: manage_member deixou de ser via de contra-assinatura DO TERMO', () => {
    const bloco = body.split("IF v_cert.type = 'volunteer_agreement' THEN")[1]?.split('ELSE')[0] ?? '';
    assert.ok(bloco.length > 200, 'não consegui isolar o ramo do Termo');
    assert.ok(!/v_is_manage_member/.test(bloco),
      'manage_member não pode aparecer como via de autorização dentro do ramo do Termo');
  });

  it('item 2: o veto de auto-contra-assinatura existe e vale para TODA rota', () => {
    assert.match(body, /v_cert\.member_id\s*=\s*v_caller_id/,
      'sem esta checagem a mesma pessoa ocupa os dois polos do instrumento');
    assert.match(body, /cannot_counter_sign_own_term/);
    const ramo = body.split("IF v_cert.type = 'volunteer_agreement' THEN")[1] ?? '';
    const posVeto = ramo.indexOf('cannot_counter_sign_own_term');
    const posRota = ramo.indexOf('v_caller_is_contracting');
    assert.ok(posVeto > -1 && posRota > -1 && posVeto < posRota,
      'o veto tem de vir ANTES da escolha de rota, ou a presidência escaparia dele');
  });

  it('item 2: a escalada cobre o caso nomeado E a vacância', () => {
    assert.match(body, /v_holder_is_director/, 'caso (a): o Termo é da própria diretoria');
    assert.match(body, /v_director_vacant/,    'caso (b): sem titular ativo a fila travaria inteira');
    assert.match(body, /president_escalation/,  'a rota escalada tem de ser nomeada no log');
  });

  it('derivação, não literal: nenhum código de capítulo no CÓDIGO do ramo do Termo', () => {
    const ramo = (body.split("IF v_cert.type = 'volunteer_agreement' THEN")[1] ?? '')
      .split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
    assert.ok(!/'PMI-[A-Z]{2}'/.test(ramo),
      'o capítulo contratante é resolvido por is_contracting_chapter, nunca por literal');
    assert.match(ramo, /is_contracting_chapter/);
  });

  it('a rota que autorizou entra no audit log', () => {
    assert.match(body, /'authority_route'/,
      'sem isto a escalada é indistinguível da via ordinária no log, e é ela que alguém vai auditar');
  });
});

describe('#2104 itens 1 e 2 — DB-aware (skip sem env)', () => {
  // O invariante que importa e que sobrevive a mudanca de gente: o conjunto NOVO tem de ser
  // subconjunto ESTRITO do antigo. Afirmar "sao 1 e eram 9" quebraria na proxima nomeacao e
  // ensinaria a proxima pessoa a atualizar o numero em vez de pensar.
  it('o conjunto autorizado ENCOLHEU: o novo e subconjunto estrito do antigo', { skip: !sb }, async () => {
    const { data: membros, error: e1 } = await sb
      .from('members').select('id, person_id, chapter, designations, is_active');
    assert.equal(e1, null, e1?.message);

    const { data: eng, error: e2 } = await sb
      .from('auth_engagements').select('person_id, kind, status').eq('kind', 'chapter_board').eq('status', 'active');
    assert.equal(e2, null, e2?.message);

    const { data: reg, error: e3 } = await sb
      .from('chapter_registry').select('chapter_code, is_contracting_chapter').eq('is_contracting_chapter', true);
    assert.equal(e3, null, e3?.message);

    assert.ok((reg ?? []).length >= 1, 'controle de vacuidade: nenhum capitulo contratante no registry');
    const contratante = new Set((reg ?? []).map((r) => `PMI-${r.chapter_code}`));
    const boardAtivo = new Set((eng ?? []).map((e) => e.person_id));

    const temDesig = (m, d) => (m.designations ?? []).includes(d);

    // conjunto ANTIGO: board do contratante (a via que a #2104 estreitou).
    const antigo = (membros ?? []).filter((m) => boardAtivo.has(m.person_id) && contratante.has(m.chapter));
    // conjunto NOVO: diretoria de voluntarios do contratante, mais a presidencia do contratante
    // (que so age nos dois casos de escalada, entao e teto).
    const novo = (membros ?? []).filter((m) => contratante.has(m.chapter)
      && (temDesig(m, 'voluntariado_director')
          || (temDesig(m, 'chapter_board') && temDesig(m, 'legal_signer'))));

    assert.ok(antigo.length > 0, 'controle de vacuidade: conjunto antigo vazio, a comparacao nao discriminaria');
    assert.ok(novo.length > 0, 'sem ninguem no conjunto novo a fila do Termo travaria inteira');

    const idsAntigo = new Set(antigo.map((m) => m.id));
    const foraDoAntigo = novo.filter((m) => !idsAntigo.has(m.id));
    assert.deepEqual(foraDoAntigo.map((m) => m.chapter), [],
      'o portao novo NAO pode autorizar quem o antigo ja nao autorizava: isso seria alargamento');
    assert.ok(novo.length < antigo.length,
      `o portao tinha de ENCOLHER: antigo=${antigo.length} novo=${novo.length}`);
  });

  it('ha titular da diretoria de voluntarios, senao so a vacancia sustenta a fila', { skip: !sb }, async () => {
    const { data, error } = await sb.from('members').select('chapter, designations, is_active');
    assert.equal(error, null, error?.message);
    const dir = (data ?? []).filter((m) => (m.designations ?? []).includes('voluntariado_director') && m.is_active);
    assert.ok(dir.length >= 1,
      'zero titulares ativos: a via ordinaria fica vazia e TODA contra-assinatura passa a depender da escalada por vacancia');
  });
});
