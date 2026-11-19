// Home (GP 19/11/2026): os números da home dizem o que contam.
//
// A meta "Artigos aprovados pela curadoria" fica como está e ganha, logo abaixo, a quebra das publicações do ano com
// avaliação externa, lida ao vivo de publication_submissions (get_public_publication_outcomes). A meta de capítulos
// ganha a nota de quantos têm acordo assinado (get_chapter_metrics), e a de horas, a nota do que é contado. O hero
// diz "pesquisadores ativos", "capítulos do PMI engajados" e "horas de presença em reuniões e eventos".
//
// O guard afirma que (A) a RPC conta cada estado pelo filtro certo e exclui confidencial e rascunho, (B) cada loader
// devolve null sem número de reserva, (C) a linha e as notas só aparecem com leitura boa e no lugar certo, (D) os
// rótulos existem nos 3 idiomas, e (E) com o banco à mão, a RPC responde ao anon e a soma das apresentadas fecha.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { createClient } from '@supabase/supabase-js';

const maskSql = (s) => s.replace(/--[^\n]*/g, '');
const read = (p) => maskJsComments(readFileSync(p, 'utf8'));
const MIG = readdirSync('supabase/migrations').filter((f) => f.endsWith('_get_public_publication_outcomes.sql')).sort().at(-1);
const SQL = maskSql(readFileSync(`supabase/migrations/${MIG}`, 'utf8'));
const DATA = read('src/lib/publicHomeData.ts');
const KPI = read('src/components/sections/KpiSection.astro');
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'].map((p) => [p, readFileSync(p, 'utf8')]);
const KEYS = ['kpis.chaptersNote', 'kpis.impactHoursNote', 'kpis.publications', 'kpis.publicationsText'];

describe('home: números completos (GP 19/11/2026)', () => {
  it('A: a RPC conta cada estado pelo filtro dele, no ano de Brasília, sem confidencial', () => {
    assert.ok(MIG, 'migration da RPC');
    assert.match(SQL, /'published', count\(\*\) FILTER \(WHERE status = 'published'\)/);
    assert.match(SQL, /'presented', count\(\*\) FILTER \(WHERE status = 'presented'\)/);
    assert.match(SQL, /'presented_chapter_event', count\(\*\) FILTER \(WHERE status = 'presented' AND target_type = 'pmi_chapter_event'\)/);
    assert.match(SQL, /'presented_congress', count\(\*\) FILTER \(WHERE status = 'presented' AND target_type IS DISTINCT FROM 'pmi_chapter_event'\)/);
    assert.match(SQL, /'under_evaluation', count\(\*\) FILTER \(WHERE status IN \('submitted', 'under_review'\)\)/);
    assert.match(SQL, /extract\(year FROM \(now\(\) AT TIME ZONE 'America\/Sao_Paulo'\)\)::int AS yr/);
    assert.match(SQL, /extract\(year FROM coalesce\(ps\.acceptance_date, ps\.presentation_date, ps\.submission_date, ps\.created_at::date\)\)::int = y\.yr/);
    assert.match(SQL, /AND NOT EXISTS \(SELECT 1 FROM public\.initiatives i WHERE i\.id = ps\.initiative_id AND i\.visibility = 'confidential'\)/);
    assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\.get_public_publication_outcomes\(\) TO anon/);
  });

  it('B: os loaders devolvem null quando a leitura falha ou vem fora do formato', () => {
    assert.match(DATA, /const d = await rpc<Record<string, unknown>>\('get_public_publication_outcomes'\);\s+const keys = \['published', 'presented', 'presented_congress', 'presented_chapter_event', 'under_evaluation'\];\s+if \(!d \|\| !keys\.every\(\(k\) => isNum\(d\[k\]\)\)\) return null;/);
    assert.match(DATA, /const d = await rpc<Record<string, unknown>>\('get_chapter_metrics'\);\s+if \(!d \|\| !isNum\(d\.engaged\) \|\| !isNum\(d\.signed\) \|\| d\.signed > d\.engaged\) return null;\s+return \{ engaged: d\.engaged, signed: d\.signed, unsigned: d\.engaged - d\.signed \};/);
  });

  it('C: a quebra vem logo depois da meta da curadoria, e cada nota só na sua meta', () => {
    assert.match(DATA, /export const PUBLICATIONS_AFTER_GOAL = 'articles_published';/);
    assert.match(KPI, /\{g\.key === PUBLICATIONS_AFTER_GOAL && pubsText && \(\s+<li class="[^"]*" data-kpi="publication_outcomes">/);
    assert.match(KPI, /const pubsText = pubs\s+\? t\('kpis\.publicationsText', lang\)[\s\S]*?\.replace\('\{evaluation\}', nf\.format\(pubs\.underEvaluation\)\)\s+: '';/);
    assert.match(DATA, /const GOAL_NOTES: Record<string, GoalNote> = \{\s+chapters_participating: \{ kind: 'chapters' \},\s+impact_hours: \{ kind: 'impactHours' \},\s+\};/);
    assert.match(KPI, /if \(note\?\.kind === 'chapters' && agreements\)\s+return t\('kpis\.chaptersNote', lang\)\.replace\('\{signed\}', String\(agreements\.signed\)\)\.replace\('\{unsigned\}', String\(agreements\.unsigned\)\);/);
    assert.match(KPI, /if \(note\?\.kind === 'impactHours'\) return t\('kpis\.impactHoursNote', lang\);\s+return '';/);
    assert.match(KPI, /\{noteFor\(g\.key\) && <p class="[^"]*" data-kpi-note=\{g\.key\}>\{noteFor\(g\.key\)\}<\/p>\}/);
  });

  it('D: rótulos novos e do hero nos 3 idiomas', () => {
    for (const [p, src] of DICTS) {
      for (const k of KEYS) assert.match(src, new RegExp(`'${k.replace('.', '\\.')}': '[^']+'`), `${p} ${k}`);
      for (const ph of ['{published}', '{presented}', '{congress}', '{chapter}', '{evaluation}']) {
        assert.match(src, new RegExp(`'kpis\\.publicationsText': '[^']*${ph.replace(/[{}]/g, '\\$&')}`), `${p} ${ph}`);
      }
      assert.match(src, /'kpis\.chaptersNote': '[^']*\{signed\}[^']*\{unsigned\}/, p);
    }
    const pt = DICTS[0][1];
    assert.match(pt, /'homeV2\.hero\.statResearchers': 'pesquisadores ativos'/);
    assert.match(pt, /'homeV2\.hero\.statChapters': 'capítulos do PMI engajados'/);
    assert.match(pt, /'homeV2\.hero\.statHours': 'horas de presença em reuniões e eventos em \{year\}'/);
  });

  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
  it('E: viva, a RPC responde ao anon, e congresso + capítulo = apresentadas', { skip: !(url && anonKey) && 'sem SUPABASE_URL/anon key' }, async () => {
    const sb = createClient(url, anonKey, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('get_public_publication_outcomes');
    assert.equal(error, null);
    for (const k of ['published', 'presented', 'presented_congress', 'presented_chapter_event', 'under_evaluation']) assert.equal(typeof data[k], 'number', k);
    assert.equal(data.presented_congress + data.presented_chapter_event, data.presented);
  });
});
