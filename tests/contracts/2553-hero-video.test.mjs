// #2553 PR 3: o vídeo do hero da home (decisões D1 a D4 do GP, 31/10/2026).
//   A. o id mora no SSOT, e o endereço do player é o domínio sem cookies, com a legenda pela língua da página
//      (ligada por padrão só em /en e /es, porque a narração é em português);
//   B. até o clique a página não tem iframe nem pedido ao YouTube: o iframe nasce DENTRO do handler de clique;
//   C. a capa é servida daqui, com tamanho declarado, e só é pedida quando a figura entra na tela (noscript sem JS);
//   D. o frame-src da CSP tem exatamente duas origens, o Calendar e o player sem cookies;
//   E. o #hero-visitor não tem utilitário de display, senão o `hidden` que o script põe para membro perde;
//   F. textos nas 3 línguas, e a política de privacidade cita o player na seção de rastreamento.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, statSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { YOUTUBE_VIDEOS, youtubeEmbedUrl } from '../../src/data/youtube-playlists.ts';
import { CSP } from '../../src/lib/securityHeaders.ts';

const semComentarios = (s) => maskJsComments(s).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
// escape completo para montar regex a partir de texto (CodeQL js/incomplete-sanitization: escapar só o ponto não basta)
const escRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const HERO = semComentarios(readFileSync('src/components/sections/HomepageHero.astro', 'utf8'));
const PRIVACY = semComentarios(readFileSync('src/pages/privacy.astro', 'utf8'));

