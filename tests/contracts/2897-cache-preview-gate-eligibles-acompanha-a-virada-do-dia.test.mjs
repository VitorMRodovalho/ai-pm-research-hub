// tests/contracts/2897-cache-preview-gate-eligibles-acompanha-a-virada-do-dia.test.mjs
// DB-aware: as camadas E e F abrem conexão, então o arquivo cai no balde behavioural. A a D são estáticas.
/**
 * #2897: o cache de preview_gate_eligibles acompanha a virada do dia, e o adapter só responde pelo
 * cache quando ele cobre todo membro ativo.
 *
 * O QUE A MEDIÇÃO DE 01/11/2026 MOSTROU:
 *   * O cache só é recalculado em escrita, e quem decide os gates depende de data
 *     (auth_engagements.is_authoritative contra CURRENT_DATE; volunteers_in_role_active;
 *     a janela de 60 dias do chapter_witness). Um vínculo notify_only passou do end_date, o can()
 *     passou a negar, e o cache ficou com a concessão antiga (4 tuplas em desvio no audit).
 *   * O adapter usava o cache se existisse UMA linha fresca do doc_type e contava só as frescas.
 *     Com 1 linha fresca em 117, respondeu source='cache' com curator 0 onde eram 3. O audit
 *     compara sem o corte de 24 h e não via esse caso.
 *
 * As camadas:
 *   A (estático) o rebuild recalcula TODO membro ativo, apaga as linhas de quem não está ativo e
 *                não tem portão de sessão (sob pg_cron não há JWT, #1548).
 *   B (estático) o ACL fecha o rebuild a service_role, DEPOIS de criar a função.
 *   C (estático) o job é agendado por nome, logo depois da virada do dia, e chama o rebuild.
 *   D (estático) a definição MAIS NOVA do adapter só usa o cache quando todo membro ativo tem
 *                linha fresca.
 *   E (vivo)     o que o adapter responde bate com o cálculo ao vivo, gate a gate, venha de onde
 *                vier (cache ou fallback). É a pergunta do consumidor; o audit existente olha o
 *                cache cru e não aplica o corte de 24 h.
 *   F (vivo)     anon não alcança o rebuild, e é barrado por PERMISSÃO, não por ausência.
 *
 * ⚠️ Nenhuma camada CHAMA o rebuild. Ele reescreve o cache, e rodar no CI curaria o estado que
 * preview-gate-eligibles-cache-equivalence e a camada E existem para pegar. A chamada pelo
 * service_role e o "todas as linhas com o mesmo last_refreshed" ficam na prova viva da PR.
 * Nenhuma camada lê cron.job: o PostgREST não expõe o schema cron (#1543, #2285, #2323).
 *
 * Cross-ref: #2897, #2323 (forma do agendamento), #1548, #1844, ADR-0016 Amendment 3.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { maskSqlNonCode } from '../helpers/new-relation-grants.mjs';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');
const REBUILD = 'rebuild_preview_gate_eligibles_cache_cron';
const JOB = 'preview-gate-eligibles-rebuild-daily';
const CACHEABLE_DOC_TYPES = [
  'cooperation_agreement',
  'cooperation_addendum',
  'volunteer_term_template',
  'volunteer_addendum',
  'policy',
];

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const ws = (s) => s.replace(/\s+/g, ' ');

/** Migrations em ordem de versão, com os comentários de linha mascarados (offsets preservados). */
function migrations() {
  return readdirSync(MIGRATIONS)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => ({ file: f, raw: readFileSync(join(MIGRATIONS, f), 'utf8') }))
    .map((m) => ({ ...m, code: maskLineComments(m.raw) }));
}

/** A migration que cria o rebuild, procurada por CONTEÚDO: renomear o arquivo para a versão que o
 *  apply registrar não pode deixar o guard verde por não achar nada. */
function migrationDoRebuild() {
  const achados = migrations().filter((m) =>
    m.code.includes(`CREATE OR REPLACE FUNCTION public.${REBUILD}()`));
  assert.ok(achados.length >= 1, `nenhuma migration cria public.${REBUILD}()`);
  return achados[achados.length - 1];
}

