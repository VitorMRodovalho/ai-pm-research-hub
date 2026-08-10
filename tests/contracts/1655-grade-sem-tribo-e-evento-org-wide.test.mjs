/**
 * Contract: #1655 (fatia) — a grade membro x evento tem linha para quem nao tem tribo,
 * e nao derruba o evento ORG-WIDE que carrega initiative_id.
 *
 * Dois defeitos medidos em 10/08/2026 em `get_attendance_grid`, ambos de SUPERFICIE:
 *
 *  1. o array 'tribes' era indexado por public.tribes, entao quem nao tem tribo nao tinha
 *     onde aparecer. A funcao publicava summary.total_members = 83 e renderizava 66 pessoas
 *     no corpo: 17 entravam na taxa e nao tinham linha. Dessas 17, 3 estao na coorte de
 *     seal_event_attendance — selar gravaria present=false para quem nao tem tela onde
 *     corrigir, e nao existe `unseal` (bloqueio do #1710).
 *  2. o filtro (initiative_id IS NULL OR type = 'tribo') derrubava 1 evento 'geral'
 *     (58 linhas de presenca, todas presentes) SO desta grade — a de tribo e a de iniciativa
 *     ja o mostravam.
 *
 * Afrouxar o filtro por TIPO tirou a contencao que o #785 usava como justificativa de
 * allowlist (a de ADR-0105 era efeito colateral dele). Por isso grid_events passou a chamar
 * rls_can_see_initiative(), que e o gate canonico e nao depende do tipo do evento.
 *
 * Tres camadas, porque nenhuma sozinha observa o mundo:
 *   A.  estatica sobre a captura MAIS RECENTE, com ponteiro DERIVADO de loadLatestCaptures()
 *       (#1682/#569: caminho de migration escrito a mao fica vermelho por trabalho correto).
 *       Comentarios fora antes de assertar, e cada afirmacao acompanhada da INVERSA — a forma
 *       antiga tem de ter sumido, senao um CREATE OR REPLACE parcial passaria.
 *   A'. md5 do corpo VIVO == a mesma captura (DB-gated). Sem isto, A fica verde com a mudanca
 *       removida do banco — guard ancorado num arquivo nao observa o mundo (#1649).
 *   B.  varredura do front, com CONTROLE POSITIVO (#1636: o controle e o que pega o scanner
 *       quebrado, que fica VERDE).
 *   C.  o gate medido no vivo. A grade e gateada em auth.uid() e o service_role nao a alcanca,
 *       entao C exerce rls_can_see_initiative() diretamente, nos dois sentidos.
 *
 * Migration: 20260810140903_1655_grade_sem_tribo_e_evento_org_wide.sql
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import {
  loadLatestCaptures, parseMigration, normalizeBody, md5,
} from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const CHAVE = 'get_attendance_grid@p_tribe_id integer, p_event_type text';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

/** Corpo da captura mais recente de get_attendance_grid, por ponteiro DERIVADO. */
function capturaMaisRecente() {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const cap = latest.get(CHAVE);
  assert.ok(cap, `sem captura de migration para ${CHAVE}`);
  const blocos = parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8'));
  const bloco = blocos.find(b => `${b.name}@${b.args}` === CHAVE);
  assert.ok(bloco, `${cap.file} nao contem o bloco de ${CHAVE}`);
  return { file: cap.file, bodyHash: cap.bodyHash, body: bloco.body };
}

/** Comentarios fora: um guard que le o texto cru casa a propria explicacao (#1586b). */
const semComentariosSql = (s) => s.replace(/--[^\n]*/g, '');
const achatado = (s) => semComentariosSql(s).replace(/\s+/g, ' ');

async function rpc(nome, corpo) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
    },
    body: JSON.stringify(corpo),
  });
  assert.ok(res.ok, `${nome} devia responder 2xx (veio ${res.status})`);
  return res.json();
}

// ── A: a captura mais recente carrega as duas mudancas, e nao a forma antiga ──────────────

