// tests/contracts/2553-og-image-por-lingua.test.mjs
/**
 * Contract: #2553 — a prévia de link (og:image / twitter:image) da página em inglês usa a imagem em
 * inglês; pt-BR e es-LATAM seguem com a original.
 *
 * POR QUE: medido em 20/10/2026, véspera do PMI Global Summit: as três línguas serviam a mesma
 * imagem, com o texto em português, e a descrição em inglês dizia "50+ researchers" com 84 membros
 * ativos no ar. Quem compartilhasse o link em inglês mostrava um cartão em português.
 *
 * O guard amarra a CONDIÇÃO (lang === 'en-US') ao RESULTADO (o caminho da imagem), com comentários
 * mascarados, e confere que as duas imagens existem com o tamanho que as meta tags declaram.
 *
 * #2553 D7 (GP 24/10/2026): as descrições de busca da home e do /about (as da prévia de link) ainda diziam
 * "50+ pesquisadores" em pt e es e "51+ pesquisadores, 8 tribos" nas 3 línguas, número escrito à mão. Os textos
 * aprovados ficam fixados aqui: mudar o texto é mudar este guard, de propósito.
 *
 * PR3 (GP 25/10/2026): C3 tirou a contagem de tribos da descrição da home nas 3 línguas (nem número, nem
 * {tribeCount}); A5 trocou o nome longo em inglês pelo curto, "AI & PM Research Hub", na descrição e no texto
 * alternativo da prévia, e a linha de baixo da imagem em inglês passou de "Study and Research Hub on ..." para
 * "Research on ...", para o texto alternativo continuar descrevendo a imagem.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const LAYOUT = maskJsComments(readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8'));
const EN = readFileSync(resolve(ROOT, 'src/i18n/en-US.ts'), 'utf8');
const DICTS = Object.fromEntries(['pt-BR', 'en-US', 'es-LATAM'].map((l) => [l, readFileSync(resolve(ROOT, `src/i18n/${l}.ts`), 'utf8')]));
const APPROVED = {
  'meta.description': {
    'pt-BR': 'Núcleo de Estudos e Pesquisa em IA e Gestão de Projetos: pesquisa voluntária em IA e gerenciamento de projetos, uma cooperação entre capítulos do PMI no Brasil sediada pelo PMI Goiás. Plataforma open-source trilíngue.',
    'en-US': 'AI & PM Research Hub: volunteer research on AI and project management, a cooperation among PMI chapters in Brazil hosted by PMI Goiás. Open-source trilingual platform.',
    'es-LATAM': 'Núcleo de Estudios e Investigación en IA y Gestión de Proyectos: investigación voluntaria en IA y gestión de proyectos, una cooperación entre capítulos del PMI en Brasil con sede en PMI Goiás. Plataforma open-source trilingüe.',
  },
  'about.meta.description': {
    'pt-BR': 'Iniciativa colaborativa entre capítulos do PMI® no Brasil, sediada pelo PMI Goiás: linhas de pesquisa aplicada em IA e gerenciamento de projetos, com produção aberta e plataforma digital própria.',
    'en-US': 'Collaborative initiative across PMI® chapters in Brazil, hosted by PMI Goiás: applied research lines on AI and project management, with open outputs and its own digital platform.',
    'es-LATAM': 'Iniciativa colaborativa entre capítulos del PMI® en Brasil, con sede en PMI Goiás: líneas de investigación aplicada en IA y gestión de proyectos, con producción abierta y plataforma digital propia.',
  },
};

function pngSize(rel) {
  const buf = readFileSync(resolve(ROOT, 'public', rel));
  assert.equal(buf.toString('ascii', 1, 4), 'PNG', `${rel} não é PNG`);
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

test('#2553: inglês => og-image-en.png; as outras línguas => og-image.png', () => {
  assert.match(
    LAYOUT,
    /const ogImage = new URL\(lang === 'en-US' \? '\/assets\/og-image-en\.png' : '\/assets\/og-image\.png', Astro\.url\)\.href;/,
    'a escolha da imagem da prévia pela língua mudou ou saiu',
  );
});

test('#2553: og:image e twitter:image leem a mesma escolha', () => {
  assert.match(LAYOUT, /<meta property="og:image" content=\{ogImage\} \/>/);
  assert.match(LAYOUT, /<meta name="twitter:image" content=\{ogImage\} \/>/);
});

test('#2553: as duas imagens existem com 1200x630, o tamanho que as meta tags declaram', () => {
  assert.match(LAYOUT, /<meta property="og:image:width" content="1200" \/>/);
  assert.match(LAYOUT, /<meta property="og:image:height" content="630" \/>/);
  for (const rel of ['assets/og-image.png', 'assets/og-image-en.png']) {
    assert.ok(existsSync(resolve(ROOT, 'public', rel)), `public/${rel} ausente`);
    assert.deepEqual(pngSize(rel), { w: 1200, h: 630 }, `public/${rel} fora de 1200x630`);
  }
});

test('#2553: a descrição em inglês não carrega contagem fixa de pesquisadores', () => {
  const m = EN.match(/'meta\.description':\s*'([^']+)'/);
  assert.ok(m, 'meta.description ausente em en-US');
  assert.doesNotMatch(m[1], /\d+\+?\s*researchers/i, `contagem fixa na descrição: "${m[1]}"`);
});

test('#2553 D7: as descrições de busca da home e do /about são os textos aprovados, sem contagem escrita à mão', () => {
  for (const [key, byLang] of Object.entries(APPROVED)) {
    for (const [lang, text] of Object.entries(byLang)) {
      const m = DICTS[lang].match(new RegExp(`^  '${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}': '([^']*)',$`, 'm'));
      assert.ok(m, `${key} ausente em ${lang}`);
      assert.doesNotMatch(m[1], /\d|\{tribeCount\}/, `${lang}: ${key} com número escrito ou interpolado`);
      assert.equal(m[1], text, `${lang}: ${key}`);
    }
  }
});
