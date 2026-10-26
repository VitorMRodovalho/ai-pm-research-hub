// Pertencimento, parte 1 (GP 26/10/2026): a área do membro mostra quem faz o Núcleo, e o visitante não ganha nada novo.
//
// O guard afirma, no código que decide (comentários mascarados):
//   A. o link de membro aparece só para quem a página de destino deixa entrar: o mesmo canExploreTribes de
//      /tribe/[id], pelo padrão de sessão do Nav (navGetMember + nav:member, que dispara de novo no logout);
//   B. cada linha da home tem "Página da linha" para /tribe/<id>, nascido escondido e ligado ao binder;
//   C. "Quem faz" tem "Ver a equipe (membros)" para /equipe, nascido escondido e ligado ao binder;
//   D. a gaveta do membro tem a Equipe ao lado do ranking; o item exige membro e sessão e tem rótulo no Nav;
//   E. /en/equipe e /es/equipe existem e levam a /equipe na língua;
//   F. get_team_by_function (captura vigente): portão antes de qualquer leitura, sem EXECUTE de anon, as contagens
//      são get_public_home_team() e cada grupo usa o MESMO predicado da home (uma fonte, comparada pelo texto),
//      a janela de vigência é a da home (quem sai do papel sai na próxima leitura) e a linha só leva as chaves nomeadas;
//   G. a página lê a função a cada visita, sem guardar nada, mostra o número da home e não monta HTML com dado;
//   H. toda chave de texto nova existe nos 3 dicionários;
//   I. (banco) como anon, a função é recusada, e o mesmo cliente lê get_public_home_team (controle).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
const norm = (s) => s.replace(/\s+/g, ' ').trim();
const DICTS = { 'pt-BR': read('src/i18n/pt-BR.ts'), 'en-US': read('src/i18n/en-US.ts'), 'es-LATAM': read('src/i18n/es-LATAM.ts') };
const hasKey = (dict, key) => new RegExp(`^  '${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}': '`, 'm').test(dict);

const GROUPS = ['management', 'line_leaders', 'initiative_leaders', 'curators', 'hub_members', 'chapter_focal_points', 'researchers'];

// ── F: as duas funções, pela captura vigente ────────────────────────────────────────────────────────────────────
const TEAM = latestFunctionCapture(ROOT, 'get_team_by_function');
const HOME = latestFunctionCapture(ROOT, 'get_public_home_team');
const TEAM_BODY = norm(maskLineComments(TEAM.body));
const HOME_BODY = norm(maskLineComments(HOME.body));
const TEAM_FILE = maskLineComments(read(`supabase/migrations/${TEAM.file}`));

/** O bloco de um grupo na home: de 'grupo', ( até o próximo grupo (ou o fim do objeto). */
function homeBlock(key) {
  const start = HOME_BODY.indexOf(`'${key}', (`);
  assert.ok(start >= 0, `get_public_home_team sem o grupo ${key}`);
  const next = GROUPS.map((g) => HOME_BODY.indexOf(`'${g}', (`, start + 1)).filter((i) => i > start);
  const end = next.length ? Math.min(...next) : HOME_BODY.indexOf(');', start);
  return HOME_BODY.slice(start, end).trim().replace(/,$/, '');
}
/** Pares origem|predicado de um trecho: FROM <origem> <apelido> WHERE <predicado>, até UNION ALL ou o fecho. */
const wherePairs = (text) => [...text.matchAll(/FROM ([\w.]+) (\w+) WHERE (.+?)(?= UNION ALL | \) c \)| \)$|$)/g)]
  .map((m) => `${m[1]} ${m[2]} | ${m[3]}`).sort();

/** Os ramos do CTE roster da página, por grupo. */
function rosterBranches() {
  const start = TEAM_BODY.indexOf('roster AS ( ');
  const end = TEAM_BODY.indexOf(' ) SELECT coalesce(jsonb_agg(', start);
  assert.ok(start >= 0 && end > start, 'CTE roster não encontrado em get_team_by_function');
  const byGroup = new Map();
  for (const branch of TEAM_BODY.slice(start + 'roster AS ( '.length, end).split(' UNION ALL ')) {
    const g = branch.match(/^SELECT '([a-z_]+)'/)?.[1];
    assert.ok(g, `ramo sem grupo: ${branch.slice(0, 60)}`);
    byGroup.set(g, [...(byGroup.get(g) ?? []), branch]);
  }
  return byGroup;
}

