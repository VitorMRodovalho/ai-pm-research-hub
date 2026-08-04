// tests/contracts/1584-governed-booking-door.test.mjs
//
// #1584 — Opção A: o token vira a única porta de agendamento de entrevista.
//
// O arco existe porque a porta governada tinha 0 tokens emitidos em 3 meses. Ao abri-la, esta
// sessão descobriu que ela não estava apenas SEM USO — estava QUEBRADA, com dois defeitos fatais
// independentes que só não apareceram porque ninguém nunca atravessou a porta:
//
//   (1) `validate_interview_booking_token` comparava `id::text = v_token_row.source_id`, e
//       `onboarding_tokens.source_id` é `uuid` desde a criação. Não existe `operator text = uuid`,
//       então TODA chamada levantava 42883.
//   (2) `_issue_interview_booking_token_core` (e antes dele a RPC pública) chamava
//       `gen_random_bytes(32)` sem qualificar, sob `SET search_path TO 'public'`. pgcrypto vive em
//       `extensions`, logo TODA emissão levantava 42883 também.
//
// Nenhum dos dois é pego por build, por lint ou por teste de assinatura: só por EXECUÇÃO. Daí a
// camada B abaixo afirmar contra o corpo VIVO, não contra o arquivo — um arquivo correto com um
// corpo vivo divergente é exatamente o modo de falha que o Phase C persegue.
//
// Camada A (estática, sempre roda): arquivo de migration + página + dicionários.
// Camada B (DB-aware, PULA sem SUPABASE_URL + SERVICE_ROLE_KEY): corpo vivo, ACL e resolução real.
//   ⚠️ um SKIP silencioso lê como verde. Conferir o número de skips, não só `fail 0`.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIGRATION_PATH = 'supabase/migrations/20260805000508_1584_opcao_a_porta_governada_agendamento.sql';
const PAGE_PATH = 'src/pages/interview-booking/[token].astro';
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];

const MIGRATION_SQL = existsSync(MIGRATION_PATH) ? readFileSync(MIGRATION_PATH, 'utf8') : '';
const PAGE_SRC = existsSync(PAGE_PATH) ? readFileSync(PAGE_PATH, 'utf8') : '';

/**
 * Remove comentários de linha SQL. Guard de AUSÊNCIA tem de olhar só o código: os comentários desta
 * migration citam nominalmente as construções defeituosas que ela corrige, e uma asserção sobre o
 * texto cru transformaria a própria documentação do defeito em falha.
 */
const stripSqlComments = (sql) => sql.replace(/^\s*--.*$/gm, '');
const MIGRATION_CODE = stripSqlComments(MIGRATION_SQL);

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

/** Corpo vivo de uma função, pelo helper de auditoria (#1562). */
async function liveBody(name) {
  const { data, error } = await sb.rpc('_audit_function_source', { p_proname: name });
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0, `função ${name} não existe no banco`);
  return data;
}

