/**
 * #2555: o menu Explorar nao leva o visitante a pagina que chega vazia.
 *
 * Medido em 04/10/2026 e de novo em 08/10/2026, como anon: /library lia hub_resources (so legivel por autenticado)
 * e recebia [], e /cpmai lia get_cpmai_course_dashboard(), que devolve {"error":"Not authenticated"}.
 * Decisao do GP de 08/10/2026: a /library sai do menu do visitante (o acervo e interno e nao tem curadoria
 * publica); a /cpmai ganha uma leitura publica so com o curso.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. o item library do menu exige membro e sessao; o item cpmai continua visivel ao visitante;
 *   B. get_public_cpmai_course e SECURITY DEFINER, filtra study_group nao arquivado E nao confidencial, e devolve
 *      os dominios por lista fechada de chaves, sem metadata solta (o metadata tem o link do grupo de WhatsApp);
 *   C. EXECUTE revogado de PUBLIC e concedido a anon;
 *   D. a ilha cai na leitura publica quando o painel devolve erro, e o visitante ve o convite para entrar;
 *   E. (banco) como anon: a leitura publica devolve o curso so com as chaves permitidas, e o painel segue negado
 *      (controle: o instrumento sabe dizer nao).
 *
 * SUPERADO EM PARTE (GP, 09/10/2026): /cpmai virou "Grupo de Estudos CPMAI · Piloto", so para participantes e
 * gestao (migration cpmai_grupo_de_estudos_so_participantes). A, D e E passam a afirmar o contrario: o item sai
 * do menu, a ilha nao cai em leitura publica, e anon nao executa get_public_cpmai_course. B e C seguem
 * afirmando o arquivo da #2555, que e historia e nao mudou.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2555_cpmai_publico\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
const FN = (SQL.match(/CREATE OR REPLACE FUNCTION public\.get_public_cpmai_course\(\)[\s\S]*?\$function\$[\s\S]*?\$function\$/) || [''])[0];
const NAV = maskJsComments(readFileSync(resolve(ROOT, 'src/lib/navigation.config.ts'), 'utf8'));
const ISLAND = maskJsComments(readFileSync(resolve(ROOT, 'src/components/cpmai/CpmaiLanding.tsx'), 'utf8'));

function navItem(key) {
  return (NAV.match(new RegExp(String.raw`\{\s*key:\s*'${key}',[^\n]*\}`)) || [''])[0];
}

test('A. library exige membro e sessao; cpmai saiu do menu', () => {
  const lib = navItem('library');
  assert.ok(lib, 'item library nao encontrado');
  assert.match(lib, /minTier:\s*'member',\s*requiresAuth:\s*true/, 'library ainda aparece ao visitante');
  assert.equal(navItem('cpmai'), '', 'cpmai voltou ao menu');
});

test('B. leitura publica: SECDEF, filtro de grupo ativo e nao confidencial, dominios por lista fechada', () => {
  assert.equal(files.length, 1, `esperava 1 migration da #2555, achei ${files.length}`);
  assert.match(FN, /SECURITY DEFINER SET search_path = public, pg_temp/);
  assert.match(FN, /WHERE i\.kind = 'study_group' AND i\.status <> 'archived'\s+AND NOT public\.is_confidential_initiative\(i\.id\)/);
  assert.match(FN, /'course', jsonb_build_object\('id', i\.id, 'title', i\.title, 'description', i\.description, 'status', i\.status\)/);
  const dom = (FN.match(/jsonb_agg\(jsonb_build_object\(([\s\S]*?)\) ORDER BY/) || ['', ''])[1];
  const chaves = [...dom.matchAll(/^\s*'([a-z_]+)',/gm)].map((m) => m[1]).sort();
  assert.deepEqual(chaves, ['domain_number', 'id', 'name_en', 'name_es', 'name_pt', 'weight_pct']);
  // metadata so pode aparecer como a lista de dominios; nunca devolvida inteira
  const usos = FN.match(/i\.metadata\b[^,)]*/g) || [];
  assert.deepEqual(usos, ["i.metadata->'domains'"], `metadata usado alem dos dominios: ${usos.join(' | ')}`);
});

test('C. EXECUTE revogado de PUBLIC e concedido a anon', () => {
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\.get_public_cpmai_course\(\) FROM PUBLIC;/);
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\.get_public_cpmai_course\(\) TO anon, authenticated, service_role;/);
});

test('D. a ilha nao cai em leitura publica e nao autoinscreve; quem nao pode ve o aviso', () => {
  assert.doesNotMatch(ISLAND, /get_public_cpmai_course|join_initiative/);
  // cada erro do painel vira o seu aviso (login, grupo inexistente, falha, e por fim forbidden); nenhum vira outra leitura
  assert.match(
    ISLAND,
    /if \(error\) next = \{ data: null, denied: 'error' \};\s+else if \(d && !d\.error\) next = \{ data: d, denied: null \};\s+else if \(d\?\.error === 'Not authenticated'\) next = \{ data: null, denied: 'login' \};\s+else if \(d\?\.error === 'No course found'\) next = \{ data: null, denied: 'none' \};\s+else next = \{ data: null, denied: 'forbidden' \};/,
    'erro do painel tem de virar aviso de acesso, nunca outra leitura',
  );
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(URL && ANON);

async function anonRpc(name) {
  const r = await fetch(`${URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
    body: '{}',
  });
  return { status: r.status, body: await r.json() };
}

test('E. (banco) como anon: a leitura publica do curso foi fechada; painel segue negado', { skip: dbGated ? false : 'SUPABASE_URL + anon key required' }, async () => {
  const pub = await anonRpc('get_public_cpmai_course');
  assert.ok([401, 403, 404].includes(pub.status), `get_public_cpmai_course como anon voltou ${pub.status}`);
  // controle positivo: o instrumento sabe dizer sim (uma leitura publica que segue aberta)
  const controle = await anonRpc('get_public_publications');
  assert.equal(controle.status, 200, 'controle: anon deveria executar get_public_publications');
  const painel = await anonRpc('get_cpmai_course_dashboard');
  assert.equal(painel.body?.error, 'Not authenticated', 'controle: o painel pessoal deveria seguir negado ao anon');
});
