/**
 * #3141: preferências de notificação numa tela só.
 *
 * O cartão do perfil gravava por update_notification_preferences colunas que ninguém lê (enabled,
 * email_digest), silenciava tipos que nenhum produtor emite (assignment, mention) e substituía
 * muted_types inteiro, apagando o que /settings/notifications tinha silenciado. O perfil passa a
 * apontar para /settings/notifications, que grava o que é lido e passa a oferecer os tipos reais
 * que só o perfil tinha, sem apagar no salvar o que já estava silenciado e ela não lista.
 *
 * Comentários JS e HTML saem antes do assert.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { maskJsComments as mask } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
// o cartão é HTML dentro de template: comentário HTML também some da tela. A remoção repete até
// estabilizar, para um comentário montado por remoções anteriores também sair.
function stripHtmlComments(src) {
  let out = src;
  let prev;
  do {
    prev = out;
    out = out.replace(/<!--[\s\S]*?-->/g, '');
  } while (out !== prev);
  return out;
}
const PROFILE = stripHtmlComments(mask(read('src/pages/profile.astro')));
const SETTINGS = mask(read('src/pages/settings/notifications.astro'));
const NEW_TYPES = ['curation_status', 'attendance_detractor', 'cr_approved', 'certificate_issued'];

function typeKeys() {
  const m = SETTINGS.match(/const NOTIFICATION_TYPE_KEYS = \[([\s\S]*?)\];/);
  assert.ok(m, 'settings: a lista NOTIFICATION_TYPE_KEYS existe');
  return [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]);
}

test('#3141: a remoção de comentário HTML não deixa sobrar um comentário montado pela passada anterior', () => {
  // numa passada só, '<!<!-- a -->-- b -->' vira '<!-- b -->', e o link escondido ali contaria como visível
  assert.equal(stripHtmlComments('<!<!-- a -->-- b --><a data-notif-settings-link>'), '<a data-notif-settings-link>');
  assert.equal(stripHtmlComments('<!<!<!-- a -->-- b -->-- c -->x'), 'x');
  assert.equal(stripHtmlComments('sem comentário'), 'sem comentário');
});

test('#3141: o perfil não grava nem lê preferências; o cartão leva à tela única', () => {
  assert.doesNotMatch(PROFILE, /update_notification_preferences/, 'perfil: sem o RPC que gravava colunas que ninguém lê');
  assert.doesNotMatch(PROFILE, /from\('notification_preferences'\)/, 'perfil: sem leitura própria das preferências');
  assert.doesNotMatch(PROFILE, /set_my_muted_notification_types/, 'perfil: não substitui muted_types');
  assert.match(PROFILE,
    /<div [^>]*data-notif-settings-card>[\s\S]*?\$\{PROFILE_I18N\.notifPrefsTitle\}[\s\S]*?<a href="\$\{lp\}\/settings\/notifications" data-notif-settings-link/,
    'perfil: o cartão de preferências tem o link para /settings/notifications com o prefixo de idioma');
});

test('#3141: a tela única oferece os tipos que só o perfil tinha, com rótulo nos 3 idiomas', () => {
  const keys = typeKeys();
  for (const k of NEW_TYPES) {
    assert.ok(keys.includes(k), `settings: ${k} na lista de silenciáveis`);
    assert.match(SETTINGS, new RegExp(`\\b${k}: t\\('notification\\.type\\.${k}', lang\\)`), `settings: rótulo de ${k}`);
    for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
      assert.match(read(`src/i18n/${lang}.ts`), new RegExp(`'notification\\.type\\.${k}': '[^']+'`), `${lang}: notification.type.${k}`);
    }
  }
});

test('#3141: todo tipo silenciável é emitido por algum produtor (nada de tipo que não existe)', () => {
  const dirs = ['supabase/migrations', 'supabase/functions'];
  const files = [];
  const walk = (d) => {
    for (const e of readdirSync(resolve(ROOT, d), { withFileTypes: true })) {
      const p = join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (/\.(sql|ts)$/.test(e.name)) files.push(p);
    }
  };
  dirs.forEach(walk);
  const corpus = files.map((f) => read(f)).join('\n');
  for (const k of typeKeys()) {
    assert.ok(corpus.includes(`'${k}'`), `o tipo ${k} aparece como literal em alguma migration ou Edge Function`);
  }
});

test('#3141: salvar os silenciados mantém os já silenciados que a tela não lista', () => {
  assert.match(SETTINGS,
    /const muted: string\[\] = currentMuted\.filter\(k => !NOTIFICATION_TYPE_KEYS\.includes\(k\)\);\s+list\.querySelectorAll\('input\[type="checkbox"\]:checked'\)\.forEach\(el => \{\s+muted\.push\(\(el as HTMLInputElement\)\.dataset\.type!\);\s+\}\);[\s\S]{0,200}?sb\.rpc\('set_my_muted_notification_types', \{ p_muted_types: muted \}\)/,
    'settings: o array enviado parte do que já estava silenciado fora da lista, soma os marcados e é o que vai ao RPC');
});
