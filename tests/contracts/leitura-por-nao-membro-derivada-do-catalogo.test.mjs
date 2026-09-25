/**
 * Leitura por NAO-MEMBRO, derivada do catalogo.
 *
 * Regra: toda relacao de `public` que `authenticated` pode ler devolve 0 linha a um usuario
 * autenticado SEM linha em `members`, exceto as relacoes da allowlist abaixo (catalogo, config ou
 * publico por decisao registrada). Uma allowlist, e nao uma lista de tabelas protegidas: a lista de
 * protegidas so cobre o que alguem lembrou de escrever nela, e tabela nova entra no guard sozinha.
 *
 * Instrumento (migration rls_leitura_restrita_a_membro):
 *   `_audit_ghost_read_catalog()` lista as relacoes por `has_any_column_privilege` (uma tabela com
 *   grant so por coluna, como `events`, sumiria de `has_table_privilege`).
 *   `_audit_ghost_read_probe(relname)` le UMA relacao pelo motor de RLS, com SET LOCAL ROLE
 *   authenticated e claims de um uuid sintetico. Tabela com mais de 5000 linhas estimadas e lida por
 *   amostra; o retorno traz `sampled`.
 *
 * Tres estados por relacao: 0 (fechada), >0 (legivel) e erro (NAO medida). Erro fora da lista de
 * erros conhecidos reprova, porque "nao medi" nao pode virar "passou".
 *
 * Controles na mesma rodada: `br_holidays` tem de dar > 0 (o instrumento sabe dizer SIM) e
 * `persons` tem de dar 0 (se a troca de papel falhasse, a leitura correria como service_role, que
 * ignora RLS, e persons daria > 0).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

/**
 * Relacoes que um nao-membro PODE ler, cada uma com o motivo. Entrar aqui e uma decisao: o motivo
 * tem de dizer por que a leitura e aceitavel sem ser membro.
 */
const PODE_LER = new Map([
  // publico por decisao registrada
  // events, recurring_event_groups e impact_hours_summary NAO estao aqui: desde
  // 20260925185424 o autenticado sem linha em members le 0 linha de events (as linhas
  // geral/webinar seguem publicas para anon, por coluna, e isso e o ultimo teste deste arquivo).
  ['blog_posts', 'so status=published (policy "Public reads published")'],
  ['tribe_selections', 'contagem por tribo na home (Track R p59); membro->tribo ja e publico em public_members'],
  ['public_members', 'view accepted-DEFINER (ADR-0096 / #82)'],
  ['impact_hours_total', 'view accepted-DEFINER (ADR-0096 / #82), agregado sem linha de pessoa'],
  ['manual_sections', 'manual de governanca, servido tambem pela RPC publica get_manual_sections'],
  // catalogo e config
  ['agenda_block_formats', 'catalogo'],
  ['br_holidays', 'catalogo (e o controle positivo deste guard)'],
  ['chapter_registry', 'catalogo de capitulos (dado institucional publico)'],
  ['cost_categories', 'catalogo'],
  ['cycle_tribe_dim', 'dimensao de tribo por ciclo (nome/lider de tribo, ja publico)'],
  ['engagement_seed_templates', 'config'],
  ['home_schedule', 'agenda da home'],
  ['offboard_reason_categories', 'catalogo'],
  ['organizations', 'catalogo'],
  ['partner_chapters', 'catalogo'],
  ['privacy_policy_versions', 'texto publico da politica'],
  ['quadrants', 'catalogo'],
  ['release_items', 'changelog publico'],
  ['releases', 'changelog publico'],
  ['revenue_categories', 'catalogo'],
  ['sla_policies', 'config'],
  ['tags', 'catalogo'],
  ['taxonomy_tags', 'catalogo'],
  ['tribe_continuity_overrides', 'linhagem historica de tribo'],
  ['tribe_lineage', 'linhagem historica de tribo'],
  ['tribe_meeting_slots', 'grade de horarios de tribo'],
  ['vep_opportunities', 'vagas publicadas no PMI VEP'],
]);

/** Erros conhecidos: a relacao NAO e medida por este guard enquanto o erro existir. */
const ERRO_CONHECIDO = new Map([
  ['blind_review_assignments', /infinite recursion detected in policy/],
  ['blind_review_pareceres', /infinite recursion detected in policy/],
  ['blind_review_sessions', /infinite recursion detected in policy/],
]);

