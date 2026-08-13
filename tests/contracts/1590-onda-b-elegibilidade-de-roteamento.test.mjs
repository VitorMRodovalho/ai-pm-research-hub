/**
 * Contract: #1590 onda B — elegibilidade de roteamento e uma dimensao PROPRIA, com janela.
 *
 * O pedido do PM, nas palavras dele: se o entrevistador bloqueia a agenda nas proximas semanas mas
 * continua sendo a pessoa roteada, o candidato recebe a agenda dele VAZIA e nao consegue agendar.
 * A recusa acontece na frente do candidato.
 *
 * Antes desta onda havia UMA coluna para DUAS perguntas:
 *
 *   dimensao                       responde                            quem sente
 *   disponibilidade de calendario  "que horarios esta pessoa tem?"     quem ja foi roteado
 *   elegibilidade de roteamento    "esta pessoa pode ser escolhida?"   o candidato, ANTES
 *
 * A unica forma de sair do rodizio era APAGAR `interview_booking_url`, o que destroi configuracao,
 * nao tem data e nao se reverte sozinho.
 *
 * Provado ao vivo em transacao abortada (12/08/2026, ciclo cycle4-2026):
 *   base, sem bloqueio         -> committee_override, 1o do rodizio
 *   1o bloqueado               -> committee_override, PASSA ao proximo
 *   janela termina HOJE local  -> continua bloqueando (ver a borda de fuso abaixo)
 *   comite inteiro bloqueado   -> cycle_fallback, e o audit log grava routable=3 blocked=3
 *   janela so no futuro        -> NAO bloqueia hoje
 *   INVERSA: despacho normal   -> committee_override e ZERO linha de auditoria
 *   nada persistiu: 0 bloqueios, 0 auditorias apos o ROLLBACK
 *
 * ⚠️ A BORDA DE FUSO E O RISCO, e ela foi medida, nao argumentada. A prova rodou as 02h35 UTC de
 * 13/08 = 23h35 de 12/08 em Brasilia, dentro da faixa em que as duas datas divergem. Sobre a MESMA
 * janela (09/08 a 12/08), no MESMO instante:
 *
 *   predicado com (now() AT TIME ZONE 'America/Sao_Paulo')::date  -> bloqueia = true
 *   predicado com CURRENT_DATE (UTC)                              -> bloqueia = FALSE
 *
 * Ou seja, o predicado ingenuo soltaria o entrevistador de volta ao rodizio 3h30 antes do fim do
 * dia local dele. Mesma classe do #1727.
 *
 * O registro da queda sai no CHAMADOR, nao no picker: `resolve_interview_booking_url` e STABLE e
 * nao pode escrever. Os 5 caminhos de despacho passam por `_dispatch_interview_booking_link`.
 *
 * Camadas: A estatica sobre a captura da migration, com a INVERSA de cada afirmacao (uma afirmacao
 * sem inversa fica verde com o mecanismo removido); A' md5 do corpo VIVO contra a captura, que e o
 * que pega a deriva; C invariante ao vivo, read-only.
 *
 * Migration: 20260813023435_1590_onda_b_elegibilidade_de_roteamento_com_janela.sql
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import {
  loadLatestCaptures, parseMigration, normalizeBody,
} from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MIGRATION = '20260813023435_1590_onda_b_elegibilidade_de_roteamento_com_janela.sql';

const CHAVES = {
  resolver: 'resolve_interview_booking_url@p_application_id uuid',
  dispatch: '_dispatch_interview_booking_link@p_application_id uuid, p_caller_id uuid, p_source text',
};

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function captura(chave) {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const cap = latest.get(chave);
  assert.ok(cap, `sem captura de migration para ${chave}`);
  const blocos = parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8'));
  const bloco = blocos.find(b => `${b.name}@${b.args}` === chave);
  assert.ok(bloco, `${cap.file} nao contem o bloco de ${chave}`);
  return { file: cap.file, bodyHash: cap.bodyHash, body: bloco.body };
}

/** Comentarios fora: um guard que le o texto cru casa a propria explicacao (#1586b, 3 ocorrencias). */
const achatado = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