test('#1655 A: o filtro de eventos admite o org-wide com initiative_id, e a forma antiga sumiu', () => {
  const { body, file } = capturaMaisRecente();
  const codigo = achatado(body);

  assert.match(
    codigo,
    /AND \(e\.initiative_id IS NULL OR e\.type IN \('tribo', 'geral', 'kickoff', 'lideranca'\)\)/i,
    `${file}: grid_events tem de admitir o evento org-wide que carrega initiative_id`,
  );
  // A INVERSA: a forma restritiva nao pode continuar no corpo, senao um merge parcial
  // (ou um CREATE OR REPLACE de outra frente) reintroduz o defeito com o teste verde.
  assert.doesNotMatch(
    codigo,
    /AND \(e\.initiative_id IS NULL OR e\.type = 'tribo'\)/i,
    `${file}: o filtro antigo por tipo unico voltou`,
  );
});

test('#1655 A: grid_events CHAMA rls_can_see_initiative (nao apenas menciona)', () => {
  const { body, file } = capturaMaisRecente();
  const codigo = achatado(body);

  // CHAMAR, nao CITAR (#1636). O proprio auditor do #785 marca "references_gate" por regex
  // sobre prosrc — inclusive dentro de comentario. Aqui os comentarios ja sairam.
  assert.match(
    codigo,
    /public\.rls_can_see_initiative\(e\.initiative_id\)/i,
    `${file}: sem a chamada do gate, afrouxar o filtro por tipo abre ADR-0105`,
  );
  // controle: a chamada tem de estar no MESMO predicado de grid_events, ligada por AND.
  assert.match(
    codigo,
    /AND \(e\.initiative_id IS NULL OR public\.rls_can_see_initiative\(e\.initiative_id\)\)/i,
    `${file}: o gate tem de filtrar grid_events, nao ficar solto no corpo`,
  );
});

test('#1655 A: o array tribes carrega o grupo sintetico dos sem-tribo', () => {
  const { body, file } = capturaMaisRecente();
  const codigo = achatado(body);

  assert.match(
    codigo,
    /UNION ALL SELECT to_jsonb\('__cross_functional__'::text\)/i,
    `${file}: sem o ramo sintetico, quem nao tem tribo volta a nao ter linha`,
  );
  // o ramo so pode existir na visao geral: com p_tribe_id preenchido o chamador pediu UMA tribo.
  assert.match(
    codigo,
    /'__cross_functional__'::text\), 'Cross-functional', NULL::integer, 1 WHERE p_tribe_id IS NULL/i,
    `${file}: o grupo sintetico tem de ser guardado por p_tribe_id IS NULL`,
  );
  // e so aparece se houver gente nele — grupo vazio na tela e ruido.
  assert.match(
    codigo,
    /AND EXISTS \(SELECT 1 FROM active_members_scoped ams WHERE ams\.tribe_id IS NULL\)/i,
    `${file}: o grupo sintetico nao pode aparecer sem populacao`,
  );
});

test('#1655 A: o escopo de membros usa IS NOT DISTINCT FROM, senao o grupo sintetico sai vazio', () => {
  const { body, file } = capturaMaisRecente();
  const codigo = achatado(body);

  // `am.tribe_id = t.real_id` com real_id NULL nunca casa: o grupo apareceria com 0 membros,
  // que e verde por vacuidade. As quatro leituras (avg_rate, avg_rate_pct, member_count,
  // members) tem de usar a comparacao NULL-safe.
  const nulSafe = (codigo.match(/am\.tribe_id IS NOT DISTINCT FROM t\.real_id/gi) || []).length;
  assert.equal(nulSafe, 4, `${file}: esperado 4 escopos NULL-safe, achados ${nulSafe}`);
  assert.doesNotMatch(
    codigo,
    /am\.tribe_id = t\.id\b/i,
    `${file}: sobrou um escopo com igualdade simples, que exclui o grupo sintetico`,
  );
});

// ── A': o banco concorda com o arquivo ───────────────────────────────────────────────────

test('#1655 A\': o corpo VIVO de get_attendance_grid == a captura mais recente', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  const { bodyHash, file } = capturaMaisRecente();
  const linhas = await rpc('_audit_function_source', { p_proname: 'get_attendance_grid' });
  assert.equal(linhas.length, 1, 'esperado exatamente 1 get_attendance_grid em pg_proc');
  assert.equal(
    md5(normalizeBody(linhas[0].prosrc)), bodyHash,
    `corpo vivo divergente de ${file}: a mudanca esta no arquivo e nao no banco (ou vice-versa)`,
  );
});

