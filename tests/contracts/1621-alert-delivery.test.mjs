/**
 * Contract: #1621 — a detecção existe e a entrega não.
 *
 * O que a medição de 2026-08-06 mostrou, e que enquadra este arquivo:
 *
 *  • NOVE RPCs `get_*_health` já leem `cron.job_run_details`. Todas de PULL. Nenhuma empurra.
 *    A plataforma tinha nove leitores de saúde e nenhum entregador.
 *  • O template `cron_failure_alert` FUNCIONA — 10 e-mails entregues — mas era alimentado por
 *    UMA fonte fora do banco (o worker `pmi-vep-sync`), e ela parou em 2026-05-09. O canal
 *    estava provado; faltavam as FONTES.
 *  • ⚠️ Um critério de aceite da issue não sobreviveu à medição. Ela pedia alertar
 *    `data_anomaly_log` com `fixed_at IS NULL`: são 151 linhas, TODAS `severity='info'` e todas
 *    administrativas. Entregá-las treinaria o GP a ignorar o canal. O gate é por SEVERITY, e o
 *    zero de hoje é declarado. Os testes abaixo travam essa decisão nos dois sentidos: o
 *    `warning` alerta, o `info` NÃO.
 *
 * A classe que motivou a issue é a terceira: `selection-stuck-scheduled-rescue-daily` teve 62
 * execuções 100% `succeeded` cobrindo os 6 dias em que estava quebrado. `status='failed'` é PISO,
 * não teto — por isso a camada 3 lê EFEITO (`rescued_count`) e não o veredito do pg_cron.
 *
 * ⚠️ Sobre o e-mail no CI. A entrega por e-mail foi provada CONTRA PRODUÇÃO nesta sessão (dois
 * envios enfileirados, dentro de uma transação abortada, portanto sem sair). Aqui ela é
 * deliberadamente SUPRIMIDA pelo parâmetro `p_deliver_email := false`: um teste de contrato que
 * dispara e-mail real para o GP a cada rodada de CI é um defeito, não uma prova — e isso não é
 * teoria, uma rodada chegou a entregar dois alertas sintéticos antes do freio existir. O que o CI prova por mutação é
 * a cadeia detecção → ledger → notificação in-app, e que a DECISÃO de e-mail respeita o teto.
 *
 * Cross-ref: issue #1621; migration 20260805000515; #1598/#1599 (a falha silenciosa de 6 dias),
 * #1609 (contador para não virar tempestade), #1532 (sonda e violação em baldes separados).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000515_1621_entrega_de_alerta.sql');
const PKG = resolve(ROOT, 'package.json');

const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// Sondas auto-identificáveis. A limpeza roda no INÍCIO e no FIM: um dado de teste que sobrevive
// à limpeza vira entidade real — aqui, um alerta permanente na caixa do GP.
const PROBE_ANOMALY = 'probe_1621_contract';
const PROBE_WATCH_MARK = 'probe_1621_contract_run';

function client() {
  return createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
}

async function purge(sb) {
  await sb.from('data_anomaly_log').delete().eq('anomaly_type', PROBE_ANOMALY);
  // filtro por COLUNA, não por caminho JSON: `metadata->>probe` é descartado pelo PostgREST e o
  // DELETE chegaria sem WHERE (o banco recusa, e a limpeza falharia calada se ele não recusasse).
  await sb.from('admin_audit_log').delete().eq('target_type', PROBE_WATCH_MARK);
  await sb.from('alert_deliveries').delete().eq('alert_kind', 'data_anomaly_open');
  await sb.from('alert_deliveries').delete().eq('alert_kind', 'cron_effect_zero_with_errors');
  await sb.from('notifications').delete().eq('type', 'platform_alert');
}


// ── STATIC ───────────────────────────────────────────────────────────────────
test('1621 static: migration 20260805000515 existe', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000515 presente');
});

test('1621 static: o ledger existe, tem chave LÓGICA e não é alcançável por anon', () => {
  assert.match(mig, /CREATE TABLE IF NOT EXISTS public\.alert_deliveries/);
  assert.match(mig, /UNIQUE \(alert_kind, alert_key\)/,
    'a chave é lógica: uma tempestade do mesmo cron no mesmo dia é UM alerta (lição do #1609)');
  assert.match(mig, /ALTER TABLE public\.alert_deliveries ENABLE ROW LEVEL SECURITY/);
  assert.match(mig, /REVOKE ALL ON TABLE public\.alert_deliveries FROM PUBLIC, anon, authenticated/,
    'REVOKE só de PUBLIC não fecha nada — o Supabase concede a anon/authenticated explicitamente');
  assert.match(mig, /notified_at\s+timestamptz/);
  assert.match(mig, /emailed_at\s+timestamptz/);
});

test('1621 static: in-app e e-mail são colunas SEPARADAS (só uma consome cota)', () => {
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.ok(sweep, 'corpo da varredura localizado');
  assert.match(sweep, /UPDATE public\.alert_deliveries SET notified_at = v_now/);
  assert.match(sweep, /UPDATE public\.alert_deliveries SET emailed_at = v_now/);
  // o e-mail só é carimbado se ALGUM envio deu certo — carimbar sem enviar apagaria o alerta
  assert.match(sweep, /IF v_emails > 0 THEN\s*\n?\s*UPDATE public\.alert_deliveries SET emailed_at/,
    'carimbar emailed_at sem envio bem-sucedido faria o alerta sumir sem ter saído');
});

test('1621 static: o gate de anomalia é por SEVERITY, não por fixed_at sozinho', () => {
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.match(sweep, /WHERE fixed_at IS NULL\s*\n?\s*AND severity IN \('warning', 'critical'\)/,
    'sem o gate de severity o primeiro disparo entregaria 151 linhas administrativas');
  // forward-defense: a versão ingênua do aceite
  assert.ok(!/FROM public\.data_anomaly_log\s*\n?\s*WHERE fixed_at IS NULL;/.test(sweep),
    'REGRESSÃO: voltou a alertar toda linha sem fixed_at, incluindo `info`');
});

test('1621 static: falha de sonda NÃO divide balde com violação (#1532)', () => {
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.match(sweep, /'vitality_probe_missing'/, 'chave ausente no payload tem balde PRÓPRIO');
  assert.match(sweep, /'cron_effect_zero_with_errors'/, 'efeito zero com erro é violação');
  assert.match(sweep, /'cron_silent'/, 'silêncio puro é ambíguo e tem balde próprio');
  // o silêncio puro só alerta se o cron DECLARAR que silêncio é anormal
  assert.match(sweep, /ELSIF v_efeito = 0 AND v_w\.alert_on_pure_silence THEN/,
    'zero efeito SEM erro pode ser "nada a fazer" — alertar sempre seria ruído');
});

test('1621 static: a carência impede a varredura de acusar a SI MESMA no primeiro disparo', () => {
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.match(sweep, /IF v_ultima_run IS NULL AND v_w\.created_at >= v_now - v_w\.expected_max_gap THEN\s*\n?\s*CONTINUE;/,
    'vigília recém-registrada não pode ter histórico — ausência de registro não é medição de parada');
});

test('1621 static: a janela de falha de cron é curta, e o agrupamento é por (job, dia)', () => {
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.match(sweep, /d\.start_time > v_now - interval '48 hours'/,
    'tempestade resolvida há dias é arqueologia; entregá-la ensina o GP a arquivar o canal');
  assert.match(sweep, /v_rec\.jobname \|\| '\|' \|\| v_rec\.dia/,
    'as 71 falhas medidas foram 3 tempestades — alertar por execução daria 71 linhas para 3 fatos');
});

test('1621 static: o filtro de falha é POSITIVO — "não teve sucesso" ≠ "falhou"', () => {
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.match(sweep, /WHERE d\.status = 'failed'/,
    'o desfecho é afirmado, não deduzido por exclusão');
  // ⚠️ Regressão medida em produção: `<> 'succeeded'` também casa o estado EM VOO. Enquanto a
  // própria varredura roda, a linha dela em cron.job_run_details está `running` — e ela abriu um
  // alerta contra SI MESMA às 02:07 UTC de 2026-08-06, com e-mail e tudo. Um filtro negativo sobre
  // uma coluna que mistura desfecho com progresso engole o em-progresso.
  assert.ok(!/d\.status <> 'succeeded'/.test(sweep),
    'REGRESSÃO: filtro negativo de volta — a varredura acusa todo cron em voo, inclusive ela mesma');
});

test('1621 static: a notificação usa o overload EXPLÍCITO de 7 argumentos', () => {
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  // `create_notification` tem TRÊS overloads e a ambiguidade já derrubou uma RPC antes.
  assert.match(sweep, /PERFORM public\.create_notification\(\s*\n?\s*v_gp\.id,/);
  assert.match(sweep, /'system',\s*\n?\s*NULL::uuid/, 'o NULL vai TIPADO — sem isso o overload fica ambíguo');
});

test('1621 static: uma falha de envio não pode apagar o alerta', () => {
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.match(sweep, /EXCEPTION WHEN OTHERS THEN[\s\S]{0,320}?RAISE WARNING '_alert_sweep_cron: envio/,
    'o envio degrada para WARNING; os alertas ficam sem emailed_at e saem na próxima rodada');
});

test('1621 static: a vigília é CONFIGURAÇÃO, e vem semeada com a falha histórica', () => {
  assert.match(mig, /CREATE TABLE IF NOT EXISTS public\.cron_vitality_watch/);
  assert.match(mig, /'selection-stuck-scheduled-rescue-daily', 'selection\.stuck_rescue_cron_run'/,
    'a semente é LITERALMENTE o cron que passou 6 dias verde e vazio');
  assert.match(mig, /'platform-alert-sweep-hourly', 'platform\.alert_sweep_run'/,
    'quem vigia o vigia');
  // sem SQL dinâmico: a vigília lê admin_audit_log, não executa string de sonda
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\([\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.ok(!/EXECUTE format\(/.test(sweep),
    'REGRESSÃO: sonda por SQL dinâmico — a vigília deve LER admin_audit_log, não executar string');
});

test('1621 static: o digest tem template próprio e o cron está agendado', () => {
  assert.match(mig, /'platform_alert_digest'/);
  assert.match(mig, /INSERT INTO public\.campaign_templates/);
  assert.match(mig, /cron\.schedule\('platform-alert-sweep-hourly', '7 \* \* \* \*'/);
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/);
});

test('1621 static: a varredura é service_role, nunca anon nem authenticated', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\._alert_sweep_cron\(boolean\) FROM PUBLIC, anon, authenticated/);
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\._alert_sweep_cron\(boolean\) TO service_role;/);
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\._alert_sweep_cron\(boolean\)[^;]*\bauthenticated\b/.test(mig),
    'REGRESSÃO: a varredura ficou alcançável por authenticated');
});

test('1621 static: o freio de entrega existe e o padrão é ENTREGAR', () => {
  // `p_deliver_email` é o freio do CI. O default TEM de ser `true`: um freio que fica ligado por
  // omissão transformaria a varredura de produção em outra defesa decorativa.
  assert.match(mig, /_alert_sweep_cron\(p_deliver_email boolean DEFAULT true\)/,
    'o padrão é entregar — o freio é a exceção, e explícita');
  const sweep = mig.match(/FUNCTION public\._alert_sweep_cron\(p_deliver_email[\s\S]*?\$function\$([\s\S]*?)\$function\$/)?.[1];
  assert.ok(sweep, 'corpo localizado com a nova assinatura');
  assert.match(sweep, /IF p_deliver_email\s*\n?\s*AND EXISTS/,
    'o freio corta o e-mail ANTES do teto — `critical` fura o teto, mas não fura o freio');
  // a notificação in-app NÃO é freada: ela não consome cota e é a prova de entrega do CI
  assert.ok(!/IF p_deliver_email[\s\S]{0,400}?create_notification/.test(sweep),
    'o freio não pode alcançar a notificação in-app, que é o que o CI prova por mutação');
});

test('1621 guard: o teste está registrado nas DUAS listas do package.json', () => {
  const pkg = readFileSync(PKG, 'utf8');
  const hits = (pkg.match(/1621-alert-delivery\.test\.mjs/g) || []).length;
  assert.equal(hits, 2, 'precisa estar em "test" E em "test:contracts" — senão nunca roda em CI');
});

// ── COMPORTAMENTAL (DB-gated) ────────────────────────────────────────────────
test('1621 behavioural: estado saudável é SILENCIOSO (um canal que fala à toa deixa de ser lido)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    await purge(sb);
    const { data, error } = await sb.rpc('_alert_sweep_cron', { p_deliver_email: false });
    assert.ifError(error);
    assert.equal(data?.success, true);
    assert.equal(typeof data?.new_count, 'number');
    assert.equal(data.emails_sent, 0, 'sem alerta novo não sai e-mail');
    await purge(sb);
  });

test('1621 behavioural MUTAÇÃO — fonte B: uma anomalia `warning` ALCANÇA o GP',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    await purge(sb);

    // baseline: sem a anomalia, nada deste tipo existe
    await sb.rpc('_alert_sweep_cron', { p_deliver_email: false });
    const { count: antes } = await sb.from('alert_deliveries')
      .select('id', { count: 'exact', head: true })
      .eq('alert_kind', 'data_anomaly_open').is('resolved_at', null);
    assert.equal(antes ?? 0, 0, 'baseline: nenhum alerta de anomalia aberto');

    // MUTAÇÃO
    const { error: insErr } = await sb.from('data_anomaly_log').insert({
      anomaly_type: PROBE_ANOMALY, severity: 'warning',
      description: 'sonda de contrato do #1621', context: {},
    });
    assert.ifError(insErr);

    const { data: depois, error } = await sb.rpc('_alert_sweep_cron', { p_deliver_email: false });
    assert.ifError(error);

    const { data: alertas } = await sb.from('alert_deliveries')
      .select('alert_kind, severity, title, notified_at')
      .eq('alert_kind', 'data_anomaly_open').is('resolved_at', null);
    assert.equal(alertas?.length, 1, 'a anomalia real virou UM alerta');
    assert.equal(alertas[0].severity, 'warning');
    assert.notEqual(alertas[0].notified_at, null, 'e foi ENTREGUE in-app — detectar sem entregar é o defeito da issue');

    const { count: notifs } = await sb.from('notifications')
      .select('id', { count: 'exact', head: true }).eq('type', 'platform_alert');
    assert.ok((notifs ?? 0) >= 1, 'existe notificação in-app para o GP');

    // O CI chama com `p_deliver_email: false`. O freio é EXPLÍCITO de propósito: o sentinela de
    // teto que eu tentei antes contém `warning` e é atropelado por `critical` — e foi assim que
    // uma rodada mandou alerta sintético para a caixa real dos dois GPs.
    assert.equal(depois.emails_sent, 0, 'com o freio ligado, nenhum e-mail sai do CI');

    await purge(sb);
  });

test('1621 behavioural MUTAÇÃO — camada 3: cron VERDE e vazio vira alerta CRÍTICO',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    await purge(sb);

    // MUTAÇÃO: a assinatura EXATA dos 6 dias do #1598 — execuções verdes, zero efeito, com erro.
    // Nenhuma delas aparece como `failed` no pg_cron, que é o ponto todo da camada 3.
    const linhas = [1, 2, 3].map(() => ({
      actor_id: null,
      action: 'selection.stuck_rescue_cron_run',
      target_type: PROBE_WATCH_MARK,
      changes: { rescued_count: 0, refused_count: 0, error_count: 1 },
      metadata: { probe: PROBE_WATCH_MARK },
    }));
    const { error: insErr } = await sb.from('admin_audit_log').insert(linhas);
    assert.ifError(insErr);

    const { error } = await sb.rpc('_alert_sweep_cron', { p_deliver_email: false });
    assert.ifError(error);

    const { data: alertas } = await sb.from('alert_deliveries')
      .select('severity, title, notified_at')
      .eq('alert_kind', 'cron_effect_zero_with_errors').is('resolved_at', null);
    assert.equal(alertas?.length, 1, 'verde-e-vazio foi detectado');
    assert.equal(alertas[0].severity, 'critical',
      'é a classe que passou 6 dias invisível — não é warning');
    assert.match(alertas[0].title, /selection-stuck-scheduled-rescue-daily/);
    assert.notEqual(alertas[0].notified_at, null, 'e ALCANÇOU o GP');

    await purge(sb);
  });

test('1621 behavioural: `info` NÃO alerta — é a decisão que separa alerta de auditoria',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    await purge(sb);

    // Mesma sonda, severidade administrativa. Sem o gate por severity, as 151 linhas `info` da
    // tabela virariam alerta e o canal morreria de ruído na primeira semana.
    const { error: insErr } = await sb.from('data_anomaly_log').insert({
      anomaly_type: PROBE_ANOMALY, severity: 'info',
      description: 'sonda de contrato do #1621 — administrativa, NAO e alerta', context: {},
    });
    assert.ifError(insErr);

    const { error } = await sb.rpc('_alert_sweep_cron', { p_deliver_email: false });
    assert.ifError(error);

    const { count } = await sb.from('alert_deliveries')
      .select('id', { count: 'exact', head: true })
      .eq('alert_kind', 'data_anomaly_open').is('resolved_at', null);
    assert.equal(count ?? 0, 0, 'linha `info` não vira alerta');

    await purge(sb);
  });

test('1621 behavioural: a vigília está registrada e alcança os crons certos',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.from('cron_vitality_watch')
      .select('job_name, effect_action, effect_key, error_key, enabled');
    assert.ifError(error);
    const nomes = (data ?? []).map((r) => r.job_name);
    assert.ok(nomes.includes('selection-stuck-scheduled-rescue-daily'),
      'a falha histórica do #1598 está vigiada');
    assert.ok(nomes.includes('platform-alert-sweep-hourly'), 'a própria varredura está vigiada');
    for (const w of data ?? []) {
      assert.ok(w.effect_action && w.effect_key,
        `vigília ${w.job_name} sem fonte de efeito seria decorativa`);
    }
  });
