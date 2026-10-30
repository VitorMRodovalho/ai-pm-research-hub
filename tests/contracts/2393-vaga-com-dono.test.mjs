/**
 * ADR-0134 §1 e §10, fatia 1 (#2393): a vaga do VEP é uma entidade com dono.
 *
 * O QUE ESTE GUARD AFIRMA:
 *   S. na migration vigente: organização obrigatória com default do chamador; iniciativa e ciclo por FK
 *      composta com a organização da vaga (nunca `tribes`); duas policies RESTRICTIVE, uma de
 *      organização e uma do portão confidencial (ADR-0105); a sonda só para service_role.
 *   W. o GET /opportunities do worker é público e continua devolvendo só id e baldes: não lê nem expõe
 *      organização, iniciativa ou ciclo.
 *   L. no banco: toda vaga tem organização, e iniciativa e ciclo da mesma organização; o portão
 *      confidencial vale nos dois sentidos, lido pela RLS como membros reais (GP, membro sem vínculo e
 *      membro com vínculo autoritativo), com controle positivo; quem não é membro lê 0.
 *   D. o painel de seleção (get_selection_dashboard) devolve o id da vaga em cada linha, e só o id: o
 *      título não passa pela função SECURITY DEFINER; e candidatura a vaga ligada a uma iniciativa
 *      nunca é shadow VEP (decisão do GP, 30/10/2026), na linha e no contador. Na captura vigente e no
 *      corpo vivo.
 *   U. a tela do GP: coluna e filtro de vaga, com o título lido pela vep_opportunities (a RLS decide);
 *      escolher uma vaga, ou ligar um balde do VEP, desliga "Ocultar decididos" e "Ocultar shadow VEP",
 *      e a visão padrão continua com os dois ligados; o papel manager tem rótulo, selo, aba e opção no
 *      formulário de vaga, cujo select é o que o salvar grava.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO no bloco que decide, com comentários mascarados.
 * Efeito colateral: nenhum. A camada viva só lê; a sonda devolve contagem.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { maskLineComments, maskJsComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, 'supabase/migrations');

/** A migration é achada pelo CONTEÚDO (o nome leva a versão que o apply_migration carimba). */
function migracao() {
  const hit = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort()
    .filter((f) => /vep_opportunities_initiative_same_org_fkey/.test(maskLineComments(readFileSync(join(MIG_DIR, f), 'utf8'))));
  assert.ok(hit.length > 0, 'nenhuma migration cria vep_opportunities_initiative_same_org_fkey');
  return maskLineComments(readFileSync(join(MIG_DIR, hit[hit.length - 1]), 'utf8'));
}
const MIG = migracao();

// ── S. migration ────────────────────────────────────────────────────────────────────────────────────

test('S1. organização obrigatória, com default do chamador e FK para organizations', () => {
  assert.match(MIG, /ALTER COLUMN organization_id SET NOT NULL,\s+ALTER COLUMN organization_id SET DEFAULT public\.auth_org\(\),\s+ADD CONSTRAINT vep_opportunities_organization_id_fkey\s+FOREIGN KEY \(organization_id\) REFERENCES public\.organizations \(id\)/);
});

test('S2. a iniciativa é da mesma organização da vaga, e nunca tribes', () => {
  assert.match(MIG, /ADD CONSTRAINT vep_opportunities_initiative_same_org_fkey\s+FOREIGN KEY \(initiative_id, organization_id\) REFERENCES public\.initiatives \(id, organization_id\)/);
  assert.doesNotMatch(MIG, /REFERENCES\s+public\.tribes/i);
});

test('S3. o ciclo é da mesma organização da vaga', () => {
  assert.match(MIG, /ADD CONSTRAINT vep_opportunities_cycle_same_org_fkey\s+FOREIGN KEY \(cycle_id, organization_id\) REFERENCES public\.selection_cycles \(id, organization_id\)/);
});

