import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

/**
 * #1543 — a cadeia de alerta de token de comms tinha TRÊS quebras independentes, e a tabela
 * `comms_token_alerts` vazia lia-se como "tokens saudáveis" quando significava "o alerta não tem como
 * disparar". Medido em 30/07/2026:
 *
 *   1. `comms_check_token_expiry()`, o ÚNICO escritor da tabela, pulava todo canal com
 *      `token_expires_at IS NULL` — o Instagram inteiro.
 *   2. O prazo real do Instagram não é `expires_at` (que é 0, não expira) e sim `data_access_expires_at`
 *      (25/09/2026), que a plataforma não tinha onde guardar.
 *   3. NÃO HAVIA CRON. A RPC só rodava quando um humano abria `/admin/comms` — e a mensagem que ela
 *      produz é "Renove em Admin → Comunicação". Esta quebra valia para TODOS os canais.
 *
 * Estes testes existem para que nenhuma das três volte em silêncio. O critério é sempre o mesmo: um
 * mecanismo de defesa precisa ser ALCANÇÁVEL e precisa ESCREVER, não apenas existir.
 */

const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = URL && KEY ? createClient(URL, KEY, { auth: { persistSession: false } }) : null;

const MIGRATION = 'supabase/migrations/20260805000498_1543_comms_token_expiry_chain.sql';

test('#1543 estático: a porta do cron NÃO tem o gate que ela não consegue satisfazer', () => {
  // A armadilha original: agendar `comms_check_token_expiry()` direto pareceria funcionar. O gate
  // `can_view_comms_analytics()` resolve `auth.uid()`, que é NULL sob pg_cron, então o job devolveria
  // zero-shape todo dia sem escrever nada — e `cron.job_run_details` registraria sucesso.
  const sql = readFileSync(MIGRATION, 'utf8');
  const cronFn = sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION public.comms_check_token_expiry_cron'));
  const corpo = cronFn.slice(0, cronFn.indexOf('$function$;'));

  assert.ok(
    !/IF NOT public\.can_view_comms_analytics\(\)/.test(corpo),
    'a porta do cron ganhou um gate de usuário: sob pg_cron auth.uid() é NULL, então ela passaria a ' +
      'devolver zero-shape todo dia sem escrever nada, e o job ficaria VERDE. A proteção aqui é o ACL.',
  );
  assert.ok(
    /REVOKE ALL ON FUNCTION public\.comms_check_token_expiry_cron\(\) FROM PUBLIC, anon, authenticated/.test(sql),
    'sem o REVOKE, tirar o gate de usuário abriria a função para qualquer authenticated',
  );
  // E a porta da UI tem de MANTER o gate — os dois requisitos são opostos e ambos precisam valer.
  const uiFn = sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION public.comms_check_token_expiry()'));
  assert.ok(
    /IF NOT public\.can_view_comms_analytics\(\)/.test(uiFn.slice(0, uiFn.indexOf('$function$;'))),
    'a porta da UI perdeu o gate #963: ela é alcançável por qualquer authenticated',
  );
});

