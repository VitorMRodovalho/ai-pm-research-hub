// tests/contracts/2840-corpo-estruturado-em-notificacoes.test.mjs
/**
 * #2840: /notifications imprimia como texto o `body` dos resumos, que é o JSON que o e-mail consome
 * (`jsonb_build_object(...)::text` em `_management_daily_digest_cron` e nos dois resumos semanais). Prende:
 *
 *   1. o corpo do resumo diário da gestão, no formato que a migration grava, vira o resumo do dicionário com as
 *      três contagens, e nenhum pedaço do JSON sobra;
 *   2. o corpo JSON dos resumos semanais não vira corpo nenhum;
 *   3. texto comum passa intacto, inclusive o que começa com chave e não é JSON;
 *   4. a página imprime o que notificationBodyText devolve, escapado, e não lê mais `n.body` em outro lugar;
 *   5. a chave existe nos 3 dicionários com os 3 marcadores, e a página a entrega ao script.
 *
 * Por que é por chamada e não por grep: um grep provaria que a função está escrita, nunca que o JSON some.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { notificationBodyText } from '../../src/lib/notification-body.ts';

const read = (p) => readFileSync(resolve(process.cwd(), p), 'utf8');
const PAGE = maskJsComments(read('src/pages/notifications.astro'));
const CRON = read('supabase/migrations/20261008140102_2580_resumo_diario_da_gestao.sql');

const KEY = 'notifications.managementDigestSummary';

/** O dicionário é lido como texto, como nos outros guards de i18n: o .ts importa sem extensão. */
function entry(lang) {
  const m = read(`src/i18n/${lang}.ts`).match(/^  'notifications\.managementDigestSummary': '([^'\n]*)',$/m);
  return m ? m[1] : undefined;
}
const PT = entry('pt-BR');

/** Mesmas chaves, na mesma ordem, do jsonb_build_object do cron; o `body` dos itens é texto livre. */
const MANAGEMENT_BODY = JSON.stringify({
  version: 1,
  generated_at: '2026-10-29T11:00:00.123456+00:00',
  alerts: [{ severity: 'critical', title: 'Alerta A', first_seen_at: '2026-10-28T10:00:00+00:00' }],
  open_count: 3,
  resolved_24h: 1,
  items: [
    { id: 'i1', type: 'system_alert', title: 'Aviso 1', body: 'detalhe do aviso', link: '/admin', created_at: '2026-10-28T12:00:00+00:00' },
    { id: 'i2', type: 'unlinked_accounts_detected', title: 'Aviso 2', body: null, link: null, created_at: '2026-10-28T13:00:00+00:00' },
  ],
});

test('#2840 (1) o resumo diário da gestão vira as três contagens do dicionário, sem sobra do JSON', () => {
  // O produtor ainda grava estas três chaves: se o cron renomear uma, a contagem viraria 0 em silêncio.
  const producer = CRON.match(/'management_daily_digest',[\s\S]*?jsonb_build_object\(([\s\S]*?)\)::text/);
  assert.ok(producer, 'nao achei o corpo do resumo no INSERT do cron');
  for (const k of ['open_count', 'resolved_24h', 'items']) {
    assert.match(producer[1], new RegExp(`'${k}',`), `o cron nao grava mais '${k}' no corpo`);
  }

  const out = notificationBodyText('management_daily_digest', MANAGEMENT_BODY, PT);
  assert.equal(out, '3 alerta(s) em aberto · 1 resolvido(s) nas últimas 24 horas · 2 aviso(s) operacional(is)');
  assert.doesNotMatch(out, /[{}"]|version|generated_at/);
});

test('#2840 (2) o corpo JSON dos resumos semanais não vira corpo', () => {
  const member = JSON.stringify({ version: 1, sections: { cards: { overdue_7plus: [] } }, consumed_notification_ids: [] });
  const leader = JSON.stringify({ version: 2, leader_id: 'x', initiative_count: 2, generated_at: 'y', initiatives: [] });
  assert.equal(notificationBodyText('weekly_member_digest', member, PT), null);
  assert.equal(notificationBodyText('weekly_tribe_digest_leader', leader, PT), null);
  assert.equal(notificationBodyText('management_daily_digest', '[1,2]', PT), null);
});

test('#2840 (3) texto comum passa intacto', () => {
  for (const body of [
    'Seu card foi movido para Em revisão.',
    '{nome} confirmou presença',
    '  [rascunho] revisar a seção 2',
    '42',
    'null',
  ]) {
    assert.equal(notificationBodyText('card_moved', body, PT), body, `texto alterado: ${body}`);
  }
  assert.equal(notificationBodyText('card_moved', '', PT), null);
  assert.equal(notificationBodyText('card_moved', '   ', PT), null);
  assert.equal(notificationBodyText('card_moved', null, PT), null);
});

test('#2840 (4) a página imprime o texto de notificationBodyText, escapado, e não n.body', () => {
  assert.match(PAGE, /import \{ notificationBodyText \} from '\.\.\/lib\/notification-body';/);
  assert.match(
    PAGE,
    /const bodyText = notificationBodyText\(n\.type, n\.body, digestTemplate\);[\s\S]*?\$\{bodyText \? `<p [^`]*>\$\{escapeHtml\(bodyText\)\}<\/p>` : ''\}/,
  );
  assert.equal((PAGE.match(/\bn\.body\b/g) || []).length, 1, 'n.body lido fora de notificationBodyText');
});

test('#2840 (5) a chave está nos 3 dicionários e a página a entrega ao script', () => {
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    for (const ph of ['{open}', '{resolved}', '{items}']) {
      assert.ok(entry(lang)?.includes(ph), `${lang}: ${KEY} sem ${ph}`);
    }
  }
  assert.match(PAGE, /<span id="i18n-notifManagementDigest" class="hidden">\{t\('notifications\.managementDigestSummary', lang\)\}<\/span>/);
  assert.match(PAGE, /const digestTemplate = document\.getElementById\('i18n-notifManagementDigest'\)\?\.textContent \|\| '';/);
});
