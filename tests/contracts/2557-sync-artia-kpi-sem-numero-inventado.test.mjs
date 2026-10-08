/**
 * #2557: o sync-artia calcula os KPIs do ciclo, grava em annual_kpi_targets e manda para o Artia.
 *
 * O KPI de capitulos lia `get_public_platform_stats().chapters_active`, chave que a RPC nao devolve, e caia sempre no
 * fallback literal 5. Outros KPIs do mesmo bloco tinham o mesmo desenho (`?? 4`, `?? 1`, `?? 0`, e entidades
 * parceiras gravadas como 0 a cada execucao). Um numero inventado sai para o relatorio sem ninguem perceber.
 *
 * O QUE ESTE GUARD AFIRMA, no bloco do modo padrao (do calculo dos KPIs ate a gravacao em annual_kpi_targets):
 *   A. capitulos vem de get_chapter_metrics().engaged, a mesma fonte das Metas e da home, e o bloco nao le mais
 *      get_public_platform_stats nem chapters_active;
 *   B. nenhum fallback numerico (`?? <numero>`) no bloco;
 *   C. nenhum KPI recebe valor literal (`results.x = { current: <numero>`);
 *   D. todo KPI gravado em `results` tem um ramo que o registra em `skipped` quando a fonte nao responde;
 *   E. `skipped` vai para o log da execucao (mcp_usage_log) e para a resposta.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SRC = maskJsComments(readFileSync(resolve(process.cwd(), 'supabase/functions/sync-artia/index.ts'), 'utf8'));
// O bloco que decide: do inicio do calculo ate o laco que grava em annual_kpi_targets.
const BLOCK = (SRC.match(/const results: Record<string, \{ current: number; pct: number; synced: boolean \}> = \{\}[\s\S]*?for \(const \[key, val\] of Object\.entries\(results\)\)/) || [''])[0];

test('o bloco de KPIs foi recortado', () => {
  assert.ok(BLOCK.length > 2000, `bloco de KPIs nao encontrado ou curto demais (${BLOCK.length})`);
});

test('A. capitulos vem de get_chapter_metrics().engaged', () => {
  assert.match(
    BLOCK,
    /sb\.rpc\('get_chapter_metrics'\)[\s\S]{0,200}?const chapters = Number\(chapData\?\.engaged\)[\s\S]{0,200}?results\.chapters_participating = \{ current: chapters,/,
    'chapters_participating precisa receber get_chapter_metrics().engaged',
  );
  assert.doesNotMatch(BLOCK, /get_public_platform_stats/, 'o bloco nao deve ler get_public_platform_stats');
  assert.doesNotMatch(BLOCK, /chapters_active/, 'chapters_active nao existe em nenhuma RPC');
});

test('B. nenhum fallback numerico no bloco', () => {
  const hits = BLOCK.match(/\?\?\s*-?\d/g) || [];
  assert.deepEqual(hits, [], `fallback numerico encontrado: ${hits.join(', ')}`);
});

test('C. nenhum KPI recebe valor literal', () => {
  const hits = BLOCK.match(/results\.\w+ = \{ current: -?\d/g) || [];
  assert.deepEqual(hits, [], `KPI com valor literal: ${hits.join(', ')}`);
});

test('D. todo KPI em results tem ramo que o registra em skipped', () => {
  const keys = [...new Set([...BLOCK.matchAll(/results\.(\w+) = \{ current:/g)].map((m) => m[1]))];
  assert.ok(keys.length >= 10, `esperava ao menos 10 KPIs, achei ${keys.length}`);
  const semRamo = keys.filter((k) => !new RegExp(`\\}\\s*else\\s*\\{\\s*skipped\\.${k} = `).test(BLOCK));
  assert.deepEqual(semRamo, [], `KPI sem ramo de skipped: ${semRamo.join(', ')}`);
});

test('E. skipped vai para o log e para a resposta', () => {
  assert.match(SRC, /tool_name: 'sync-artia',[\s\S]{0,120}?response_summary: \{[\s\S]{0,300}?\n\s*skipped,\n/, 'skipped no mcp_usage_log');
  assert.match(SRC, /kpis: results,\s*skipped,/, 'skipped na resposta');
});
