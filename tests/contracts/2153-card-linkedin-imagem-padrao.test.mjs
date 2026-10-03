// tests/contracts/2153-card-linkedin-imagem-padrao.test.mjs
/**
 * Contract: #2153 — o card de LinkedIn do Top Content (admin/comms) usa a imagem padrão do Núcleo
 * quando o post não tem imagem.
 *
 * POR QUE: a API do LinkedIn não entrega imagem do post. Medido em 03/09/2026, depois do deploy da
 * EF com o resolver de mídia: 0 de 50 posts com `cached_image_url`, 0 com `payload.image_urn`. Todo
 * card de LinkedIn caía no placeholder de câmera. Decisão do GP (03/10/2026): o card passa a usar a
 * imagem padrão do Núcleo, em vez de seguir tentando a API.
 *
 * O guard recorta `loadTopContent` (comentários mascarados) e amarra a condição ao resultado:
 * canal linkedin => imagem padrão, e só depois de esgotar cached_image_url e thumbnail_url. Uma
 * string solta passaria com o mecanismo removido (lição de #2335, #2286, #2341).
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const COMMS = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/comms.astro'), 'utf8'));

const inicio = COMMS.indexOf('async function loadTopContent(');
const fim = COMMS.indexOf('function wireTopContentFilter(', inicio);
const BLOCO = inicio >= 0 && fim > inicio ? COMMS.slice(inicio, fim) : '';

test('#2153: o recorte de loadTopContent existe', () => {
  assert.ok(BLOCO.length > 0, 'loadTopContent ou wireTopContentFilter não encontrado em comms.astro');
});

test('#2153: a imagem padrão do Núcleo é o og-image servido em /assets', () => {
  const m = COMMS.match(/const NUCLEO_DEFAULT_CARD_IMG = '([^']+)';/);
  assert.ok(m, 'constante NUCLEO_DEFAULT_CARD_IMG ausente (fora de comentário)');
  assert.equal(m[1], '/assets/og-image.png');
  assert.ok(existsSync(resolve(ROOT, 'public', m[1].replace(/^\//, ''))), 'o arquivo da imagem padrão não existe em public/');
});

test('#2153: só o LinkedIn, e só depois do cache e do thumbnail, cai na imagem padrão', () => {
  assert.match(
    BLOCO,
    /const img = m\.cached_image_url \|\| m\.thumbnail_url \|\| \(m\.channel === 'linkedin' \? NUCLEO_DEFAULT_CARD_IMG : ''\);/,
    'a ordem cached_image_url -> thumbnail_url -> padrão (só linkedin) mudou',
  );
});

test('#2153: o <img> do card usa a variável que carrega a imagem padrão', () => {
  assert.match(
    BLOCO,
    /\$\{img \? `<img src="\$\{escapeHtml\(img\)\}"/,
    'o card voltou a montar a imagem sem passar pela variável img',
  );
});
