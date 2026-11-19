/**
 * Visitante logado sem linha em members: o texto e os botões apontam o caminho que existe.
 *
 * profile, attendance e gamification diziam a quem entrou sem cadastro "fale com o gestor para ser
 * incluído como membro" ou "cadastre-se como membro". Nenhum dos dois é o caminho: a entrada é pela
 * seleção, e quem já foi aprovado com outro e-mail vincula a conta em /claim/start. O gestor fica
 * como contato para dúvidas.
 *
 * Cada asserção recorta o bloco que a página mostra a esse visitante e amarra o link ao seu destino
 * e ao seu rótulo, sobre o corpo com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => `src/i18n/${l}.ts`);

// bloco que a página revela ao visitante logado sem cadastro: [arquivo, marcador de início, fim, chave do texto]
const BLOCKS = [
  ['src/pages/profile.astro', '<div id="profile-not-registered"', '<script', 'guest.contactAdmin'],
  ['src/pages/attendance.astro', '<p id="auth-not-found-msg"', '</p>', 'guest.contactAdmin'],
  ['src/pages/gamification.astro', '<div id="guest-banner"', '</p>', 'guest.limitedAccess'],
];

const blockOf = (file, startMark, endMark) => {
  const src = maskAstro(read(file));
  const i = src.indexOf(startMark);
  assert.ok(i >= 0, `${file}: bloco ${startMark} presente`);
  const j = src.indexOf(endMark, i + startMark.length);
  assert.ok(j > i, `${file}: fim do bloco encontrado`);
  return src.slice(i, j);
};

for (const [file, startMark, endMark, textKey] of BLOCKS) {
  test(`${file}: o bloco do visitante sem cadastro aponta seleção e vínculo, e o gestor não é o caminho`, () => {
    const block = blockOf(file, startMark, endMark);
    assert.match(block, new RegExp(`\\{t\\('${esc(textKey)}', lang\\)\\}`), `o bloco mostra ${textKey}`);
    assert.match(block, /<a id="guest-apply-cta" href=\{`\$\{langPrefix\}\/#join`\}[^>]*>\s*\{t\('guest\.applyCta', lang\)\}/,
      'o link "como participar" leva à seção #join da home, no idioma da página');
    assert.match(block, /<a id="guest-claim-cta" href=\{`\$\{langPrefix\}\/claim\/start`\}[^>]*>\s*\{t\('guest\.claimCta', lang\)\}/,
      'o link de vínculo leva a /claim/start com um rótulo que diz vincular (guest.claimCta), não o "Próximos passos" do header');
    const firstLink = block.match(/<a [^>]*>/);
    assert.ok(firstLink && /id="guest-apply-cta"/.test(firstLink[0]), 'a primeira ação do bloco é a candidatura, não o e-mail do gestor');
    for (const tag of block.match(/<a [^>]*mailto:[^>]*>/g) || []) {
      assert.doesNotMatch(tag, /inline-block|bg-navy|px-5/, 'o e-mail do gestor é contato para dúvidas, não o botão principal');
    }
  });
}

test('i18n: o texto do visitante sem cadastro descreve a entrada pela seleção e não promete inclusão pelo gestor nem cadastro livre', () => {
  for (const d of DICTS) {
    const src = read(d);
    const val = (k) => {
      const m = src.match(new RegExp(`^  '${esc(k)}': '((?:[^'\\\\]|\\\\.)+)',$`, 'm'));
      return m ? m[1] : null;
    };
    for (const k of ['guest.contactAdmin', 'guest.limitedAccess']) {
      const v = val(k);
      assert.ok(v, `${k} em ${d}`);
      assert.match(v, /seleção|selection|selección/i, `${k} em ${d} diz que a entrada é pela seleção`);
      assert.doesNotMatch(v, /ser incluíd|added as a member|incluido como miembro|cadastre-se|register as a member|regístrate/i,
        `${k} em ${d} não promete inclusão pelo gestor nem cadastro livre`);
      assert.doesNotMatch(v, /—/, `${k} em ${d} sem travessão longo`);
      assert.doesNotMatch(v, /abaixo|ao lado|below|beside|abajo|al lado/i,
        `${k} em ${d} não aponta posição: em attendance e gamification o link não fica "abaixo" do texto`);
    }
    for (const k of ['guest.applyCta', 'guest.questions']) assert.ok(val(k), `${k} em ${d}`);
    const claimCta = val('guest.claimCta');
    assert.ok(claimCta, `guest.claimCta em ${d}`);
    assert.match(claimCta, /vincul|link/i, `guest.claimCta em ${d} diz vincular, que é o que o texto manda fazer`);
  }
});
