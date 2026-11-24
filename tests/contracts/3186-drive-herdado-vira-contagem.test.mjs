// tests/contracts/3186-drive-herdado-vira-contagem.test.mjs
/**
 * #3186: a permissão herdada da pasta de cima não abre item da revisão de acesso (#3179). Vira contagem por pasta de
 * trabalho, no retorno de record_drive_folder_acl e na tela, com a indicação de que a decisão é na pasta de cima. A
 * permissão direta segue como antes. O ensaio de 24/11/2026 leu 371 achados, 355 deles herdados.
 *
 * O que este guard afirma, com a condição amarrada ao resultado dentro do bloco que decide:
 *   G31 a classificação: o veredito 'inherited' vem depois das conferências de quem fica e antes do achado, só para
 *       inherited IS TRUE (NULL segue direta); 'findings' conta só a direta; a contagem do herdado e do herdado fora do
 *       cadastro sai no retorno; 'findings_inherited' saiu; a contagem da pasta é gravada depois do dry_run.
 *   G32 a tabela da contagem: sem e-mail nem pessoa, RLS fechado, só service_role; close_reason aceita 'inherited'.
 *   G33 a tela: o herdado por pasta viva, com o portão rls_can_see_initiative (ADR-0105), e o total no resumo.
 *   G34 o reconcile soma 'inherited' e 'inherited_unknown_person', sem 'findings_inherited'.
 *   G35 a ilha mostra o bloco do herdado e as chaves existem nos três idiomas.
 *   G36 a volta do cron: o mesmo nome e horário, sem skip_acl_review.
 *   M   cada predicado reprova a mutação do seu defeito.
 *
 * A camada viva (DB-gated) roda G31 e G33 sobre o corpo em produção.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

/** Tira comentário de linha e colapsa espaço (a mesma forma do guard da #3179). */
function sql(b) {
  return b.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}
