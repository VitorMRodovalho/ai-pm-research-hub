// tests/contracts/2130-sinal-de-parada-alcanca-a-notificacao.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2130 — o sinal de parada alcanca a NOTIFICACAO, nao so a campanha.
 *
 * SINTOMA (01-12/09/2026): um lider de tribo ativo ficou 94 dias sem receber e-mail; um guest nunca
 * recebeu nenhum e-mail de onboarding. Os dois por supressao do provedor apos reclamacao de spam.
 * A plataforma tinha 15 sinais de parada registrados e NENHUM leitor.
 *
 * AS DUAS METADES DA CAUSA:
 *   (a) o Resend responde **200 para endereco suprimido**: aceita, devolve id, e suprime depois por
 *       webhook. "O provedor aceitou" e "a pessoa recebeu" sao dois fatos com tempos diferentes;
 *   (b) `notifications` nao guardava o `resend_id` do aceite, entao o webhook de desfecho nao tinha
 *       onde pousar — 12 dos 15 sinais ficaram orfaos.
 *
 * E O ACHADO QUE FECHOU: `email.suppressed` **nem estava** no `validEvents` do EF do webhook. Ele era
 * gravado em `email_webhook_events` (o insert acontece ANTES do filtro) e caia no `else`. Por isso a
 * coluna `processed` virou, sem querer, um medidor exato de "tipo que ninguem le": os cinco da lista
 * a 100% processados, os tres de fora a 0% (`email.sent` 4.587, `delivery_delayed` 57,
 * `suppressed` 43 — medido 12/09/2026 23:35 UTC).
 *
 * O QUE ESTE ARQUIVO DEFENDE, e por que cada camada existe:
 *
 *   A (estatico) — a correcao inteira, nao metade dela. O par EF-do-webhook + RPC anda JUNTO: o
 *     `CASE` de `process_email_webhook` nao tem ramo `ELSE`, entao admitir um tipo no `validEvents`
 *     sem criar o ramo levanta `CASE_NOT_FOUND` e o evento continua `processed = false` — o defeito
 *     sobreviveria a propria correcao, com a aparencia de ter sido corrigido. A camada A prova a
 *     INCLUSAO nessa direcao, e derivando os dois catalogos do codigo, nao de lista de nomes escrita
 *     aqui (uma lista aqui envelhece sozinha e passa a afirmar texto morto).
 *
 *   A' (inversa) — reprova se o bloco de `campaign_recipients` sumir. "Acrescentar depois" e a forma
 *     mais facil de apagar o que ja funcionava, e a campanha ja funcionava.
 *
 *   B (vivo, com controle positivo) — nenhum tipo TRATADO acumula `processed = false`. Sem o
 *     controle positivo, um periodo sem webhook nenhum daria zero e passaria por AUSENCIA.
 *
 *   C (vivo, discriminacao) — uma notificacao cujo `resend_id` tem evento de supressao nao pode
 *     estar `delivered`. E a asserção que separa "entregue" de "aceito e depois suprimido".
 *
 *   D (vivo, o detector de deploy) — o unico ponto que a spec diz exigir alguem olhando: se a
 *     captura do `resend_id` nao pegou no EF de envio, `email_sent_at` continua sendo escrito e
 *     `resend_id` fica nulo para sempre, e toda a cadeia acima fica INERTE em silencio.
 *
 * A DIVIDA HISTORICA, e por que as camadas vivas tem corte: as 43 linhas de `suppressed` e as 57 de
 * `delivery_delayed` anteriores a esta onda ficam `processed = false` PARA SEMPRE — aqueles webhooks
 * chegaram e foram embora, e `processed` so e escrito quando a RPC e chamada. Cobrar o passado
 * deixaria este arquivo vermelho de forma permanente e incorrigivel, que e exatamente a pressao que
 * faz alguem contornar o portao. Entao as camadas vivas medem a partir de CORTE.
 *
 * Cross-ref: #2130 (spec no comentario 5641960282), #2129, #1424 (o EF de envio), #1513 (o webhook).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');

/**
 * CORTE das camadas vivas: o instante em que esta onda passou a valer. E o timestamp da propria
 * migration, lido do NOME DO ARQUIVO em vez de digitado aqui, para os dois nao poderem divergir.
 */
