/**
 * /cpmai: Grupo de Estudos CPMAI · Piloto, só para participantes e gestão (decisão do GP, 09/10/2026).
 *
 * Antes: /cpmai no menu do visitante, leitura pública para anon (#2555), autoinscrição por join_initiative
 * (que nem lia join_policy, valendo para qualquer iniciativa) e o painel com sessões e contador para qualquer
 * membro. Hermético: lê a migration, a ilha, a página, o menu e o sitemap. Cada asserção amarra a condição ao
 * resultado dentro do bloco que decide; comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const migs = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => /^\d{14}_cpmai_grupo_de_estudos_so_participantes\.sql$/.test(f));
const MIG = maskLineComments(read(`supabase/migrations/${migs[0]}`));

function fnBody(name) {
  const start = MIG.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(start >= 0, `a migration precisa definir ${name}`);
  const open = MIG.indexOf('$function$', start);
  return MIG.slice(open, MIG.indexOf('$function$;', open + 10));
}

test('uma migration só', () => assert.equal(migs.length, 1));

test('autoinscrição só onde a iniciativa declara join_policy = open, e antes de gravar', () => {
  const body = fnBody('join_initiative');
  assert.match(body, /IF v_initiative\.join_policy IS DISTINCT FROM 'open' THEN\s+RAISE EXCEPTION 'Self-enrollment not allowed/);
  assert.ok(body.indexOf("join_policy IS DISTINCT FROM 'open'") < body.indexOf('INSERT INTO public.engagements'),
    'a checagem precisa vir antes do INSERT');
});

test('o CPMAI passa a entrada pela gestão por configuração, não por id no código da RPC', () => {
  assert.match(MIG, /UPDATE public\.initiatives SET join_policy = 'invite_only'[^;]*WHERE id = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19'/);
  assert.doesNotMatch(fnBody('join_initiative'), /2f5846f3/);
});

test('painel: só engajado ativo/onboarding ou manage_platform, e o portão confidencial; os demais recebem forbidden', () => {
  assert.match(
    fnBody('get_cpmai_course_dashboard'),
    /IF NOT public\.rls_can_see_initiative\(v_initiative\.id\)\s+OR NOT \(public\.can_by_member\(v_member_id, 'manage_platform'\)\s+OR EXISTS \(SELECT 1 FROM public\.engagements e\s+WHERE e\.initiative_id = v_initiative\.id AND e\.person_id = v_person_id\s+AND e\.status IN \('active', 'onboarding'\)\)\) THEN\s+RETURN jsonb_build_object\('error', 'forbidden'\);/,
  );
});

test('o portão do painel vem antes de montar a resposta com sessões e progresso', () => {
  const body = fnBody('get_cpmai_course_dashboard');
  assert.ok(body.indexOf("'error', 'forbidden'") < body.indexOf("'upcoming_sessions'"));
});

test('a leitura pública do curso fecha para PUBLIC, anon e authenticated', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_public_cpmai_course\(\) FROM PUBLIC, anon, authenticated;/);
  assert.doesNotMatch(MIG, /GRANT EXECUTE ON FUNCTION public\.get_public_cpmai_course\(\) TO[^;]*\b(anon|authenticated)\b/);
});

const ISLAND = maskJsComments(read('src/components/cpmai/CpmaiLanding.tsx'));
const PAGE = maskJsComments(read('src/pages/cpmai.astro'));

test('tela: sem autoinscrição, sem leitura pública, sem contador de inscritos', () => {
  assert.doesNotMatch(ISLAND, /join_initiative|get_public_cpmai_course|enrollment_count/);
});

test('tela: sem curso, mostra o aviso de acesso; com curso, o conteúdo do grupo', () => {
  assert.match(ISLAND, /\{!course && \(\s+<div[^>]*role="status">\s+\{denied === 'login'/);
  assert.match(ISLAND, /\{course && <div>/);
});

test('página fora do menu, do sitemap e da indexação', () => {
  assert.doesNotMatch(read('src/lib/navigation.config.ts'), /\{\s*key:\s*'cpmai'/);
  assert.match(read('astro.config.mjs'), /&& !page\.includes\('\/cpmai'\)/);
  assert.match(PAGE, /<meta slot="head" name="robots" content="noindex" \/>/);
});

test('texto de grupo de estudos nas 3 línguas, com o aviso de que não substitui o curso oficial', () => {
  for (const [f, title] of [['pt-BR', 'Grupo de Estudos CPMAI · Piloto'], ['en-US', 'CPMAI Study Group · Pilot'], ['es-LATAM', 'Grupo de Estudio CPMAI · Piloto']]) {
    const dict = read(`src/i18n/${f}.ts`);
    assert.match(dict, new RegExp(`'cpmai\\.title': "${title}"`), f);
    assert.match(dict, /'cpmai\.disclaimer': "[^"]*(NÃO substitui|does NOT replace|NO reemplaza)[^"]*21/, f);
    assert.doesNotMatch(dict, /'cpmai\.enroll_cta'/, f);
  }
});
