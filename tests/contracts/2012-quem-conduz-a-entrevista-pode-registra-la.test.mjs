// tests/contracts/2012-quem-conduz-a-entrevista-pode-registra-la.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2012 — quem CONDUZ a entrevista passa a poder REGISTRÁ-LA, e a recusa por autoridade
 * deixa rastro.
 *
 * SINTOMA (25/08/2026): um avaliador do comitê conduziu uma entrevista às 20h e não conseguiu
 * criar o registro. A plataforma deixava o entrevistador PONTUAR (`submit_interview_scores`, depois da
 * #1972) e não deixava criar o registro do que ele mesmo conduziu — `schedule_interview` exigia
 * `role='lead'` OU `manage_platform`. Medido em 26/08 no `cycle4-2026`: 2 de 7 passavam.
 *
 * O CONSERTO É O DA #1972, do outro lado do fluxo: a designação é CRIADA, o portão não é
 * contornado. E ele NÃO se apoia em `can_interview` sozinho — medido em 26/08, essa coluna é
 * `true` em 13 de 13 linhas de `selection_committee` (4 evaluator, 4 lead, 5 observer), então
 * sozinha ela não discrimina ninguém: alargar só por ela entregaria a criação do registro
 * também aos observadores, que nesta plataforma são leitura (`isObserver` bloqueia a pontuação;
 * o eixo `operate_selection` do #1838 exclui exatamente esse papel).
 *
 * O que este arquivo prova:
 *   (A) o corpo VIVO é o corpo capturado (md5) — a migration é a captura, não um arquivo que
 *       descreve algo que produção não executa mais (#1932);
 *   (B) o caminho novo é ESTREITO: comitê do ciclo + can_interview + papel que decide + lista de
 *       UM que é o próprio chamador, e sem bypass;
 *   (C) a recusa por autoridade REGISTRA em vez de levantar (a forma da #1594: `RAISE` e
 *       `INSERT` na mesma transação matam a linha de auditoria);
 *   (D) as asserções MORDEM — cada defeito reinjetado tem de reprovar;
 *   (E) a superfície de leitura (tela + MCP) sabe nomear o código novo;
 *   (F) controle de população: o alargamento é de poucas pessoas, e nenhum observador entra.
 *
 * Cross-ref: #2012, #1972, #1594, #1613/#472 corr.3, #1838, #1932.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260826212137_2012_quem_conduz_a_entrevista_pode_registra_la.sql');
const ADMIN = resolve(ROOT, 'src/pages/admin/selection.astro');
const MCP = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const MIG_SRC = read(MIG);
const ADMIN_SRC = read(ADMIN);
const MCP_SRC = read(MCP);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/**
 * Captura VIGENTE — a migration mais nova que define a função, nunca um arquivo fixo (#1932).
 * O par (função → arquivo) é resolvido pelo scanner compartilhado, então quando uma migration
 * posterior recriar `schedule_interview` este guard segue afirmando o corpo CORRENTE.
 */
const capturaVigente = () => latestFunctionCapture(ROOT, 'schedule_interview');

/**
 * Violações do desenho da #2012 num corpo de `schedule_interview`. Devolve LISTA de mensagens
 * (vazia = saudável) para que a mesma função sirva ao corpo real e ao corpo adulterado — é o
 * que faz a reinjeção do defeito ser um teste da ASSERÇÃO, e não outra afirmação sobre o texto.
 */
function violacoes(corpo) {
  const v = [];

  // (B1) o caminho novo pede comitê DO CICLO — não comitê em geral.
  if (!/FROM public\.selection_committee sc\b/.test(corpo)
      || !/sc\.cycle_id = v_app\.cycle_id/.test(corpo)
      || !/sc\.member_id = v_caller\.id/.test(corpo)) {
    v.push('o caminho novo não amarra o comitê ao CICLO da candidatura');
  }

  // (B2) `can_interview` sozinho não discrimina (13/13 linhas em `true`): o papel tem de entrar.
  if (!/sc\.can_interview/.test(corpo)) {
    v.push('o caminho novo não exige can_interview');
  }
  if (!/sc\.role <> 'observer'/.test(corpo)) {
    v.push("o caminho novo não exclui o papel de leitura (sc.role <> 'observer')");
  }

  // (B3) lista de UM, e esse um é o próprio chamador — senão vira agendamento de terceiro.
  if (!/cardinality\(coalesce\(p_interviewer_ids, ARRAY\[\]::uuid\[\]\)\) = 1/.test(corpo)
      || !/p_interviewer_ids\[1\] = v_caller\.id/.test(corpo)) {
    v.push('o caminho novo não está preso à lista de UM que é o próprio chamador');
  }

  // (B4) o caminho novo NUNCA recebe o bypass — é o que mantém P0002/P0003 e a allow-list de
  // status valendo integralmente para ele (aceite 3 da issue).
  if (!/v_authority_path IS DISTINCT FROM 'self_interviewer'/.test(corpo)) {
    v.push('o caminho novo pode receber p_bypass_gate — a allow-list de status deixa de contê-lo');
  }

  // (B5) precedência: quem já passava passa pelo mesmo caminho de antes.
  const iLead = corpo.indexOf("THEN 'committee_lead'");
  const iAdmin = corpo.indexOf("THEN 'manage_platform'");
  const iSelf = corpo.indexOf("THEN 'self_interviewer'");
  if (!(iLead > 0 && iAdmin > iLead && iSelf > iAdmin)) {
    v.push('a precedência lead > manage_platform > self não está escrita nessa ordem');
  }

  // (C) a recusa por autoridade REGISTRA e RETORNA. `RAISE` mataria a linha no rollback (#1594).
  if (!/'P0005', 'UNAUTHORIZED_NOT_INTERVIEW_AUTHORITY'/.test(corpo)) {
    v.push('a recusa por autoridade não registra P0005 em gate_attempts');
  }
  if (/RAISE EXCEPTION 'Unauthorized: must be committee lead/.test(corpo)) {
    v.push('a recusa por autoridade ainda levanta — a linha de auditoria morre no rollback');
  }
  const iLog = corpo.indexOf("'P0005', 'UNAUTHORIZED_NOT_INTERVIEW_AUTHORITY'");
  const iRet = corpo.indexOf("'gate_failed_code', 'P0005'");
  if (!(iLog > 0 && iRet > iLog)) {
    v.push('o log de P0005 não precede o envelope de recusa');
  }

  // (controle negativo) o que a #2012 NÃO mexeu tem de continuar de pé.
  if (!/IF NOT v_can_bypass THEN[\s\S]*'GATE_NO_PEER_REVIEW'[\s\S]*'GATE_NO_SCORE'[\s\S]*END IF;/.test(corpo)) {
    v.push('P0002/P0003 saíram de dentro do IF NOT v_can_bypass');
  }
  if (!/v_can_bypass AND v_app\.status IN \('screening', 'submitted', 'objective_eval', 'objective_cutoff'\)/.test(corpo)) {
    v.push('a allow-list P0004 do #472 corr.3 foi alterada');
  }
  if (/'P0001'/.test(corpo)) {
    v.push('P0001 (GATE_NO_AI, aposentado pela #1640) voltou ao corpo');
  }

  return v;
}

// ── A/B/C — estático sobre a captura vigente ─────────────────────────────────────────
test('#2012 static: a migration existe no timestamp registrado pelo apply_migration', () => {
  assert.ok(MIG_SRC.length > 0, `migration esperada em ${MIG}`);
  assert.match(MIG_SRC, /CREATE OR REPLACE FUNCTION public\.schedule_interview\(/);
});

test('#2012 static: o corpo capturado tem o desenho inteiro da issue', () => {
  const cap = capturaVigente();
  assert.ok(cap?.body, 'alguma migration captura schedule_interview');
  assert.deepEqual(violacoes(cap.body), [], 'o corpo capturado tem de estar saudável');
});

// ── D — as asserções mordem ──────────────────────────────────────────────────────────
test('#2012 static: reprova o corpo que entrega o registro ao observador', () => {
  const { body } = capturaVigente();
  const adulterado = body.replace("\n      AND sc.role <> 'observer'", '');
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoes(adulterado);
  assert.ok(v.some((m) => m.includes('papel de leitura')),
    `esperava a violação do papel de leitura, e veio: ${JSON.stringify(v)}`);
});

test('#2012 static: reprova o corpo que aceita entrevistador de TERCEIRO', () => {
  const { body } = capturaVigente();
  const adulterado = body.replace(
    /v_self_only := cardinality\(coalesce\(p_interviewer_ids, ARRAY\[\]::uuid\[\]\)\) = 1\s*\n\s*AND p_interviewer_ids\[1\] = v_caller\.id;/,
    'v_self_only := true;',
  );
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoes(adulterado);
  assert.ok(v.some((m) => m.includes('lista de UM')),
    `esperava a violação da lista de um, e veio: ${JSON.stringify(v)}`);
});

test('#2012 static: reprova o corpo que volta a LEVANTAR a recusa de autoridade', () => {
  const { body } = capturaVigente();
  const i = body.indexOf('  IF v_authority_path IS NULL THEN');
  assert.ok(i > 0, 'não achei o bloco de recusa para adulterar');
  const fim = body.indexOf('\n  END IF;', i);
  assert.ok(fim > i, 'não achei o fim do bloco de recusa');
  const adulterado =
    body.slice(0, i) +
    "  IF v_authority_path IS NULL THEN\n" +
    "    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';" +
    body.slice(fim);
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoes(adulterado);
  assert.ok(v.some((m) => m.includes('morre no rollback')),
    `esperava a violação da recusa que levanta, e veio: ${JSON.stringify(v)}`);
});

test('#2012 static: reprova o corpo que devolve o bypass ao caminho novo', () => {
  const { body } = capturaVigente();
  const adulterado = body.replace(
    /\s*\n\s*AND v_authority_path IS DISTINCT FROM 'self_interviewer'/,
    '',
  );
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoes(adulterado);
  assert.ok(v.some((m) => m.includes('p_bypass_gate')),
    `esperava a violação do bypass, e veio: ${JSON.stringify(v)}`);
});

// ── E — a superfície de leitura sabe nomear o código novo ────────────────────────────
test('#2012 static: a tela de auditoria nomeia P0005 (rótulo E cor)', () => {
  assert.ok(ADMIN_SRC.length > 0, 'admin/selection.astro tem de existir');
  // O renderer usa `gateCodeLabels[a.gate_failed_code] || 'FALHOU'`: sem entrada, a recusa nova
  // aparece como um "FALHOU" mudo, que é auditoria decorativa outra vez.
  assert.match(ADMIN_SRC, /P0005: 'Sem autoridade'/, 'sem rótulo, P0005 vira "FALHOU" genérico');
  assert.match(ADMIN_SRC, /P0005: 'bg-[a-z]+-\d+ text-[a-z]+-\d+'/, 'P0005 sem cor própria');
});

test('#2012 static: o MCP documenta P0005 no timeline de gate', () => {
  assert.ok(MCP_SRC.length > 0, 'nucleo-mcp/index.ts tem de existir');
  assert.match(MCP_SRC, /P0005 UNAUTHORIZED_NOT_INTERVIEW_AUTHORITY/);
  // e a ferramenta de agendamento para de descrever autoridade que não é mais a vigente
  assert.doesNotMatch(
    MCP_SRC,
    /Books an interview for an application\. Authority: must be committee lead \(selection_committee\.role='lead'\) or superadmin\./,
    'a descrição do schedule_interview ficou defasada em relação ao portão',
  );
});

// ── A — o corpo vivo é o corpo capturado ─────────────────────────────────────────────
test('#2012 db: md5 do corpo VIVO bate com a captura vigente',
  { skip: dbGated ? false : skipMsg }, async () => {
    const cap = capturaVigente();
    const md5Arquivo = createHash('md5').update(cap.body.replace(/\s+/g, ' ')).digest('hex');
    const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
    assert.ifError(error);
    const vivas = (data ?? []).filter((f) => f.proname === 'schedule_interview');
    assert.equal(vivas.length, 1, `esperava UMA schedule_interview viva, achei ${vivas.length}`);
    assert.equal(vivas[0].body_md5, md5Arquivo,
      `o corpo vivo divergiu da captura (${cap.file}) — ou a migration não foi aplicada, ou ` +
      'alguém redefiniu a função fora dela (classe do #1932)');
    assert.equal(vivas[0].is_secdef, true, 'continua SECURITY DEFINER');
  });

test('#2012 db: o corpo VIVO carrega o desenho, não só o arquivo',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb().rpc('_audit_function_source', { p_proname: 'schedule_interview' });
    assert.ifError(error);
    assert.ok(data?.length > 0, 'schedule_interview não existe no banco');
    for (const row of data) assert.deepEqual(violacoes(row.prosrc), []);
  });

// ── F — controle de população ────────────────────────────────────────────────────────
test('#2012 db: o papel vem do CATÁLOGO — um papel novo reprova em vez de herdar o portão',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Derivado do domínio da coluna, não de lista de nomes de pessoa (aceite 4 da issue). Se o
    // catálogo crescer, alguém tem de DECIDIR se o papel novo registra entrevista — e descobre
    // isso aqui, em vermelho, e não pela porta aberta.
    const CATALOGO = ['evaluator', 'lead', 'observer'];
    const { data, error } = await sb().from('selection_committee').select('role');
    assert.ifError(error);
    const observados = [...new Set((data ?? []).map((r) => r.role))].sort();
    for (const papel of observados) {
      assert.ok(CATALOGO.includes(papel),
        `papel '${papel}' fora do catálogo conhecido (${CATALOGO.join('|')}): o portão da #2012 ` +
        'exclui apenas observer, então um papel novo entraria por omissão');
    }
  });

test('#2012 db: o alargamento é ESTREITO e nenhum observador entra',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data: rows, error } = await sb()
      .from('selection_committee').select('member_id, role, can_interview');
    assert.ifError(error);

    const ganham = new Set(
      (rows ?? []).filter((r) => r.can_interview && r.role !== 'observer').map((r) => r.member_id),
    );
    const soObservador = new Set(
      (rows ?? []).filter((r) => r.role === 'observer').map((r) => r.member_id),
    );
    for (const id of ganham) soObservador.delete(id);

    assert.ok(ganham.size > 0, 'se ninguém ganha, o conserto não desbloqueia o caso que o gerou');
    for (const id of soObservador) {
      assert.ok(!ganham.has(id), `observador ${id} entrou no caminho de registro`);
    }

    const { count: ativos, error: e2 } = await sb()
      .from('members').select('id', { count: 'exact', head: true })
      .eq('is_active', true).is('offboarded_at', null);
    assert.ifError(e2);
    assert.ok(ganham.size < ativos / 4,
      `a população habilitada (${ganham.size}) precisa ser muito menor que a de ativos (${ativos}): ` +
      'registrar entrevista é ato de comitê, não capacidade geral');
  });

test('#2012 db: `can_interview` sozinho não seria portão — o guard mede isso, não o assume',
  { skip: dbGated ? false : skipMsg }, async () => {
    // A razão de o predicado pedir DUAS coisas. Se um dia a coluna voltar a discriminar, este
    // teste não falha: ele só documenta, com número vivo, por que o papel entrou na conta.
    const { data, error } = await sb().from('selection_committee').select('role, can_interview');
    assert.ifError(error);
    const total = (data ?? []).length;
    const comFlag = (data ?? []).filter((r) => r.can_interview).length;
    const observadoresComFlag = (data ?? []).filter((r) => r.can_interview && r.role === 'observer').length;
    assert.ok(total > 0, 'sem comitê não há o que medir');
    if (comFlag === total && observadoresComFlag > 0) {
      console.warn(`[#2012] can_interview está true em ${comFlag}/${total} linhas do comitê, ` +
        `${observadoresComFlag} delas de observador: a coluna é rótulo, não autoridade. ` +
        'É por isso que o portão pede também o papel.');
    }
    assert.ok(comFlag <= total);
  });
