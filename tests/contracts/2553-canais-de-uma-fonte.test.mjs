// #2553 PR 2: os canais oficiais saem de comms_channel_config (get_public_channels), não do BaseLayout.
//
// Medido em 21/10/2026: o rodapé tinha as 4 URLs escritas à mão, embora o comentário dele já nomeasse
// comms_channel_config como fonte. O guard afirma que (A) o rodapé não carrega URL de canal e renderiza a lista que o
// loader devolve, e (B) o loader lê a RPC pública, filtra o que não é URL https e, na falha, devolve o último
// resultado bom ou nada, nunca uma URL de reserva.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const LAYOUT = readFileSync('src/layouts/BaseLayout.astro', 'utf8');
const LOADER = maskJsComments(readFileSync('src/lib/publicChannels.ts', 'utf8'));
const CHANNEL_URLS = /youtube\.com\/@|linkedin\.com\/company|instagram\.com\/|open\.spotify\.com\/show/i;

describe('#2553 canais de uma fonte', () => {
  it('A1: o BaseLayout não carrega URL de canal escrita', () => {
    assert.doesNotMatch(LAYOUT, CHANNEL_URLS);
  });

  it('A2: o rodapé renderiza um link por canal devolvido, com o href vindo da fonte', () => {
    assert.match(LAYOUT, /const channels = await loadPublicChannels\(\);/);
    assert.match(LAYOUT, /\{channels\.map\(\(c\) => \(\s*<a href=\{c\.url\}[^>]*aria-label=\{CHANNEL_ICON\[c\.channel\]\.label\}/);
  });

  it('B1: o loader lê get_public_channels com prazo e cache, e não tem URL de reserva', () => {
    assert.match(LOADER, /sb\.rpc\('get_public_channels'\)\.abortSignal\(AbortSignal\.timeout\(TIMEOUT_MS\)\)/);
    assert.match(LOADER, /if \(cache && Date\.now\(\) - cache\.at < TTL_MS\) return cache\.rows;/);
    assert.doesNotMatch(LOADER, /https:\/\//);
  });

  it('B2: na falha vale o último resultado bom ou nada; só passa URL https de canal conhecido', () => {
    assert.match(LOADER, /if \(error \|\| !Array\.isArray\(data\)\) return cache\?\.rows \?\? \[\];/);
    assert.match(LOADER, /\} catch \{\s+return cache\?\.rows \?\? \[\];\s+\}/);
    assert.match(LOADER, /const rows = data\.filter\(isPublicChannel\);\s+cache = \{ at: Date\.now\(\), rows \};/);
    assert.match(LOADER, /KNOWN\.includes\(r\.channel as ChannelKey\)\s+&& typeof r\.url === 'string'\s+&& \/\^https:\\\/\\\/\\S\+\$\/\.test\(r\.url\)/);
  });
});
