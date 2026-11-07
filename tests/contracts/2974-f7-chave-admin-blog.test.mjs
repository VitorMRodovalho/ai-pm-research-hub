/**
 * #2974 (F7): a chave de permissão `admin.blog` sai de `src/lib/permissions.ts`.
 *
 * Ela era declarada no tipo `Permission` e dada ao tier `manager` em `TIER_PERMISSIONS`, e nenhuma tela a consultava:
 * desde a #3001, `/admin/blog` decide pela declaração da rota em `ADMIN_ROUTE_ACCESS`, que pergunta a ação da policy de
 * `blog_posts`. Uma chave que só existe na matriz faz a matriz dizer que o tier tem um acesso que nenhuma tela dá.
 *
 * O guard varre `src` e exige que a chave não seja declarada, dada nem consultada em lugar nenhum, e que a página do blog
 * continue decidindo pela declaração da rota. O `astro build` não confere tipo em script de `.astro`, então tirar a
 * chave do tipo não impede, sozinho, uma consulta nova a ela. Os textos de i18n `admin.blog.*` são outra coisa e não
 * contam: a chave de permissão é a string inteira entre aspas.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { TIER_PERMISSIONS, DESIGNATION_PERMISSIONS } from '../../src/lib/permissions.ts';
import { ADMIN_ROUTE_ACCESS } from '../../src/lib/navigation.config.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const CHAVE = 'admin.blog';
const CITA_A_CHAVE = /(['"`])admin\.blog\1/;

function arquivosDe(dir) {
  const fora = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) fora.push(...arquivosDe(p));
    else if (/\.(?:ts|tsx|astro|mjs|js|json)$/.test(e.name)) fora.push(p);
  }
  return fora;
}

test('F7: a regra de busca reconhece a chave entre aspas e não confunde com o i18n admin.blog.*', () => {
  for (const sim of ["hasPermission(m, 'admin.blog')", '"admin.blog"', '`admin.blog`']) {
    assert.match(sim, CITA_A_CHAVE, `a busca não reconhece ${sim}`);
  }
  for (const nao of ["t('admin.blog.slugLabel', lang)", "'admin.blogs'", "'admin.blog_manage'"]) {
    assert.doesNotMatch(nao, CITA_A_CHAVE, `a busca confunde ${nao} com a chave`);
  }
});

test('F7: admin.blog não é declarada nem dada a tier ou designação', () => {
  const src = maskJsComments(readFileSync(resolve(ROOT, 'src/lib/permissions.ts'), 'utf8'));
  const ini = src.indexOf('export type Permission =');
  assert.ok(ini >= 0, 'permissions.ts não tem o tipo Permission');
  const tipo = src.slice(ini, src.indexOf(';', ini));
  assert.match(tipo, /\|\s*'admin\.publications'/, 'o tipo Permission não tem a forma que o guard lê');
  assert.doesNotMatch(tipo, CITA_A_CHAVE, 'o tipo Permission declara admin.blog');
  for (const [nome, mapa] of [['TIER_PERMISSIONS', TIER_PERMISSIONS], ['DESIGNATION_PERMISSIONS', DESIGNATION_PERMISSIONS]]) {
    assert.ok(Object.keys(mapa).length > 0, `${nome} veio vazio`);
    for (const [quem, lista] of Object.entries(mapa)) {
      assert.ok(!lista.includes(CHAVE), `${nome}.${quem} dá admin.blog`);
    }
  }
});

test('F7: nenhum arquivo de src cita a chave admin.blog', () => {
  const arquivos = arquivosDe(resolve(ROOT, 'src'));
  const rel = arquivos.map((p) => relative(ROOT, p));
  assert.ok(rel.includes('src/pages/admin/blog.astro') && rel.includes('src/lib/permissions.ts'),
    'a varredura de src não chegou aos arquivos que importam');
  const citam = rel.filter((p, i) => CITA_A_CHAVE.test(readFileSync(arquivos[i], 'utf8')));
  assert.deepEqual(citam, [], 'há arquivo de src que cita a chave admin.blog');
});

test('F7: a página do blog decide pela declaração da rota', () => {
  const rota = ADMIN_ROUTE_ACCESS['/admin/blog'];
  assert.ok(rota && rota.actions.length > 0, "ADMIN_ROUTE_ACCESS['/admin/blog'] não declara ação");
  const pagina = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/blog.astro'), 'utf8'));
  assert.match(pagina, /\breturn canEnterAdminRoute\('\/admin\/blog', member\);/, 'a página do blog não decide por canEnterAdminRoute');
});
