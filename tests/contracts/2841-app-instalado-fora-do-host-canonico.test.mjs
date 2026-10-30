// tests/contracts/2841-app-instalado-fora-do-host-canonico.test.mjs
/**
 * #2841: o Chrome no Android instala o site como app tambem nos hosts sem manifest, e esse app nao tem push. Prende:
 *
 *   1. o BaseLayout renderiza o aviso so FORA do host canonico, com o link para a mesma pagina no host canonico;
 *   2. o aviso fica escondido numa aba e so aparece no app aberto pelo icone (display-mode: standalone), na mesma
 *      classe que envolve o aviso;
 *   3. o texto e o link nomeiam o host canonico e existem nos 3 dicionarios.
 *
 * Quem decide o (2) e o navegador; este guard prende a regra, e a PR leva a medicao num Chromium com o display-mode
 * emulado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const read = (p) => readFileSync(resolve(process.cwd(), p), 'utf8');
const LAYOUT = read('src/layouts/BaseLayout.astro');
const NOTICE = read('src/components/notifications/OtherHostAppNotice.astro');

test('#2841 (1) o aviso so sai fora do host canonico, apontando para a mesma pagina nele', () => {
  assert.match(LAYOUT, /const isInstallHost = Astro\.url\.host === SEO_CANONICAL_HOST;/);
  assert.match(LAYOUT, /const seoCanonicalUrl = new URL\(Astro\.url\.pathname, SEO_CANONICAL_ORIGIN\)\.href;/);
  assert.match(LAYOUT, /\{!isInstallHost && <OtherHostAppNotice lang=\{lang\} href=\{seoCanonicalUrl\} \/>\}/);
  assert.equal(LAYOUT.split('<OtherHostAppNotice').length - 1, 1, 'um unico aviso, o condicionado');
  assert.match(NOTICE, /<a href=\{href\} rel="noopener"/);
});

test('#2841 (2) escondido na aba, visivel so no app instalado', () => {
  const style = NOTICE.slice(NOTICE.indexOf('<style>'), NOTICE.indexOf('</style>'));
  assert.match(NOTICE, /^<div class="other-host-app-notice[ "]/m, 'a classe tem de estar no elemento que envolve o aviso');
  assert.match(style, /^  \.other-host-app-notice \{\s+display: none;\s+\}/m, 'fora do app o aviso nao aparece');
  assert.match(
    style,
    /@media \(display-mode: standalone\) \{\s+\.other-host-app-notice \{\s+display: block;\s+\}\s+\}/,
    'no app instalado o aviso aparece',
  );
  assert.doesNotMatch(NOTICE, /\bhidden\b/, 'atributo hidden venceria o CSS do app');
});

test('#2841 (3) o texto nomeia o host canonico e existe nos 3 dicionarios', () => {
  assert.match(NOTICE, /import \{ SEO_CANONICAL_HOST \} from '\.\.\/\.\.\/lib\/canonical';/);
  for (const key of ['text', 'link']) {
    assert.match(NOTICE, new RegExp(`\\{t\\('otherHostApp\\.${key}', lang\\)\\.replace\\('\\{host\\}', SEO_CANONICAL_HOST\\)\\}`));
    for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
      const m = read(`src/i18n/${lang}.ts`).match(new RegExp(`^  'otherHostApp\\.${key}': '([^'\\n]+)',$`, 'm'));
      assert.ok(m, `${lang}: falta otherHostApp.${key}`);
      assert.ok(m[1].includes('{host}'), `${lang}: otherHostApp.${key} sem {host}`);
    }
  }
});