describe('#1584 A — camada estática (migration, página, i18n)', () => {
  it('a migration existe no timestamp canônico', () => {
    assert.ok(existsSync(MIGRATION_PATH), `migration esperada em ${MIGRATION_PATH}`);
    assert.ok(MIGRATION_SQL.length > 0, 'migration não pode estar vazia');
  });

  it('A4 — a base do link do candidato é o alias institucional, e o domínio pessoal sumiu', () => {
    assert.match(MIGRATION_CODE, /https:\/\/nucleoia\.pmigo\.org\.br\/interview-booking\//);
    assert.doesNotMatch(
      MIGRATION_CODE,
      /v_booking_url_base\s+text\s*:=\s*'https:\/\/nucleoia\.vitormr\.dev/,
      'link para candidato não pode sair do domínio pessoal'
    );
  });

  it('regressão (1) — a comparação de token é uuid = uuid, nunca text = uuid', () => {
    assert.match(
      MIGRATION_CODE,
      /WHERE id = v_token_row\.source_id/,
      'source_id é uuid; comparar com id::text levanta 42883 em runtime'
    );
    assert.doesNotMatch(MIGRATION_CODE, /id::text\s*=\s*v_token_row\.source_id/);
  });

  it('regressão (2) — gen_random_bytes é qualificado com o schema extensions', () => {
    assert.match(MIGRATION_CODE, /extensions\.gen_random_bytes\(32\)/);
    // A ocorrência NUA não pode existir em nenhum ponto do CÓDIGO: `assert.doesNotMatch` afirma
    // ausência universal, que é o que se quer aqui (ao contrário de `assert.match`, que se
    // satisfaz com uma ocorrência qualquer).
    assert.doesNotMatch(
      MIGRATION_CODE,
      /(?<!extensions\.)\bgen_random_bytes\(32\)/,
      'sob search_path=public o nome nu não resolve — pgcrypto vive em extensions'
    );
  });

  it('A1 — o resolvedor é PURO: não escreve no log de despacho', () => {
    const m = MIGRATION_CODE.match(
      /CREATE OR REPLACE FUNCTION public\.resolve_interview_booking_url[\s\S]*?\n\$function\$;/
    );
    assert.ok(m, 'corpo de resolve_interview_booking_url não encontrado na migration');
    assert.doesNotMatch(
      m[0],
      /INSERT\s+INTO\s+public\.selection_dispatch_url_log/i,
      'escrever o log dentro do resolvedor faria toda leitura de página gravar despacho e envenenar o LRD'
    );
  });

  it('A1 — a exclusão de observer do rodízio é preservada', () => {
    assert.match(MIGRATION_CODE, /sc\.role IN \('evaluator', 'lead'\)/);
  });

  it('A5 — a página lê o destino do payload e não carrega literal de calendário', () => {
    assert.ok(existsSync(PAGE_PATH), `página esperada em ${PAGE_PATH}`);
    assert.match(PAGE_SRC, /payload\?\.booking_url/, 'o destino tem de vir do payload da RPC');
    // Teste 4 da #1584 (mutação): recolocar o literal na página derruba esta asserção.
    assert.doesNotMatch(
      PAGE_SRC,
      /calendar\.app\.google/,
      'o literal ignorava o round-robin e mandava todo candidato para a agenda institucional'
    );
  });

  it('A5 — token válido sem destino tem estado próprio, distinto de link expirado', () => {
    assert.match(PAGE_SRC, /noBookingUrl/);
    assert.match(PAGE_SRC, /interview\.booking\.error\.noUrlTitle/);
    assert.match(PAGE_SRC, /interview\.booking\.error\.noUrlBody/);
  });

  it('A5 — as chaves novas existem nos TRÊS dicionários', () => {
    for (const dict of DICTS) {
      assert.ok(existsSync(dict), `dicionário ausente: ${dict}`);
      const src = readFileSync(dict, 'utf8');
      for (const key of ['interview.booking.error.noUrlTitle', 'interview.booking.error.noUrlBody']) {
        assert.ok(src.includes(`'${key}'`), `${dict} não tem a chave ${key}`);
      }
    }
  });

  it('assinaturas inalteradas usam CREATE OR REPLACE (preserva ACL)', () => {
    for (const fn of [
      'issue_interview_booking_token',
      'validate_interview_booking_token',
      'notify_selection_cutoff_approved',
    ]) {
      assert.match(MIGRATION_CODE, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}`));
      assert.doesNotMatch(
        MIGRATION_CODE,
        new RegExp(`DROP\\s+FUNCTION\\s+(?:IF EXISTS\\s+)?public\\.${fn}`, 'i'),
        `DROP em ${fn} forçaria re-GRANT`
      );
    }
  });

  it('a função interna nova nasce com REVOKE explícito de PUBLIC (classe #965)', () => {
    for (const fn of ['resolve_interview_booking_url', '_issue_interview_booking_token_core']) {
      assert.match(
        MIGRATION_CODE,
        new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\([^)]*\\) FROM PUBLIC, anon, authenticated`),
        `${fn} precisa revogar de anon e authenticated NOMINALMENTE: o default-privileges do ` +
          `Supabase concede a esses papéis, e revogar só de PUBLIC não remove nada`
      );
    }
  });
});

