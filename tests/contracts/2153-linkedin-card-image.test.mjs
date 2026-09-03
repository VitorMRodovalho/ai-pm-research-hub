// tests/contracts/2153-linkedin-card-image.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json.
/**
 * Contract: #2153 — o card de LinkedIn do Top Content nao tinha imagem porque NENHUM caminho de
 * escrita produzia valor para o canal. Medido em 02-03/09/2026 sobre `comms_media_items`:
 *
 *   canal      linhas  caption  thumbnail_url  cached_image_url
 *   instagram      88       79             42                70
 *   linkedin       50       50              0                 0   <- o defeito
 *   youtube        92       92             92                 0
 *
 * Duas causas somadas, e nenhuma era "o sync falhou": `fetchLinkedInMedia` gravava
 * `thumbnail_url: null` fixo, e o cache do #889 vivia atras de `if (cfg.channel === 'instagram')`.
 *
 * A sondagem da API em 03/09/2026 (50 posts da organizacao) mostrou que a referencia de midia vem
 * na MESMA listagem que ja entregava a legenda, em tres formas:
 *
 *   content.media.id = urn:li:image: ..... 16      content.media.id = urn:li:video: ...  5
 *   content.multiImage.images[0].id ......  9      content.media.id = urn:li:document:   3
 *   content.article.thumbnail ............  5      content.reference (link externo) ....  7
 *                                                  sem content .........................  5
 *
 * Logo 30 dos 50 tem imagem alcancavel, e 20 nao tem — este teste NAO exige 50, porque exigir
 * cobertura total transformaria um limite da fonte em falha do codigo.
 *
 * Ratchet estatico (a EF roda em Deno). Offline, sem banco.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const EF = readFileSync(resolve(process.cwd(), 'supabase/functions/sync-comms-metrics/index.ts'), 'utf8');
const semComentarios = EF.replace(/^\s*\/\/.*$/gm, '');

test('#2153 o cache de imagem alcanca o LinkedIn, e nao so o Instagram', () => {
  // O gate era `cfg.channel === 'instagram'`, e por isso o LinkedIn nunca entrou no caminho que
  // grava cached_image_url. Afirmado sobre o codigo sem comentarios: o comentario que EXPLICA o
  // defeito tambem contem a string do gate antigo, e um match cru passaria por causa dele.
  const iCache = semComentarios.indexOf("cacheMediaImage(sb, ch,");
  assert.ok(iCache > 0, 'o cache deixou de ser chamado com o canal como variavel');
  assert.match(
    semComentarios,
    /cfg\.channel === 'instagram' \|\| cfg\.channel === 'linkedin'/,
    'o gate de canal do cache tem de cobrir os dois canais',
  );
});

test('#2153 so URN de IMAGEM vira origem — video e documento ficam de fora', () => {
  // `content.media.id` tambem carrega urn:li:video: (5 posts) e urn:li:document: (3). Pedir
  // /rest/images para eles seria chamada garantida a falhar, e o prefixo e o que separa.
  // As duas pontas sao verificadas SEPARADAMENTE e ancoradas no seu proprio sitio. A primeira
  // versao deste teste procurava `startsWith('urn:li:image:')` no arquivo inteiro, e por isso
  // sobrevivia a remover a checagem da CAPTURA: a ocorrencia do RESOLVER satisfazia o match
  // sozinha. Injetar o defeito foi o que mostrou — o teste continuou verde com video e documento
  // entrando na captura. Presenca no arquivo nao e presenca no lugar certo.
  assert.match(
    semComentarios,
    /cand\.find\([\s\S]{0,120}?startsWith\('urn:li:image:'\)/,
    'a CAPTURA tem de exigir o prefixo: content.media.id tambem carrega video (5) e documento (3)',
  );
  assert.match(
    semComentarios,
    /imageUrn\.startsWith\('urn:li:image:'\)/,
    'o RESOLVER tem de recusar URN que nao seja de imagem, e nao confiar em quem o chamou',
  );
  const checagens = (semComentarios.match(/startsWith\('urn:li:image:'\)/g) || []).length;
  assert.ok(checagens >= 2, `esperadas ao menos 2 checagens de prefixo (captura + resolver), achei ${checagens}`);
});

test('#2153 as tres formas medidas da listagem sao lidas', () => {
  for (const forma of ['media?.id', 'multiImage?.images?.\\[0\\]?.id', 'article?.thumbnail']) {
    assert.match(
      semComentarios, new RegExp(forma.replace(/\?/g, '\\?')),
      `a forma ${forma} nao e lida: ela responde por parte dos 30 posts com imagem`,
    );
  }
});

test('#2153 a URL resolvida NAO e persistida — ela expira', () => {
  // /rest/images devolve `downloadUrl` com `downloadUrlExpiresAt`. Gravar essa URL em
  // thumbnail_url daria um link que morre sozinho, que e exatamente o defeito que o #889
  // resolveu para o Instagram. O destino da URL resolvida e o cache, e so ele.
  assert.match(semComentarios, /downloadUrl/, 'o resolver tem de ler downloadUrl');
  assert.ok(
    !/thumbnail_url:\s*(await\s+)?resolveLinkedInImageUrl/.test(semComentarios),
    'a URL resolvida nao pode ir para thumbnail_url: ela expira',
  );
  const iResolver = semComentarios.indexOf('resolveLinkedInImageUrl(activeCfg.oauth_token');
  assert.ok(iResolver > 0, 'o resolver tem de ser chamado a partir do bloco de cache');
});

test('#2153 o URN sobrevive a um dia em que a listagem por autor falhar', () => {
  // Mesmo raciocinio da legenda no #2142: o upsert reescreve `payload` inteiro, entao o caminho
  // de reserva (stored_urns) precisa RELER o image_urn ja gravado e repassa-lo. Sem isso, uma
  // falha da listagem apagaria as imagens ja descobertas.
  assert.match(
    semComentarios,
    /image_urn:\s*\(r as any\)\.payload\?\.image_urn/,
    'o fallback por URNs guardados tem de repassar o image_urn ja gravado',
  );
  assert.match(
    semComentarios,
    /\.select\('external_id, published_at, caption, payload'\)/,
    'o fallback precisa selecionar payload para conseguir reler o image_urn',
  );
});

test('#2153 "0 cacheadas" nao pode ler igual nas duas causas', () => {
  // Zero imagens tem duas causas muito diferentes: ja estava tudo cacheado, ou nenhuma origem foi
  // alcancada. Foi assim que o defeito passou despercebido — o sync ficava verde com 0 dos 50.
  assert.match(
    semComentarios,
    /Comms media cache \[\$\{ch\}\]:.*cacheada.*sem origem.*ja tinha/s,
    'o log tem de separar cacheadas, sem origem e ja cacheadas',
  );
});
