// tests/contracts/2806-site-push.test.mjs
/**
 * #2806, site do push web (veiculo 2b). Prende:
 *
 *   1. o service worker NAO guarda nada: sem handler de fetch, sem Cache API, sem importScripts; todo push vira
 *      notificacao (o Safari revoga quem nao mostra) e o clique so abre caminho do proprio site;
 *   2. o manifest tem start_url e scope relativos, display standalone e os icones de 192 e 512 que existem em disco
 *      com esse tamanho;
 *   3. o manifest so e anunciado em nucleoia.org, e esse host e a MESMA origem que o banco aceita em
 *      push_allowed_origins (os dois veiculos nao podem divergir);
 *   4. a inscricao nasce com userVisibleOnly e a chave publica VAPID valida, manda location.origin para o banco
 *      conferir contra o cabecalho, e desfaz a inscricao do navegador se o banco recusar;
 *   5. o logout cancela o push deste aparelho ANTES do signOut;
 *   6. na pagina, o service worker e registrado antes do clique e o primeiro await do clique e o subscribe.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const R = (p) => resolve(process.cwd(), p);
const read = (p) => readFileSync(R(p), 'utf8');
const SW = maskJsComments(read('public/sw.js'));
const PUSH = maskJsComments(read('src/lib/push.ts'));
const NAV = maskJsComments(read('src/components/nav/Nav.astro'));
const PAGE = maskJsComments(read('src/pages/settings/notifications.astro'));
const LAYOUT = read('src/layouts/BaseLayout.astro');

function pngSize(path) {
  const b = readFileSync(R(path));
  assert.equal(b.subarray(1, 4).toString('latin1'), 'PNG', `${path} nao e PNG`);
  return [b.readUInt32BE(16), b.readUInt32BE(20)];
}

test('#2806 site: o service worker nao guarda nada e todo push vira notificacao', () => {
  assert.doesNotMatch(SW, /addEventListener\(\s*['"]fetch['"]/, 'service worker com handler de fetch');
  assert.doesNotMatch(SW, /\bcaches\./, 'service worker usando a Cache API');
  assert.doesNotMatch(SW, /importScripts\s*\(/);
  assert.match(SW, /self\.addEventListener\('push', \(event\) => \{[\s\S]*?event\.waitUntil\(\s+self\.registration\.showNotification\(title, \{[\s\S]*?data: \{ url: safePath\(data\.url\) \},/);
});

test('#2806 site: o clique so abre caminho do proprio site', () => {
  assert.match(SW, /function safePath\(u\) \{\s+return typeof u === 'string' && u\.startsWith\('\/'\) && !u\.startsWith\('\/\/'\) && !u\.includes\('\\\\'\) \? u : FALLBACK_PATH;\s+\}/);
  assert.match(SW, /const target = new URL\(safePath\(event\.notification\.data && event\.notification\.data\.url\), self\.location\.origin\)\.href;/);
  assert.match(SW, /return self\.clients\.openWindow\(target\);/);
});

test('#2806 site: manifest relativo, standalone, com os icones de 192 e 512 em disco', () => {
  const m = JSON.parse(read('public/manifest.webmanifest'));
  assert.equal(m.start_url, '/');
  assert.equal(m.scope, '/');
  assert.equal(m.id, '/');
  assert.equal(m.display, 'standalone');
  const any = m.icons.filter((i) => (i.purpose ?? 'any') === 'any');
  for (const size of [192, 512]) {
    const icon = any.find((i) => i.sizes === `${size}x${size}` && i.type === 'image/png');
    assert.ok(icon, `icone ${size} ausente do manifest`);
    assert.deepEqual(pngSize(`public${icon.src}`), [size, size], `${icon.src} nao tem ${size}x${size}`);
  }
  for (const i of m.icons) assert.ok(i.src.startsWith('/') && !i.src.startsWith('//'), `icone com URL absoluta: ${i.src}`);
});

test('#2806 site: o manifest so sai em nucleoia.org, a mesma origem que o banco aceita', () => {
  assert.match(LAYOUT, /const isInstallHost = Astro\.url\.host === SEO_CANONICAL_HOST;/);
  assert.match(LAYOUT, /\{isInstallHost && <link rel="manifest" href="\/manifest\.webmanifest" \/>\}/);
  assert.equal(LAYOUT.split('rel="manifest"').length - 1, 1, 'um unico link de manifest, o condicionado');
  const host = read('src/lib/canonical.ts').match(/export const SEO_CANONICAL_HOST = "([^"]+)";/)?.[1];
  assert.equal(host, 'nucleoia.org');
  const mig = readdirSync(R('supabase/migrations')).filter((f) => f.endsWith('_2806_push_subscriptions.sql'));
  assert.equal(mig.length, 1);
  const origins = read(`supabase/migrations/${mig[0]}`).match(/\('push_allowed_origins', '(\[[^']*\])'::jsonb,/)?.[1];
  assert.deepEqual(JSON.parse(origins), [`https://${host}`], 'o host instalavel e a origem aceita pelo banco divergiram');
  assert.match(PUSH, /if \(w\.location\.host !== SEO_CANONICAL_HOST\) return 'other-host';/);
});

test('#2806 site: inscricao com userVisibleOnly, chave valida, origem conferida e desfeita se o banco recusar', () => {
  const key = PUSH.match(/export const VAPID_PUBLIC_KEY = '([A-Za-z0-9_-]+)';/)?.[1];
  assert.ok(key, 'VAPID_PUBLIC_KEY ausente');
  const raw = Buffer.from(key, 'base64url');
  assert.equal(raw.length, 65, 'chave publica P-256 nao comprimida tem 65 octetos');
  assert.equal(raw[0], 4);
  assert.match(PUSH, /const sub = await reg\.pushManager\.subscribe\(\{ userVisibleOnly: true, applicationServerKey: b64urlToBuffer\(VAPID_PUBLIC_KEY\) \}\);\s+try \{\s+await saveSubscription\(sb, sub\);\s+\} catch \(err\) \{\s+[^\n]*\n\s+await sub\.unsubscribe\(\)/);
  // rpcChecked lanca na falha de rede E na recusa que vem no corpo (#2704)
  assert.match(PUSH, /await rpcChecked\(sb, 'register_push_subscription', \{[\s\S]*?p_origin: location\.origin,/);
});

test('#2806 site: o logout cancela o push deste aparelho antes do signOut', () => {
  assert.match(NAV, /import \{ unregisterThisDevice \} from '\.\.\/\.\.\/lib\/push';/);
  assert.match(NAV, /\(window as any\)\.doLogout = async \(\) => \{\s+await unregisterThisDevice\(sb\);\s+await sb\.auth\.signOut\(\);/);
  assert.match(PUSH, /export async function unregisterThisDevice\(sb: RpcClient\)[\s\S]*?const reg = await navigator\.serviceWorker\.getRegistration\('\/'\);\s+if \(reg\) await disablePush\(sb, reg\);/);
});

test('#2806 site: o service worker e registrado antes do clique, e o clique vai direto ao subscribe', () => {
  const regAt = PAGE.indexOf('const reg = await registerServiceWorker();');
  const clickAt = PAGE.indexOf("toggle.addEventListener('click', async () => {");
  assert.ok(regAt > 0 && clickAt > regAt, 'registro do service worker tem de vir antes do handler do clique');
  const handler = PAGE.slice(clickAt);
  const firstAwait = handler.slice(handler.indexOf('await'));
  assert.match(firstAwait, /^await disablePush\(sb, reg\);\s+else await enablePush\(sb, reg\);/, 'o primeiro await do clique tem de ser o subscribe');
});
