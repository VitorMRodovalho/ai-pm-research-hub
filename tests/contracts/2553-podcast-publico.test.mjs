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
 *   E. Idioma do áudio (decisão do GP em 06/10/2026): a EF grava o <language> do item, ou o do canal,
 *      como tag BCP 47; a página mostra o selo só quando o áudio está noutro idioma que o da página, com
 *      o nome vindo do Intl e nenhum nome de idioma escrito à mão.
 *   F. YouTube (decisão do GP em 07/10/2026): a RPC liga o episódio ao vídeo já ingerido do canal cujo título
 *      contém o título do episódio, publicado até 7 dias antes ou depois, o mais próximo; a página tem o botão
 *      da playlist das pílulas pela fonte única de playlists e o link do vídeo só quando ele existe.
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

const EPISODE_KEYS = ['audio_language', 'audio_type', 'audio_url', 'cover_url', 'duration_seconds', 'id', 'published_at', 'series', 'title', 'video_url'];

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

test('B2: htmlToText decodifica, tira as tags até o ponto fixo e remove o < ou > que sobrar', () => {
  const ef = maskJs(read('supabase/functions/sync-comms-metrics/index.ts'));
  const fn = ef.match(/function htmlToText\(html: string\): string \{([\s\S]*?)\n\}/);
  assert.ok(fn, 'htmlToText presente');
  const body = fn[1];
  const decode = body.indexOf('let text = xmlDecode(html)');
  const loop = body.match(/do \{\s*prev = text\s*text = text\.replace\(\/<\[\^<>\]\*>\/g, ''\)\s*\} while \(text !== prev\)/);
  const sobra = body.indexOf("return text.replace(/[<>]/g, '')");
  assert.ok(decode >= 0, 'xmlDecode recebe o html cru');
  assert.ok(loop, 'o strip de tags roda num laço até o texto parar de mudar');
  assert.ok(loop.index > decode, 'o laço vem depois da decodificação');
  assert.ok(sobra > loop.index, 'a remoção de < e > vem depois do laço');
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

test('E1: a EF grava o idioma do áudio a partir do <language> do item ou do canal', () => {
  const ef = maskJs(read('supabase/functions/sync-comms-metrics/index.ts'));
  const fn = ef.match(/async function fetchSpotifyMedia[\s\S]*?\n\}/);
  assert.ok(fn, 'fetchSpotifyMedia presente');
  assert.match(fn[0], /const feedLanguage = normalizeLanguageTag\(xmlText\(xml\.split\(\/<item\\b\/\)\[0\], 'language'\)\)/);
  assert.match(fn[0], /audio_language: normalizeLanguageTag\(xmlText\(block, 'language'\)\) \?\? feedLanguage,/);
  const norm = ef.match(/function normalizeLanguageTag\(v: string \| null\): string \| null \{([\s\S]*?)\n\}/);
  assert.ok(norm, 'normalizeLanguageTag presente');
  assert.match(norm[1], /if \(!m\) return null/);
  assert.match(norm[1], /return m\[2\] \? `\$\{m\[1\]\.toLowerCase\(\)\}-\$\{m\[2\]\.toUpperCase\(\)\}` : m\[1\]\.toLowerCase\(\)/);
});

test('E2: a página mostra o selo só quando o áudio está noutro idioma, com o nome vindo do Intl', () => {
  const page = maskJs(read('src/pages/podcast.astro'));
  const fn = page.match(/function audioLanguageLabel\(tag: string \| null\): string \| null \{([\s\S]*?)\n\}/);
  assert.ok(fn, 'audioLanguageLabel presente');
  assert.match(fn[1], /if \(!tag \|\| tag\.split\('-'\)\[0\]\.toLowerCase\(\) === pageLanguage\) return null;/);
  assert.match(fn[1], /name = new Intl\.DisplayNames\(\[locale\], \{ type: 'language' \}\)\.of\(tag\) \?\? tag;/);
  assert.match(fn[1], /return t\('podcast\.audioLanguage', lang\)\.replace\('\{language\}', name\);/);
  assert.match(page, /const pageLanguage = locale\.split\('-'\)\[0\];/);
  assert.match(page, /const audioLabel = audioLanguageLabel\(e\.audio_language\);/);
  assert.match(page, /\{audioLabel && \(\s+<p class="podcast-audio-lang[^"]*">[\s\S]*?\{audioLabel\}\s+<\/p>/);
});

test('E3: nenhum nome de idioma escrito à mão na página nem no aviso', () => {
  const page = read('src/pages/podcast.astro');
  assert.doesNotMatch(page, /portugu[eêé]s|portuguese|ingl[eê]s|english|espa[nñ]ol|spanish/i, 'o nome do idioma vem do Intl');
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const linha = read(`src/i18n/${dict}.ts`).match(/^\s*'podcast\.audioLanguage': '([^']*)',/m);
    assert.ok(linha, `${dict}: podcast.audioLanguage`);
    assert.match(linha[1], /\{language\}/, `${dict}: o texto tem o marcador do idioma`);
    assert.doesNotMatch(linha[1], /portugu|english|ingl|espa|spanish/i, `${dict}: sem nome de idioma fixo`);
  }
});

test('F1: a RPC liga o episódio ao vídeo publicado do canal pelo título, na janela de 7 dias, o mais próximo', () => {
  const body = bodyOf(capture());
  assert.match(body, /'video_url', CASE WHEN v\.video_id IS NOT NULL THEN 'https:\/\/www\.youtube\.com\/watch\?v=' \|\| v\.video_id END/);
  const lat = body.match(/LEFT JOIN LATERAL \(([\s\S]*?)\) v ON true/);
  assert.ok(lat, 'o vínculo é um LEFT JOIN LATERAL v');
  const b = lat[1];
  assert.match(b, /WHERE y\.channel = 'youtube'\s+AND y\.media_type = 'VIDEO'/);
  assert.match(b, /AND y\.external_id ~ '\^\[A-Za-z0-9_-\]\{11\}\$'/, 'só id de vídeo do YouTube vira URL');
  assert.match(b, /AND y\.published_at IS NOT NULL\s+AND y\.published_at <= now\(\)/, 'vídeo agendado não entra');
  assert.match(b, /AND y\.published_at BETWEEN e\.published_at - interval '7 days' AND e\.published_at \+ interval '7 days'/);
  assert.match(b, /AND length\(e\.title\) >= 15/, 'título curto não casa com nada');
  assert.match(b, /AND strpos\(lower\(y\.caption\), lower\(e\.title\)\) > 0/);
  assert.match(b, /ORDER BY abs\(extract\(epoch FROM \(y\.published_at - e\.published_at\)\)\)\s+LIMIT 1/);
});

test('F2: a página tem o botão da playlist pela fonte única e o link do vídeo só quando ele existe', () => {
  const page = maskJs(read('src/pages/podcast.astro'));
  assert.match(page, /import \{ getPlaylistUrl \} from '\.\.\/data\/youtube-playlists';/);
  assert.match(page, /<a href=\{getPlaylistUrl\('pills'\)\}[^>]*class="podcast-youtube[^"]*">[\s\S]*?\{t\('podcast\.watchYoutube', lang\)\}\s+<\/a>/);
  assert.match(page, /\{e\.video_url && \(\s+<a href=\{e\.video_url\}[^>]*class="podcast-video[^"]*">[\s\S]*?\{t\('podcast\.watchVideo', lang\)\}\s+<\/a>/);
  assert.doesNotMatch(page, /youtube\.com\/(watch|playlist)|youtu\.be\//, 'nenhum vídeo ou playlist escrito à mão na página');
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