async function rpc(fn, body = {}) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(body),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${fn} -> ${r.status}: ${text.slice(0, 300)}`);
  return JSON.parse(text);
}

async function emLotes(itens, n, fn) {
  const out = [];
  for (let i = 0; i < itens.length; i += n) {
    out.push(...(await Promise.all(itens.slice(i, i + n).map(fn))));
  }
  return out;
}

// ── Camada estatica: as duas migrations de events ───────────────────────────────────────────────
// Estado pretendido: anon le events so por coluna (sem ata/notas); authenticated tem SELECT de
// tabela, porque o nucleo-mcp le a ata direto com o JWT do membro, e a LINHA passa a exigir membro.
const MIG_DIR = resolve(process.cwd(), 'supabase/migrations');
const migFile = (sufixo) => readdirSync(MIG_DIR).find((f) => f.endsWith(sufixo));
const semComentario = (f) => readFileSync(resolve(MIG_DIR, f), 'utf8').replace(/--[^\n]*/g, '');

test('migration: anon le events por coluna, sem ata nem notas', () => {
  const f = migFile('_rls_leitura_restrita_a_membro.sql');
  assert.ok(f, 'migration *_rls_leitura_restrita_a_membro.sql ausente');
  const sql = semComentario(f);
  assert.match(sql, /REVOKE SELECT ON public\.events FROM anon, authenticated;/);
  const grant = sql.match(/GRANT SELECT \(([^)]*)\) ON public\.events TO anon, authenticated;/);
  assert.ok(grant, 'GRANT SELECT (colunas) ON public.events ausente');
  const cols = grant[1].split(',').map((c) => c.trim());
  for (const c of ['minutes_text', 'notes', 'minutes_edit_history', 'external_attendees']) {
    assert.ok(!cols.includes(c), `${c} nao pode estar no grant por coluna de events`);
  }
  for (const c of ['id', 'title', 'date', 'meeting_link', 'recording_url', 'youtube_url', 'duration_minutes', 'time_start']) {
    assert.ok(cols.includes(c), `${c} e lida pela home como anon e precisa estar no grant`);
  }
});

// Derivado do CONSUMIDOR: toda coluna que src/ seleciona direto de events precisa estar no grant do
// anon (a home le events deslogada). A primeira versao deste grant foi escrita a partir de uma
// busca truncada e quebrou uma leitura; a lista aqui vem do codigo, nao de quem escreveu o grant.
function leiturasDiretasDeEvents(dir) {
  const out = [];
  for (const ent of readdirSync(dir, { withFileTypes: true })) {
    const p = resolve(dir, ent.name);
    if (ent.isDirectory()) { out.push(...leiturasDiretasDeEvents(p)); continue; }
    if (!/\.(astro|ts|tsx|js|mjs)$/.test(ent.name) || ent.name === 'database.gen.ts') continue;
    const src = readFileSync(p, 'utf8');
    for (const m of src.matchAll(/from\(\s*['"`]events['"`]\s*\)\s*\.select\(\s*['"`]([^'"`]+)['"`]/g)) {
      out.push({ arquivo: p.slice(process.cwd().length + 1), colunas: m[1] });
    }
  }
  return out;
}

test('consumidor: toda coluna que src/ le direto de events esta no grant do anon', () => {
  const f = migFile('_rls_leitura_restrita_a_membro.sql');
  const grant = semComentario(f).match(/GRANT SELECT \(([^)]*)\) ON public\.events TO anon, authenticated;/);
  const permitidas = new Set(grant[1].split(',').map((c) => c.trim()));
  const leituras = leiturasDiretasDeEvents(resolve(process.cwd(), 'src'));
  assert.ok(leituras.length >= 2, `o parser deveria achar ao menos as 2 leituras da home (achou ${leituras.length})`);
  const faltando = [];
  for (const { arquivo, colunas } of leituras) {
    for (const bruto of colunas.split(',')) {
      const c = bruto.trim();
      if (!c || c.includes('(') || c.includes(')')) continue; // relacao embutida: nao e coluna de events
      if (!permitidas.has(c)) faltando.push(`${arquivo}: ${c}`);
    }
  }
  assert.deepEqual(faltando, [], 'coluna lida direto de events fora do grant do anon');
});