const ARQUIVO_MIGRATION = '20260912234500_2130_desfecho_do_provedor_alcanca_a_notificacao.sql';
const CORTE = (() => {
  const v = ARQUIVO_MIGRATION.slice(0, 14);
  assert.match(v, /^\d{14}$/, 'o nome da migration de #2130 deve comecar com o timestamp de 14 digitos');
  const [Y, M, D, h, m, s] = [v.slice(0, 4), v.slice(4, 6), v.slice(6, 8), v.slice(8, 10), v.slice(10, 12), v.slice(12, 14)];
  return `${Y}-${M}-${D}T${h}:${m}:${s}Z`;
})();

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const lerEF = (nome) => readFileSync(join(ROOT, 'supabase/functions', nome, 'index.ts'), 'utf8');
const capturaRPC = () => latestFunctionCapture(ROOT, 'process_email_webhook');

function migracoesConcatenadas() {
  return readdirSync(MIGRATIONS)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => readFileSync(join(MIGRATIONS, f), 'utf8'))
    .join('\n');
}

/**
 * Os tipos que o EF do webhook ADMITE, lidos do proprio `validEvents`.
 *
 * ⚠️ Com os comentarios MASCARADOS antes de medir. O bloco que documenta esta correcao cita
 * `'email.suppressed'` e `'email.sent'` em prosa, e sem mascarar o guard casaria o comentario que
 * descreve o anti-padrao em vez do codigo — ficaria verde mesmo com a lista vazia.
 */