test('S4. leitura e escrita só na própria organização (RESTRICTIVE)', () => {
  assert.match(MIG, /CREATE POLICY vep_opportunities_v4_org_scope ON public\.vep_opportunities\s+AS RESTRICTIVE FOR ALL\s+USING \(organization_id = public\.auth_org\(\)\)\s+WITH CHECK \(organization_id = public\.auth_org\(\)\);/);
});

test('S5. vaga de iniciativa confidencial passa pelo portão da ADR-0105 (RESTRICTIVE)', () => {
  assert.match(MIG, /CREATE POLICY vep_opportunities_confidential_visibility ON public\.vep_opportunities\s+AS RESTRICTIVE FOR SELECT TO public\s+USING \(public\.rls_can_see_initiative\(initiative_id\)\);/);
});

test('S6. a sonda de leitura como membro não é executável por anon nem authenticated', () => {
  assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\._audit_member_read_probe\(text, uuid\) FROM PUBLIC, anon, authenticated;/);
});

// ── W. worker: o endpoint público não expõe o dono da vaga ──────────────────────────────────────────

const WORKER = maskJsComments(readFileSync(join(ROOT, 'cloudflare-workers/pmi-vep-sync/src/index.ts'), 'utf8'));
const DB = maskJsComments(readFileSync(join(ROOT, 'cloudflare-workers/pmi-vep-sync/src/db.ts'), 'utf8'));

test('W1. GET /opportunities devolve só id e baldes de cada vaga ativa', () => {
  const ini = WORKER.indexOf('async function handleOpportunities(');
  assert.ok(ini !== -1, 'handleOpportunities existe');
  const corpo = WORKER.slice(ini, WORKER.indexOf('\n}\n', ini));
  const m = corpo.match(/\.map\(\(o\) => \(\{([\s\S]*?)\}\)\)/);
  assert.ok(m, 'o objeto devolvido por vaga é montado num .map explícito');
  const chaves = [...m[1].matchAll(/^\s*([a-z_]+):/gm)].map((x) => x[1]).sort();
  assert.deepEqual(chaves, ['import_buckets', 'opportunity_id'], 'o endpoint público só leva id e baldes');
  assert.doesNotMatch(corpo, /initiative|cycle_id|organization_id|\.\.\.o\b/, 'nada do dono da vaga, nem espalhamento da linha');
});

test('W2. a leitura do worker nem traz organização, iniciativa ou ciclo', () => {
  const ini = DB.indexOf('export async function getAllOpportunities(');
  assert.ok(ini !== -1, 'getAllOpportunities existe');
  const sel = DB.slice(ini).match(/\.select\('([^']*)'\)/);
  assert.ok(sel, 'a leitura usa lista fechada de colunas');
  assert.doesNotMatch(sel[1], /\*|initiative_id|cycle_id|organization_id/);
});

// ── D. o painel de seleção devolve a vaga de cada candidatura ───────────────────────────────────────