/** Corpo de uma função, do cabeçalho até o fecho do seu bloco dollar-quoted. */
function corpoDaFuncao(code, header) {
  const start = code.indexOf(header);
  assert.ok(start >= 0, `não achei ${header}`);
  const tag = code.slice(start).match(/AS\s+(\$[a-z_]*\$)/);
  assert.ok(tag, `não achei o início do corpo de ${header}`);
  const open = code.indexOf(tag[1], start) + tag[1].length;
  const close = code.indexOf(tag[1], open);
  assert.ok(close > open, `não achei o fim do corpo de ${header}`);
  return { start, body: code.slice(open, close), end: close + tag[1].length };
}

// ═══════════════════════════════════════════════════════════════════════════
test('A · o rebuild recalcula todo membro ativo, varre os inativos e não tem portão de sessão', () => {
  const { code } = migrationDoRebuild();
  const { body } = corpoDaFuncao(code, `CREATE OR REPLACE FUNCTION public.${REBUILD}()`);
  const b = ws(body);

  assert.match(b,
    /FOR v_member IN SELECT m\.id FROM public\.members m WHERE m\.is_active = true LOOP PERFORM public\._refresh_preview_gate_eligibles_for_member\(v_member\.id\);/,
    'o laço tem de percorrer os membros ATIVOS e recalcular cada um: é o que alinha o cache à data de hoje');

  assert.match(b,
    /DELETE FROM public\.preview_gate_eligibles_cache c WHERE NOT EXISTS \( SELECT 1 FROM public\.members m WHERE m\.id = c\.member_id AND m\.is_active = true \);/,
    'a varredura tem de apagar só as linhas de quem NÃO está ativo');

  assert.ok(!/auth\.uid\(\)|RAISE\s+EXCEPTION/i.test(body),
    'o rebuild ganhou portão de sessão ou exceção: sob pg_cron não há JWT (#1548), e o job ' +
    'rodaria vermelho todo dia sem atualizar nada. A proteção é o ACL (camada B).');
});

test('B · o ACL fecha o rebuild a service_role, depois de criar a função', () => {
  const { raw } = migrationDoRebuild();
  const top = maskSqlNonCode(raw);
  const create = top.indexOf(`CREATE OR REPLACE FUNCTION public.${REBUILD}()`);
  assert.ok(create >= 0, 'o CREATE do rebuild precisa estar no topo da migration');

  const revoke = top.search(new RegExp(
    `REVOKE ALL ON FUNCTION public\\.${REBUILD}\\(\\) FROM PUBLIC, anon, authenticated;`));
  assert.ok(revoke >= 0,
    'falta o REVOKE de PUBLIC, anon e authenticated: função nova nasce com EXECUTE para PUBLIC, ' +
    'e sem portão de sessão qualquer um reescreveria o cache');
  assert.ok(revoke > create,
    'o REVOKE veio antes do CREATE: a função ainda não existia, e ela nasceria aberta');

  const grant = top.search(new RegExp(
    `GRANT EXECUTE ON FUNCTION public\\.${REBUILD}\\(\\) TO service_role;`));
  assert.ok(grant > create, 'falta o GRANT EXECUTE ao service_role, depois do CREATE');
});

test('C · o job é agendado por nome, logo depois da virada do dia, e chama o rebuild', () => {
  const { code } = migrationDoRebuild();
  const m = code.match(new RegExp(
    `cron\\.schedule\\(\\s*'${JOB}',\\s*'([^']+)',\\s*\\$cron\\$([\\s\\S]*?)\\$cron\\$\\s*\\)`));
  assert.ok(m, `o job ${JOB} tem de ser agendado por nome, com o comando em bloco $cron$`);

  const [minuto, hora, ...resto] = m[1].split(' ');
  assert.equal(hora, '0',
    `o job foi para ${m[1]}. Quem decide os gates vira às 00:00 UTC (CURRENT_DATE), e cada hora ` +
    'depois disso é uma hora com o cache errado e o CI vermelho no equivalence.');
  assert.ok(Number(minuto) >= 1 && Number(minuto) <= 5,
    `minuto ${minuto}: tem de ser logo depois da virada, e não o minuto 0 (#1844)`);
  assert.deepEqual(resto, ['*', '*', '*'], `o job tem de rodar todo dia, e está em ${m[1]}`);

  assert.match(m[2], new RegExp(`^\\s*SELECT public\\.${REBUILD}\\(\\);\\s*$`),
    'o comando do job tem de chamar o rebuild, e só ele');
});