function tiposAdmitidosPeloWebhook() {
  const src = maskJsComments(lerEF('resend-webhook'));
  const m = src.match(/const\s+validEvents\s*=\s*\[([^\]]*)\]/);
  assert.ok(m, 'resend-webhook deve declarar `const validEvents = [...]`');
  const tipos = [...m[1].matchAll(/['"]([a-z_.]+)['"]/g)].map((x) => x[1]);
  assert.ok(tipos.length >= 5, `validEvents esvaziou: ${JSON.stringify(tipos)}`);
  return new Set(tipos);
}

/** Os tipos que a RPC VIGENTE tem ramo para tratar, lidos dos `WHEN` do CASE-comando. */
function tiposComRamoNaRPC() {
  const corpo = maskLineComments(capturaRPC().block);
  const tipos = [...corpo.matchAll(/WHEN\s+'(email\.[a-z_]+)'\s+THEN/g)].map((x) => x[1]);
  assert.ok(tipos.length >= 5, `os WHEN da RPC esvaziaram: ${JSON.stringify(tipos)}`);
  return new Set(tipos);
}

// ═══════════════════════════════════════════════════════════════════════════
// A — a correcao inteira, e derivada do codigo
// ═══════════════════════════════════════════════════════════════════════════

test('#2130 A: o sinal de parada deixou de cair no `else` — suppressed e delivery_delayed entram no validEvents', () => {
  const admitidos = tiposAdmitidosPeloWebhook();
  for (const t of ['email.suppressed', 'email.delivery_delayed']) {
    assert.ok(admitidos.has(t), `${t} deve ser admitido pelo webhook (era descartado no else)`);
  }
  // `email.sent` fica FORA de proposito: e ruido de aceite, nao desfecho. Se ele entrasse, cada
  // envio viraria uma chamada de RPC a mais, e o numero do dia (#1424 Fase B) le a tabela direto.
  assert.ok(!admitidos.has('email.sent'),
    'email.sent nao deve virar decisao: e ruido de aceite, e quem mede o envio do dia le email_webhook_events');
});

test('#2130 A: todo tipo admitido pelo webhook TEM ramo na RPC — o CASE nao tem ELSE, e CASE_NOT_FOUND e silencioso', () => {
  const admitidos = tiposAdmitidosPeloWebhook();
  const comRamo = tiposComRamoNaRPC();
  const semRamo = [...admitidos].filter((t) => !comRamo.has(t)).sort();
  assert.deepEqual(semRamo, [], [
    'Tipos admitidos pelo EF do webhook SEM ramo `WHEN` em process_email_webhook.',
    '',
    'Por que isto e falha e nao detalhe: o `CASE p_event_type` da RPC nao tem ramo `ELSE`, de',
    'proposito. Um tipo sem ramo levanta CASE_NOT_FOUND, a RPC aborta, `processed` FICA FALSO e o',
    'webhook so registra um erro no log — ou seja, o defeito de #2130 volta inteiro, com a',
    'aparencia de estar corrigido.',
    '',
    `Sem ramo: ${JSON.stringify(semRamo)}`,
  ].join('\n'));
});

/**
 * A ARMADILHA QUE FICA DE PE depois de #2130, e que esta asserção existe para desarmar.
 *
 * `_shared/webhook-parser.ts` declara a SUA PROPRIA lista, `VALID_WEBHOOK_EVENTS`, com os CINCO
 * tipos originais, e dela deriva um campo `isValid`. Medido em 12/09/2026: nenhum caminho de
 * producao le `isValid` nem `VALID_WEBHOOK_EVENTS` — o unico leitor e o teste do proprio parser,
 * que fixa o tamanho em 5. Ou seja, hoje a divergencia e inofensiva porque a lista esta MORTA.
 *
 * Mas um parser existe para ser usado, e ligar `isValid` no filtro do webhook e a coisa mais
 * natural do mundo de se fazer numa limpeza futura. No instante em que alguem fizer isso,
 * `email.suppressed` volta a ser descartado e o defeito de #2130 RENASCE inteiro — com o agravante
 * de que o `validEvents` do index.ts continuaria correto, entao a leitura do arquivo certo
 * mostraria a correcao de pe.
 *
 * Entao em vez de refatorar (fora do escopo) ou de reprovar por uma divergencia que hoje nao faz
 * mal, esta asserção trava o PORTAO: o webhook nao pode passar a decidir pela lista do parser.
 * Ela e verdadeira hoje e fica vermelha exatamente no dia em que a armadilha for armada.
 */
test('#2130 A: o webhook NAO decide pela lista morta do parser (a armadilha que recria o defeito)', () => {
  const src = maskJsComments(lerEF('resend-webhook'));
  assert.doesNotMatch(src, /VALID_WEBHOOK_EVENTS/,
    'o webhook nao pode filtrar por VALID_WEBHOOK_EVENTS: essa lista tem os 5 tipos originais e descartaria email.suppressed de novo');
  assert.doesNotMatch(src, /\bisValid\b/,
    'o webhook nao pode gatear por `isValid` do parser: ele e derivado de VALID_WEBHOOK_EVENTS, que nao conhece email.suppressed');
  // E o controle: o filtro vigente continua sendo o `validEvents` local, que #2130 ampliou.
  assert.match(src, /validEvents\.includes\(eventType\)/,
    'o filtro do webhook deve seguir sendo validEvents.includes(eventType)');
});

test("#2130 A: a RPC vigente escreve o desfecho em `notifications`, e nao so em campaign_recipients", () => {
  const corpo = maskLineComments(capturaRPC().block);
  assert.match(corpo, /UPDATE\s+notifications\s+SET/i,
    'a captura vigente de process_email_webhook deve dar UPDATE em notifications');
  assert.match(corpo, /email_delivery_status\s*=/i,
    'deve gravar email_delivery_status');
  assert.match(corpo, /WHERE\s+resend_id\s*=\s*p_resend_id/i,
    'deve pousar pelo resend_id, que e a chave que o aceite passou a guardar');
});

test("#2130 A': a inversa — o bloco de campaign_recipients continua de pe (a campanha ja funcionava)", () => {
  const corpo = maskLineComments(capturaRPC().block);
  for (const alvo of [
    /UPDATE\s+campaign_recipients\s+SET[\s\S]{0,200}delivered\s*=\s*true/i,
    /UPDATE\s+campaign_recipients\s+SET[\s\S]{0,400}open_count\s*=\s*open_count\s*\+\s*1/i,
    /UPDATE\s+campaign_recipients\s+SET[\s\S]{0,200}click_count\s*=\s*click_count\s*\+\s*1/i,
    /UPDATE\s+campaign_recipients\s+SET[\s\S]{0,200}bounced_at\s*=\s*COALESCE/i,
    /UPDATE\s+campaign_recipients\s+SET[\s\S]{0,200}unsubscribed\s*=\s*true/i,
    /UPDATE\s+campaign_sends\s+SET[\s\S]{0,300}delivered_count/i,
    /UPDATE\s+email_webhook_events\s+SET\s+processed\s*=\s*true/i,
  ]) {
    assert.match(corpo, alvo,
      `#2130 acrescentou e APAGOU: o bloco original de campanha perdeu ${alvo}`);
  }
});

test('#2130 A: o EF de envio guarda o id do aceite e nao confunde dedup com aceite', () => {
  const src = maskJsComments(lerEF('send-notification-email'));
  const i = src.indexOf('if (res.ok)');
  assert.ok(i > 0, 'o EF deve ter o ramo de sucesso `if (res.ok)`');
  const ramoOk = src.slice(i, src.indexOf('} else {', i));
  assert.match(ramoOk, /resend_id\s*:/,
    'o ramo de sucesso deve gravar resend_id (era JOGADO FORA — a causa (b) de #2130)');
  assert.match(ramoOk, /res\.json\(\)/,
    'o ramo de sucesso deve LER a resposta do Resend para extrair o id');
  assert.match(ramoOk, /email_delivery_status\s*:\s*'accepted'/,
    "o aceite deve ser carimbado como 'accepted' — nao como entrega");
  // O caminho de dedup carimba `email_sent_at` SEM ENVIAR. Se ele marcasse 'accepted', o campo
  // carregaria dois significados e um detector de nao-entrega leria provedor onde nao houve provedor.
  assert.match(src, /richDupIds[\s\S]{0,400}email_delivery_status\s*:\s*'deduplicated'/,
    "os duplicados de digest rico devem ser 'deduplicated', nunca 'accepted'");
});

test('#2130 A: o CHECK admite EXATAMENTE os valores que algum caminho escreve (diferenca simetrica nos dois sentidos)', () => {
  const sql = maskLineComments(migracoesConcatenadas());
  const m = sql.match(/notifications_email_delivery_status_check[\s\S]{0,400}?email_delivery_status\s+IN\s*\(([^)]*)\)/i);
  assert.ok(m, 'a migration de #2130 deve declarar o CHECK nomeado notifications_email_delivery_status_check');
  const noCheck = new Set([...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]));

  // Os valores que os caminhos de escrita REALMENTE produzem, lidos do codigo.
  const corpoRPC = maskLineComments(capturaRPC().block);
  const doCase = corpoRPC.match(/v_notif_status\s*:=\s*CASE[\s\S]*?END;/i);
  assert.ok(doCase, 'a RPC deve derivar o desfecho da notificacao num CASE-expressao para v_notif_status');
  const escritos = new Set([...doCase[0].matchAll(/THEN\s+'([a-z_]+)'/g)].map((x) => x[1]));
  const efEnvio = maskJsComments(lerEF('send-notification-email'));
  for (const v of [...efEnvio.matchAll(/email_delivery_status\s*:\s*'([a-z_]+)'/g)].map((x) => x[1])) {
    escritos.add(v);
  }

  const admitidoSemCaminho = [...noCheck].filter((v) => !escritos.has(v)).sort();
  const escritoSemCheck = [...escritos].filter((v) => !noCheck.has(v)).sort();

  assert.deepEqual(escritoSemCheck, [], [
    'Valor gravado por algum caminho e RECUSADO pelo CHECK — a escrita vai falhar em producao.',
    `Gravados fora do CHECK: ${JSON.stringify(escritoSemCheck)}`,
  ].join('\n'));
  assert.deepEqual(admitidoSemCaminho, [], [
    'Valor admitido pelo CHECK que NENHUM caminho de escrita produz.',
    '',
    'Ampliar o CHECK admite o valor mas nao cria o caminho que ele percorre: o portao passa a',
    'aceitar um estado que nunca existe, e quem le a lista infere uma capacidade que a plataforma',
    'nao tem.',
    '',
    `Admitidos sem caminho: ${JSON.stringify(admitidoSemCaminho)}`,
  ].join('\n'));
});