// A chave sai pelo `||` colado ao objeto da linha, logo antes do ORDER BY do jsonb_agg das candidaturas
// do ciclo (o subselect `sa.*`). Casar só `vep_opportunity_id` ficaria verde com a chave num objeto
// qualquer, ou num comentário.
const RE_CHAVE_DA_LINHA = /\)\s*\|\|\s*jsonb_build_object\('vep_opportunity_id', a\.vep_opportunity_id\)\s*ORDER BY COALESCE\(a\.leader_score, a\.research_score, a\.final_score\) DESC NULLS LAST\)\s*FROM \(\s*SELECT\s+sa\.\*,/;
// Decisão do GP (30/10/2026): candidatura a vaga ligada a uma iniciativa nunca é shadow VEP. A condição
// é casada DENTRO do bloco que decide a chave, em AND com o status terminal e com o membro mais antigo;
// a mesma string solta em outro lugar não decide nada.
const RE_SHADOW = /'is_shadow_vep', \(\s*a\.status IN \('approved', 'converted', 'cancelled', 'rejected', 'withdrawn'\)\s*AND NOT EXISTS \(\s*SELECT 1 FROM public\.vep_opportunities o\s+WHERE o\.opportunity_id = a\.vep_opportunity_id\s+AND o\.initiative_id IS NOT NULL\s*\)\s*AND EXISTS \(\s*SELECT 1 FROM public\.members m\s+WHERE m\.is_active = true\s+AND lower\(m\.email\) = lower\(a\.email\)\s+AND m\.created_at < a\.created_at\s*\)\s*\),/;
// O contador do painel é a outra definição de sombra na mesma função; a regra tem de ser a mesma lá.
const RE_SHADOW_COUNT = /'shadow_vep_count', \(\s*SELECT count\(\*\) FROM public\.selection_applications a\s+WHERE a\.cycle_id = v_cycle_id\s+AND a\.status IN \('approved', 'converted', 'cancelled', 'rejected', 'withdrawn'\)\s+AND NOT EXISTS \(\s*SELECT 1 FROM public\.vep_opportunities o\s+WHERE o\.opportunity_id = a\.vep_opportunity_id\s+AND o\.initiative_id IS NOT NULL\s*\)\s+AND EXISTS \(\s*SELECT 1 FROM public\.members m\s+WHERE m\.is_active = true\s+AND lower\(m\.email\) = lower\(a\.email\)\s+AND m\.created_at < a\.created_at\s*\)\s*\),/;
// A única forma permitida de ler a vep_opportunities no painel: o teste de existência da iniciativa.
const RE_LEITURA_PERMITIDA = /NOT EXISTS \(\s*SELECT 1 FROM public\.vep_opportunities o\s+WHERE o\.opportunity_id = a\.vep_opportunity_id\s+AND o\.initiative_id IS NOT NULL\s*\)/g;
const leiturasDaVaga = (corpo) => ({
  mencoes: (corpo.match(/vep_opportunities/g) || []).length,
  permitidas: (corpo.match(RE_LEITURA_PERMITIDA) || []).length,
});
const DASH = maskLineComments(latestFunctionCapture(ROOT, 'get_selection_dashboard').body);

test('D1. a linha do painel leva o id da vaga, no objeto de cada candidatura', () => {
  assert.match(DASH, RE_CHAVE_DA_LINHA);
});

test('D2. o título da vaga não passa pela função SECURITY DEFINER do painel', () => {
  // A função passa por cima da RLS; o título de vaga de iniciativa confidencial vazaria por aqui. As únicas
  // leituras da tabela permitidas são os dois NOT EXISTS da regra de shadow (D4 e D5), que não devolvem
  // coluna nenhuma. Ler o título acrescentaria uma menção que não é teste de existência.
  assert.deepEqual(leiturasDaVaga(DASH), { mencoes: 2, permitidas: 2 });
});

test('D4. candidatura a vaga ligada a uma iniciativa nunca é shadow VEP', () => {
  assert.match(DASH, RE_SHADOW);
});

test('D5. o contador de shadow do painel usa a mesma regra da linha', () => {
  assert.match(DASH, RE_SHADOW_COUNT);
});

// ── U. a tela do GP ─────────────────────────────────────────────────────────────────────────────────

const PAGE = maskJsComments(readFileSync(join(ROOT, 'src/pages/admin/selection.astro'), 'utf8'));
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => [l, readFileSync(join(ROOT, `src/i18n/${l}.ts`), 'utf8')]);

/** Recorta a função de 2 espaços de recuo que começa em `inicio` até o fecho dela. */
function funcao(inicio) {
  const ini = PAGE.indexOf(inicio);
  assert.ok(ini !== -1, `${inicio} existe`);
  return PAGE.slice(ini, PAGE.indexOf('\n  }\n', ini));
}