describe('#1584 B — camada DB-aware (corpo vivo, ACL, resolução real)', { skip: !sb ? 'sem SUPABASE_URL + SERVICE_ROLE_KEY' : false }, () => {
  it('o corpo VIVO de validate_interview_booking_token está livre do 42883', async () => {
    const rows = await liveBody('validate_interview_booking_token');
    for (const r of rows) {
      assert.doesNotMatch(r.prosrc, /id::text\s*=\s*v_token_row\.source_id/, 'corpo vivo ainda quebra com text = uuid');
      assert.match(r.prosrc, /WHERE id = v_token_row\.source_id/);
      assert.match(r.prosrc, /'booking_url'/, 'a página depende de booking_url no payload');
    }
  });

  it('o corpo VIVO da emissão qualifica gen_random_bytes', async () => {
    const rows = await liveBody('_issue_interview_booking_token_core');
    for (const r of rows) {
      const code = stripSqlComments(r.prosrc);
      assert.match(code, /extensions\.gen_random_bytes\(32\)/);
      assert.doesNotMatch(code, /(?<!extensions\.)\bgen_random_bytes\(32\)/);
    }
  });

  it('o corpo VIVO do despacho usa a fonte compartilhada e emite token', async () => {
    const rows = await liveBody('notify_selection_cutoff_approved');
    for (const r of rows) {
      // #1595 — resolve + emite + grava despacho saíram daqui para
      // `_dispatch_interview_booking_link`, porque o MESMO trio passou a ser necessário em mais
      // quatro lugares e duplicá-lo plantaria a quinta porta paralela. Afirmar aqui o LOCAL da
      // definição barraria essa refatoração legítima, então a asserção segue a função: o despacho
      // tem de passar pela fonte única, e a fonte única tem de fazer as duas coisas.
      assert.match(r.prosrc, /public\._dispatch_interview_booking_link\(/, 'A1/A6: o despacho tem de ir pela fonte única');
      assert.match(r.prosrc, /'interview_booking_url', v_token_url/, 'A6: o e-mail leva o link do token, não o do Google');
    }
    const helper = await liveBody('_dispatch_interview_booking_link');
    for (const r of helper) {
      assert.match(r.prosrc, /public\.resolve_interview_booking_url\(/, 'A1: a resolução tem de ser compartilhada');
      assert.match(r.prosrc, /public\._issue_interview_booking_token_core\(/, 'A6: a fonte única tem de emitir token');
      assert.match(r.prosrc, /INSERT INTO public\.selection_dispatch_url_log/, 'a linha de despacho é ato do DESPACHO');
    }
  });

  it('a RPC pública delega ao core em vez de duplicar os gates', async () => {
    const rows = await liveBody('issue_interview_booking_token');
    for (const r of rows) {
      assert.match(r.prosrc, /public\._issue_interview_booking_token_core\(/);
      assert.match(r.prosrc, /can_by_member\(v_caller\.id, 'manage_platform'/, 'o gate de chamador fica na RPC pública');
    }
  });

  it('as funções internas novas não são alcançáveis por anon', async () => {
    const { data, error } = await sb.rpc('_audit_function_execute_acl', {
      p_names: ['resolve_interview_booking_url', '_issue_interview_booking_token_core'],
    });
    assert.ifError(error);
    assert.ok(data.length >= 2, 'ambas as funções precisam existir no banco');
    for (const row of data) {
      assert.equal(row.anon_exec, false, `${row.proname} não pode ser executável por anon`);
      assert.equal(row.authenticated_exec, false, `${row.proname} não pode ser executável por authenticated`);
    }
  });

  // Testes 2 e 3 da #1584. O resolvedor é STABLE e não escreve, então pode ser chamado contra a
  // base viva sem poluir nada — é a única asserção aqui que exercita comportamento, não texto.
  for (const track of ['leader', 'researcher']) {
    it(`resolução real da trilha ${track} devolve destino e trilha coerentes`, async () => {
      const { data: apps, error: appErr } = await sb
        .from('selection_applications')
        .select('id, role_applied, selection_cycles!inner(cycle_code, status)')
        .eq('role_applied', track)
        .eq('selection_cycles.status', 'open')
        .limit(1);
      assert.ifError(appErr);
      if (!apps?.length) {
        // Sem candidatura viva da trilha não há o que afirmar; dizer isso alto evita ler como verde.
        console.log(`[1584] sem candidatura '${track}' em ciclo aberto — asserção de trilha não exercida`);
        return;
      }

      const { data, error } = await sb.rpc('resolve_interview_booking_url', { p_application_id: apps[0].id });
      assert.ifError(error);
      const row = Array.isArray(data) ? data[0] : data;
      assert.ok(row, 'o resolvedor tem de devolver uma linha');
      assert.ok(row.url && row.url.length > 0, 'ciclo aberto tem de resolver algum destino');
      assert.ok(
        ['cycle_fallback', 'committee_override', 'member_global'].includes(row.resolution_path),
        `trilha de resolução inesperada: ${row.resolution_path}`
      );
      if (track === 'leader') {
        assert.equal(row.resolution_path, 'cycle_fallback', 'leader nunca consulta o comitê');
        assert.equal(row.evaluator_id, null);
      } else if (row.resolution_path !== 'cycle_fallback') {
        // Teste 3: quem é sorteado tem de ser evaluator/lead com URL — nunca observer.
        assert.ok(row.evaluator_id, 'trilha de comitê tem de nomear o avaliador');
        const { data: seat, error: seatErr } = await sb
          .from('selection_committee')
          .select('role, can_interview')
          .eq('member_id', row.evaluator_id)
          .limit(1);
        assert.ifError(seatErr);
        assert.ok(['evaluator', 'lead'].includes(seat?.[0]?.role), 'observer não pode entrar no rodízio');
      }
    });
  }

  it('a precedência do resolvedor está protegida contra reescrita', async () => {
    const rows = await liveBody('resolve_interview_booking_url');
    for (const r of rows) {
      assert.match(r.prosrc, /'committee_override'/);
      assert.match(r.prosrc, /'member_global'/);
      assert.match(r.prosrc, /'cycle_fallback'/);
      assert.match(r.prosrc, /ORDER BY lrd\.last_dispatched NULLS FIRST/, 'LRD: avaliador nunca usado vem primeiro');
      assert.doesNotMatch(r.prosrc, /INSERT\s+INTO/i, 'o resolvedor tem de continuar puro no corpo vivo');
    }
  });
});
