// tests/contracts/1640-ia-fora-da-precondicao-do-convite.test.mjs
//
// #1640 — a ausência de consentimento para análise por IA negava o convite de entrevista.
//
// O gate `GATE_NO_AI` (P0001) rodava ANTES dos outros dois, em duas RPCs:
// `_issue_interview_booking_token_core` (modo `full`) e `schedule_interview` (fora do bypass).
// Ou seja, a ausência de um consentimento de terceira finalidade (LGPD art. 7º, I) negava efeito
// ao procedimento seletivo, que corre por base autônoma (art. 7º, V).
//
// Medido em 07/08/2026 antes da correção:
//   - 6 candidaturas em `interview_pending` sem consentimento, TODAS com 2 avaliações e nota
//     objetiva calculada — o gate de IA era o único obstáculo; 4 nunca receberam convite algum.
//   - `schedule_interview` acumulou ZERO recusas `GATE_NO_AI` em 31 tentativas, mas 14 agendamentos
//     passaram por `bypass_granted` sobre candidaturas sem consentimento, e 13 desses 14 já tinham
//     as 2 avaliações e a nota. Zero recusas não era imunidade: era contorno por bypass de admin,
//     que desliga JUNTO o peer-review e a nota.
//
// A regra que este arquivo afirma: candidatura SEM `ai_analysis`, COM 2 avaliações e COM nota
// objetiva, RECEBE token. E os dois gates que sobraram (P0002 peer-review, P0003 nota) continuam
// recusando — eles são requisitos de conclusão do processo objetivo, não dados opcionais.
//
// Camada A (estática, sempre roda): a migration.
// Camada B (DB-aware, PULA sem SUPABASE_URL + SERVICE_ROLE_KEY): corpo vivo + comportamento.
//   ⚠️ um SKIP silencioso lê como verde. Conferir o número de skips, não só `fail 0`.
//
// ⚠️ RESÍDUO DECLARADO: a metade comportamental EMITE um token real e o apaga no `finally`. O alvo
// é escolhido por predicado num ciclo FECHADO — nenhum cron age sobre ciclo fechado (é exatamente o
// que a #1586 corrigiu), então a janela entre emitir e apagar não alcança candidato em processo
// vivo. A linha de `gate_attempts` que a emissão deixa é verdadeira e fica.
//
// ⚠️ `schedule_interview` NÃO é exercida por comportamento: ela cria linha de entrevista e promove
// o status de uma candidatura real. Aqui ela é afirmada pelo corpo VIVO, não por chamada.

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { createSyntheticApplication } from '../helpers/selection-fixtures.mjs';

const MIGRATION_PATH =
  'supabase/migrations/20260807000200_1640_ia_sai_da_precondicao_do_convite_e_do_agendamento.sql';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

/**
 * Guard de AUSÊNCIA tem de olhar só o CÓDIGO. Os comentários desta migration (e os do corpo vivo,
 * que os carrega) explicam nominalmente o gate que ela remove — assertar sobre o texto cru
 * transformaria a documentação do defeito em falha do teste.
 */
const stripSqlComments = (sql) => sql.replace(/^\s*--.*$/gm, '');

const MIGRATION_SQL = read(MIGRATION_PATH);
const MIGRATION_CODE = stripSqlComments(MIGRATION_SQL);

/** Extrai o bloco `CREATE OR REPLACE FUNCTION public.<name> ... $function$ ... $function$;`. */
function fnBlock(sql, name) {
  const re = new RegExp(
    `CREATE OR REPLACE FUNCTION public\\.${name}\\s*\\([\\s\\S]*?\\n\\$function\\$;`,
  );
  return sql.match(re)?.[0] || '';
}

const GATED_FNS = ['_issue_interview_booking_token_core', 'schedule_interview'];

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = Boolean(SUPABASE_URL && SUPABASE_SRK);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = dbGated
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