test('U1. o filtro de papel tem ramo de manager, e o de vaga compara o id da vaga da linha', () => {
  const filtro = funcao('function applyFilters() {');
  assert.match(filtro, /\} else if \(filterRole === 'manager'\) \{\s*if \(r\.role_applied !== 'manager'\) return false;\s*\}/);
  assert.match(filtro, /if \(filterOpportunity !== 'all' && String\(r\.vep_opportunity_id \?\? ''\) !== filterOpportunity\) return false;/);
});

test('U2. manager tem selo próprio, em vez de cair no de pesquisador', () => {
  assert.match(PAGE, /\} else if \(r\.role_applied === 'manager'\) \{\s*trackBadge = `[^`]*\$\{esc\(ROLE_LABELS\.manager \|\| 'Gerente'\)\}[^`]*`;\s*\} else \{/);
});

test('U3. o rótulo de manager existe no i18n, no fallback e nos 3 dicionários', () => {
  assert.match(PAGE, /roleLabels: \{\s*researcher: t\('admin\.selection\.researcher', lang\),\s*leader: t\('admin\.selection\.leader', lang\),\s*both: t\('admin\.selection\.statusBoth', lang\),\s*manager: t\('admin\.selection\.manager', lang\),\s*\}/);
  assert.match(PAGE, /roleLabels: \{ researcher: 'Pesquisador', leader: 'Líder', both: 'Ambos', manager: 'Gerente' \}/);
  for (const [l, d] of DICTS) {
    for (const k of ['manager', 'allOpportunities', 'colOpportunity']) {
      assert.match(d, new RegExp(`^  'admin\\.selection\\.${k}': '[^']+',$`, 'm'), `${l} tem admin.selection.${k}`);
    }
  }
});

test('U4. o select de papel do formulário de vaga tem manager, e é ele que o salvar grava', () => {
  // Sem a opção, abrir uma vaga manager no formulário zera o select e o salvar grava role_default ''.
  const sel = PAGE.match(/<select id="opp-role"[^>]*>([\s\S]*?)<\/select>/);
  assert.ok(sel, 'o select opp-role existe');
  assert.match(sel[1], /<option value="manager">[^<]+<\/option>/);
  assert.match(PAGE, /role_default: \(document\.getElementById\('opp-role'\) as HTMLSelectElement\)\.value,/);
});

