/**
 * Contract #2553 (recorte do podcast): a página pública /podcast lê os episódios de UMA fonte, sem PII.
 *
 * DESENHO (spec docs/specs/2553-vitrine-producao-e-conhecimento.md, 4.1 e 4.2; decisão D4 do GP em
 * 06/10/2026): episódio de podcast é o canal `spotify` de comms_media_items, ingerido do RSS público
 * pela EF sync-comms-metrics. O site lê pela RPC SECURITY DEFINER get_public_podcast_episodes.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. Banco (estático, captura VIGENTE via latestFunctionCapture): o objeto de cada episódio tem
 *      EXATAMENTE as chaves permitidas (sem descrição, que cita pessoas e depende da D1; sem autor);
 *      a leitura é do canal spotify e só do que a rodada mais recente do sync viu; anon executa e
 *      PUBLIC não.
 *   B. EF (estático): o canal spotify tem fetcher de mídia, não exige token, e o fetcher não lê o
 *      autor do item (`dc:creator`).
 *   C. Página (estático): lê a RPC, não carrega lista de episódio escrita à mão, tem /en e /es, e
 *      toda chave i18n que usa existe nos 3 dicionários. A CSP libera o áudio e a capa do feed sem
 *      abrir frame-src.
 *   D. Banco (vivo, DB-aware): o anon chama a RPC e nenhum episódio traz chave fora da lista.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const maskJs = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

const EPISODE_KEYS = ['audio_type', 'audio_url', 'cover_url', 'duration_seconds', 'id', 'published_at', 'series', 'title'];

function capture() {
  const hit = latestFunctionCapture(ROOT, 'get_public_podcast_episodes');
  assert.ok(hit, 'get_public_podcast_episodes tem captura em supabase/migrations');
  return hit;
}
const bodyOf = (hit) => (typeof hit === 'string' ? hit : hit.block ?? hit.body ?? hit.sql);

test('A1: o objeto de cada episódio tem exatamente as chaves permitidas', () => {
  const body = bodyOf(capture());
  const m = body.match(/jsonb_agg\(\s*jsonb_build_object\(([\s\S]*?)\)\s*ORDER BY/);
  assert.ok(m, 'o episódio é montado num jsonb_build_object dentro do jsonb_agg');
  const keys = [...m[1].matchAll(/^\s*'([a-z_]+)'\s*,/gm)].map((k) => k[1]).sort();
  assert.deepEqual(keys, EPISODE_KEYS);
});

test('A2: lê o canal spotify e só o que a rodada mais recente do sync viu', () => {
  const body = bodyOf(capture());
  const eps = body.match(/eps AS \(([\s\S]*?)\n  \)/);
  assert.ok(eps, 'CTE eps presente');
  assert.match(eps[1], /WHERE m\.channel = 'spotify'/);
  assert.match(eps[1], /AND m\.synced_at >= u\.em - interval '1 hour'/);
  assert.match(body, /ultima AS \(\s*SELECT max\(m\.synced_at\) AS em\s+FROM public\.comms_media_items m\s+WHERE m\.channel = 'spotify'/);
});

test('A3: SECURITY DEFINER com search_path fixo; anon executa e PUBLIC não', () => {
  const hit = capture();
  const body = bodyOf(hit);
  assert.match(body, /SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
  const file = read(join('supabase/migrations', hit.file));
  assert.match(file, /REVOKE ALL ON FUNCTION public\.get_public_podcast_episodes\(integer\) FROM PUBLIC;/);
  assert.match(file, /GRANT EXECUTE ON FUNCTION public\.get_public_podcast_episodes\(integer\) TO anon\b/);
});

test('B1: a EF lê o RSS do spotify sem token e sem gravar o autor do item', () => {
  const ef = maskJs(read('supabase/functions/sync-comms-metrics/index.ts'));
  const fetchers = ef.match(/const MEDIA_FETCHERS[^\n]*\{\n([\s\S]*?)\n\}/);
  assert.ok(fetchers, 'MEDIA_FETCHERS presente');
  assert.match(fetchers[1], /\bspotify: fetchSpotifyMedia\b/);
  assert.match(ef, /const PUBLIC_FEED_CHANNELS = new Set\(\[[^\]]*'spotify'/);
  const worth = ef.match(/function isTokenWorthTrying[\s\S]*?\n\}/);
  assert.ok(worth, 'isTokenWorthTrying presente');
  assert.match(worth[0], /if \(PUBLIC_FEED_CHANNELS\.has\(cfg\.channel\)\) return true/);
  const fn = ef.match(/async function fetchSpotifyMedia[\s\S]*?\n\}/);
  assert.ok(fn, 'fetchSpotifyMedia presente');
  assert.match(fn[0], /channel: 'spotify'/);
  assert.match(fn[0], /media_type: 'EPISODE'/);
  assert.doesNotMatch(fn[0], /creator/i, 'o autor do item não é lido');
});

test('B2: htmlToText decodifica antes de tirar as tags e remove o < ou > que sobrar', () => {
  const ef = maskJs(read('supabase/functions/sync-comms-metrics/index.ts'));
  const fn = ef.match(/function htmlToText\(html: string\): string \{([\s\S]*?)\n\}/);
  assert.ok(fn, 'htmlToText presente');
  const body = fn[1];
  const decode = body.indexOf('xmlDecode(html)');
  const strip = body.indexOf(".replace(/<[^>]+>/g, '')");
  const sobra = body.indexOf(".replace(/[<>]/g, '')");
  assert.ok(decode >= 0, 'xmlDecode recebe o html cru');
  assert.ok(strip > decode, 'o strip de tags vem depois da decodificação');
  assert.ok(sobra > strip, 'a remoção de < e > vem depois do strip de tags');
  assert.equal((body.match(/xmlDecode\(/g) || []).length, 1, 'uma decodificação só, no início');
});

test('C1: a página lê a RPC e não carrega episódio escrito à mão', () => {
  const page = read('src/pages/podcast.astro');
  assert.match(page, /sb\.rpc\('get_public_podcast_episodes'/);
  assert.match(page, /const episodes: Episode\[\] = \(data as any\)\?\.episodes \?\? \[\];/);
  assert.doesNotMatch(page, /anchor\.fm|cloudfront\.net|open\.spotify\.com/, 'URL de episódio ou do show não mora na página');
});

test('C2: /en/podcast e /es/podcast existem e redirecionam com o idioma', () => {
  for (const [dir, lang] of [['en', 'en-US'], ['es', 'es-LATAM']]) {
    const p = `src/pages/${dir}/podcast.astro`;
    assert.ok(existsSync(join(ROOT, p)), p);
    assert.match(read(p), new RegExp(`url=/podcast\\?lang=${lang}"`));
  }
});

test('C3: toda chave podcast.* usada na página existe nos 3 dicionários', () => {
  const page = read('src/pages/podcast.astro');
  const used = [...new Set([...page.matchAll(/t\('(podcast\.[a-zA-Z.]+)'/g)].map((m) => m[1]))];
  assert.ok(used.length > 0);
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const s = read(`src/i18n/${dict}.ts`);
    for (const k of used) assert.match(s, new RegExp(`^\\s*'${k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}':`, 'm'), `${dict}: ${k}`);
  }
});

test('C4: a CSP libera o áudio e a capa do feed, sem abrir frame-src', () => {
  const ssot = read('src/lib/securityHeaders.ts');
  assert.match(ssot, /"media-src 'self' https:\/\/anchor\.fm https:\/\/d3ctxlq1ktw2nl\.cloudfront\.net; "/);
  assert.match(ssot, /"img-src [^"]*https:\/\/d3t3ozftmdmh3i\.cloudfront\.net; "/);
  assert.match(ssot, /"frame-src https:\/\/calendar\.google\.com; "/);
});

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
// SUPABASE_ANON_KEY primeiro: no CI, PUBLIC_SUPABASE_ANON_KEY é 'mock-key-for-build' no nível do job.
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && ANON_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + PUBLIC_SUPABASE_ANON_KEY required';

test('D1: o anon lê os episódios e nenhum traz chave fora da lista', { skip: dbGated ? false : skipMsg }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await anon.rpc('get_public_podcast_episodes', { p_limit: 200 });
  assert.equal(error, null, error?.message);
  assert.ok(Array.isArray(data?.episodes), 'episodes é lista');
  assert.equal(data.total, data.episodes.length, 'total conta a mesma população da lista (limite acima do total)');
  for (const e of data.episodes) {
    assert.deepEqual(Object.keys(e).sort(), EPISODE_KEYS, `episódio ${e.id}`);
  }
});