/** Tira comentário de TS (linha e bloco) e colapsa espaço. */
function ts(b) {
  return b.replace(/\/\*[\s\S]*?\*\//g, ' ').split('\n')
    .map((l) => { const i = l.search(/(^|[^:"'])\/\//); return i >= 0 ? l.slice(0, i + (l[i] === '/' ? 0 : 1)) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, 'supabase/migrations');
const pick = (re) => readdirSync(MIG_DIR).filter((f) => re.test(f)).sort().pop();
const MIG = pick(/_3186_drive_herdado_vira_contagem\.sql$/);
const MIG_CRON = pick(/_3186b_drive_religa_revisao_no_cron\.sql$/);
const EF_PATH = join(ROOT, 'supabase/functions/reconcile-initiative-drive-access/index.ts');
const ISLAND = join(ROOT, 'src/components/admin/members/DriveFolderAccessReviewIsland.tsx');
const LOCALES = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => join(ROOT, `src/i18n/${l}.ts`));
const KEYS = ['sumInherited', 'inheritedTitle', 'inheritedHint', 'colInherited'];

const body = (fn) => {
  const c = latestFunctionCapture(ROOT, fn);
  assert.ok(c, `${fn}: sem captura em supabase/migrations`);
  return c.body;
};
const slice = (s, from, to) => {
  const a = s.indexOf(from);
  if (a < 0) return '';
  const b = s.indexOf(to, a + from.length);
  return b < 0 ? s.slice(a) : s.slice(a, b + to.length);
};
const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));
const ok = (o, msg) => assert.deepEqual(o, allTrue(o), msg);

/** G31: o herdado vira contagem. */
export function herdadoViraContagem(recordBody) {
  const s = sql(recordBody);
  const corpo = s.slice(s.indexOf('BEGIN'));
  const dry = corpo.indexOf('IF p_dry_run THEN RETURN');
  const grava = corpo.indexOf('INSERT INTO public.drive_folder_inherited_access');
  return {
    vereditoDepoisDeQuemFica: /THEN 'manage_platform_exception' ELSE 'on_roster' END WHEN w\.inherited IS TRUE THEN 'inherited' ELSE 'finding' END\)\), '\[\]'::jsonb\)/.test(s),
    achadoSoDireto: /'findings', count\(\*\) FILTER \(WHERE c\.verdict = 'finding'\),/.test(s),
    contaOHerdado: /'inherited', count\(\*\) FILTER \(WHERE c\.verdict = 'inherited'\),/.test(s),
    contaOHerdadoForaDoCadastro: /'inherited_unknown_person', count\(\*\) FILTER \(WHERE c\.verdict = 'inherited' AND c\.member_id IS NULL\),/.test(s),
    semFindingsInherited: !/findings_inherited/.test(s),
    gravaAContagem: /INSERT INTO public\.drive_folder_inherited_access \(drive_folder_id, inherited_count, inherited_unknown_person\) VALUES \(p_drive_folder_id, \(v_counts->>'inherited'\)::int, \(v_counts->>'inherited_unknown_person'\)::int\) ON CONFLICT \(drive_folder_id\) DO UPDATE SET inherited_count = EXCLUDED\.inherited_count, inherited_unknown_person = EXCLUDED\.inherited_unknown_person,/.test(s),
    gravaDepoisDoDryRun: dry > 0 && grava > dry,
  };
}

/** G32: a tabela da contagem e o motivo de fechamento. */
export function tabelaDaContagem(migText) {
  const m = sql(migText);
  const tab = slice(m, 'CREATE TABLE IF NOT EXISTS public.drive_folder_inherited_access (', ');');
  return {
    semEmailNemPessoa: tab !== '' && !/email|person_id|member_id/.test(tab),
    rlsFechado: /ALTER TABLE public\.drive_folder_inherited_access ENABLE ROW LEVEL SECURITY;/.test(m)
      && /CREATE POLICY drive_folder_inherited_access_deny_all ON public\.drive_folder_inherited_access AS PERMISSIVE FOR ALL TO public USING \(false\) WITH CHECK \(false\);/.test(m),
    soServico: /REVOKE ALL ON public\.drive_folder_inherited_access FROM PUBLIC, anon, authenticated;/.test(m)
      && !/GRANT [^;]* ON public\.drive_folder_inherited_access TO [^;]*(authenticated|anon)/.test(m),
    motivoHerdado: /ADD CONSTRAINT drive_folder_access_findings_close_reason_check CHECK \(close_reason IN \('permission_gone','covered_by_grant','offboarding_lane','on_roster', 'manage_platform_exception','inherited'\)\);/.test(m),
  };
}

/** G33: a tela devolve o herdado por pasta, com o portão. */
export function telaDoHerdado(listBody) {
  const l = sql(listBody);
  return {
    porPastaVivaComPortao: /FROM public\.drive_folder_inherited_access h JOIN LATERAL \( SELECT [^;]*? FROM public\.initiative_drive_links l JOIN public\.initiatives i ON i\.id = l\.initiative_id WHERE l\.drive_folder_id = h\.drive_folder_id AND l\.link_purpose = 'workspace' AND l\.unlinked_at IS NULL AND public\.rls_can_see_initiative\(l\.initiative_id\) \) ini ON ini\.initiatives IS NOT NULL WHERE h\.inherited_count > 0;/.test(l),
    devolve: /RETURN jsonb_build_object\( 'rows', v_rows, 'inherited_by_folder', v_inh,/.test(l),
    totalNoResumo: /'inherited', \(SELECT coalesce\(sum\(\(x->>'inherited_count'\)::int\), 0\) FROM jsonb_array_elements\(v_inh\) x\)/.test(l),
  };
}

/** G34: o reconcile soma o herdado. */
export function reconcileSomaOHerdado(efText) {
  const e = ts(efText);
  const ret = slice(e, 'const sum = (k: string) =>', '};');
  return {
    somaOHerdado: /inherited: sum\("inherited"\), inherited_unknown_person: sum\("inherited_unknown_person"\)/.test(ret),
    achadoDireto: /findings: sum\("findings"\)/.test(ret),
    semFindingsInherited: ret !== '' && !/findings_inherited/.test(ret),
  };
}

/** G35: a ilha e os idiomas. */
export function ilhaMostraOHerdado(islandText, localeTexts) {
  const i = ts(islandText);
  const r = {
    leOHerdado: /const inh = data\.inherited_by_folder \?\? \[\];/.test(i),
    mostraPorPasta: /\{inh\.length > 0 && \( [^]*?\{inh\.map\(\(f\) => \( [^]*?\{f\.inherited_count\}/.test(i),
    totalNoResumo: /t\('driveFolderReview\.sumInherited', 'Herdados da pasta de cima'\)\}: \{s\.inherited \?\? 0\}/.test(i),
  };
  for (const [n, txt] of localeTexts) r[`chaves_${n}`] = KEYS.every((k) => new RegExp(`'driveFolderReview\\.${k}': '`).test(txt));
  return r;
}

/** G36: a volta do cron. */
export function cronReligado(cronMig) {
  const c = sql(cronMig);
  return {
    mesmoNomeEHorario: /SELECT cron\.schedule\( 'membership-drive-reconcile-daily', '0 4 \* \* \*', \$cron\$/.test(c),
    corpoSemPausa: /body := '\{"source":"pg_cron"\}'::jsonb,/.test(c),
    semSkip: !/skip_acl_review/.test(c),
  };
}

test('#3186 G31: o herdado vira contagem na classificação', () => {
  assert.ok(MIG, 'migration *_3186_drive_herdado_vira_contagem.sql ausente');
  ok(herdadoViraContagem(body('record_drive_folder_acl')), 'o herdado deixou de virar contagem');
});
test('#3186 G32: a tabela da contagem', () => ok(tabelaDaContagem(readFileSync(join(MIG_DIR, MIG), 'utf8')), 'a tabela mudou'));
test('#3186 G33: a tela devolve o herdado por pasta', () => ok(telaDoHerdado(body('admin_list_drive_folder_access_findings')), 'a tela mudou'));
test('#3186 G34: o reconcile soma o herdado', () => ok(reconcileSomaOHerdado(readFileSync(EF_PATH, 'utf8')), 'o reconcile mudou'));
test('#3186 G35: a ilha mostra o herdado nos três idiomas', () => {
  ok(ilhaMostraOHerdado(readFileSync(ISLAND, 'utf8'), LOCALES.map((p) => [p.split('/').pop(), readFileSync(p, 'utf8')])), 'a ilha mudou');
});
test('#3186 G36: o cron volta sem skip_acl_review', () => {
  assert.ok(MIG_CRON, 'migration *_3186b_drive_religa_revisao_no_cron.sql ausente');
  ok(cronReligado(readFileSync(join(MIG_DIR, MIG_CRON), 'utf8')), 'o cron mudou');
});

test('#3186 M: cada predicado reprova a mutação do seu defeito', () => {
  const mut = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutação não aplicou: ${a}`); return out; };
  const R = body('record_drive_folder_acl');
  const L = body('admin_list_drive_folder_access_findings');
  const M = readFileSync(join(MIG_DIR, MIG), 'utf8');
  const EF = readFileSync(EF_PATH, 'utf8');
  const I = readFileSync(ISLAND, 'utf8');
  const PT = readFileSync(LOCALES[0], 'utf8');
  const C = readFileSync(join(MIG_DIR, MIG_CRON), 'utf8');
  // G31
  assert.equal(herdadoViraContagem(mut(R, "             WHEN w.inherited IS TRUE THEN 'inherited'\n", '')).vereditoDepoisDeQuemFica, false);
  assert.equal(herdadoViraContagem(mut(R, "WHEN w.inherited IS TRUE THEN 'inherited'", "WHEN w.inherited IS NOT FALSE THEN 'inherited'")).vereditoDepoisDeQuemFica, false);
  assert.equal(herdadoViraContagem(mut(R, "'inherited', count(*) FILTER (WHERE c.verdict = 'inherited'),", "'inherited', count(*) FILTER (WHERE c.verdict = 'finding'),")).contaOHerdado, false);
  assert.equal(herdadoViraContagem(mut(R, "WHERE c.verdict = 'inherited' AND c.member_id IS NULL", "WHERE c.verdict = 'inherited'")).contaOHerdadoForaDoCadastro, false);
  assert.equal(herdadoViraContagem(mut(R, "'findings',  count(*) FILTER (WHERE c.verdict = 'finding'),", "'findings',  count(*) FILTER (WHERE c.verdict IN ('finding','inherited')),")).achadoSoDireto, false);
  assert.equal(herdadoViraContagem(mut(R, "'inherited', count(*)", "'findings_inherited', count(*) FILTER (WHERE c.inherited IS TRUE), 'inherited', count(*)")).semFindingsInherited, false);
  assert.equal(herdadoViraContagem(mut(R, 'SET inherited_count = EXCLUDED.inherited_count,', 'SET inherited_count = drive_folder_inherited_access.inherited_count,')).gravaAContagem, false);
  const grava = slice(R, '  INSERT INTO public.drive_folder_inherited_access', 'updated_at = now();\n');
  const semGrava = mut(R, grava, '');
  assert.equal(herdadoViraContagem(mut(semGrava, '  IF p_dry_run THEN\n', grava + '\n  IF p_dry_run THEN\n')).gravaDepoisDoDryRun, false);
  // G32
  assert.equal(tabelaDaContagem(mut(M, '  inherited_count          integer NOT NULL', '  permission_email citext,\n  inherited_count          integer NOT NULL')).semEmailNemPessoa, false);
  assert.equal(tabelaDaContagem(mut(M, 'ON public.drive_folder_inherited_access\n  AS PERMISSIVE FOR ALL TO public USING (false)', 'ON public.drive_folder_inherited_access\n  AS PERMISSIVE FOR ALL TO public USING (true)')).rlsFechado, false);
  assert.equal(tabelaDaContagem(mut(M, 'TO service_role;\n\n-- ── 3.', 'TO service_role, authenticated;\n\n-- ── 3.')).soServico, false);
  assert.equal(tabelaDaContagem(mut(M, "'manage_platform_exception','inherited'));", "'manage_platform_exception'));")).motivoHerdado, false);
  // G33
  assert.equal(telaDoHerdado(mut(L, "         AND public.rls_can_see_initiative(l.initiative_id)\n    ) ini ON ini.initiatives IS NOT NULL\n   WHERE h.inherited_count", "    ) ini ON ini.initiatives IS NOT NULL\n   WHERE h.inherited_count")).porPastaVivaComPortao, false);
  assert.equal(telaDoHerdado(mut(L, "AND l.unlinked_at IS NULL\n         AND public.rls_can_see_initiative(l.initiative_id)\n    ) ini", "\n         AND public.rls_can_see_initiative(l.initiative_id)\n    ) ini")).porPastaVivaComPortao, false);
  assert.equal(telaDoHerdado(mut(L, "    'inherited_by_folder', v_inh,\n", '')).devolve, false);
  assert.equal(telaDoHerdado(mut(L, "sum((x->>'inherited_count')::int)", "sum((x->>'unknown_person')::int)")).totalNoResumo, false);
  // G34
  assert.equal(reconcileSomaOHerdado(mut(EF, 'inherited: sum("inherited"), ', '')).somaOHerdado, false);
  assert.equal(reconcileSomaOHerdado(mut(EF, 'findings: sum("findings"), ', 'findings: sum("findings"), findings_inherited: sum("findings_inherited"), ')).semFindingsInherited, false);
  // G35
  assert.equal(ilhaMostraOHerdado(mut(I, '{inh.map((f) => (', '{[].map((f) => ('), []).mostraPorPasta, false);
  assert.equal(ilhaMostraOHerdado(mut(I, '{s.inherited ?? 0}', '{0}'), []).totalNoResumo, false);
  assert.equal(ilhaMostraOHerdado(I, [['pt-BR.ts', mut(PT, "  'driveFolderReview.inheritedHint': '", "  'driveFolderReview.xHint': '")]])['chaves_pt-BR.ts'], false);
  // G36
  assert.equal(cronReligado(mut(C, `'{"source":"pg_cron"}'::jsonb`, `'{"source":"pg_cron","skip_acl_review":true}'::jsonb`)).semSkip, false);
  assert.equal(cronReligado(mut(C, `'{"source":"pg_cron"}'::jsonb`, `'{"source":"pg_cron","skip_acl_review":true}'::jsonb`)).corpoSemPausa, false);
  assert.equal(cronReligado(mut(C, "  '0 4 * * *',", "  '0 5 * * *',")).mesmoNomeEHorario, false);
});

// ───────────────────────── vivo ─────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

async function vivo(proname) {
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

test(dbGated ? '#3186 vivo: o corpo em produção passa nos mesmos predicados' : `SKIP: ${skipMsg}`, { skip: !dbGated }, async () => {
  ok(herdadoViraContagem(await vivo('record_drive_folder_acl')));
  ok(telaDoHerdado(await vivo('admin_list_drive_folder_access_findings')));
});