// ═══════════════════════════════════════════════════════════════════════════
// B, C, D — vivo
// ═══════════════════════════════════════════════════════════════════════════

test('#2130 B: nenhum tipo TRATADO acumula processed = false depois do corte (com controle positivo)', async (t) => {
  if (!dbGated) return t.skip(skipMsg);
  const tratados = [...tiposComRamoNaRPC()];
  const c = sb();

  const { data: tudo, error } = await c
    .from('email_webhook_events')
    .select('event_type, processed, created_at')
    .in('event_type', tratados)
    .gte('created_at', CORTE)
    .limit(5000);
  assert.equal(error, null, `consulta falhou: ${error?.message}`);

  // CONTROLE POSITIVO, na MESMA medicao: sem ele, um periodo sem webhook nenhum daria zero orfaos e
  // este teste passaria por AUSENCIA de dado, nao por ausencia de defeito.
  if ((tudo ?? []).length === 0) {
    t.diagnostic(`nenhum evento de tipo tratado desde o corte ${CORTE}: nada a afirmar (0 e ausencia de webhook, nao ausencia de defeito)`);
    return;
  }

  const limite = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const orfaos = (tudo ?? []).filter((e) => !e.processed && e.created_at < limite);
  const porTipo = {};
  for (const e of orfaos) porTipo[e.event_type] = (porTipo[e.event_type] ?? 0) + 1;

  assert.deepEqual(porTipo, {}, [
    'Evento de tipo TRATADO parado em processed = false por mais de 24 h.',
    '',
    'Foi exatamente assim que #2130 ficou invisivel: `processed` so e escrito quando a RPC e',
    'chamada, entao um tipo que nao chega a decisao acumula silenciosamente. Se um tipo tratado',
    'acumula, a RPC esta abortando (CASE_NOT_FOUND?) ou o webhook nao a chama.',
    '',
    `Corte: ${CORTE} · eventos tratados desde o corte: ${tudo.length} · orfaos: ${orfaos.length}`,
    `Por tipo: ${JSON.stringify(porTipo)}`,
  ].join('\n'));
});

