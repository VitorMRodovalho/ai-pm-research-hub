/**
 * #2613 — biblioteca de publicações: página permanente por obra, coleções e citação pronta.
 *
 * Hermético: lê a migration, as páginas e a biblioteca de citação. Cada asserção amarra a CONDIÇÃO
 * ao RESULTADO dentro do bloco que decide (CLAUDE.md, regra de guard), com comentários mascarados:
 *  - as três leitoras públicas só devolvem obra publicada E aprovada pelo portão da ADR-0105;
 *  - a tabela ganha a policy RESTRICTIVE do portão (antes anon lia a linha publicada sem ele);
 *  - o slug não muda depois da primeira publicação;
 *  - as páginas leem só pela RPC e respondem 404 quando ela não devolve nada;
 *  - a citação sai no formato esperado (ABNT, APA, BibTeX).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import {
  formatAbnt, formatApa, formatBibtex, splitName, licenseInfo, safeHttpUrl,
} from '../../src/lib/publication-citation.ts';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const MIG = maskLineComments(read('supabase/migrations/20261009193146_2613_biblioteca_pagina_por_obra.sql'));

/** Corpo de uma função da migration: do CREATE até o $function$; que fecha o corpo. */
function fnBody(name) {
  const start = MIG.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(start >= 0, `a migration precisa definir ${name}`);
  const open = MIG.indexOf('$function$', start);
  const close = MIG.indexOf('$function$;', open + 10);
  return MIG.slice(open, close);
}

test('#2613 leitora da lista: só obra publicada e visível pelo portão confidencial', () => {
  assert.match(
    fnBody('get_public_publications'),
    /WHERE pp\.is_published = true\s+AND public\.rls_can_see_initiative\(pp\.initiative_id\)\s+AND public\.rls_can_see_item\(pp\.board_item_id\)/,
  );
});

test('#2613 leitora da lista: a coleção só aparece se a iniciativa dela for visível', () => {
  assert.match(
    fnBody('get_public_publications'),
    /LEFT JOIN public\.publication_collections pc ON pc\.id = pp\.collection_id AND pc\.is_published = true\s+AND public\.rls_can_see_initiative\(pc\.initiative_id\)/,
  );
});

test('#2613 LinkedIn do autor só de membro ativo', () => {
  assert.match(
    fnBody('get_public_publication'),
    /'linkedin_url', CASE WHEN pm\.is_active THEN pm\.linkedin_url END\)/,
  );
});

test('#2613 pdf_url e external_url só aceitam http(s)', () => {
  assert.match(MIG, /ADD CONSTRAINT public_publications_urls_http\s+CHECK \(\(pdf_url IS NULL OR pdf_url ~\* '\^https\?:\/\/'\) AND \(external_url IS NULL OR external_url ~\* '\^https\?:\/\/'\)\)/);
});