test('migration: authenticated volta ao SELECT de tabela e a linha de events exige membro', () => {
  const f = migFile('_events_select_de_tabela_para_membro.sql');
  assert.ok(f, 'migration *_events_select_de_tabela_para_membro.sql ausente');
  const sql = semComentario(f);
  assert.match(sql, /GRANT SELECT ON public\.events TO authenticated;/);
  assert.doesNotMatch(sql, /GRANT SELECT ON public\.events TO[^;]*\banon\b/, 'anon nao pode voltar ao SELECT de tabela');
  const bloco = sql.match(/CREATE POLICY events_read_authenticated ON public\.events[\s\S]*?;/);
  assert.ok(bloco, 'policy events_read_authenticated ausente');
  assert.match(bloco[0], /FOR SELECT TO authenticated\s+USING \(\(SELECT public\.rls_is_member\(\)\)\);/,
    'a linha de events para authenticated tem de decidir so por rls_is_member()');
  assert.doesNotMatch(bloco[0], /\btype\b/, 'o ramo por tipo (geral/webinar) nao pode voltar para authenticated');
});

// ── Camada viva ─────────────────────────────────────────────────────────────────────────────────
test('controles: o instrumento diz SIM (br_holidays) e diz NAO (persons)', { skip: dbGated ? false : skipMsg }, async () => {
  const [sim, nao] = await Promise.all([
    rpc('_audit_ghost_read_probe', { p_relname: 'br_holidays' }),
    rpc('_audit_ghost_read_probe', { p_relname: 'persons' }),
  ]);
  assert.equal(sim.error, null, `br_holidays deu erro: ${sim.error}`);
  assert.ok(sim.ghost_rows > 0, 'controle positivo: br_holidays precisa ser legivel ao nao-membro');
  assert.equal(nao.error, null, `persons deu erro: ${nao.error}`);
  assert.equal(nao.ghost_rows, 0, 'controle negativo: persons legivel => a troca de papel nao aconteceu');
});

test('nenhuma relacao fora da allowlist e legivel por nao-membro', { skip: dbGated ? false : skipMsg }, async () => {
  const catalogo = await rpc('_audit_ghost_read_catalog');
  assert.ok(Array.isArray(catalogo) && catalogo.length > 100,
    `catalogo suspeito (${Array.isArray(catalogo) ? catalogo.length : typeof catalogo} relacoes)`);
  const nomes = new Set(catalogo.map((r) => r.relname));

  const velhas = [...PODE_LER.keys(), ...ERRO_CONHECIDO.keys()].filter((n) => !nomes.has(n));
  assert.deepEqual(velhas, [], `entrada de allowlist que nao existe mais no catalogo: ${velhas.join(', ')}`);

  // Erro de transporte (ex.: statement_timeout sob carga) vira "nao medida" COM o nome da relacao,
  // em vez de derrubar a verificacao inteira sem dizer qual foi. Timeout ganha uma segunda tentativa.
  const sondar = async (relname) => {
    for (let tentativa = 1; ; tentativa++) {
      try {
        return await rpc('_audit_ghost_read_probe', { p_relname: relname });
      } catch (e) {
        if (tentativa < 2 && /57014|statement timeout/.test(String(e))) continue;
        return { relname, error: `transporte: ${String(e.message || e).slice(0, 160)}` };
      }
    }
  };
  const medidas = await emLotes(catalogo, 4, (r) => sondar(r.relname));

  const legiveis = medidas.filter((m) => m.error == null && m.ghost_rows > 0 && !PODE_LER.has(m.relname));
  const naoMedidas = medidas.filter((m) => m.error != null
    && !(ERRO_CONHECIDO.has(m.relname) && ERRO_CONHECIDO.get(m.relname).test(m.error)));

  assert.deepEqual(
    naoMedidas.map((m) => `${m.relname}: ${m.error}`), [],
    'relacao NAO medida (erro fora dos conhecidos) — nao medir nao pode passar',
  );
  assert.deepEqual(
    legiveis.map((m) => `${m.relname}(${m.relkind}${m.sampled ? ', amostra' : ''})`), [],
    'relacao legivel por nao-membro fora da allowlist',
  );
});

test('anon nao le ata nem notas de events pela API', { skip: (SUPABASE_URL && ANON_KEY) ? false : 'Skipped: SUPABASE_URL + PUBLIC_SUPABASE_ANON_KEY required' }, async () => {
  for (const col of ['minutes_text', 'notes', 'minutes_edit_history', 'external_attendees']) {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/events?select=${col}&limit=1`, {
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
    });
    assert.notEqual(r.status, 200, `anon leu events.${col}`);
  }
  // controle: a leitura da home segue funcionando
  const ok = await fetch(`${SUPABASE_URL}/rest/v1/events?select=id,title,date,meeting_link&type=eq.geral&limit=1`, {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
  });
  assert.equal(ok.status, 200, 'a home le events como anon e precisa seguir com 200');
});