test('#2130 C: notificacao com sinal de supressao nao pode estar `delivered`', async (t) => {
  if (!dbGated) return t.skip(skipMsg);
  const c = sb();

  const { data: sup, error: e1 } = await c
    .from('email_webhook_events')
    .select('resend_id')
    .eq('event_type', 'email.suppressed')
    .not('resend_id', 'is', null)
    .limit(1000);
  assert.equal(e1, null, `consulta de supressao falhou: ${e1?.message}`);

  const ids = [...new Set((sup ?? []).map((r) => r.resend_id))];
  if (ids.length === 0) {
    t.diagnostic('nenhum evento de supressao com resend_id: nada a discriminar');
    return;
  }

  const { data: nots, error: e2 } = await c
    .from('notifications')
    .select('id, resend_id, email_delivery_status')
    .in('resend_id', ids.slice(0, 500));
  assert.equal(e2, null, `consulta de notificacoes falhou: ${e2?.message}`);

  const contraditorias = (nots ?? []).filter((n) => n.email_delivery_status === 'delivered');
  assert.deepEqual(contraditorias.map((n) => n.id), [], [
    'Notificacao marcada `delivered` cujo resend_id tem evento de supressao.',
    '',
    'As duas coisas nao podem coexistir: supressao significa que o provedor NAO entregou, e',
    'confundi-las e o erro que deixou um lider de tribo 94 dias sem e-mail parecendo atendido.',
    '',
    `Supressoes com id: ${ids.length} · notificacoes casadas: ${(nots ?? []).length} · contraditorias: ${contraditorias.length}`,
  ].join('\n'));
});

test('#2130 D: se o EF de envio foi implantado, os envios novos TEM resend_id — senao a cadeia e inerte', async (t) => {
  if (!dbGated) return t.skip(skipMsg);
  const c = sb();

  const { data, error } = await c
    .from('notifications')
    .select('id, resend_id, email_delivery_status, email_sent_at')
    .gte('email_sent_at', CORTE)
    .limit(2000);
  assert.equal(error, null, `consulta falhou: ${error?.message}`);

  const enviados = (data ?? []).filter((n) => n.email_delivery_status !== 'deduplicated');
  if (enviados.length === 0) {
    // Honesto: nenhum envio depois do corte nao e defeito nenhum. A fila estava vazia em 12/09
    // (0 pendentes), e o cron de 5 min nao envia o que nao existe. Esta camada passa a valer no
    // primeiro envio real, e e por isso que a spec pede "alguem olhando os primeiros envios".
    t.diagnostic(`nenhum envio depois do corte ${CORTE}: camada D ainda nao tem o que medir`);
    return;
  }

  const semId = enviados.filter((n) => !n.resend_id);
  assert.deepEqual(semId.length, 0, [
    'Envio posterior ao corte SEM resend_id — a captura do EF nao pegou.',
    '',
    'Este e o unico ponto que a spec de #2130 diz exigir alguem olhando: se a captura nao pegou,',
    '`email_sent_at` continua sendo escrito, `resend_id` fica nulo para sempre, e TODA a cadeia de',
    'desfecho acima fica inerte — sem nada ficar vermelho por conta propria.',
    '',
    `Envios depois do corte: ${enviados.length} · sem resend_id: ${semId.length}`,
    `Amostra: ${JSON.stringify(semId.slice(0, 5).map((n) => n.id))}`,
  ].join('\n'));
});