// ── B: o front trata o grupo sintetico como grupo, e nao como tribo ──────────────────────

const GRID_TAB = resolve(ROOT, 'src/components/attendance/AttendanceGridTab.tsx');

test('#1655 B: o KPI "melhor tribo" nao pode nomear o grupo sintetico', () => {
  const src = readFileSync(GRID_TAB, 'utf8');
  // controle POSITIVO: se o arquivo mudar de nome ou o KPI sumir, o scanner tem de acusar
  // em vez de ficar verde por nao achar nada (#1636).
  assert.match(src, /const bestTribe = useMemo\(/, 'controle positivo: bestTribe sumiu do arquivo');

  const memo = src.slice(src.indexOf('const bestTribe = useMemo('));
  const corpo = memo.slice(0, memo.indexOf('}, [data]);'));
  assert.match(
    corpo,
    /tribe_id !== CROSS_FUNCTIONAL_ID/,
    'bestTribe tem de excluir o grupo sintetico, senao o KPI nomeia "Cross-functional"',
  );
});

test('#1655 B: o fallback de linhas orfas nao volta (era inerte por construcao)', () => {
  const src = readFileSync(GRID_TAB, 'utf8');
  assert.match(src, /const groupedByTribe = useMemo\(/, 'controle positivo: groupedByTribe sumiu');
  // as linhas sao achatadas de data.tribes[].members[], entao nenhuma pode ficar fora do
  // tribeMap: um ramo de orfas so pode ser codigo morto que PARECE cobertura.
  assert.doesNotMatch(src, /orphanRows/, 'o fallback de orfas voltou; ele nunca pode disparar');
});

test('#1655 B: o sentinel e um so, e vem do modulo (nao redeclarado por escopo)', () => {
  const src = readFileSync(GRID_TAB, 'utf8');
  const decls = (src.match(/const CROSS_FUNCTIONAL_ID = /g) || []).length;
  assert.equal(decls, 1, `esperada 1 declaracao do sentinel, achadas ${decls}`);
  assert.match(src, /const CROSS_FUNCTIONAL_ID = '__cross_functional__';/,
    'o sentinel do front tem de ser o mesmo que a RPC publica');
});

// ── C: o gate discrimina no vivo ─────────────────────────────────────────────────────────

test('#1655 C: rls_can_see_initiative contem a iniciativa confidencial e libera o resto', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  const busca = async (qs) => {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/initiatives?${qs}`, {
      headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    });
    assert.ok(res.ok, `leitura de initiatives devia responder 2xx (veio ${res.status})`);
    return res.json();
  };

  // sem iniciativa (evento org-level): passa sempre.
  const semIniciativa = await rpc('rls_can_see_initiative', { p_initiative_id: null });
  assert.equal(semIniciativa, true, 'evento sem iniciativa tem de passar pelo gate');

  // controle POSITIVO: uma iniciativa NAO confidencial tem de passar. Sem ele, um gate que
  // recusa tudo passaria no teste da recusa e derrubaria a grade inteira.
  const abertas = await busca('visibility=neq.confidential&select=id&limit=1');
  assert.equal(abertas.length, 1, 'controle positivo: esperada ao menos 1 iniciativa nao confidencial');
  assert.equal(
    await rpc('rls_can_see_initiative', { p_initiative_id: abertas[0].id }), true,
    'iniciativa aberta tem de passar pelo gate',
  );

  // o lado da recusa. service_role nao tem auth.uid() nem manage_platform, entao ve false.
  const confidenciais = await busca('visibility=eq.confidential&select=id');
  assert.ok(
    confidenciais.length >= 1,
    'sem iniciativa confidencial na base, a contencao de ADR-0105 nao pode ser exercida: ' +
    'este teste passaria por POPULACAO ZERO. Reavaliar o guard antes de silencia-lo.',
  );
  for (const ini of confidenciais) {
    assert.equal(
      await rpc('rls_can_see_initiative', { p_initiative_id: ini.id }), false,
      'iniciativa confidencial nao pode passar pelo gate para um chamador sem engajamento',
    );
  }
});
