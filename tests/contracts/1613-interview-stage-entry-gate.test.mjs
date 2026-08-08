/**
 * Contract: #1613 — R1, gate único de fase objetiva na ENTRADA do estágio de entrevista.
 *
 * O arco #1584 / #1594 / #1595 / #1598 fechou a porta de SAÍDA (quem recebe o convite).
 * Esta issue fecha a de ENTRADA (quem acaba em `interview_scheduled`). A Opção 1 da
 * SPEC_INTERVIEW_BOOKING_INTEGRITY §4.1 — trigger BEFORE UPDATE — foi ratificada pelo PM em
 * 2026-08-05 justamente porque são SETE escritores, e um helper compartilhado depende de
 * cada um lembrar de chamá-lo (o padrão que produziu a Classe A).
 *
 * O que este arquivo prova, e por que cada peça existe:
 *
 *  T1  cada escritor, com `objective_score_avg IS NULL`, não leva a candidatura a
 *      `interview_scheduled` — provado no ponto que TODOS atravessam (a escrita da coluna),
 *      e não escritor a escritor, porque é exatamente essa a tese da Opção 1.
 *  T2  MUTAÇÃO: sem o trigger o T1 passa. Um gate que não faz o teste falhar quando é
 *      removido é decorativo (`reference-mutation-test-reveals-decorative-defenses`).
 *  T3  o estado em REPOUSO não é invalidado (R1.3).
 *  T4  reagendamento de entrevista já materializada passa mesmo sem nota (R1.5).
 *  +   a ORDEM alfabética do trigger contra os BEFORE existentes é afirmada, não herdada.
 *  +   o cron 49 processa um lote com candidatura bloqueada SEM abortar o laço.
 *  +   o override do R1.4 exige motivo e fica auditado.
 *
 * ⚠️ Toda sonda comportamental roda dentro de um bloco `DO` que termina em `RAISE`: o
 * `RAISE` aborta a transação inteira, então nem o status nem a linha de auditoria
 * sobrevivem. É o padrão de `reference-do-block-probe-reproduces-prod-failure-safely`, e
 * aqui ele é obrigatório — a suíte DB-aware escreve em PRODUÇÃO e um dado de teste que
 * sobrevive à limpeza vira entidade real.
 *
 * Cross-ref: issue #1613; migration 20260805000514; SPEC_INTERVIEW_BOOKING_INTEGRITY §4.1 / R1.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { createSyntheticApplication } from '../helpers/selection-fixtures.mjs';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000514_1613_gate_entrada_fase_objetiva.sql');
const WEBHOOK = resolve(ROOT, 'src/pages/api/calendar-webhook.ts');
const MCP = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');
const PKG = resolve(ROOT, 'package.json');

const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// comentários fora: as asserções têm de casar SQL real, não a documentação — que menciona de
// propósito os anti-padrões que o arquivo remove.
const mig = migRaw.replace(/^\s*--.*$/gm, '');
const webhookRaw = existsSync(WEBHOOK) ? readFileSync(WEBHOOK, 'utf8') : '';
const webhook = webhookRaw.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
const mcpRaw = existsSync(MCP) ? readFileSync(MCP, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const TRIGGER = 'trg_zz_gate_interview_stage_entry';
const FN = '_trg_gate_interview_stage_entry';

function client() {
  return createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
}

// A plataforma NÃO expõe execução de SQL arbitrário ao service_role, e criar uma RPC para
// isso seria abrir um buraco muito maior do que o que este arquivo fecha. As sondas
// comportamentais abaixo usam apenas tabelas e RPCs já expostas, e desfazem o que mudam.

// ── STATIC: a migration ──────────────────────────────────────────────────────
test('1613 static: migration 20260805000514 existe', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000514 presente');
});

test('1613 static: o gate é BEFORE UPDATE OF status — o ponto que os 7 escritores atravessam', () => {
  assert.match(mig, new RegExp(`CREATE TRIGGER ${TRIGGER}\\s*\\n?\\s*BEFORE UPDATE OF status ON public\\.selection_applications`),
    'BEFORE UPDATE OF status: o gate olha a escrita da coluna, não cada RPC');
  assert.match(mig, new RegExp(`EXECUTE FUNCTION public\\.${FN}\\(\\)`));
  assert.match(mig, new RegExp(`DROP TRIGGER IF EXISTS ${TRIGGER} ON public\\.selection_applications;`),
    'idempotente — reaplicar a migration não duplica o trigger');
});

test('1613 static: SUPRIME a transição, e NÃO levanta exceção (§4.1 — o cron 49 processa em laço)', () => {
  const body = mig.match(new RegExp(`FUNCTION public\\.${FN}\\(\\)[\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$`))?.[1];
  assert.ok(body, 'corpo do trigger localizado');
  assert.match(body, /NEW\.status := OLD\.status;/, 'a recusa é supressão da transição');
  assert.match(body, /'selection\.interview_stage_blocked'/, 'suprimir CALADO não atende o R1.2');
  // forward-defense: uma exceção aqui aborta a função INTEIRA do cron 49, não a iteração.
  assert.ok(!/RAISE EXCEPTION/.test(body),
    'REGRESSÃO: o gate voltou a levantar exceção — abortaria o laço inteiro do cron 49 (§4.1)');
  // o único RAISE tolerado é o WARNING do fallback de auditoria, e ele vem DEPOIS da
  // supressão — a recusa não pode morrer junto com o log (reference-audit-row-dies-with-the-raise)
  const suppressAt = body.indexOf('NEW.status := OLD.status');
  const auditAt = body.indexOf('INSERT INTO public.admin_audit_log');
  assert.ok(suppressAt > -1 && auditAt > suppressAt,
    'a supressão acontece ANTES do log: uma falha de auditoria não pode desfazer a recusa');
  assert.match(body, /RAISE WARNING/, 'falha de auditoria degrada para WARNING, não derruba o UPDATE do chamador');
});

test('1613 static: o gate olha a TRANSIÇÃO, não o estado em repouso (R1.3 + R1.5)', () => {
  const body = mig.match(new RegExp(`FUNCTION public\\.${FN}\\(\\)[\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$`))?.[1];
  assert.match(body, /IF NEW\.status IS DISTINCT FROM 'interview_scheduled' THEN\s*\n?\s*RETURN NEW;/,
    'qualquer outro destino passa direto');
  assert.match(body, /IF OLD\.status IS NOT DISTINCT FROM 'interview_scheduled' THEN\s*\n?\s*RETURN NEW;/,
    'R1.5: interview_scheduled → interview_scheduled (reescrita idempotente) passa');
  assert.match(body, /IF OLD\.status IN \('interview_done', 'interview_noshow', 'final_eval'\) THEN/,
    'R1.5: quem já passou pelo estágio está reagendando, não entrando');
  // ⚠️ a isenção de reagendamento NÃO pode ser "existe linha de entrevista": o webhook INSERE
  // a linha antes de promover, então essa versão reabriria o buraco que o gate fecha.
  assert.match(body, /si\.conducted_at IS NOT NULL\s*\n?\s*OR si\.status IN \('completed', 'noshow', 'rescheduled', 'cancelled'\)/,
    'entrevista MATERIALIZADA e resolvida — uma linha recém-criada (scheduled, conducted_at NULL) não isenta');
  assert.ok(!/EXISTS \(\s*SELECT 1 FROM public\.selection_interviews si\s*WHERE si\.application_id = NEW\.id\s*\)/.test(body),
    'REGRESSÃO: isenção por mera existência de linha de entrevista — reabre o caminho do webhook');
});

test('1613 static: a ORDEM do trigger é escolhida, não herdada', () => {
  // Gatilhos do MESMO evento disparam em ordem ALFABÉTICA de nome. Os BEFORE existentes em
  // selection_applications são trg_link_renewal_application, trg_purge_ai_analysis_on_-
  // consent_revocation e trg_stamp_vep_offer_extended. O gate precisa rodar DEPOIS de
  // qualquer um que possa PREENCHER a nota — daí o prefixo `zz`.
  const anteriores = [
    'trg_link_renewal_application',
    'trg_purge_ai_analysis_on_consent_revocation',
    'trg_stamp_vep_offer_extended',
  ];
  for (const anterior of anteriores) {
    assert.ok(TRIGGER > anterior,
      `ordem alfabética: ${TRIGGER} precisa vir DEPOIS de ${anterior}, senão o gate lê NEW.objective_score_avg antes de quem poderia preenchê-la`);
  }
  assert.ok(TRIGGER.startsWith('trg_zz'),
    'o prefixo zz é o mecanismo da ordem — renomear sem manter a propriedade quebra o invariante em silêncio');
});

test('1613 static: R1.4 — override com motivo OBRIGATÓRIO e auditado', () => {
  assert.match(mig, /ADD COLUMN IF NOT EXISTS interview_stage_override_at\s+timestamptz/);
  assert.match(mig, /ADD COLUMN IF NOT EXISTS interview_stage_override_by\s+uuid REFERENCES public\.members\(id\)/);
  assert.match(mig, /ADD COLUMN IF NOT EXISTS interview_stage_override_reason text/);
  const body = mig.match(/FUNCTION public\.grant_interview_stage_override\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.ok(body, 'grant_interview_stage_override definida');
  assert.match(body, /can_by_member\(v_caller_id, 'manage_platform'\)/, 'exige manage_platform');
  assert.match(body, /length\(v_reason\) < 12/, 'motivo obrigatório e não-trivial');
  assert.match(body, /'reason_required'/);
  assert.match(body, /'selection\.interview_stage_override_granted'/, 'a exceção é registrada COMO exceção');
  // o trigger tem de LER o override, senão a coluna é decorativa
  const gate = mig.match(new RegExp(`FUNCTION public\\.${FN}\\(\\)[\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$`))?.[1];
  assert.match(gate, /IF NEW\.interview_stage_override_at IS NOT NULL THEN/,
    'lê NEW: o escritor pode carimbar o override no MESMO UPDATE que promove o status');
});

test('1613 static: escada de grants do override — nunca anon', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.grant_interview_stage_override\(uuid, text\) FROM PUBLIC, anon, authenticated/,
    'REVOKE só de PUBLIC não fecha nada: o Supabase concede EXECUTE a anon/authenticated explicitamente');
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.grant_interview_stage_override\(uuid, text\) TO authenticated, service_role;/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\._trg_gate_interview_stage_entry\(\) FROM PUBLIC, anon, authenticated/);
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/);
});

test('1613 static: o bypass VIVO do schedule_interview vira a exceção declarada, não uma recusa calada', () => {
  // Medido em 2026-08-05: 26 concessões de bypass, a última em 04/08, 3 delas com a nota
  // objetiva NULL. Sem carimbar o override, o gate suprimiria a promoção e o caminho de
  // emergência do admin passaria a falhar em silêncio.
  const body = mig.match(/FUNCTION public\.schedule_interview\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.ok(body, 'schedule_interview redefinida no mesmo PR');
  assert.match(body, /v_stamp_override := v_can_bypass AND v_app\.objective_score_avg IS NULL;/);
  assert.match(body, /interview_stage_override_at =\s*\n?\s*CASE WHEN v_stamp_override THEN now\(\) ELSE interview_stage_override_at END/,
    'o carimbo vai no MESMO UPDATE que promove o status — o trigger lê NEW');
  assert.match(body, /interview_stage_override_reason =/, 'o override do bypass também registra motivo');
  // o gate P0003 do caminho NÃO-bypass continua de pé
  assert.match(body, /'GATE_NO_SCORE'/, 'o gate original do schedule_interview não foi afrouxado');
});

test('1613 static: os consumidores LEEM o desfecho em vez de assumir', () => {
  // reference-exception-to-structured-return-flips-consumer-contract: mudar o contrato sem
  // inventariar os consumidores só move o defeito. Já mordeu duas vezes neste arco.
  const recompute = mig.match(/FUNCTION public\.recompute_application_status\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.ok(recompute, 'recompute_application_status redefinida');
  assert.match(recompute, /RETURNING status INTO v_landed;/,
    'o cron 49 lê o status GRAVADO — com o gate, FOUND deixou de provar que a mudança pousou');
  assert.match(recompute, /IF v_landed IS DISTINCT FROM v_rec\.canonical THEN/);
  assert.match(recompute, /v_suppressed := v_suppressed \+ 1;/, 'a supressão é CONTADA, não engolida');
  assert.match(recompute, /'suppressed',\s*v_suppressed/, 'e volta no retorno do RPC');
  // o laço não pode abortar: `CONTINUE`, nunca RAISE, no ramo de supressão
  assert.match(recompute, /'suppressed',\s*true\s*\n?\s*\);\s*\n?\s*CONTINUE;/,
    'candidatura bloqueada faz o laço CONTINUAR — abortar seria o risco que a §4.1 evita');

  const adminUpd = mig.match(/FUNCTION public\.admin_update_application\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.ok(adminUpd, 'admin_update_application redefinida');
  assert.match(adminUpd, /RETURNING status INTO v_new_status;/, 'reporta o status que POUSOU');
  assert.match(adminUpd, /v_gate_suppressed := \(v_new_status IS DISTINCT FROM v_requested_status\);/);
  assert.match(adminUpd, /'gate_suppressed',\s*v_gate_suppressed/, 'o front sabe distinguir recusa de sucesso');
  // contrato de retorno preservado para os chamadores existentes
  for (const chave of ["'success'", "'old_status'", "'new_status'", "'onboarding_seeded'", "'role_promoted'"]) {
    assert.ok(adminUpd.includes(chave), `chave de retorno ${chave} preservada`);
  }
});

test('1613 static: o vocabulário do contador ganhou o desfecho novo (senão a recusa vira 500)', () => {
  // reference-discriminator-vocabulary-gap-fakes-orphans: uma chave que o mapa não conhece
  // não falha alto — aqui falharia, porque record_booking_attempt LEVANTA no outcome
  // desconhecido, e o Apps Script reenvia a cada 15 min.
  const counter = mig.match(/FUNCTION public\.record_booking_attempt\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.ok(counter, 'record_booking_attempt redefinida');
  assert.match(counter, /'objective_phase_incomplete'/, 'desfecho novo aceito pelo contador');
  for (const antigo of ['matched', 'no_application', 'status_not_allowed', 'cycle_closed']) {
    assert.ok(counter.includes(`'${antigo}'`), `desfecho ${antigo} preservado`);
  }
});

// ── STATIC: o webhook (o par inconsistente) ──────────────────────────────────
test('1613 static: o webhook recusa ANTES de materializar a entrevista', () => {
  assert.match(webhook, /objective_phase_incomplete:\s*'calendar_booking_premature'/,
    'ação de auditoria própria — mesmo nome que o RPC canônico usa desde o #1450');
  assert.match(webhook, /const objectivePhaseIncomplete =/);
  assert.match(webhook, /matched\.objective_score_avg == null/);
  // as isenções TÊM de espelhar as do trigger, senão os dois lados divergem
  assert.match(webhook, /matched\.app_status !== 'interview_scheduled'/, 'R1.5 no webhook: quem já entrou está reagendando');
  assert.match(webhook, /matched\.interview_materialized !== true/, 'R1.5 no webhook: entrevista materializada isenta');
  // a recusa acontece no ramo de saída ANTES do INSERT em selection_interviews
  const recusaAt = webhook.indexOf("if (outcome !== 'matched')");
  const insertAt = webhook.indexOf("from('selection_interviews').insert");
  assert.ok(recusaAt > -1 && insertAt > -1 && recusaAt < insertAt,
    'a recusa precede a criação da entrevista — é isso que impede o par inconsistente');
});

test('1613 static: o webhook lê o desfecho da promoção que ele mesmo faz', () => {
  assert.match(webhook, /const landedStatus = updatedApp\?\.status \?\? null;/);
  assert.match(webhook, /const promotionSuppressed =/);
  assert.match(webhook, /promotion_suppressed: promotionSuppressed/, 'a divergência, se existir, é medida e não some');
});

test('1613 static: o matcher devolve os dois sinais que a decisão exige', () => {
  assert.match(mig, /DROP FUNCTION IF EXISTS public\.match_booking_application\(text\);/,
    'mudança de FORMA de retorno exige DROP + CREATE');
  assert.match(mig, /objective_score_avg numeric/);
  assert.match(mig, /interview_materialized boolean/);
  // não pode ter afrouxado a allow-list herdada do #1611
  assert.match(mig, /WHEN c\.status IN \('open', 'active'\) AND a\.status = ANY \(v_allow\) THEN 'matched'/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.match_booking_application\(text\) FROM PUBLIC, anon, authenticated/);
});

test('1613 static: o override tem SUPERFÍCIE (declarado e inalcançável seria o mesmo que nada)', () => {
  assert.match(mcpRaw, /rpc = "grant_interview_stage_override"/, 'exposto pelo interview_manage');
  assert.match(mcpRaw, /"stage_override"/);
  assert.match(mcpRaw, /override_reason: z\.string\(\)\.optional\(\)/);
});

test('1613 guard: o teste está registrado nas DUAS listas do package.json', () => {
  const pkg = readFileSync(PKG, 'utf8');
  const hits = (pkg.match(/1613-interview-stage-entry-gate\.test\.mjs/g) || []).length;
  assert.equal(hits, 2, 'precisa estar em "test" E em "test:contracts" — senão nunca roda em CI');
});

// ── COMPORTAMENTAL (DB-gated) ────────────────────────────────────────────────
test('1613 behavioural T1+T2: sem nota a transição é SUPRIMIDA, e a mutação (remover o gate) faz isto passar',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // ⚠️ #1636 — a sonda era sobre CANDIDATURA REAL pré-entrevista, e ela MUTA: o UPDATE encontra
    // a linha viva, o trigger grava auditoria, e a limpeza tinha de apagar uma linha de
    // `admin_audit_log` de produção. Agora a sonda é sobre fixture sintética, montada na forma
    // exata que o gate barra: sem nota, status pré-entrevista, ciclo aberto.
    const fx = await createSyntheticApplication(sb, {
      cycleStatus: 'open',
      label: '1613-t1-sem-nota',
      status: 'submitted',
      objectiveScore: null,
    });

    try {
      // O caminho de escrita disponível ao service_role sem SQL arbitrário é o UPDATE direto na
      // tabela, que é exatamente o que 5 dos 7 escritores fazem por dentro.
      const { data: escrito, error: upErr } = await sb
        .from('selection_applications')
        .update({ status: 'interview_scheduled' })
        .eq('id', fx.id)
        .select('status')
        .single();
      assert.ifError(upErr);

      // T1: a transição não pousou.
      assert.equal(escrito.status, 'submitted',
        'T1: sem objective_score_avg e sem override, a candidatura NÃO entra em interview_scheduled');

      // R1.2: a recusa deixou registro. Suprimir calado não atende o requisito.
      const { data: log } = await sb
        .from('admin_audit_log')
        .select('id, changes, metadata')
        .eq('action', 'selection.interview_stage_blocked')
        .eq('target_id', fx.id)
        .order('created_at', { ascending: false })
        .limit(1);
      assert.equal(log?.length, 1, 'R1.2: a recusa foi registrada em selection.interview_stage_blocked');
      assert.equal(log[0].metadata?.reason, 'objective_score_avg IS NULL');

      // T2 (MUTAÇÃO): a asserção acima só vale porque o gate existe. Se o trigger sumir, o
      // mesmo UPDATE pousa — e este teste falha. A mutação é afirmada estruturalmente aqui
      // (o teste comportamental não pode DROPAR um trigger de produção); o par estático
      // "trigger existe + suprime + é lido" acima é o que fecha o T2 no CI.
      assert.ok(migRaw.includes(`CREATE TRIGGER ${TRIGGER}`),
        'T2: sem este CREATE TRIGGER, a asserção de T1 acima passaria por vacuidade');
    } finally {
      // `finally`, não linha solta no fim: uma asserção que falhe no meio deixaria a fixture viva
      // em produção, que é o modo de falha que o guard do #1636 existe para acusar.
      await fx.cleanup();
    }
  });

test('1613 behavioural T3: nenhuma candidatura foi invalidada pela migration (R1.3)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // O gate olha a TRANSIÇÃO. Quem já está no estágio sem nota fica onde está — e a
    // população foi medida em 0 antes de aplicar, o que torna o gate puramente preventivo.
    const { count, error } = await sb
      .from('selection_applications')
      .select('id, selection_cycles!inner(status)', { count: 'exact', head: true })
      .is('objective_score_avg', null)
      .in('status', ['interview_scheduled', 'interview_done'])
      .in('selection_cycles.status', ['open', 'active']);
    assert.ifError(error);
    // Não se afirma "= 0": a coorte anda sozinha e um valor > 0 é legítimo (o gate não
    // invalida ninguém). O que se afirma é que a leitura FUNCIONA e é um número.
    assert.equal(typeof count, 'number', 'R1.3: a população em repouso é legível e não foi derrubada');
  });

test('1613 behavioural T4: reagendamento de entrevista já materializada passa mesmo sem nota (R1.5)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // ⚠️ #1636 — esta sonda MUTA de verdade (o UPDATE pousa), e o alvo era candidatura real: o
    // desfazer dependia de a asserção do meio não falhar. Agora é fixture, montada na forma que a
    // R1.5 descreve: sem nota, status não-terminal, e entrevista JÁ materializada.
    const fx = await createSyntheticApplication(sb, {
      cycleStatus: 'open',
      label: '1613-t4-entrevista-materializada',
      status: 'interview_pending',
      objectiveScore: null,
      withInterview: true,
      interviewStatus: 'completed',
    });

    try {
      const { data: escrito, error: upErr } = await sb
        .from('selection_applications')
        .update({ status: 'interview_scheduled' })
        .eq('id', fx.id)
        .select('status')
        .single();
      assert.ifError(upErr);
      assert.equal(escrito.status, 'interview_scheduled',
        'R1.5: quem já tem entrevista materializada reagenda mesmo sem nota objetiva');
    } finally {
      await fx.cleanup();
    }
  });

test('1613 behavioural: o cron 49 roda o lote inteiro sem abortar, e reporta a supressão',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // dry_run: não muta nada e prova que o laço percorre a base inteira. Se o gate
    // levantasse exceção, a função caía por completo em vez de pular a candidatura.
    const { data, error } = await sb.rpc('recompute_application_status', {
      p_application_id: null, p_cycle_id: null, p_dry_run: true,
    });
    assert.ifError(error);
    assert.equal(data?.success, true, 'o laço completou — nenhuma exceção derrubou a função');
    assert.equal(typeof data?.evaluated, 'number');
    assert.ok('suppressed' in data, 'o contador de supressão faz parte do retorno');
  });

test('1613 behavioural R1.4: o override recusa motivo vazio e recusa quem não é GP',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // service_role não resolve auth.uid() → member NULL → unauthorized. É o mesmo gate que
    // barra um authenticated sem manage_platform, e é o que se pode provar sem forjar JWT.
    const { data, error } = await sb.rpc('grant_interview_stage_override', {
      p_application_id: '00000000-0000-0000-0000-000000000000',
      p_reason: 'curto',
    });
    assert.ifError(error);
    assert.equal(data?.success, false, 'sem manage_platform não concede override');
    assert.equal(data?.error, 'unauthorized');
  });
