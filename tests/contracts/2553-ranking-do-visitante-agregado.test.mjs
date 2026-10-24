// #2553 D4 (GP 20/10/2026): quem não entrou deixa de receber o ranking com nomes. O /gamification do visitante passa
// a mostrar o agregado de get_public_gamification_summary (quantas pessoas, quantas por nível), e nenhuma tela chama
// mais get_public_leaderboard, para que o REVOKE do anon (pacote DB-2) não quebre nada.
//
// Medido em 21/10/2026: o único consumidor de get_public_leaderboard em src era o ramo anon do /gamification (top 10
// com nome), e o outro era scripts/smoke-test.mjs, também como anon.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const PAGE = maskJsComments(readFileSync('src/pages/gamification.astro', 'utf8'));
const SMOKE = maskJsComments(readFileSync('scripts/smoke-test.mjs', 'utf8'));
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];
const KEYS = ['gamification.lb.publicSummary', 'gamification.lb.publicLevels', 'gamification.lb.publicNamesNote', 'gamification.lb.publicLogin'];

function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}

describe('#2553 ranking do visitante em agregado', () => {
  it('A1: nenhum arquivo de src chama get_public_leaderboard (o tipo gerado não conta)', () => {
    const callers = walk('src')
      .filter((f) => /\.(astro|ts|tsx|mjs|js)$/.test(f) && !f.endsWith('database.gen.ts'))
      .filter((f) => /get_public_leaderboard/.test(maskJsComments(readFileSync(f, 'utf8'))));
    assert.deepEqual(callers, []);
  });

  it('A2: o ramo do visitante lê o agregado e retorna antes de qualquer lista por pessoa', () => {
    assert.match(PAGE, /if \(!MEMBER\) \{\s+const \{ data: summary, error: summaryError \} = await sb\.rpc\('get_public_gamification_summary'\);\s+if \(summaryError\) throw summaryError;\s+renderPublicSummary\(summary\);\s+return;\s+\}/);
  });

  it('A3: o resumo do visitante não lê campo de pessoa', () => {
    const body = PAGE.match(/function renderPublicSummary\(summary: any\) \{[\s\S]*?\n  \}\n/)?.[0] ?? '';
    assert.ok(body, 'renderPublicSummary ausente');
    assert.doesNotMatch(body, /\.name\b|member_name|member_id|chapter|tribe_name|photo/);
    assert.match(body, /l\.members/);
    assert.match(body, /data-action="open-auth"/);
  });

  it('A4: as 4 chaves novas existem nos 3 dicionários', () => {
    for (const dict of DICTS) {
      const src = readFileSync(dict, 'utf8');
      for (const key of KEYS) assert.match(src, new RegExp(`'${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}': '`), `${key} ausente em ${dict}`);
    }
  });

  it('A5: o smoke-test não chama mais o leaderboard com nomes como anon', () => {
    assert.doesNotMatch(SMOKE, /rpc\/get_public_leaderboard/);
    assert.match(SMOKE, /rpc\/get_public_gamification_summary/);
  });
});