test('#2613 apagar coleção ou iniciativa com obra ligada é recusado (RESTRICT, não SET NULL)', () => {
  assert.match(MIG, /collection_id\s+uuid REFERENCES public\.publication_collections\(id\) ON DELETE RESTRICT/);
  assert.match(MIG, /CREATE TABLE IF NOT EXISTS public\.publication_collections \([\s\S]*?initiative_id\s+uuid REFERENCES public\.initiatives\(id\) ON DELETE RESTRICT/);
});

test('#2613 backfill genérico de slug não toca is_published (não dispara o aviso de publicação)', () => {
  assert.match(MIG, /UPDATE public\.public_publications SET title = title WHERE is_published AND slug IS NULL;/);
  assert.doesNotMatch(MIG, /SET is_published = is_published/);
});

test('#2613 leitora da obra: filtra pelo slug, publicada e pelo portão', () => {
  assert.match(
    fnBody('get_public_publication'),
    /WHERE pp\.slug = p_slug\s+AND pp\.is_published = true\s+AND public\.rls_can_see_initiative\(pp\.initiative_id\)\s+AND public\.rls_can_see_item\(pp\.board_item_id\)\s*$/,
  );
});

test('#2613 irmãs da coleção na página da obra também passam pelo portão', () => {
  assert.match(
    fnBody('get_public_publication'),
    /WHERE s\.collection_id = pc\.id AND s\.is_published = true\s+AND public\.rls_can_see_initiative\(s\.initiative_id\)\s+AND public\.rls_can_see_item\(s\.board_item_id\)/,
  );
});

test('#2613 leitora da coleção: coleção publicada e visível, e cada obra listada também', () => {
  const body = fnBody('get_public_publication_collection');
  assert.match(body, /WHERE pc\.slug = p_slug\s+AND pc\.is_published = true\s+AND public\.rls_can_see_initiative\(pc\.initiative_id\)\s*$/);
  assert.match(body, /WHERE s\.collection_id = pc\.id AND s\.is_published = true\s+AND public\.rls_can_see_initiative\(s\.initiative_id\)\s+AND public\.rls_can_see_item\(s\.board_item_id\)/);
});

test('#2613 a tabela ganha a policy RESTRICTIVE de SELECT do portão (ADR-0105)', () => {
  assert.match(
    MIG,
    /CREATE POLICY public_publications_confidential_gate ON public\.public_publications AS RESTRICTIVE FOR SELECT\s+USING \(public\.rls_can_see_initiative\(initiative_id\) AND public\.rls_can_see_item\(board_item_id\)\);/,
  );
});

test('#2613 o slug é permanente depois da primeira publicação', () => {
  assert.match(
    fnBody('_public_publications_slug_guard'),
    /IF TG_OP = 'UPDATE' AND OLD\.first_published_at IS NOT NULL THEN\s+IF NEW\.slug IS DISTINCT FROM OLD\.slug THEN\s+RAISE EXCEPTION/,
  );
  assert.match(
    MIG,
    /CREATE TRIGGER trg_public_publications_slug_guard\s+BEFORE INSERT OR UPDATE ON public\.public_publications/,
  );
});

test('#2613 obra publicada nasce com slug: o trigger gera e o CHECK garante', () => {
  assert.match(fnBody('_public_publications_slug_guard'), /IF NEW\.is_published AND NEW\.slug IS NULL THEN\s+v_base := public\._publication_slugify\(NEW\.title\);/);
  assert.match(MIG, /ADD CONSTRAINT public_publications_published_has_slug\s+CHECK \(NOT is_published OR slug IS NOT NULL\)/);
});

const PAGE = maskJsComments(read('src/pages/publications/[slug].astro'));
const COLL = maskJsComments(read('src/pages/publications/collections/[slug].astro'));

test('#2613 página da obra lê só pela RPC com portão e responde 404 sem obra', () => {
  assert.match(PAGE, /const \{ data: pub \} = await sb\.rpc\('get_public_publication', \{ p_slug: slug \?\? '' \}\);\s+if \(!pub\) Astro\.response\.status = 404;/);
  assert.doesNotMatch(PAGE, /\.from\(['"]public_publications['"]\)/);
});

test('#2613 página da coleção lê só pela RPC com portão e responde 404 sem coleção', () => {
  assert.match(COLL, /const \{ data: col \} = await sb\.rpc\('get_public_publication_collection', \{ p_slug: slug \?\? '' \}\);\s+if \(!col\) Astro\.response\.status = 404;/);
  assert.doesNotMatch(COLL, /\.from\(['"]publication_collections['"]\)/);
});

test('#2613 página da obra: todo link vindo de coluna livre passa por safeHttpUrl', () => {
  assert.match(PAGE, /const pdfUrl = safeHttpUrl\(pub\?\.pdf_url\);/);
  assert.match(PAGE, /const externalUrl = safeHttpUrl\(pub\?\.external_url\);/);
  assert.match(PAGE, /const linkedinOf = \(name: string\) => safeHttpUrl\(/);
  assert.doesNotMatch(PAGE, /href=\{pub\.(pdf_url|external_url)\}/);
});

test('#2613 página da obra: anterior e próximo vêm da ordem da coleção', () => {
  assert.match(PAGE, /const prev = idx > 0 \? siblings\[idx - 1\] : null;/);
  assert.match(PAGE, /const next = idx >= 0 && idx < siblings\.length - 1 \? siblings\[idx \+ 1\] : null;/);
});

test('#2613 redirects /en e /es levam à página com a língua', () => {
  for (const [dir, code] of [['en', 'en-US'], ['es', 'es-LATAM']]) {
    const obra = `src/pages/${dir}/publications/[slug].astro`;
    const col = `src/pages/${dir}/publications/collections/[slug].astro`;
    assert.ok(existsSync(resolve(ROOT, obra)), obra);
    assert.ok(existsSync(resolve(ROOT, col)), col);
    assert.match(read(obra), new RegExp(`url=/publications/\\$\\{slug\\}\\?lang=${code}`));
    assert.match(read(col), new RegExp(`url=/publications/collections/\\$\\{slug\\}\\?lang=${code}`));
  }
});

const FIXTURE = {
  title: 'Capítulo 6 — Linhagem & Dados',
  authors: ['Ana de Souza', 'João Pedro da Silva Filho'],
  publication_date: '2026-10-03',
  publication_type: 'toolkit',
  doi: '10.6084/m9.figshare.34063218',
  slug: 'capitulo-6',
  collection: { title: 'Qualidade de Dados em Projetos de IA', position: 6 },
};
const ORIGIN = 'https://exemplo.org';

test('#2613 nome: sufixo fica com o sobrenome, partícula com o prenome', () => {
  assert.deepEqual(splitName('João Pedro da Silva Filho'), { given: 'João Pedro da', family: 'Silva Filho' });
  assert.deepEqual(splitName('Ana de Souza'), { given: 'Ana de', family: 'Souza' });
});

test('#2613 ABNT: SOBRENOME em caixa alta, In: da coleção e, com DOI, só o DOI', () => {
  assert.equal(
    formatAbnt(FIXTURE, ORIGIN, new Date('2026-10-09T15:00:00Z')),
    'SOUZA, Ana de; SILVA FILHO, João Pedro da. Capítulo 6 — Linhagem & Dados. In: NÚCLEO IA & GP. '
    + 'Qualidade de Dados em Projetos de IA. [S. l.]: Núcleo IA & GP, 2026. DOI: 10.6084/m9.figshare.34063218.',
  );
});

test('#2613 ABNT sem DOI nem autor: entrada pelo título, [s.d.], URL e acesso no fuso de Brasília', () => {
  const obra = { ...FIXTURE, doi: null, authors: [], publication_date: null, collection: null };
  // 02:30Z de 10/10 ainda é 9 de outubro em Brasília
  assert.equal(
    formatAbnt(obra, ORIGIN, new Date('2026-10-10T02:30:00Z')),
    'CAPÍTULO 6 — Linhagem & Dados. [S. l.]: Núcleo IA & GP, [s.d.]. '
    + 'Disponível em: https://exemplo.org/publications/capitulo-6. Acesso em: 9 out. 2026.',
  );
});

test('#2613 APA sem autor: o título vai para a posição do autor', () => {
  assert.equal(
    formatApa({ ...FIXTURE, authors: [], collection: null }, ORIGIN),
    'Capítulo 6 — Linhagem & Dados. (2026). Núcleo IA & GP. https://doi.org/10.6084/m9.figshare.34063218',
  );
});

test('#2613 APA: iniciais sem partícula, & antes do último autor, URL do DOI', () => {
  assert.equal(
    formatApa(FIXTURE, ORIGIN),
    'Souza, A., & Silva Filho, J. P. (2026). Capítulo 6 — Linhagem & Dados. In Qualidade de Dados em Projetos de IA. '
    + 'Núcleo IA & GP. https://doi.org/10.6084/m9.figshare.34063218',
  );
});

test('#2613 sem DOI, a citação aponta a página permanente da obra', () => {
  const semDoi = { ...FIXTURE, doi: null, collection: null };
  assert.match(formatApa(semDoi, ORIGIN), /Núcleo IA & GP\. https:\/\/exemplo\.org\/publications\/capitulo-6$/);
});

test('#2613 BibTeX sem autor omite o campo; escape numa passada só', () => {
  const bib = formatBibtex({ ...FIXTURE, authors: [], collection: null, title: 'a\\b {x} ~^' }, ORIGIN);
  assert.match(bib, /^@misc\{/);
  assert.doesNotMatch(bib, /author = /);
  assert.match(bib, /title = \{a\\textbackslash\{\}b \\\{x\\\} \\textasciitilde\{\}\\textasciicircum\{\}\}/);
});

test('#2613 safeHttpUrl recusa javascript: e texto solto', () => {
  assert.equal(safeHttpUrl('javascript:alert(1)'), null);
  assert.equal(safeHttpUrl('nota sem url'), null);
  assert.equal(safeHttpUrl('https://exemplo.org/a'), 'https://exemplo.org/a');
});

test('#2613 BibTeX: incollection com booktitle e & escapado', () => {
  const bib = formatBibtex(FIXTURE, ORIGIN);
  assert.match(bib, /^@incollection\{souza2026capitulo,\n/);
  assert.match(bib, /title = \{Capítulo 6 — Linhagem \\& Dados\}/);
  assert.match(bib, /author = \{Souza, Ana de and Silva Filho, João Pedro da\}/);
  assert.match(bib, /booktitle = \{Qualidade de Dados em Projetos de IA\}/);
});

test('#2613 licença SPDX conhecida vira rótulo com link; desconhecida mostra o identificador sem link', () => {
  assert.deepEqual(licenseInfo('CC-BY-4.0'), { label: 'CC BY 4.0', url: 'https://creativecommons.org/licenses/by/4.0/' });
  assert.deepEqual(licenseInfo('LicencaPropria'), { label: 'LicencaPropria', url: '' });
  assert.equal(licenseInfo(null), null);
});