describe('pertencimento parte 1: equipe por função, só para membro', () => {
  it('A: o link de membro segue o portão da página de destino, pelo padrão de sessão do Nav', () => {
    const bind = maskJsComments(read('src/lib/tribes/member-only.ts'));
    assert.match(bind, /^import \{ canExploreTribes \} from '\.\/access';$/m);
    assert.match(bind, /const ok = canExploreTribes\(member\);\s*document\.querySelectorAll<HTMLElement>\(selector\)\.forEach\(\(el\) => \{\s*el\.hidden = !ok;\s*\}\);/);
    assert.match(bind, /sync\(\(window as any\)\.navGetMember\?\.\(\) \?\? null\);\s*window\.addEventListener\('nav:member', \(\(e: CustomEvent\) => sync\(e\.detail\)\) as EventListener\);/);
    // o mesmo predicado decide a página da linha: quem vê o link é quem a página deixa entrar
    const tribe = maskAstro(read('src/pages/tribe/[id].astro'));
    assert.match(tribe, /if \(!canExploreTribes\(currentMember\)\) \{\s*showDenied\(/);
    // o Nav dispara nav:member também no logout (detail null), e é isso que esconde o link de novo
    assert.match(maskAstro(read('src/components/nav/Nav.astro')), /renderLoggedOut\(\);\s*window\.dispatchEvent\(new CustomEvent\('nav:member', \{ detail: null \}\)\);/);
  });

  it('B: cada linha da home leva à página da linha, só para membro', () => {
    const lines = maskAstro(read('src/components/sections/ResearchLinesSection.astro'));
    const anchors = [...lines.matchAll(/<a\b[^>]*\bdata-line-page\b[^>]*>/g)];
    assert.equal(anchors.length, 1, 'esperava um link de página da linha');
    assert.match(anchors[0][0], /^<a href=\{`\$\{langPrefix\}\/tribe\/\$\{l\.id\}`\} hidden data-line-page\b/);
    // dentro do detalhe de cada linha (o map das linhas), não fora dele
    const row = lines.slice(lines.indexOf('{lines.map((l) => {'), lines.indexOf('</details>'));
    assert.ok(row.includes('data-line-page'), 'o link não está no detalhe da linha');
    assert.match(lines, /<script>\s*import \{ showForMembers \} from '\.\.\/\.\.\/lib\/tribes\/member-only';[\s\S]*?showForMembers\('\[data-line-page\]'\);/);
    assert.match(lines, /const langPrefix = lang === 'pt-BR' \? '' : lang === 'en-US' \? '\/en' : '\/es';/);
  });

  it('C: "Quem faz" leva à Equipe, só para membro', () => {
    const team = maskAstro(read('src/components/sections/TeamSummarySection.astro'));
    const anchors = [...team.matchAll(/<a\b[^>]*\bdata-team-page\b[^>]*>/g)];
    assert.equal(anchors.length, 1, 'esperava um link para a Equipe');
    assert.match(anchors[0][0], /^<a href=\{`\$\{langPrefix\}\/equipe`\} hidden data-team-page\b/);
    assert.match(team, /<script>\s*import \{ showForMembers \} from '\.\.\/\.\.\/lib\/tribes\/member-only';[\s\S]*?showForMembers\('\[data-team-page\]'\);/);
  });

  it('D: a gaveta do membro tem a Equipe ao lado do ranking; o visitante não', () => {
    const nav = maskJsComments(read('src/lib/navigation.config.ts'));
    const item = norm(nav.match(/\{ key: 'equipe',[^\n]*\}/)?.[0] ?? '');
    assert.match(item, /href: '\/equipe', minTier: 'member', requiresAuth: true, section: 'drawer', group: 'member', navSlot: 'none', drawerSection: 'explorar'/);
    const ranking = norm(nav.match(/\{ key: 'gamification',[^\n]*\}/)?.[0] ?? '');
    assert.match(ranking, /href: '\/gamification'[^}]*section: 'both'[^}]*drawerSection: 'explorar'/, 'o ranking saiu da gaveta');
    assert.match(maskAstro(read('src/components/nav/Nav.astro')), /^\s+equipe: t\('nav\.equipe', lang\),$/m, 'o Nav não tem rótulo para a Equipe');
  });

  it('E: /en/equipe e /es/equipe levam a /equipe na língua', () => {
    for (const [dir, lang] of [['en', 'en-US'], ['es', 'es-LATAM']]) {
      const p = `src/pages/${dir}/equipe.astro`;
      assert.ok(existsSync(join(ROOT, p)), `${p} ausente`);
      assert.match(read(p), new RegExp(`<meta http-equiv="refresh" content="0;url=/equipe\\?lang=${lang}">`), p);
    }
  });

  it('F1: get_team_by_function recusa quem não tem vínculo antes de ler, e anon não executa', () => {
    assert.match(TEAM.block, /\bSTABLE SECURITY DEFINER\b/);
    assert.match(TEAM.block, /SET search_path TO 'public', 'pg_temp'/);
    const gate = TEAM_BODY.match(/BEGIN IF NOT public\.rls_is_authoritative_member\(\) THEN RAISE EXCEPTION '[^']*' USING ERRCODE = 'insufficient_privilege'; END IF;/);
    assert.ok(gate, 'portão ausente ou sem recusa');
    assert.ok(gate.index < TEAM_BODY.indexOf(' FROM '), 'há leitura antes do portão');
    assert.match(TEAM_FILE, /REVOKE ALL ON FUNCTION public\.get_team_by_function\(\) FROM PUBLIC, anon;\s*GRANT EXECUTE ON FUNCTION public\.get_team_by_function\(\) TO authenticated, service_role;/);
    assert.doesNotMatch(TEAM_FILE, /GRANT EXECUTE ON FUNCTION public\.get_team_by_function\(\) TO [^;]*\banon\b/);
  });

  it('F2: uma fonte: as contagens são get_public_home_team() e cada grupo usa o predicado da home', () => {
    assert.match(TEAM_BODY, /RETURN jsonb_build_object\( 'counts', public\.get_public_home_team\(\), 'rows', v_rows,/);
    const branches = rosterBranches();
    assert.deepEqual([...branches.keys()].sort(), [...GROUPS].sort());
    for (const g of GROUPS) {
      const home = homeBlock(g);
      const mine = branches.get(g).map((b) => b.replace(/^.*? FROM /, 'FROM '));
      if (g === 'researchers') {
        assert.match(home, /FROM public\.v_operational_members\)$/, 'a home mudou a fonte dos pesquisadores');
        assert.deepEqual(mine, ['FROM public.v_operational_members om'], 'pesquisadores fora de v_operational_members');
        continue;
      }
      const want = wherePairs(home);
      assert.ok(want.length > 0, `predicado da home não lido para ${g}`);
      assert.deepEqual(mine.flatMap(wherePairs), want, `${g}: o predicado da página não é o da home`);
    }
  });

  it('F3: os CTEs são os da home: população de members e janela de vigência dos engajamentos', () => {
    const cte = (body, name) => body.match(new RegExp(`${name} AS \\( (SELECT [\\s\\S]*?) \\)(?:,| SELECT )`))?.[1] ?? '';
    assert.equal(cte(TEAM_BODY, 'active_members'), cte(HOME_BODY, 'active_members'));
    assert.ok(cte(HOME_BODY, 'active_members'), 'CTE active_members da home não lido');
    const tail = (s) => s.slice(s.indexOf(' FROM public.engagements e'));
    const home = tail(cte(HOME_BODY, 'live_engagements'));
    assert.match(home, /e\.start_date <= CURRENT_DATE AND \(e\.end_date IS NULL OR e\.end_date >= CURRENT_DATE\)/, 'janela da home não lida');
    assert.equal(tail(cte(TEAM_BODY, 'live_engagements')), home);
  });

  it('F4: cada linha só leva as chaves nomeadas, sem contato e sem id de membro', () => {
    const obj = TEAM_BODY.match(/SELECT coalesce\(jsonb_agg\(jsonb_build_object\( (.*?) \) ORDER BY r\.team_group/)?.[1] ?? '';
    const keys = [...obj.matchAll(/'([a-z_]+)', /g)].map((m) => m[1]).sort();
    assert.deepEqual(keys, ['chapter', 'group', 'initiative_id', 'key', 'name', 'photo_url', 'role', 'tribe_id']);
    assert.match(obj, /'key', md5\(r\.who::text\),/, 'a chave da pessoa não é opaca');
    assert.doesNotMatch(TEAM_BODY, /email|phone|linkedin|pmi_id|auth_id|birth_date|address/i);
  });

  it('G: a página lê a função a cada visita, mostra o número da home e não monta HTML com dado', () => {
    const page = maskAstro(read('src/pages/equipe.astro'));
    const script = page.slice(page.lastIndexOf('<script>'));
    assert.match(script, /const \{ data, error \} = await sb\.rpc\('get_team_by_function'\);/);
    assert.doesNotMatch(page, /localStorage|sessionStorage|caches\.|indexedDB/, 'a página guarda a equipe no navegador');
    assert.match(script, /const n = data\.counts\?\.\[g\];\s*if \(typeof n === 'number'\) head\.append\(el\('span', '[^']*', countLabel\(n\)\)\);/);
    assert.equal([...script.matchAll(/countLabel\(/g)].length, 2, 'countLabel chamado com outra fonte');
    assert.doesNotMatch(script, /innerHTML|outerHTML|insertAdjacentHTML|document\.write/);
    assert.match(script, /function onMember\(m: unknown\) \{\s*if \(!canExploreTribes\(m\)\) \{[\s\S]*?only\('equipe-gate'\);\s*return;/);
    assert.match(script, /if \(error\.code === '42501'\) \{ loaded = false; only\('equipe-gate'\); return; \}/);
  });

  it('H: toda chave de texto nova existe nos 3 dicionários', () => {
    const page = read('src/pages/equipe.astro');
    const fm = page.split(/^---$/m)[1] ?? '';
    const list = (name) => JSON.parse((fm.match(new RegExp(`const ${name} = (\\[[^\\]]*\\]) as const;`))?.[1] ?? '[]').replace(/'/g, '"'));
    const keys = new Set([
      ...[...page.matchAll(/\bt\('([\w.]+)'/g)].map((m) => m[1]),
      ...list('GROUPS').map((g) => `equipe.group.${g}`),
      ...list('ROLES').map((r) => `equipe.role.${r}`),
      'homeV2.lines.linePage', 'homeV2.team.toTeamPage', 'nav.equipe',
    ]);
    assert.ok(list('GROUPS').length === 7 && list('ROLES').length >= 13, 'listas de grupos e papéis não lidas');
    for (const [lang, dict] of Object.entries(DICTS)) {
      assert.deepEqual([...keys].filter((k) => !hasKey(dict, k)), [], `${lang}: chaves ausentes`);
    }
  });
});

// ── I: banco, como anon (pula sem URL e chave anônima) ─────────────────────────────────────────────────────────
const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
describe('pertencimento parte 1, banco', { skip: !(URL && ANON) && 'Supabase URL + anon key required' }, () => {
  it('I: anon não lê a equipe, e o mesmo cliente lê as contagens da home (controle)', async () => {
    const sb = createClient(URL, ANON, { auth: { persistSession: false } });
    const home = await sb.rpc('get_public_home_team');
    assert.equal(home.error, null, 'controle: anon deveria ler get_public_home_team');
    assert.deepEqual(Object.keys(home.data).sort(), [...GROUPS].sort());
    const team = await sb.rpc('get_team_by_function');
    assert.equal(team.data, null, 'anon recebeu dado da equipe');
    assert.equal(team.error?.code, '42501', `anon deveria ser recusado (42501), veio ${team.error?.code}`);
  });
});
