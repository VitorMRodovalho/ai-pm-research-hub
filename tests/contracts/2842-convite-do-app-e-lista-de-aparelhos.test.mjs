// tests/contracts/2842-convite-do-app-e-lista-de-aparelhos.test.mjs
/**
 * #2842: instalar o app zera a permissao de notificacao e derruba a inscricao, sem aviso, e a tela contava como
 * ativo o aparelho morto. Prende:
 *
 *   1. o nome do aparelho sai do user agent na ordem certa (Edge e Samsung Internet antes do Chrome, iOS antes do
 *      macOS, Android antes do Linux);
 *   2. cada aparelho mostra a data do ultimo aviso entregue, "nunca" ou "parou de receber", e a contagem e so dos
 *      que o envio ainda tenta;
 *   3. a pagina monta a lista com textContent a partir dessas funcoes;
 *   4. desligar o push em /settings/notifications encerra o convite neste aparelho;
 *   5. o convite so e renderizado no host instalavel, so aparece no app, sem dispensa e sem inscricao ativa, registra
 *      o service worker antes do clique e o primeiro await do clique e o subscribe;
 *   6. as chaves estao nos 3 dicionarios, com os marcadores.
 *
 * (1) e (2) chamam as funcoes de verdade: um grep provaria que estao escritas, nunca o que devolvem.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { deviceName, describePushDevice, activePushDeviceCount } from '../../src/lib/push-devices.ts';

const read = (p) => readFileSync(resolve(process.cwd(), p), 'utf8');
const PAGE = maskJsComments(read('src/pages/settings/notifications.astro'));
const PUSH = maskJsComments(read('src/lib/push.ts'));
const INVITE = maskJsComments(read('src/components/notifications/PushInvite.astro'));
const LAYOUT = read('src/layouts/BaseLayout.astro');

const LABELS = {
  device: '{browser}, {os}',
  unknown: 'desconhecido',
  lastSuccess: 'ultimo em {date}',
  never: 'nunca',
  disabled: 'parou em {date}',
};

test('#2842 (1) o nome do aparelho sai do user agent na ordem certa', () => {
  const cases = [
    ['Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36', 'Chrome, Android'],
    ['Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36 EdgA/130.0.0.0', 'Edge, Android'],
    ['Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/26.0 Chrome/122.0.0.0 Mobile Safari/537.36', 'Samsung Internet, Android'],
    ['Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1', 'Safari, iOS'],
    ['Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0.0.0 Mobile/15E148 Safari/604.1', 'Chrome, iOS'],
    ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0', 'Edge, Windows'],
    ['Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15', 'Safari, macOS'],
    ['Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0', 'Firefox, Linux'],
    ['', 'desconhecido'],
    [null, 'desconhecido'],
  ];
  for (const [ua, expected] of cases) assert.equal(deviceName(ua, LABELS), expected, `user agent: ${ua}`);
});

test('#2842 (2) cada aparelho diz quando recebeu, e a contagem e so do que o envio tenta', () => {
  const ua = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
  const fmt = (iso) => `D(${iso})`;
  const ok = { user_agent: ua, created_at: '2026-10-28T10:00:00Z', last_success_at: '2026-10-29T23:16:00Z', disabled_at: null };
  const never = { user_agent: ua, created_at: '2026-10-30T10:00:00Z', last_success_at: null, disabled_at: null };
  const dead = { user_agent: ua, created_at: '2026-10-20T10:00:00Z', last_success_at: '2026-10-21T10:00:00Z', disabled_at: '2026-10-25T10:00:00Z' };
  assert.equal(describePushDevice(ok, LABELS, fmt), 'Chrome, Android · ultimo em D(2026-10-29T23:16:00Z)');
  assert.equal(describePushDevice(never, LABELS, fmt), 'Chrome, Android · nunca');
  assert.equal(describePushDevice(dead, LABELS, fmt), 'Chrome, Android · parou em D(2026-10-25T10:00:00Z)');
  assert.equal(activePushDeviceCount([ok, never, dead]), 2);
  assert.equal(activePushDeviceCount([]), 0);
});

test('#2842 (3) a pagina lista os aparelhos com textContent a partir das funcoes', () => {
  assert.match(PAGE, /import \{ describePushDevice, activePushDeviceCount \} from '\.\.\/\.\.\/lib\/push-devices';/);
  const start = PAGE.indexOf('const showDevices = async () => {');
  assert.ok(start > 0, 'showDevices nao encontrado');
  const body = PAGE.slice(start, PAGE.indexOf('\n      };', start));
  assert.match(body, /i18n\.pushDevices\.replace\('\{n\}', String\(activePushDeviceCount\(rows\)\)\)/);
  assert.match(body, /deviceListEl\.replaceChildren\(\.\.\.rows\.map\(\(row: any\) => \{\s+const li = document\.createElement\('li'\);\s+li\.textContent = describePushDevice\(row, i18n\.pushDeviceLabels, /);
  assert.doesNotMatch(body, /innerHTML|data\.length/);
  for (const [field, key] of [['device', 'Name'], ['unknown', 'Unknown'], ['lastSuccess', 'Last'], ['never', 'Never'], ['disabled', 'Disabled']]) {
    assert.match(PAGE, new RegExp(`${field}: t\\('settings\\.notifications\\.pushDevice${key}', lang\\),`));
  }
});

test('#2842 (4) desligar o push nas configuracoes encerra o convite neste aparelho', () => {
  assert.match(PAGE, /if \(on\) await disablePush\(sb, reg\);\s+else await enablePush\(sb, reg\);\s+if \(on\) dismissPushInvite\(\);\s+on = !on;/);
  assert.match(
    PUSH,
    /export function pushInviteDismissed\(\): boolean \{\s+try \{\s+return localStorage\.getItem\(PUSH_INVITE_DISMISSED_KEY\) === '1';/,
  );
  assert.match(PUSH, /export function dismissPushInvite\(\): void \{\s+try \{\s+localStorage\.setItem\(PUSH_INVITE_DISMISSED_KEY, '1'\);/);
});

test('#2842 (5) o convite: so no host instalavel, so no app, e o clique vai direto ao subscribe', () => {
  assert.match(LAYOUT, /const isInstallHost = Astro\.url\.host === SEO_CANONICAL_HOST;/);
  assert.match(LAYOUT, /\{isInstallHost && <PushInvite lang=\{lang\} \/>\}/);
  assert.match(PUSH, /if \(isIos && !isInstalledApp\(w\)\) return 'ios-not-installed';/);
  assert.match(PUSH, /export function isInstalledApp\(w: Window\): boolean \{[\s\S]*?return w\.matchMedia\?\.\('\(display-mode: standalone\)'\)\.matches === true \|\| nav\.standalone === true;/);

  const gate = INVITE.indexOf("if (!isInstalledApp(window) || pushInviteDismissed() || pushSupport(window) !== 'ok') return;");
  const reg = INVITE.indexOf('const reg = await registerServiceWorker();');
  const active = INVITE.indexOf("if (existing && Notification.permission === 'granted') return;");
  const show = INVITE.indexOf('box.hidden = false;');
  const click = INVITE.indexOf("enableBtn.addEventListener('click', async () => {");
  assert.ok(gate > 0 && reg > gate && active > reg && show > active && click > show,
    `ordem errada: gate=${gate} reg=${reg} active=${active} show=${show} click=${click}`);
  const handler = INVITE.slice(click);
  assert.match(handler.slice(handler.indexOf('await')), /^await enablePush\(sb, reg\);\s+box\.hidden = true;/, 'o primeiro await do clique tem de ser o subscribe');
  assert.match(INVITE, /laterBtn\.addEventListener\('click', \(\) => \{\s+dismissPushInvite\(\);\s+box\.hidden = true;\s+\}\);/);
});

test('#2842 (6) as chaves estao nos 3 dicionarios, com os marcadores', () => {
  const keys = {
    'settings.notifications.pushDeviceName': ['{browser}', '{os}'],
    'settings.notifications.pushDeviceUnknown': [],
    'settings.notifications.pushDeviceLast': ['{date}'],
    'settings.notifications.pushDeviceNever': [],
    'settings.notifications.pushDeviceDisabled': ['{date}'],
    'pushInvite.text': [],
    'pushInvite.enable': [],
    'pushInvite.later': [],
    'pushInvite.error': [],
  };
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = read(`src/i18n/${lang}.ts`);
    for (const [key, placeholders] of Object.entries(keys)) {
      const m = dict.match(new RegExp(`^  '${key.replace(/\./g, '\\.')}': '([^'\\n]+)',$`, 'm'));
      assert.ok(m, `${lang}: falta ${key}`);
      for (const ph of placeholders) assert.ok(m[1].includes(ph), `${lang}: ${key} sem ${ph}`);
    }
  }
  for (const key of ['text', 'enable', 'later', 'error']) {
    assert.match(read('src/components/notifications/PushInvite.astro'), new RegExp(`t\\('pushInvite\\.${key}', lang\\)`));
  }
});
