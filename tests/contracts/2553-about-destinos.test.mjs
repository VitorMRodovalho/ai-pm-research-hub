// #2553 D7 (GP 20/10/2026): consertar e promover o /about. Esta parte é a mecânica, sem decisão pendente:
//   A. nenhum botão do visitante leva a tela de admin; o "seleção" leva às portas de entrada da home (#join);
//   B. os cards de linha levam à lista de linhas da home (#tribes), porque /tribe/<id> nega o visitante;
//   C. publicação sem URL fica sem link (antes, href="#");
//   D. o JSON-LD não declara o PMI como organização-mãe (D11: "Não é um programa do PMI, Inc.") e conta os
//      pesquisadores pela fonte única da home, sem número escrito;
//   E. (GP 24/10/2026) o /about entra no menu de quem visita: item público na barra de cima, com rótulo nas 3 línguas,
//      e o Nav entrega ao visitante os itens dessa barra.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ISLAND = maskJsComments(readFileSync('src/components/islands/ImpactPageIsland.tsx', 'utf8'));
const PAGE = maskJsComments(readFileSync('src/pages/about.astro', 'utf8'));

describe('#2553 D7 /about, destinos', () => {
  it('A: nenhum link do /about vai para /admin, e o botão da seleção vai para #join', () => {
    assert.doesNotMatch(ISLAND, /href=\{`\$\{lp\}\/admin\//);
    assert.match(ISLAND, /<a href=\{`\$\{lp\}\/#join`\}[^>]*>\{l\.ctaSelection\}<\/a>/);
  });

  it('B: os cards de linha vão para a lista de linhas da home, não para /tribe/<id>', () => {
    assert.match(ISLAND, /<a key=\{tribe\.id\} href=\{`\$\{lp\}\/#tribes`\}/);
    assert.doesNotMatch(ISLAND, /href=\{`\/tribe\/\$\{tribe\.id\}`\}/);
  });

  it('C: publicação sem URL não vira link para "#"', () => {
    assert.doesNotMatch(ISLAND, /external_url \|\| '#'/);
    assert.match(ISLAND, /const Tag = pub\.external_url \? 'a' : 'div';/);
  });

  it('D: o JSON-LD não põe o PMI como organização-mãe e não escreve o número de pesquisadores', () => {
    assert.doesNotMatch(PAGE, /"parentOrganization": \{[^}]*Project Management Institute/);
    assert.match(PAGE, /const researchers = \(await loadHomeStats\(\)\)\?\.members \?\? null;/);
    assert.match(PAGE, /\.\.\.\(researchers !== null \? \{ "numberOfEmployees": \{ "@type": "QuantitativeValue", "value": researchers \} \} : \{\}\)/);
    assert.doesNotMatch(PAGE, /"value": \d+/);
  });

  it('E: o /about está no menu de quem visita, com rótulo nas 3 línguas', () => {
    const NAV = maskJsComments(readFileSync('src/lib/navigation.config.ts', 'utf8'));
    assert.match(NAV, /\{ key: 'about',\s+labelKey: 'nav\.about',\s+href: '\/about',\s+minTier: 'visitor', requiresAuth: false, section: 'main',\s+group: 'tools', navSlot: 'primary' \},/);
    for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
      assert.match(readFileSync(`src/i18n/${lang}.ts`, 'utf8'), /^  'nav\.about': '[^']+',$/m, `${lang}: nav.about`);
    }
    const COMP = maskJsComments(readFileSync('src/components/nav/Nav.astro', 'utf8'));
    assert.match(COMP, /const publicMainItems = mainItems\.filter\(i => !i\.requiresAuth\);/);
    assert.match(COMP, /const primaryPublicItems = publicMainItems\.filter\(i => \(i as any\)\.navSlot === 'primary'\);/);
    assert.match(COMP, /const visitorNavItems = isHomePage\s+\? primaryPublicItems\s+: \[\.\.\.homeAnchorItems\.filter\([^\n]*\), \.\.\.primaryPublicItems\];/);
  });
});