// ─────────────────────────────────────────────────────────────────────────────
// Camada A — estática
// ─────────────────────────────────────────────────────────────────────────────
describe('#1640 A — a migration tira a IA da pré-condição nas DUAS RPCs', () => {
  it('a migration existe no timestamp canônico', () => {
    assert.ok(existsSync(MIGRATION_PATH), `migration esperada em ${MIGRATION_PATH}`);
    assert.ok(MIGRATION_SQL.length > 0, 'migration não pode estar vazia');
  });

  for (const fn of GATED_FNS) {
    it(`${fn}: nenhuma condição de bloqueio lê consentimento nem análise de IA`, () => {
      const block = fnBlock(MIGRATION_CODE, fn);
      assert.ok(block, `bloco de ${fn} não encontrado`);

      // Ausência da CONDIÇÃO, não da coluna: `has_consent` continua no payload de auditoria.
      assert.doesNotMatch(
        block,
        /consent_ai_analysis_at IS NULL/,
        `${fn}: a ausência de consentimento voltou a bloquear`,
      );
      assert.doesNotMatch(
        block,
        /v_app\.ai_analysis IS NULL/,
        `${fn}: a ausência de análise voltou a bloquear`,
      );
      assert.doesNotMatch(block, /GATE_NO_AI/, `${fn}: o código de recusa por IA voltou`);
      assert.doesNotMatch(block, /'P0001'/, `${fn}: P0001 voltou`);
    });

    it(`${fn}: os gates do processo OBJETIVO continuam de pé`, () => {
      const block = fnBlock(MIGRATION_CODE, fn);
      assert.match(block, /'GATE_NO_PEER_REVIEW'/, `${fn}: peer-review não pode sair junto`);
      assert.match(block, /'GATE_NO_SCORE'/, `${fn}: o gate de nota não pode sair junto`);
      assert.match(block, /'P0002'/, `${fn}: P0002 tem de continuar`);
      assert.match(block, /'P0003'/, `${fn}: P0003 tem de continuar`);
      // #1594: recusa RETORNA, nunca levanta — um RAISE desfaz o INSERT de auditoria.
      assert.doesNotMatch(
        block.match(/'P0002'[\s\S]*'P0003'[\s\S]{0,600}/)?.[0] || '',
        /RAISE EXCEPTION/,
        `${fn}: um RAISE entre as recusas reabre a #1594`,
      );
    });

    it(`${fn}: consentimento e análise continuam OBSERVÁVEIS no payload`, () => {
      const block = fnBlock(MIGRATION_CODE, fn);
      assert.match(
        block,
        /'has_consent', \(v_app\.consent_ai_analysis_at IS NOT NULL\)/,
        `${fn}: deixar de gravar has_consent cega a auditoria sobre a própria correção`,
      );
      assert.match(block, /'has_ai_analysis', \(v_app\.ai_analysis IS NOT NULL\)/);
    });
  }

  it('schedule_interview mantém o gate de status P0004 e a allow-list do bypass', () => {
    const block = fnBlock(MIGRATION_CODE, 'schedule_interview');
    assert.match(block, /'P0004'/, 'P0004 não faz parte desta correção');
    assert.match(
      block,
      /v_can_bypass := p_bypass_gate AND public\.can_by_member\(v_caller\.id, 'manage_member'::text\)/,
      'a autoridade do bypass não muda aqui',
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Camada B — DB-aware
// ─────────────────────────────────────────────────────────────────────────────
describe('#1640 B — corpo vivo', () => {
  for (const fn of GATED_FNS) {
    it(`${fn}: o corpo VIVO não recusa por IA e mantém P0002/P0003`, { skip: dbGated ? false : skipMsg }, async () => {
      const { data, error } = await sb.rpc('_audit_function_source', { p_proname: fn });
      assert.ifError(error);
      assert.ok(data?.length > 0, `${fn} não existe no banco`);
      for (const row of data) {
        const code = stripSqlComments(row.prosrc);
        assert.doesNotMatch(code, /GATE_NO_AI/, `${fn}: o gate de IA continua VIVO em produção`);
        assert.doesNotMatch(code, /'P0001'/, `${fn}: P0001 continua vivo em produção`);
        assert.doesNotMatch(code, /consent_ai_analysis_at IS NULL/, `${fn}: condição viva`);
        assert.match(code, /'GATE_NO_PEER_REVIEW'/, `${fn}: peer-review sumiu do corpo vivo`);
        assert.match(code, /'GATE_NO_SCORE'/, `${fn}: o gate de nota sumiu do corpo vivo`);
      }
    });
  }
});

describe('#1640 B — a regra: sem análise de IA, com peer-review e nota, RECEBE token', () => {
  let alvo = null;
  let tokenEmitido = null;
  let fixture = null;

  before(async () => {
    if (!dbGated) return;

    // ⚠️ #1636 — o alvo era candidatura REAL escolhida por predicado, e este bloco é o caminho de
    // PASSAGEM: ele EMITE token de agendamento. Foi por aqui que nasceram os 4 tokens de 07/08 que
    // sobreviveram à limpeza e ficaram vivos até 21/08 apontando para candidaturas reais.
    //
    // A fixture carrega a forma que a issue afirma: SEM consentimento de IA e SEM análise, mas com
    // peer-review completo e nota calculada. Ciclo fechado porque nenhum cron age ali.
    fixture = await createSyntheticApplication(sb, {
      cycleStatus: 'closed',
      label: '1640-passa-sem-ia',
      consentAi: false,
      aiAnalysis: false,
      evaluations: 2,      // peer-review completo → não recusa por P0002
      objectiveScore: 9.1, // nota calculada        → não recusa por P0003
    });
    alvo = fixture.application;
  });

  after(async () => {
    // O CASCADE leva gate_attempts e avaliações; o token sai à mão dentro do `cleanup` — ele NÃO
    // tem FK para a candidatura (vínculo polimórfico por `source_id`), que é precisamente por que
    // os tokens de 07/08 sobreviveram sem ninguém notar.
    if (fixture) await fixture.cleanup();
  });

  it('a emissão PASSA sem consentimento de IA', { skip: dbGated ? false : skipMsg }, async () => {
    // #1636: a fixture é construída, então a asserção é sempre exercida.
    assert.ok(alvo, 'a fixture não foi criada');

    const { data, error } = await sb.rpc('_issue_interview_booking_token_core', {
      p_application_id: alvo.id,
      p_bypass_granted: false,
      p_caller_id: null,
      p_bypass_requested: false,
    });
    assert.ifError(error);
    assert.equal(
      data?.success,
      true,
      `a emissão foi recusada (${data?.gate_failed_reason}) — a ausência de IA voltou a impedir o convite`,
    );
    assert.equal(data?.gate_mode, 'full', 'tem de ser o modo full: é ele que continha o gate');
    assert.ok(data?.token, 'sucesso sem token não é sucesso');
    tokenEmitido = data.token;

    // E a passagem fica auditada com o retrato de que NÃO havia consentimento — é essa linha que
    // permite medir a correção depois.
    const { data: rows, error: e1 } = await sb
      .from('gate_attempts')
      .select('gate_passed, payload')
      .eq('application_id', alvo.id)
      .eq('gate_passed', true)
      .order('attempted_at', { ascending: false })
      .limit(1);
    assert.ifError(e1);
    assert.equal(rows?.[0]?.payload?.has_consent, false, 'o payload precisa registrar a ausência');
    assert.equal(rows?.[0]?.payload?.gate_mode, 'full');
  });
});

describe('#1640 B — o que NÃO saiu: o peer-review continua barrando, e a recusa continua auditada', () => {
  let semPeerReview = null;
  let fixture = null;

  before(async () => {
    if (!dbGated) return;
    // #1636: fixture no lugar do predicado sobre prod. P0002 é o PRIMEIRO gate que sobrou, então
    // zero avaliações torna a recusa determinística, independente da nota. Com fixture dá para
    // afirmar o par que o predicado não conseguia isolar: SEM avaliações e COM nota, o que prova
    // que quem barrou foi o peer-review e não o P0003.
    fixture = await createSyntheticApplication(sb, {
      cycleStatus: 'closed',
      label: '1640-sem-peer-review',
      evaluations: 0,
      objectiveScore: 9.1,
    });
    semPeerReview = fixture.application;
  });

  after(async () => {
    if (fixture) await fixture.cleanup();
  });

  it('sem 2 avaliações a emissão RECUSA com P0002 e deixa linha', { skip: dbGated ? false : skipMsg }, async () => {
    assert.ok(semPeerReview, 'a fixture não foi criada');

    const { count: antes } = await sb
      .from('gate_attempts')
      .select('id', { count: 'exact', head: true })
      .eq('application_id', semPeerReview.id)
      .eq('gate_passed', false);

    const { data, error } = await sb.rpc('_issue_interview_booking_token_core', {
      p_application_id: semPeerReview.id,
      p_bypass_granted: false,
      p_caller_id: null,
      p_bypass_requested: false,
    });
    assert.ifError(error);
    assert.equal(data?.success, false, 'tirar o gate de IA não pode ter aberto os outros dois');
    assert.equal(data?.gate_failed_code, 'P0002');
    assert.equal(data?.gate_failed_reason, 'GATE_NO_PEER_REVIEW');

    const { count: depois } = await sb
      .from('gate_attempts')
      .select('id', { count: 'exact', head: true })
      .eq('application_id', semPeerReview.id)
      .eq('gate_passed', false);
    assert.equal(
      depois,
      (antes ?? 0) + 1,
      'a linha de recusa não sobreviveu — é o defeito da #1594 voltando por outra porta',
    );
  });
});
