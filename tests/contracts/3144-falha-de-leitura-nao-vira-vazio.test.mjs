/**
 * #3144: falha de leitura não vira lista vazia nem documento inválido.
 *
 * /attendance descartava o `error` do RPC (o supabase-js não lança), e a falha virava "Nenhum evento
 * encontrado". /certificates mostrava "Nenhum certificado" sem ter lido. /verify dizia a um terceiro que
 * um documento genuíno é inválido quando a chamada falhava. O limite de taxa da #991 continua indistinto
 * de não encontrado, porque chega como dado ({valid:false}), não como erro.
 *
 * Comentários JS saem antes do assert.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments as mask } from '../helpers/guard-pin-staleness.mjs';

const read = (p) => readFileSync(resolve(process.cwd(), p), 'utf8');
const ATT = mask(read('src/pages/attendance.astro'));
const CERTS = mask(read('src/pages/certificates.astro'));
const VERIFY = mask(read('src/pages/verify/[code].astro'));
const LANGS = ['pt-BR', 'en-US', 'es-LATAM'];

function slice(src, from, to) {
  const a = src.indexOf(from);
  assert.ok(a >= 0, `achou ${from}`);
  const b = src.indexOf(to, a + from.length);
  assert.ok(b > a, `achou o fim depois de ${from}`);
  return src.slice(a, b);
}

test('#3144 A4: /attendance lança no erro do RPC e mostra o texto de falha, não a lista vazia', () => {
  const fn = slice(ATT, 'async function loadEvents() {', "if (!(window as any).__attendanceDelegationBound)");
  assert.match(fn,
    /const \{ data, error \} = await sb\.rpc\('get_events_with_attendance', \{ p_limit: 500, p_offset: 0 \}\);\s+if \(error\) throw error;\s+ALL_EVENTS = data \|\| \[\];/,
    'attendance: o erro do RPC é lançado antes de virar lista');
  assert.match(fn, /\} catch \(e\) \{[\s\S]*?el\.innerHTML = `<div [^>]*data-events-load-failed>\$\{I18N\.loadFailed\}<\/div>`;\s+toast\(I18N\.loadFailed, 'error'\);/,
    'attendance: o catch mostra a falha traduzida');
  assert.match(ATT, /loadFailed: t\('attendance\.loadFailed', lang\),/, 'attendance: a chave vai ao script');
});

test('#3144 A5: /certificates sem cliente ou com erro diz que não carregou, não "nenhum certificado"', () => {
  assert.match(CERTS,
    /if \(!sb\) \{ container\.innerHTML = `<p [^>]*data-certs-load-failed>\$\{t\('certificates\.loadFailed', lang\)\}<\/p>`; return; \}/,
    'certificates: sem cliente, texto de falha');
  assert.match(CERTS,
    /\} catch \(e\) \{\s+console\.error\('Certificates load failed:', e\);\s+container\.innerHTML = `<p [^>]*data-certs-load-failed>\$\{t\('certificates\.loadFailed', lang\)\}<\/p>`;/,
    'certificates: no catch, texto de falha');
  const empties = CERTS.match(/t\('certificates\.empty', lang\)/g) || [];
  assert.equal(empties.length, 1, 'certificates: "nenhum certificado" só no ramo da lista vazia');
  assert.match(CERTS, /if \(!data\?\.length\) \{\s+container\.innerHTML = `<div class="text-center py-12">[\s\S]*?t\('certificates\.empty', lang\)/,
    'certificates: e esse único uso é o da lista vazia');
});

test('#3144 A11: /verify sem cliente ou com erro diz que não verificou, e só {valid:false} vira inválido', () => {
  const fn = slice(VERIFY, 'async function doVerify(code: string) {', "document.getElementById('verify-form')");
  assert.match(fn, /if \(!sb\) \{\s+if \(loading\) loading\.classList\.add\('hidden'\);\s+result\.classList\.remove\('hidden'\);\s+result\.innerHTML = renderUnavailable\(lang\);\s+return;\s+\}/,
    'verify: sem cliente, indisponível');
  assert.match(fn, /if \(error\) throw error;\s+if \(loading\) loading\.classList\.add\('hidden'\);\s+result\.classList\.remove\('hidden'\);\s+result\.innerHTML = renderResult\(data, lang\);/,
    'verify: o resultado do RPC (inclusive o limite de taxa) passa por renderResult');
  assert.match(fn, /\} catch \(err\) \{\s+console\.error\('Verify failed:', err\);\s+if \(loading\) loading\.classList\.add\('hidden'\);\s+result\.classList\.remove\('hidden'\);\s+result\.innerHTML = renderUnavailable\(lang\);/,
    'verify: no catch, indisponível');
  assert.doesNotMatch(fn, /renderResult\(null/, 'verify: nenhum caminho de falha declara o documento inválido');
  const un = slice(VERIFY, 'function renderUnavailable(lang: Lang): string {', 'async function doVerify');
  assert.match(un, /t\('verify\.unavailable', lang\)[\s\S]*t\('verify\.unavailableHint', lang\)/, 'verify: o estado indisponível usa as chaves próprias');
  assert.doesNotMatch(un, /verify\.invalid/, 'verify: e não o texto de inválido');
});

test('#3144: as chaves novas existem nos 3 idiomas', () => {
  for (const lang of LANGS) {
    const d = read(`src/i18n/${lang}.ts`);
    for (const k of ['attendance.loadFailed', 'certificates.loadFailed', 'verify.unavailable', 'verify.unavailableHint']) {
      assert.match(d, new RegExp(`'${k.replaceAll('.', '\\.')}': (?:"[^"]+"|'[^']+'),`), `${lang}: ${k}`);
    }
  }
});