test('D · o adapter mais novo só usa o cache quando todo membro ativo tem linha fresca', () => {
  const header = 'CREATE OR REPLACE FUNCTION public.preview_gate_eligibles(';
  const def = migrations().filter((m) => m.code.includes(header)).at(-1);
  assert.ok(def, 'nenhuma migration define public.preview_gate_eligibles');
  const { body } = corpoDaFuncao(def.code, header);
  const atrib = ws(body).match(/v_use_cache := ([^;]*);/);
  assert.ok(atrib, `${def.file}: não achei a atribuição de v_use_cache`);

  assert.equal(atrib[1],
    "p_doc_type = ANY(public._cacheable_preview_doc_types()) AND NOT EXISTS ( SELECT 1 FROM public.members m WHERE m.is_active = true AND NOT EXISTS ( SELECT 1 FROM public.preview_gate_eligibles_cache c WHERE c.member_id = m.id AND c.doc_type = p_doc_type AND c.last_refreshed >= v_stale_cutoff ) )",
    `${def.file}: o adapter voltou a usar o cache sem que TODO membro ativo tenha linha fresca. ` +
    'Com uma linha fresca só, ele conta só as frescas e responde source=cache com menos ' +
    'signatários do que existem (#2897).');
});

// ═══════════════════════════════════════════════════════════════════════════
test('E · o adapter responde o mesmo que o cálculo ao vivo, gate a gate',
  { skip: !dbGated && skipMsg }, async (t) => {
  const client = sb();
  const { data: audit, error: auditErr } = await client.rpc('_audit_preview_gate_eligibles_drift');
  assert.ifError(auditErr);
  assert.ok(Array.isArray(audit) && audit.length > 0, 'o audit tem de devolver linhas');
  const live = new Map(audit.map((r) => [`${r.doc_type}/${r.gate_kind}`, r.live_count]));

  const divergencias = [];
  const fontes = [];
  for (const docType of CACHEABLE_DOC_TYPES) {
    const { data: gates, error } = await client.rpc('preview_gate_eligibles',
      { p_doc_type: docType, p_submitter_id: null });
    assert.ifError(error);
    assert.ok(Array.isArray(gates) && gates.length > 0, `${docType}: o adapter não devolveu gates`);
    for (const g of gates) {
      if (g.gate_kind === 'submitter_acceptance') continue;
      const key = `${docType}/${g.gate_kind}`;
      assert.ok(live.has(key), `${key}: o adapter devolveu um gate que o audit não conhece`);
      fontes.push(`${key}=${g.source}`);
      if (g.count !== live.get(key)) {
        divergencias.push(`${key}: adapter=${g.count} (source=${g.source}) ao vivo=${live.get(key)}`);
      }
    }
  }
  t.diagnostic(`fontes: ${[...new Set(fontes.map((f) => f.split('=')[1]))].join(', ')}`);
  assert.deepEqual(divergencias, [],
    'o adapter responde uma contagem diferente do cálculo ao vivo. Com source=cache e o audit ' +
    'limpo, é a mistura de linhas frescas e velhas (#2897).');
});

test('F · anon NÃO alcança o rebuild, e é barrado por PERMISSÃO, não por ausência',
  { skip: (!dbGated || !ANON_KEY) && skipMsg }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc(REBUILD);
  assert.ok(error, 'anon conseguiu rodar o rebuild: sem portão de sessão, o ACL é a ÚNICA barreira');
  assert.notEqual(error.code, 'PGRST202',
    'anon foi barrado porque a função não existe no schema cache, não pelo ACL. Nesse estado o ' +
    'cron também não roda, e este guard estaria verde sobre um rebuild que não existe.');
});
