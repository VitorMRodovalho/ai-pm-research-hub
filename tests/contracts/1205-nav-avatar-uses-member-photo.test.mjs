import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  resolveAvatarUrl,
  sanitizeAvatarUrl,
  initialsFor,
  derivedStorageHost,
} from '../../src/lib/avatar.ts';

/**
 * #1205 — a foto do membro tem UMA fonte.
 *
 * O nav lia `user.user_metadata.avatar_url` (a foto da identidade OAuth) enquanto o card do
 * /profile lia `members.photo_url` (a foto que o membro sobe na plataforma). Quem subia foto via
 * plataforma via a foto no perfil e continuava vendo as iniciais no nav, do lado do badge de papel
 * — foi exatamente o que o William reportou (nota de voz + print, 29/07/2026). E a allowlist de XSS
 * do nav só permitia hosts de provedor OAuth, então nem lendo photo_url a imagem passaria.
 *
 * Ver `reference-ui-displays-one-source-authorizes-another`.
 */

const NAV = readFileSync('src/components/nav/Nav.astro', 'utf8');
// Host injetado de proposito: fora do runtime do Vite nao ha import.meta.env, e um teste que
// dependesse dele passaria por acidente (ou pularia calado). O caminho default e coberto abaixo.
const STORAGE_HOST = 'ldrfrvwhxsmgaabwmaik.supabase.co';
const STORAGE_PHOTO = `https://${STORAGE_HOST}/storage/v1/object/public/member-photos/avatars/x.jpg?t=1`;
const OAUTH_PHOTO = 'https://lh3.googleusercontent.com/a/abc123';

test('a foto da plataforma vence a da identidade OAuth', () => {
  assert.equal(
    resolveAvatarUrl(
      { photo_url: STORAGE_PHOTO },
      { user_metadata: { avatar_url: OAUTH_PHOTO } },
      STORAGE_HOST,
    ),
    STORAGE_PHOTO,
  );
});

test('sem foto na plataforma, cai para a identidade OAuth', () => {
  assert.equal(
    resolveAvatarUrl({ photo_url: null }, { user_metadata: { avatar_url: OAUTH_PHOTO } }, STORAGE_HOST),
    OAUTH_PHOTO,
  );
});

test('sem nenhuma das duas, devolve null (chamador desenha as iniciais)', () => {
  assert.equal(resolveAvatarUrl(null, null, STORAGE_HOST), null);
  assert.equal(resolveAvatarUrl({ photo_url: '' }, { user_metadata: {} }, STORAGE_HOST), null);
});

test('o host de Storage do proprio projeto e permitido', () => {
  // A regressao original: allowlist só com hosts OAuth rejeitava a foto da plataforma em silêncio.
  assert.equal(sanitizeAvatarUrl(STORAGE_PHOTO, STORAGE_HOST), STORAGE_PHOTO);
});

test('host desconhecido e esquema nao-http sao rejeitados', () => {
  assert.equal(sanitizeAvatarUrl('https://evil.example.com/a.jpg', STORAGE_HOST), null);
  assert.equal(sanitizeAvatarUrl('javascript:alert(1)', STORAGE_HOST), null);
  assert.equal(sanitizeAvatarUrl('data:image/png;base64,AAAA', STORAGE_HOST), null);
  assert.equal(sanitizeAvatarUrl('not a url', STORAGE_HOST), null);
  // Sem host de Storage resolvido, a foto da plataforma NAO passa: e o modo de falha que o #1205
  // teve por meses, e ele precisa continuar sendo explicito e nao um crash.
  assert.equal(sanitizeAvatarUrl(STORAGE_PHOTO, null), null);
});

test('iniciais usam duas letras em maiuscula e nao quebram em nome vazio', () => {
  assert.equal(initialsFor('William Junio'), 'WJ');
  assert.equal(initialsFor('  '), '?');
  assert.equal(initialsFor(null), '?');
});

test('o Nav resolve avatar pelo helper central, nao lendo user_metadata direto', () => {
  assert.match(
    NAV,
    /resolveAvatarUrl\(_member, _user\)/,
    'o Nav precisa resolver o avatar pelo helper (member.photo_url primeiro)',
  );
  assert.doesNotMatch(
    NAV,
    /_user\?\.user_metadata\?\.avatar_url/,
    'ler user_metadata.avatar_url direto no Nav e a regressao do #1205: ignora members.photo_url',
  );
});

test('a derivacao default do host de Storage nao lanca fora do runtime do Vite', () => {
  // Vale o contrato, nao o valor: em node nao ha import.meta.env, e o helper precisa degradar
  // para null (ou ler do env) em vez de estourar dentro do render do nav.
  const host = derivedStorageHost();
  assert.ok(host === null || typeof host === 'string');
});