describe('#2553 PR 3, vídeo do hero', () => {
  it('A: o id vem do SSOT e o player é o youtube-nocookie, com a legenda pela língua da página', () => {
    assert.match(YOUTUBE_VIDEOS.homeHero, /^[A-Za-z0-9_-]{11}$/);
    const esperado = { 'pt-BR': ['pt', null], 'en-US': ['en', '1'], 'es-LATAM': ['es', '1'] };
    for (const [lang, [legenda, ligada]] of Object.entries(esperado)) {
      const u = new URL(youtubeEmbedUrl('homeHero', lang));
      assert.equal(u.origin, 'https://www.youtube-nocookie.com', lang);
      assert.equal(u.pathname, `/embed/${YOUTUBE_VIDEOS.homeHero}`, lang);
      assert.equal(u.searchParams.get('cc_lang_pref'), legenda, lang);
      assert.equal(u.searchParams.get('hl'), legenda, lang);
      assert.equal(u.searchParams.get('cc_load_policy'), ligada, `${lang}: legenda ligada só fora do pt`);
      for (const [k, v] of [['autoplay', '1'], ['playsinline', '1'], ['rel', '0']]) assert.equal(u.searchParams.get(k), v, `${lang} ${k}`);
    }
    // o componente pega o endereço do helper, nunca escrito à mão
    assert.match(HERO, /const heroVideoEmbed = youtubeEmbedUrl\('homeHero', lang\);/);
    assert.match(HERO, /<figure id="hero-video"[^>]*data-embed-src=\{heroVideoEmbed\}/);
    assert.doesNotMatch(HERO, /youtube(-nocookie)?\.com\/embed|youtu\.be\/|watch\?v=|OaIxsiY5tOA/, 'id e endereço moram no SSOT');
  });

  it('B: sem iframe no HTML do servidor; o iframe nasce no clique, com o endereço do data-embed-src', () => {
    const marcacao = HERO.slice(0, HERO.indexOf('<script'));
    assert.doesNotMatch(marcacao, /<iframe/i);
    const handler = HERO.match(/heroVideoPlay\.addEventListener\('click', \(\) => \{([\s\S]*?)\n    \}, \{ once: true \}\);/);
    assert.ok(handler, 'o handler de clique do vídeo existe');
    assert.match(handler[1], /const frame = document\.createElement\('iframe'\);\s*frame\.src = heroVideo\.dataset\.embedSrc/);
    assert.match(handler[1], /heroVideoPlay\.replaceWith\(frame\);/);
    assert.equal((HERO.match(/createElement\('iframe'\)/g) || []).length, 1, 'o único iframe é o do clique');
  });

  it('C: a capa só é pedida quando a figura entra na tela; sem JavaScript, vale a cópia em noscript', () => {
    // a <picture> que o script controla nasce sem endereço de capa: só data-srcset/data-src, e o <img> com o GIF vazio
    const viva = HERO.match(/<picture id="hero-video-capa">([\s\S]*?)<\/picture>/);
    assert.ok(viva, 'a picture da capa existe');
    assert.doesNotMatch(viva[1], /\ssrcset=/, 'nenhum srcset real antes da interseção');
    assert.match(viva[1], /<source type="image\/avif" data-srcset=\{heroCapaAvif\}/);
    assert.match(viva[1], /<img src=\{heroCapaVazia\} data-src="\/assets\/home\/hero-video-capa-960\.webp" width="960" height="540" alt=""/);
    assert.match(HERO, /const heroCapaVazia = 'data:image\/gif;base64,[A-Za-z0-9+/=]+';/);
    // o observador decide: margem 0, e a capa só carrega na interseção, copiando data-* para os atributos reais
    const obs = HERO.match(/new IntersectionObserver\(\(entradas\) => \{([\s\S]*?)\}, \{ rootMargin: '([^']*)' \}\);/);
    assert.ok(obs, 'o IntersectionObserver da capa existe');
    assert.equal(obs[2], '0px', 'sem margem: só quando a figura entra na tela');
    assert.match(obs[1], /if \(entradas\.some\(\(e\) => e\.isIntersecting\)\) \{ observador\.disconnect\(\); carregarCapa\(\); \}/);
    const carregar = HERO.match(/const carregarCapa = \(\) => \{([\s\S]*?)\n    \};/);
    assert.ok(carregar, 'carregarCapa existe');
    assert.match(carregar[1], /s\.srcset = s\.dataset\.srcset/);
    assert.match(carregar[1], /img\.src = img\.dataset\.src/);
    assert.equal((HERO.match(/carregarCapa\(\)/g) || []).length, 1, 'carregarCapa só é chamada pelo observador');
    // sem JavaScript: a cópia em noscript tem a capa de verdade
    const ns = HERO.match(/<noscript>([\s\S]*?)<\/noscript>/);
    assert.ok(ns, 'há fallback em noscript');
    assert.match(ns[1], /<source type="image\/avif" srcset=\{heroCapaAvif\}/);
    assert.match(ns[1], /<img src="\/assets\/home\/hero-video-capa-960\.webp" width="960" height="540"/);
    for (const w of [960, 1600]) {
      for (const ext of ['avif', 'webp']) {
        const arq = `public/assets/home/hero-video-capa-${w}.${ext}`;
        assert.match(HERO, new RegExp(`/assets/home/hero-video-capa-${w}\\.${ext} ${w}w`), `${arq} no srcset`);
        assert.ok(statSync(arq).size < 100_000, `${arq} passa de 100 KB`);
      }
    }
  });

  it('D: frame-src tem exatamente o Calendar e o player sem cookies', () => {
    const diretiva = CSP.match(/frame-src ([^;]*);/);
    assert.ok(diretiva, 'a CSP declara frame-src');
    assert.deepEqual(diretiva[1].trim().split(/\s+/).sort(), ['https://calendar.google.com', 'https://www.youtube-nocookie.com']);
  });

  it('E: o #hero-visitor não tem utilitário de display (o hidden de membro precisa vencer)', () => {
    const tag = HERO.match(/<div id="hero-visitor" class="([^"]*)"/);
    assert.ok(tag, '#hero-visitor existe');
    assert.doesNotMatch(tag[1], /(^|\s)([a-z0-9]+:)*(grid|flex|block|inline-flex|inline-block)(\s|$)/);
  });

  it('F: textos nas 3 línguas e a política cita o player na seção de rastreamento', () => {
    const chaves = ['homeV2.hero.videoPlay', 'homeV2.hero.videoTitle', 'homeV2.hero.videoMeta', 'homeV2.hero.videoOpenYoutube', 'privacy.s10track.youtube'];
    for (const dic of ['pt-BR', 'en-US', 'es-LATAM']) {
      const src = readFileSync(`src/i18n/${dic}.ts`, 'utf8');
      for (const k of chaves) assert.match(src, new RegExp(`'${escRe(k)}': '[^']{4,}',`), `${dic}: ${k}`);
      assert.match(src, /'privacy\.s10track\.youtube': '[^']*youtube-nocookie\.com[^']*',/, `${dic}: a política nomeia o domínio`);
    }
    const s10 = PRIVACY.match(/\{t\('privacy\.s10track\.title', lang\)\}([\s\S]*?)<\/section>/);
    assert.ok(s10, 'a seção 10 existe');
    assert.match(s10[1], /<li>\{t\('privacy\.s10track\.youtube', lang\)\}<\/li>/);
  });
});
