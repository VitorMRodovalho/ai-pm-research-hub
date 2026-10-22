// #2553 PR 2 (home v2), pacote DB-1: as leitoras públicas novas da home.
//
// Decisões do GP em 19 e 20/10/2026 (D3, D4, D8, D9, D11 e cursos). O guard afirma as duas metades:
//   (A) estático, sem banco: cada função amarra a CONDIÇÃO ao RESULTADO dentro do bloco que decide, com os comentários
//       de linha mascarados (o preâmbulo descreve tudo e não pode decidir nada);
//   (B) efeito, com banco: como anon cada RPC responde, devolve só as chaves que a decisão nomeia e bate com a fonte
//       que a home já usa (controle positivo: o mesmo cliente anon chama get_homepage_stats).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const DIR = 'supabase/migrations';
const files = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort();
const FILE = files.find((f) => /_2553_home_v2_leitoras_publicas\.sql$/.test(f));
const SQL = FILE ? maskLineComments(readFileSync(join(DIR, FILE), 'utf8')) : '';

/** O corpo inteiro de uma função desta migration, do CREATE ao $function$ que a fecha. */
function fn(name) {
  const re = new RegExp(`CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${name}\\(\\)[\\s\\S]*?\\$function\\$;`, 'i');
  return SQL.match(re)?.[0] ?? '';
}
/** As chaves de primeiro nível de um jsonb_build_object no formato 'chave', ( ... ). */
const topKeys = (block) => [...block.matchAll(/^\s{4}'([a-z_]+)',/gm)].map((m) => m[1]).sort();

const PUBLIC_FNS = [
  'get_public_line_fields', 'get_public_home_team', 'get_public_cpmai_wall', 'get_public_trail_summary',
  'get_public_gamification_summary', 'get_public_channels', 'get_public_chapter_entries',
];
const TEAM_KEYS = ['chapter_focal_points', 'curators', 'hub_members', 'initiative_leaders', 'line_leaders', 'management', 'researchers'];
const CHANNEL_KEY = { linkedin: 'company_url', instagram: 'profile_url', youtube: 'channel_url', spotify: 'show_url' };
const LINKEDIN = 'https://www.linkedin.com/company/nucleo-ia/';
const PMI_MEMBER_ONLY = ['DATA_LANDSCAPE', 'AI_INFRA', 'AI_AGILE'];

