// tests/contracts/2806-notification-bell-mobile.test.mjs
/**
 * #2806: o balao do sino no celular e no app instalado.
 *
 *   1. no celular o balao ocupa a largura da tela abaixo do nav; os 350 px presos a direita do sino ficam so do sm
 *      para cima (medido num Pixel: viewport de 485 px, balao comecando em -44 px);
 *   2. o toque no aviso leva ao link dele, filtrado por safeNavigationUrl, e a linha mostra o titulo do aviso;
 *   3. os textos do balao vem do dicionario (os tres idiomas) pelo pacote global, nada em ingles fixo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const R = (p) => resolve(process.cwd(), p);
const BELL = maskJsComments(readFileSync(R('src/components/notifications/NotificationBell.tsx'), 'utf8'));
const LAYOUT = readFileSync(R('src/layouts/BaseLayout.astro'), 'utf8');

test('#2806 sino: no celular o balao cabe na tela; 350 px a direita do sino so do sm para cima', () => {
  assert.match(BELL, /\{open && \(\s+<div className="fixed inset-x-2 top-14 sm:absolute sm:inset-x-auto sm:right-0 sm:top-full sm:mt-1 sm:w-\[350px\] [^"]*"/);
  assert.doesNotMatch(BELL, /className="[^"]*(?<![:\w-])absolute right-0 [^"]*w-\[350px\]/, 'balao absoluto de 350 px sem o prefixo sm:');
});

test('#2806 sino: o toque leva ao link filtrado e a linha mostra o titulo', () => {
  assert.match(BELL, /const openNotification = async \(n: Notification\) => \{\s+if \(!n\.is_read\) await markRead\(n\.id\);\s+const href = safeNavigationUrl\(n\.link\);\s+if \(href\) window\.location\.href = href;\s+\};/);
  assert.match(BELL, /onClick=\{\(\) => openNotification\(n\)\}/);
  assert.match(BELL, /\{n\.title \|\| n\.type\.replace\(\/_\/g, ' '\)\}/);
});

test('#2806 sino: textos do dicionario, nos tres idiomas, pelo pacote global', () => {
  for (const s of ['>Notifications<', 'Mark all read', 'No notifications.', 'aria-label="Notifications"', "'now'"]) {
    assert.ok(!BELL.includes(s), `texto fixo no sino: ${s}`);
  }
  const keys = [...new Set([...BELL.matchAll(/t\('(comp\.notificationBell\.[a-zA-Z]+)'/g)].map((m) => m[1]))];
  assert.ok(keys.length >= 8, `chaves do sino achadas: ${keys.length}`);
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = readFileSync(R(`src/i18n/${lang}.ts`), 'utf8');
    for (const k of keys) assert.match(dict, new RegExp(`\\n  '${k.replace(/\./g, '\\.')}': '[^']+',\\n`), `${lang}: ${k}`);
  }
  assert.match(LAYOUT, /const globalI18nBundle = buildPageI18n\(\[[^\]]*'comp\.notificationBell'[^\]]*\], lang\);/);
});