test('U5. escolher uma vaga mostra o funil inteiro; a visão padrão continua com os dois filtros ligados', () => {
  const funil = funcao('function showWholeFunnel() {');
  assert.match(funil, /if \(filterHideDecided\) \{\s*filterHideDecided = false;/);
  assert.match(funil, /if \(filterHideShadowVep\) \{\s*filterHideShadowVep = false;/);
  const ini = PAGE.indexOf("document.getElementById('sel-opportunity')?.addEventListener('change'");
  assert.ok(ini !== -1, 'o filtro de vaga tem handler de change');
  const handler = PAGE.slice(ini, PAGE.indexOf('\n    });\n', ini));
  assert.match(handler, /filterOpportunity = \(e\.target as HTMLSelectElement\)\.value;\s*if \(filterOpportunity !== 'all'\) showWholeFunnel\(\);\s*applyFilters\(\);\s*$/);
  assert.match(PAGE, /let filterHideDecided = true;/);
  assert.match(PAGE, /let filterHideShadowVep = true;/);
});

test('U8. ligar um balde do VEP mostra o funil inteiro, senão os baldes de approved e rejected ficam vazios', () => {
  // applyFilters corta decidido e shadow antes de olhar o balde; "Oferta aceita" só conta approved.
  const ini = PAGE.indexOf("document.querySelectorAll('.filter-vep-chip').forEach((chip) => {");
  assert.ok(ini !== -1, 'os baldes do VEP têm handler');
  const handler = PAGE.slice(ini, PAGE.indexOf('\n    });\n', ini));
  assert.match(handler, /filterVep = filterVep === val \? 'all' : val;\s*if \(filterVep !== 'all'\) showWholeFunnel\(\);/);
});

test('U6. o título da vaga vem da vep_opportunities, com a sessão de quem olha', () => {
  const carga = funcao('async function loadOpportunityTitles() {');
  assert.match(carga, /await sb\.from\('vep_opportunities'\)\.select\('opportunity_id, title'\);/);
  assert.match(carga, /opportunityTitles = Object\.fromEntries\(data\.map\(/);
  assert.match(PAGE, /const oppTitle = oppId \? \(opportunityTitles\[oppId\] \|\| ''\) : '';/);
  assert.match(PAGE, /data-sort="vep_opportunity_id">\{t\('admin\.selection\.colOpportunity', lang\)\}/);
  assert.match(PAGE, /<select id="sel-opportunity"[^>]*>/);
});

test('U7. a aba de manager existe ao lado de pesquisador e líder', () => {
  const abas = PAGE.slice(PAGE.indexOf('id="sel-role-toggle"'), PAGE.indexOf('</div>', PAGE.indexOf('id="sel-role-toggle"')));
  assert.match(abas, /data-role="manager">\{t\('admin\.selection\.manager', lang\)\}<\/button>/);
});

// ── L. banco ────────────────────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const skip = SUPABASE_URL && SUPABASE_KEY ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

async function sbClient() {
  const { createClient } = await import('@supabase/supabase-js');
  return createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
}

/** Lê a tabela inteira em páginas: o PostgREST corta em 1000 linhas e uma leitura truncada mediria
 *  outra população. `ordem` é uma coluna única, para as páginas não se sobreporem. */
async function ler(sb, tabela, colunas, ordem = 'id') {
  const linhas = [];
  for (let de = 0; ; de += 1000) {
    const { data, error } = await sb.from(tabela).select(colunas).order(ordem).range(de, de + 999);
    assert.ifError(error);
    linhas.push(...data);
    if (data.length < 1000) break;
  }
  assert.ok(linhas.length > 0, `a leitura de ${tabela} precisa trazer linhas`);
  return linhas;
}

test('L1. toda vaga tem organização, e iniciativa e ciclo da mesma organização', { skip }, async () => {
  const sb = await sbClient();
  const vagas = await ler(sb, 'vep_opportunities', 'opportunity_id, organization_id, initiative_id, cycle_id');
  const ini = new Map((await ler(sb, 'initiatives', 'id, organization_id')).map((i) => [i.id, i.organization_id]));
  const cic = new Map((await ler(sb, 'selection_cycles', 'id, organization_id')).map((c) => [c.id, c.organization_id]));
  const ruins = vagas.filter((v) => !v.organization_id
    || (v.initiative_id && ini.get(v.initiative_id) !== v.organization_id)
    || (v.cycle_id && cic.get(v.cycle_id) !== v.organization_id));
  assert.deepEqual(ruins.map((v) => v.opportunity_id), [], 'vaga sem organização ou com dono de outra organização');
  // Controle positivo: sem nenhuma vaga com iniciativa, a checagem de mesma organização passaria vazia.
  assert.ok(vagas.some((v) => v.initiative_id), 'nenhuma vaga com iniciativa: o teste perdeu o objeto');
});

test('L2. o portão confidencial vale nos dois sentidos, lido pela RLS como membros reais', { skip }, async () => {
  const sb = await sbClient();
  const vagas = await ler(sb, 'vep_opportunities', 'opportunity_id, initiative_id');
  const confidenciais = new Set((await ler(sb, 'initiatives', 'id, visibility'))
    .filter((i) => i.visibility === 'confidential').map((i) => i.id));
  const confDeVaga = new Set(vagas.map((v) => v.initiative_id).filter((id) => id && confidenciais.has(id)));
  // Controle positivo: sem vaga em iniciativa confidencial, o portão não teria o que barrar.
  assert.ok(confDeVaga.size > 0, 'nenhuma vaga em iniciativa confidencial: o teste perdeu o objeto');

  const total = vagas.length;
  const abertas = vagas.filter((v) => !v.initiative_id || !confidenciais.has(v.initiative_id)).length;
  const membros = (await ler(sb, 'members', 'id, auth_id, is_active, is_superadmin'))
    .filter((m) => m.is_active && m.auth_id);
  const vinculos = (await ler(sb, 'auth_engagements', 'auth_id, initiative_id, is_authoritative', 'engagement_id'))
    .filter((e) => e.is_authoritative && confDeVaga.has(e.initiative_id));
  const ondeTem = new Map();
  for (const e of vinculos) {
    if (!ondeTem.has(e.auth_id)) ondeTem.set(e.auth_id, new Set());
    ondeTem.get(e.auth_id).add(e.initiative_id);
  }

  const gp = async (m) => {
    if (m.is_superadmin) return true;
    const { data, error } = await sb.rpc('can_by_member', { p_member_id: m.id, p_action: 'manage_platform' });
    assert.ifError(error);
    return data === true;
  };
  const sonda = async (m) => {
    const { data, error } = await sb.rpc('_audit_member_read_probe', { p_relname: 'vep_opportunities', p_member_id: m.id });
    assert.ifError(error);
    assert.equal(data?.error ?? null, null, `a sonda precisa medir, e não errar: ${data?.error}`);
    return data.member_rows;
  };

  let comGp = null; let semVinculo = null; let comVinculo = null;
  for (const m of membros) {
    if (comGp && semVinculo && comVinculo) break;
    const ehGp = await gp(m);
    if (ehGp) { comGp ??= m; continue; }
    if (ondeTem.has(m.auth_id)) comVinculo ??= m; else semVinculo ??= m;
  }
  assert.ok(comGp && semVinculo && comVinculo, 'faltou um dos três perfis (GP, sem vínculo, com vínculo)');

  assert.equal(await sonda(comGp), total, 'o GP vê todas as vagas');
  assert.equal(await sonda(semVinculo), abertas, 'quem não tem vínculo vê só as vagas gerais e as de iniciativa padrão');
  const minhas = vagas.filter((v) => ondeTem.get(comVinculo.auth_id).has(v.initiative_id)).length;
  assert.ok(minhas > 0, 'o perfil com vínculo precisa ter vaga na iniciativa dele');
  assert.equal(await sonda(comVinculo), abertas + minhas, 'quem tem vínculo vê também as vagas da iniciativa dele');
});

test('L3. quem não é membro não lê vaga', { skip }, async () => {
  const sb = await sbClient();
  const { data, error } = await sb.rpc('_audit_ghost_read_probe', { p_relname: 'vep_opportunities' });
  assert.ifError(error);
  assert.equal(data?.error ?? null, null, `a sonda de não-membro precisa medir: ${data?.error}`);
  assert.equal(data.ghost_rows, 0);
});

test('D3. o corpo VIVO do painel leva o id da vaga e a regra nova de shadow', { skip }, async () => {
  const sb = await sbClient();
  const { data, error } = await sb.rpc('_audit_function_source', { p_proname: 'get_selection_dashboard' });
  assert.ifError(error);
  assert.equal(data?.length, 1, 'get_selection_dashboard precisa existir com uma assinatura só');
  assert.ok(typeof data[0].prosrc === 'string' && data[0].prosrc.length > 1000, 'corpo vivo legível');
  const vivo = maskLineComments(data[0].prosrc);
  assert.match(vivo, RE_CHAVE_DA_LINHA);
  assert.match(vivo, RE_SHADOW);
  assert.match(vivo, RE_SHADOW_COUNT);
  assert.deepEqual(leiturasDaVaga(vivo), { mencoes: 2, permitidas: 2 });
});