describe('#2553 DB-1, estático', () => {
  it('a migration existe', () => {
    assert.ok(FILE, 'migration *_2553_home_v2_leitoras_publicas.sql ausente');
  });

  for (const name of PUBLIC_FNS) {
    it(`${name}: SECURITY DEFINER, search_path fixo, fora de PUBLIC e com EXECUTE para anon`, () => {
      const body = fn(name);
      assert.ok(body, `${name} não está definida na migration`);
      assert.match(body, /\bSECURITY DEFINER\b/);
      assert.match(body, /SET search_path TO 'public', 'pg_temp'/);
      assert.match(SQL, new RegExp(`REVOKE ALL ON FUNCTION public\\.${name}\\(\\) FROM PUBLIC;\\s*GRANT EXECUTE ON FUNCTION public\\.${name}\\(\\) TO anon, authenticated, service_role;`));
    });
  }

  it('research_line_fields nasce deny-all e o gatilho recusa par que não é vertical x linha', () => {
    assert.match(SQL, /ALTER TABLE public\.research_line_fields ENABLE ROW LEVEL SECURITY;\s*REVOKE ALL ON TABLE public\.research_line_fields FROM PUBLIC, anon, authenticated;/);
    assert.match(SQL, /IF NOT EXISTS \(SELECT 1 FROM public\.initiatives v\s+WHERE v\.id = NEW\.vertical_initiative_id AND v\.kind = 'community_vertical'\) THEN\s+RAISE EXCEPTION/);
    assert.match(SQL, /IF NOT EXISTS \(SELECT 1 FROM public\.initiatives l\s+WHERE l\.id = NEW\.line_initiative_id AND l\.legacy_tribe_id IS NOT NULL\) THEN\s+RAISE EXCEPTION/);
    assert.match(SQL, /BEFORE INSERT OR UPDATE ON public\.research_line_fields\s+FOR EACH ROW EXECUTE FUNCTION public\._research_line_fields_pair_check\(\);/);
  });

  it('get_public_line_fields: só pares entre iniciativas visíveis, pelo portão de confidencial nos dois lados', () => {
    const body = fn('get_public_line_fields');
    assert.match(body, /SELECT l\.legacy_tribe_id, v\.id, v\.title\s+FROM public\.research_line_fields f/);
    assert.match(body, /AND public\.rls_can_see_initiative\(v\.id\)\s+AND public\.rls_can_see_initiative\(l\.id\)/);
    assert.match(body, /coalesce\(v\.visibility, 'standard'\) <> 'confidential'\s+AND coalesce\(l\.visibility, 'standard'\) <> 'confidential'/);
  });

  it('get_public_home_team: só contagens, e o CTE que alimenta as lideranças passa pelo portão de confidencial', () => {
    const body = fn('get_public_home_team');
    assert.deepEqual(topKeys(body), TEAM_KEYS);
    assert.match(body, /live_engagements AS \([\s\S]*?coalesce\(i\.visibility, 'standard'\) <> 'confidential'\s+AND public\.rls_can_see_initiative\(i\.id\)\s+\)/);
    assert.match(body, /'line_leaders', \(\s+SELECT count\(DISTINCT le\.person_id\) FROM live_engagements le\s+WHERE le\.legacy_tribe_id IS NOT NULL AND le\.role IN \('leader', 'co_leader'\)/);
    assert.match(body, /'researchers', \(SELECT count\(\*\) FROM public\.v_operational_members\)/);
    assert.doesNotMatch(body, /\.name\b|photo_url|linkedin_url|email/);
  });

  it('get_public_cpmai_wall: o selo da certificação pelo catálogo, o Credly exigido, só ativos, e só nome, ano e link', () => {
    const body = fn('get_public_cpmai_wall');
    assert.match(body, /RETURNS TABLE\(name text, certified_year integer, credly_url text\)/);
    assert.match(body, /WHERE m\.is_active = true\s+AND m\.current_cycle_active = true\s+AND btrim\(coalesce\(m\.credly_url, ''\)\) ~\* '\^https:\/\/\(www\\\.\)\?credly\\\.com\/'\s+AND b->>'name' = \(SELECT c\.credly_badge_name FROM public\.courses c WHERE c\.code = 'PMI_CPMAI_MASTER'\)/);
    // nunca o texto "cpmai" como filtro: ele pega quem só tem o curso introdutório
    assert.doesNotMatch(body, /I?LIKE|~\*?\s*'[^']*cpmai|category/i);
    assert.doesNotMatch(body, /photo_url|chapter|email|linkedin/);
  });

  it('get_public_trail_summary: a população é v_operational_members e concluir é ter todos os cursos da trilha', () => {
    const body = fn('get_public_trail_summary');
    assert.match(body, /FROM public\.v_operational_members om\s+LEFT JOIN public\.course_progress cp\s+ON cp\.member_id = om\.id AND cp\.course_id IN \(SELECT t\.id FROM trail t\)/);
    assert.match(body, /'completed_all', \(SELECT count\(\*\) FROM per_person p, total WHERE total\.n > 0 AND p\.done >= total\.n\)/);
    assert.match(body, /count\(DISTINCT cp\.course_id\) FILTER \(WHERE cp\.status = 'completed'\) AS done/);
  });

  it('get_public_gamification_summary: a mesma população do leaderboard, os níveis da fonte única, nenhum nome', () => {
    const body = fn('get_public_gamification_summary');
    assert.match(body, /WHERE m\.is_active = true AND m\.current_cycle_active = true AND m\.gamification_opt_out = false/);
    assert.match(body, /WHERE ps\.key = 'gamification_level_thresholds'/);
    assert.match(body, /WHERE p\.pts >= l\.min_points AND \(l\.max_points IS NULL OR p\.pts <= l\.max_points\)/);
    assert.doesNotMatch(body, /m\.name|member_name|chapter|tribe/);
  });

  it('get_public_channels: cada canal pela sua chave de URL, e nenhuma outra leitura do config', () => {
    const body = fn('get_public_channels');
    for (const [channel, key] of Object.entries(CHANNEL_KEY)) {
      assert.match(body, new RegExp(`WHEN '${channel}'\\s+THEN c\\.config->>'${key}'`), `${channel} deveria ler ${key}`);
    }
    const reads = [...body.matchAll(/config\s*(->>?|#>>?|\?)\s*'?([a-z_]*)/g)].map((m) => `${m[1]}${m[2]}`);
    assert.deepEqual(reads.sort(), Object.values(CHANNEL_KEY).map((k) => `->>${k}`).sort(),
      `leitura do config fora da lista de URLs: ${reads.join(', ')}`);
    assert.doesNotMatch(body, /api_key|oauth|refresh|token|c\.config\s*(?:,|\)|AS|$)/i);
    assert.match(body, /WHERE u\.url ~ '\^https:\/\/\[\^\[:space:\]\]\+\$'/);
  });

  it('get_public_chapter_entries: o ano e a sede, sem situação jurídica', () => {
    const body = fn('get_public_chapter_entries');
    assert.match(body, /RETURNS TABLE\(display_code text, entry_year integer, is_host boolean\)/);
    assert.match(body, /extract\(year FROM pc\.partnership_start\)::integer,\s+coalesce\(cr\.is_contracting_chapter, false\)/);
    assert.doesNotMatch(body, /partnership_status|signed|announced/);
  });

  it('cursos: os 3 gratuitos só para membro PMI saem de is_free, free_for amarrado a is_free, e get_trail_courses devolve free_for', () => {
    assert.match(SQL, /UPDATE public\.courses SET is_free = false\s+WHERE code IN \('DATA_LANDSCAPE', 'AI_INFRA', 'AI_AGILE'\);\s+GET DIAGNOSTICS v_rows = ROW_COUNT;\s+IF v_rows <> 3 THEN\s+RAISE EXCEPTION/);
    assert.match(SQL, /ADD CONSTRAINT courses_free_for_matches_is_free\s+CHECK \(coalesce\(free_for = 'everyone', false\) = coalesce\(is_free, false\)\);/);
    assert.match(SQL, /WHEN code IN \('DATA_LANDSCAPE', 'AI_INFRA', 'AI_AGILE', [^)]*\) THEN 'pmi_members'\s+WHEN is_free = true THEN 'everyone'/);
    const trail = fn('get_trail_courses');
    assert.match(trail, /has_credly\s+boolean,\s+free_for\s+text\s+\)/);
    assert.match(trail, /\(c\.credly_badge_name IS NOT NULL\) AS has_credly,\s+c\.free_for\s+FROM public\.courses c/);
    assert.match(SQL, /DROP FUNCTION IF EXISTS public\.get_trail_courses\(\);\s+CREATE FUNCTION public\.get_trail_courses\(\)/);
    assert.match(SQL, /\$function\$;\s+GRANT EXECUTE ON FUNCTION public\.get_trail_courses\(\) TO anon, authenticated, service_role;/);
  });

  it('capítulos: os 10 anunciados em 30/04/2026 e a sede no início do piloto, abortando se o banco não for o medido', () => {
    assert.match(SQL, /UPDATE public\.partner_chapters SET partnership_start = DATE '2026-04-30'\s+WHERE partnership_start IS NULL AND partnership_status = 'announced_at_risk'[\s\S]{0,200}?IF coalesce\(array_length\(v_codes, 1\), 0\) <> 10 THEN\s+RAISE EXCEPTION/);
    assert.match(SQL, /SELECT c\.cycle_start INTO v_pilot FROM public\.cycles c WHERE c\.cycle_code = 'pilot';/);
    assert.match(SQL, /UPDATE public\.partner_chapters SET partnership_start = v_pilot\s+WHERE chapter_code = 'PMI-GO' AND partnership_start = DATE '2025-07-01';\s+GET DIAGNOSTICS v_go_rows = ROW_COUNT;\s+IF v_go_rows <> 1 THEN\s+RAISE EXCEPTION/);
    assert.match(SQL, /COMMENT ON COLUMN public\.partner_chapters\.partnership_start IS\s+'#2553/);
  });

  it('metas: o rótulo de CPMAI e o de webinars dizem a janela do ano, e só trocam o rótulo de hoje', () => {
    for (const [key, today] of [['cpmai_certified', 'Certificados CPMAI'], ['webinars_completed', 'Webinares/Talks']]) {
      assert.match(SQL, new RegExp(`UPDATE public\\.portfolio_kpi_targets SET metric_label = v_\\w+_new\\s+WHERE cycle_code = 'cycle3-2026' AND metric_key = '${key}' AND metric_label->>'pt' = '${today.replace('/', '\\/')}';\\s+GET DIAGNOSTICS v_rows = ROW_COUNT;\\s+IF v_rows <> 1 THEN\\s+RAISE EXCEPTION`), key);
    }
    assert.match(SQL, /v_cpmai_new  jsonb := jsonb_build_object\(\s+'pt', 'Certificações PMI-CPMAI conquistadas no ano',/);
    assert.match(SQL, /v_web_new    jsonb := jsonb_build_object\(\s+'pt', 'Webinars realizados no ano',/);
    assert.match(SQL, /'kpi\.label_set', 'portfolio_kpi_targets'/);
  });

  it('canais: o Instagram ganha profile_url sem apagar as outras chaves', () => {
    assert.match(SQL, /SET config = coalesce\(config, '\{\}'::jsonb\) \|\| jsonb_build_object\('profile_url', 'https:\/\/www\.instagram\.com\/nucleo\.ia\.gp'\)\s+WHERE channel = 'instagram' AND NOT \(coalesce\(config, '\{\}'::jsonb\) \? 'profile_url'\);/);
  });
});

// ── (B) efeito, como anon ──────────────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } }) : null;
const skip = !anon && 'sem SUPABASE_URL + chave anon';

async function call(name, args) {
  const { data, error } = await anon.rpc(name, args);
  assert.equal(error, null, `${name} como anon: ${error?.message}`);
  return data;
}
const keysOf = (o) => Object.keys(o).sort();

describe('#2553 DB-1, efeito como anon', { skip }, () => {
  it('controle positivo e população única: equipe, trilha e hero contam as mesmas pessoas', async () => {
    const stats = await call('get_homepage_stats');
    assert.ok(Number.isInteger(stats?.members) && stats.members > 0, 'controle positivo: get_homepage_stats não respondeu ao anon');

    const team = await call('get_public_home_team');
    assert.deepEqual(keysOf(team), TEAM_KEYS);
    for (const k of TEAM_KEYS) assert.ok(Number.isInteger(team[k]) && team[k] >= 0, `${k} não é contagem`);
    assert.equal(team.researchers, stats.members);

    const trail = await call('get_public_trail_summary');
    assert.deepEqual(keysOf(trail), ['avg_pct', 'completed_all', 'population', 'trail_courses']);
    assert.equal(trail.population, stats.members);
    assert.ok(trail.completed_all <= trail.population && trail.trail_courses > 0);
  });

  it('mural: só nome, ano e o Credly da pessoa', async () => {
    const rows = await call('get_public_cpmai_wall');
    assert.ok(Array.isArray(rows));
    for (const r of rows) {
      assert.deepEqual(keysOf(r), ['certified_year', 'credly_url', 'name']);
      assert.match(r.credly_url, /^https:\/\/(www\.)?credly\.com\//i);
    }
  });

  it('gamificação: agregado sem nome, níveis da fonte única', async () => {
    const g = await call('get_public_gamification_summary');
    assert.deepEqual(keysOf(g), ['levels', 'participants', 'total_points', 'with_points']);
    assert.ok(g.levels.length > 0, 'nenhum nível: platform_settings.gamification_level_thresholds não foi lido');
    for (const l of g.levels) assert.deepEqual(keysOf(l), ['emoji', 'max_points', 'members', 'min_points', 'slug']);
    assert.ok(g.levels.reduce((s, l) => s + l.members, 0) <= g.participants);
  });

  it('canais: canal e URL, nada mais, e o LinkedIn é a página da empresa', async () => {
    const rows = await call('get_public_channels');
    assert.deepEqual(rows.map((r) => r.channel).sort(), Object.keys(CHANNEL_KEY).sort());
    for (const r of rows) {
      assert.deepEqual(keysOf(r), ['channel', 'url']);
      assert.match(r.url, /^https:\/\/\S+$/);
    }
    assert.equal(rows.find((r) => r.channel === 'linkedin').url, LINKEDIN);
  });

  it('capítulos: um ano por capítulo ativo, e a sede entra em 2024', async () => {
    const [rows, active] = [await call('get_public_chapter_entries'), await call('get_active_chapters')];
    assert.equal(rows.length, active.length);
    for (const r of rows) {
      assert.deepEqual(keysOf(r), ['display_code', 'entry_year', 'is_host']);
      assert.ok(Number.isInteger(r.entry_year), `${r.display_code} sem ano de entrada`);
    }
    const hosts = rows.filter((r) => r.is_host);
    assert.equal(hosts.length, 1);
    assert.equal(hosts[0].entry_year, 2024);
  });

  it('vínculo de campo: as chaves que a home lê, e nenhuma outra', async () => {
    const pairs = await call('get_public_line_fields');
    for (const r of pairs) assert.deepEqual(keysOf(r), ['tribe_id', 'vertical_id', 'vertical_title']);
  });

  it('metas: os 2 rótulos novos saem pela fonte que a home lê', async () => {
    const rows = await call('exec_portfolio_health');
    assert.equal(rows.find((r) => r.metric_key === 'cpmai_certified')?.label?.pt, 'Certificações PMI-CPMAI conquistadas no ano');
    assert.equal(rows.find((r) => r.metric_key === 'webinars_completed')?.label?.pt, 'Webinars realizados no ano');
  });

  it('cursos: os 3 gratuitos só para membro PMI saem com esse rótulo', async () => {
    const rows = await call('get_trail_courses');
    for (const code of PMI_MEMBER_ONLY) {
      assert.equal(rows.find((r) => r.code === code)?.free_for, 'pmi_members', code);
    }
  });
});