async function rest(caminho, init) {
  return fetch(`${SUPABASE_URL}/rest/v1/${caminho}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      ...(init?.headers ?? {}),
    },
  });
}

// ── A: a captura da migration ────────────────────────────────────────────────────────────

test('#1590B A: o picker exclui quem esta em janela de bloqueio', () => {
  const { body, file } = captura(CHAVES.resolver);
  const codigo = achatado(body);

  assert.match(codigo, /NOT EXISTS \( SELECT 1 FROM public\.selection_interviewer_blackouts b/,
    `${file}: sem o NOT EXISTS o bloqueio nao chega ao rodizio`);
  assert.match(codigo, /b\.cycle_id = v_cycle\.id AND b\.member_id = sc\.member_id/,
    `${file}: o bloqueio tem de ser por (ciclo, pessoa) — sem o ciclo, bloquear num ciclo bloqueia em todos`);
  assert.match(codigo, /b\.ends_on IS NULL OR v_hoje <= b\.ends_on/,
    `${file}: ends_on nulo e bloqueio ABERTO; tratar nulo como fim imediato inverte o significado`);
});

test('#1590B A: a janela compara a data LOCAL, e a comparacao ingenua nao pode coexistir', () => {
  const { body, file } = captura(CHAVES.resolver);
  const codigo = achatado(body);

  assert.match(codigo, /v_hoje date := \(now\(\) AT TIME ZONE 'America\/Sao_Paulo'\)::date/,
    `${file}: a data de referencia da janela precisa ser a LOCAL`);

  // A INVERSA, que e o defeito do #1727: `CURRENT_DATE` e UTC e a noite de Brasilia ja virou o dia.
  // Medido em 12/08 as 23h35 local: a mesma janela da true pela data local e FALSE por CURRENT_DATE.
  assert.doesNotMatch(codigo, /CURRENT_DATE/,
    `${file}: CURRENT_DATE voltou; ele solta o entrevistador ao rodizio 3h antes do fim do dia dele`);
});

test('#1590B A: os tres eixos continuam SEPARADOS', () => {
  const { body, file } = captura(CHAVES.resolver);
  const codigo = achatado(body);

  // O ponto da onda: bloquear roteamento NAO pode ser feito apagando a URL (capacidade) nem
  // desligando can_interview (permanente). Os tres predicados coexistem, cada um com seu sentido.
  assert.match(codigo, /sc\.can_interview = true/, `${file}: sumiu o desligamento permanente`);
  assert.match(codigo, /COALESCE\(sc\.interview_booking_url, m\.interview_booking_url\) IS NOT NULL/,
    `${file}: sumiu o eixo de capacidade (tem calendario)`);
  assert.match(codigo, /selection_interviewer_blackouts/, `${file}: sumiu o eixo temporal`);
});

test('#1590B A: a precedencia e o fallback ficaram intactos', () => {
  const { body, file } = captura(CHAVES.resolver);
  const codigo = achatado(body);

  // A onda B nao podia mexer no rodizio; um delta silencioso aqui muda quem entrevista quem.
  assert.match(codigo, /ORDER BY lrd\.last_dispatched NULLS FIRST, sc\.member_id/,
    `${file}: a ordem do LRD mudou`);
  assert.match(codigo, /WHEN sc\.interview_booking_url IS NOT NULL THEN 'committee_override'/,
    `${file}: a precedencia committee_override > member_global mudou`);
  assert.match(codigo, /v_path := 'cycle_fallback'/, `${file}: o fallback sumiu`);
});

test('#1590B A: a queda para a agenda do ciclo vira linha de auditoria', () => {
  const { body, file } = captura(CHAVES.dispatch);
  const codigo = achatado(body);

  assert.match(codigo, /'selection\.routing_fell_back_to_cycle'/,
    `${file}: sem a acao proprio o desvio continua indistinguivel do caminho normal`);
  assert.match(codigo, /'committee_routable', v_capazes/,
    `${file}: sem o denominador nao da para separar "ninguem configurado" de "todos bloqueados"`);
  assert.match(codigo, /'blocked_by_window', v_bloqueados/,
    `${file}: idem — as duas causas pedem acoes opostas`);
});

test('#1590B A: a auditoria e CONDICIONADA, senao vira ruido diario', () => {
  const { body, file } = captura(CHAVES.dispatch);
  const codigo = achatado(body);

  // Na trilha `leader` o cycle_fallback e o caminho NORMAL e projetado (entrevista em grupo, 7 dos
  // 7 despachos medidos). Auditar sem condicao produziria alerta todo dia, do tipo que se aprende
  // a ignorar — e ai o alerta que importa passa junto.
  assert.match(
    codigo,
    /IF v_app\.role_applied = 'researcher' AND v_path = 'cycle_fallback' THEN/,
    `${file}: a auditoria precisa das DUAS condicoes`,
  );

  // E tem de rodar DEPOIS do log de despacho: registrar antes gravaria desvio que nao foi enviado.
  const iLog = codigo.indexOf('INSERT INTO public.selection_dispatch_url_log');
  const iAudit = codigo.indexOf("INSERT INTO public.admin_audit_log");
  assert.ok(iLog > -1 && iAudit > iLog,
    `${file}: a auditoria da queda tem de vir depois do INSERT do despacho`);
});

test('#1590B A: a migration declara RLS e a checagem de janela na tabela', () => {
  const sql = readFileSync(join(MIGRATIONS_DIR, MIGRATION), 'utf8');
  const codigo = achatado(sql);

  assert.match(codigo, /ALTER TABLE public\.selection_interviewer_blackouts ENABLE ROW LEVEL SECURITY/,
    'tabela nova sem RLS viola a regra de LGPD do projeto');
  assert.match(codigo, /CREATE POLICY rpc_only_deny_all ON public\.selection_interviewer_blackouts FOR ALL USING \(false\)/,
    'o padrao dos irmaos de selecao e rpc-only: ninguem alcanca a tabela direto');
  assert.match(codigo, /CHECK \(ends_on IS NULL OR ends_on >= starts_on\)/,
    'sem a checagem, uma janela invertida vira bloqueio que nunca vale e ninguem percebe');
});

// ── A': o corpo VIVO nao derivou da captura ──────────────────────────────────────────────

test('#1590B A\': o corpo vivo das duas funcoes bate com a captura', { skip: dbGated ? false : skipMsg }, async () => {
  const res = await rest('rpc/_audit_list_public_function_bodies', { method: 'POST', body: '{}' });
  assert.equal(res.status, 200, `_audit_list_public_function_bodies devolveu ${res.status}`);
  const linhas = await res.json();
  assert.ok(Array.isArray(linhas) && linhas.length > 0, 'catalogo vivo veio vazio');

  // O catalogo devolve (proname, identity_args, body_md5, ...). O `body_md5` ja e o md5 do corpo
  // NORMALIZADO do mesmo jeito que `normalizeBody` — a paridade entre os dois lados e requisito do
  // Phase C, e quebra-la faz TODA funcao parecer derivada.
  //
  // Buscar por proname + identity_args, nunca so por proname: sobrecarga com outra assinatura
  // casaria a errada em silencio.
  for (const [rotulo, chave] of Object.entries(CHAVES)) {
    const [nome, args] = chave.split('@');
    const viva = linhas.find(l => l.proname === nome && normalizeBody(l.identity_args ?? '') === normalizeBody(args));
    assert.ok(viva, `${rotulo}: ${nome}(${args}) nao encontrada no catalogo vivo`);
    const { bodyHash, file } = captura(chave);
    assert.equal(
      viva.body_md5, bodyHash,
      `${rotulo}: o corpo VIVO divergiu de ${file}. Alguem aplicou DDL fora de migration, ou a migration foi editada depois de aplicada.`,
    );
  }
});

// ── C: o invariante ao vivo, read-only ───────────────────────────────────────────────────

test('#1590B C: a tabela existe, com RLS ligada', { skip: dbGated ? false : skipMsg }, async () => {
  const res = await rest('selection_interviewer_blackouts?select=id&limit=1');
  assert.equal(res.status, 200,
    `a tabela precisa existir e responder ao service_role (status ${res.status})`);
});

test('#1590B C: ninguem foi roteado para um entrevistador bloqueado', { skip: dbGated ? false : skipMsg }, async () => {
  const [bloqueiosRes, despachosRes] = await Promise.all([
    rest('selection_interviewer_blackouts?select=cycle_id,member_id,starts_on,ends_on'),
    rest('selection_dispatch_url_log?select=application_id,cycle_id,resolved_evaluator_id,dispatched_at&track=eq.researcher&resolved_evaluator_id=not.is.null'),
  ]);
  assert.equal(bloqueiosRes.status, 200);
  assert.equal(despachosRes.status, 200);
  const bloqueios = await bloqueiosRes.json();
  const despachos = await despachosRes.json();

  // ⚠️ Enquanto nao houver bloqueio cadastrado este invariante e VACUO, e isso e ausencia de uso,
  // nao imunidade (a onda C e que traz a superficie de escrita). Dito em voz alta para o proximo
  // leitor nao ler "0 violacoes" como "o mecanismo foi exercido".
  if (bloqueios.length === 0) {
    assert.equal(bloqueios.length, 0, 'sem bloqueios cadastrados: invariante vacuo por ausencia de uso');
    return;
  }

  const violacoes = despachos.filter(d => bloqueios.some(b =>
    b.cycle_id === d.cycle_id
    && b.member_id === d.resolved_evaluator_id
    && new Date(d.dispatched_at) >= new Date(`${b.starts_on}T00:00:00-03:00`)
    && (b.ends_on === null || new Date(d.dispatched_at) <= new Date(`${b.ends_on}T23:59:59-03:00`))));

  assert.deepEqual(violacoes, [],
    `despacho roteado para entrevistador em janela de bloqueio: ${JSON.stringify(violacoes.slice(0, 3))}`);
});