test('#1543 estático: o agendamento existe e aponta para a porta _cron', () => {
  // Quebra 3. Um mecanismo que só roda quando alguém abre uma página não é vigilância.
  //
  // ⚠️ Este teste é ESTÁTICO por limitação real: o schema `cron` não é alcançável pelo PostgREST, então
  // nenhum teste daqui consegue ler `cron.job`. É o mesmo padrão de `p569-s3-ots-cron-lease-retention-
  // health`. O que ele prova é que a migration MANDA agendar; que o job está de fato ativo foi verificado
  // ao vivo no apply (jobid 83, `20 9 * * *`, active) e é o que o `check-invariants` cobre no CI.
  const sql = readFileSync(MIGRATION, 'utf8');

  assert.match(
    sql,
    /SELECT cron\.unschedule\('comms-token-expiry-daily'\)\s+WHERE EXISTS \(SELECT 1 FROM cron\.job WHERE jobname = 'comms-token-expiry-daily'\);/,
    'o unschedule idempotente sumiu: reaplicar a migration passaria a duplicar o job',
  );
  assert.match(
    sql,
    /cron\.schedule\(\s*'comms-token-expiry-daily'/,
    "o agendamento de 'comms-token-expiry-daily' sumiu — a quebra 3 voltou",
  );
  assert.match(
    sql,
    /SELECT public\.comms_check_token_expiry_cron\(\);/,
    'o cron aponta para outra coisa que não a porta _cron; se voltar para a RPC gateada, roda em vácuo',
  );
});

test('#1543 nenhum canal OAuth fica sem prazo E sem sonda ao mesmo tempo', { skip: !sb }, async () => {
  // Quebras 1 e 2. Não afirma que todo canal tem prazo — o token do Instagram legitimamente não expira.
  // Afirma que nenhum canal está invisível: ou há um prazo conhecido, ou houve confirmação recente na API
  // do provedor. Estar sem os dois é exatamente o estado em que o IG passou meses.
  const { data, error } = await sb
    .from('comms_channel_config')
    .select('channel, oauth_token, api_key, token_expires_at, data_access_expires_at, token_checked_at');
  assert.equal(error, null, `leitura de comms_channel_config falhou: ${error?.message}`);
  assert.ok(data.length > 0, 'sem canais para avaliar — o teste não pode passar por vacuidade');

  const LIMITE_SONDA_DIAS = 7;
  const cegos = data
    .filter((c) => c.channel !== 'youtube' && c.oauth_token)
    .filter((c) => {
      const temPrazo = !!(c.token_expires_at || c.data_access_expires_at);
      const sondaFresca = c.token_checked_at
        && Date.now() - new Date(c.token_checked_at).getTime() < LIMITE_SONDA_DIAS * 864e5;
      return !temPrazo && !sondaFresca;
    })
    .map((c) => c.channel);

  assert.deepEqual(
    cegos,
    [],
    'canal OAuth sem prazo conhecido E sem sonda recente: nada está vigiando a validade dele. Foi este ' +
      'estado que deixou o Instagram fora de toda defesa. O scan emite alert_type=unknown para ele; se ' +
      'este teste falha, a sonda do provedor parou de rodar.',
  );
});

test('#1543 a varredura pelo caminho do cron ESCREVE, e não só devolve', { skip: !sb }, async () => {
  // O coração da issue: o mecanismo tem de produzir efeito, não apenas responder 200. Aqui a chamada vai
  // por service_role (sem auth.uid()), que é a condição do pg_cron.
  const { data, error } = await sb.rpc('comms_check_token_expiry_cron');
  assert.equal(error, null, `a porta do cron não é alcançável por service_role: ${error?.message}`);
  assert.ok(data && typeof data === 'object', 'resposta sem shape utilizável');
  assert.ok('alerts_created' in data && 'active_alerts' in data, 'shape mudou; a UI consome estas chaves');
  assert.ok(Array.isArray(data.active_alerts), 'active_alerts deveria ser array');
});

test('#1543 a porta da UI continua negando quem não tem o gate', { skip: !sb }, async () => {
  // O contraponto do teste acima, e a prova de que a separação em duas portas não afrouxou o #963:
  // a MESMA sessão sem auth.uid() recebe zero-shape da porta gateada.
  const { data, error } = await sb.rpc('comms_check_token_expiry');
  assert.equal(error, null, `chamada falhou: ${error?.message}`);
  assert.equal(data.alerts_created, 0, 'a porta gateada escreveu sem gate satisfeito');
  assert.deepEqual(data.active_alerts, [], 'a porta gateada vazou alertas para sessão sem autoridade');
});

test("#1543 'unknown' está no vocabulário e é distinguível de dispensa humana", { skip: !sb }, async () => {
  // 'expira em 5 dias' e 'não sei se expira' são afirmações diferentes e pedem ações diferentes; empilhar
  // as duas em 'warning' é o vício que o #1537 desmontou em outra tabela na mesma semana.
  const { error } = await sb
    .from('comms_token_alerts')
    .select('id')
    .eq('alert_type', 'unknown')
    .limit(1);
  assert.equal(error, null, `'unknown' não é aceito pelo CHECK de alert_type: ${error?.message}`);

  // Resolução automática deixa acknowledged_by NULL de propósito: comms_acknowledge_alert() sempre grava
  // o auth.uid() de quem dispensou, então NULL é o marcador de "foi a máquina". Se alguém preencher esse
  // campo na resolução automática, a coluna passa a mentir sobre um ato humano que não houve.
  const { data: autos, error: errAutos } = await sb
    .from('comms_token_alerts')
    .select('id, channel, alert_type, acknowledged, acknowledged_by')
    .eq('acknowledged', true)
    .is('acknowledged_by', null);
  assert.equal(errAutos, null, `leitura falhou: ${errAutos?.message}`);
  for (const a of autos ?? []) {
    assert.equal(
      a.alert_type,
      'unknown',
      `alerta ${a.id} foi resolvido pela máquina mas é do tipo ${a.alert_type}; só 'unknown' se resolve ` +
        'sozinho (quando a sonda descobre o prazo). Os demais exigem ato humano.',
    );
  }
});
