/**
 * Hook que responde a caixa de confirmação do Supabase para apply_migration (#2477, #2830, #2834).
 *
 * Desde a 0.13.0 do servidor MCP do Supabase, SQL que o classificador deles chama de destrutivo (DROP,
 * DELETE, TRUNCATE, remoção de coluna, UPDATE sem WHERE) pede confirmação ao cliente. Decisão do GP,
 * 06/10/2026: a sessão orquestradora responde essa caixa, menos quando a migration apaga dado; aí a caixa
 * fica para uma pessoa.
 *
 * #2830: até 29/10/2026 este guard montava o evento com tool_name e tool_use_id, que a entrada documentada
 * do evento Elicitation não traz. O evento padrão aqui é o DOCUMENTADO.
 *
 * #2834: a correção da #2830 procurava a chamada pendente no transcript, e este guard montava o transcript já
 * com ela. Medido em 29/10/2026: o Claude Code só grava a chamada no transcript DEPOIS que ela termina, e a
 * caixa abre DURANTE a chamada. Agora o SQL vem do registro que o db-write-gate.py deixa no PreToolUse, e este
 * guard roda OS DOIS hooks em sequência, com o transcript SEM a chamada pendente, que é o estado real.
 *
 * O QUE ESTE GUARD AFIRMA, rodando os hooks de verdade (python3) com arquivos temporários:
 *   A. aceita só com tudo junto: servidor supabase, caixa de formulário sem campo, este projeto, sessão
 *      orquestradora, UMA chamada registrada no PreToolUse que ainda não está no transcript, e migration que
 *      não apaga dado fora de função; com tool_use_id no evento, aceita a chamada registrada com esse id;
 *   B. qualquer condição faltando, ele não responde (a caixa aparece): sem registro, só registros de chamadas
 *      que já terminaram, dois pendentes, registro vencido, transcript ilegível, modo diferente de form...;
 *      e o PreToolUse só registra apply_migration da orquestradora neste projeto, e NEGA a chamada quando não
 *      consegue registrar;
 *   C. migration que apaga dado no nível de cima, ou num bloco DO, fica para a pessoa;
 *   D. nunca sai com código diferente de 0 (o código 2 recusaria a caixa) e registra a decisão, com as
 *      chaves do evento e o começo da mensagem;
 *   E. está registrado no .claude/settings.json, e o portão de escrita no banco continua antes da chamada.
 *
 * Hermético: python3 e arquivos temporários; sem banco e sem rede (DB_GATE_SKIP_QUEUE=1).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ROOT = process.cwd();
const HOOK = join(ROOT, '.claude/hooks/supabase-confirm-gate.py');
const GATE = join(ROOT, '.claude/hooks/db-write-gate.py');
const base = mkdtempSync(join(tmpdir(), 'supabase-confirm-gate-'));
const ORQ = 'orq-0000-1111';
const orqFile = join(base, 'orquestrador');
writeFileSync(orqFile, `${ORQ}\t2026-10-06T18:00Z\tteste\n`);
const logFile = join(base, 'gate.log');

const MIGRATIONS = {
  toolu_ok: [
    'DROP TRIGGER IF EXISTS t ON public.x;',
    'CREATE OR REPLACE FUNCTION public.f() RETURNS void LANGUAGE plpgsql AS $function$',
    'BEGIN DELETE FROM public.x WHERE a = 1; END; $function$;',
    "COMMENT ON FUNCTION public.f() IS 'nunca DELETE FROM x; TRUNCATE y';",
    'UPDATE public.x SET y = 1 WHERE z = 2;',
    'ALTER TABLE public.x DROP CONSTRAINT c;',
  ].join('\n'),
  toolu_delete: 'DELETE FROM public.x WHERE id = 1;',
  toolu_truncate: 'TRUNCATE public.x;',
  toolu_drop_table: 'DROP TABLE IF EXISTS public.x;',
  toolu_drop_column: 'ALTER TABLE public.x DROP COLUMN y;',
  toolu_update_all: 'UPDATE public.x SET y = 1;',
  toolu_do_delete: 'DO $$ BEGIN IF true THEN DELETE FROM public.x; END IF; END $$;',
  toolu_do_execute: "DO $$ BEGIN EXECUTE 'DROP TABLE public.x'; END $$;",
};
const sqlOf = (id) => MIGRATIONS[id.replace(/^old_/, '')] ?? 'SELECT 1;';

let n = 0;
const fresh = (prefix) => join(base, `${prefix}-${n++}`);

// PreToolUse do db-write-gate.py de verdade: roda ANTES da chamada e deixa o registro dela.
function preToolUse(state, id, { session = ORQ, tool = 'mcp__supabase__apply_migration', input } = {}) {
  const ev = {
    session_id: session, transcript_path: join(base, 'qualquer.jsonl'), cwd: base,
    hook_event_name: 'PreToolUse', tool_name: tool,
    tool_input: input ?? { name: `m_${id}`, query: sqlOf(id) }, tool_use_id: id,
  };
  const r = spawnSync('python3', [GATE], {
    input: JSON.stringify(ev),
    env: { ...process.env, LANE_ORCH_FILE: orqFile, DB_GATE_SKIP_QUEUE: '1', SUPABASE_CONFIRM_GATE_STATE: state },
    encoding: 'utf8',
  });
  const out = (r.stdout || '').trim();
  return { code: r.status, decision: out ? JSON.parse(out).hookSpecificOutput : null };
}

// Linhas no formato do transcript do Claude Code, que só existem para chamadas que JÁ terminaram.
const useLine = (id, name = 'mcp__supabase__apply_migration') => JSON.stringify({
  type: 'assistant',
  message: { role: 'assistant', content: [{ type: 'tool_use', id, name, input: { name: `m_${id}`, query: sqlOf(id) } }] },
});
const resultLine = (id) => JSON.stringify({
  type: 'user',
  message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: id, content: 'ok' }] },
});

// Chamadas antigas da sessão, já terminadas, inclusive as que apagavam dado.
const ANTIGAS = Object.keys(MIGRATIONS).filter((k) => k !== 'toolu_ok').map((k) => `old_${k}`);

// A caixa como ela chega de verdade: as terminadas foram registradas E estão no transcript; as pendentes
// foram registradas e NÃO estão no transcript.
function cenario({ pendentes = ['toolu_ok'], terminadas = ANTIGAS } = {}) {
  const state = fresh('state');
  const linhas = [];
  for (const id of terminadas) {
    preToolUse(state, id);
    linhas.push(useLine(id), resultLine(id));
  }
  for (const id of pendentes) preToolUse(state, id);
  const transcript = `${fresh('transcript')}.jsonl`;
  writeFileSync(transcript, linhas.join('\n') + '\n');
  return { state, transcript };
}

const MSG = 'This SQL includes destructive operations (DROP, DELETE, TRUNCATE or UPDATE without WHERE).\n'
  + 'It may permanently remove data, tables, schemas or other objects.\n'
  + 'Apply the migration to project ldrfrvwhxsmgaabwmaik?';

// Entrada documentada do evento Elicitation: campos comuns + mcp_server_name, message, mode,
// elicitation_id, requested_schema. Sem tool_name e sem tool_use_id.
function event(sc, over = {}) {
  return {
    session_id: ORQ,
    transcript_path: sc.transcript,
    cwd: ROOT,
    hook_event_name: 'Elicitation',
    mcp_server_name: 'supabase',
    message: MSG,
    mode: 'form',
    elicitation_id: 'el-1',
    requested_schema: { type: 'object', properties: {} },
    ...over,
  };
}

function run(input, state, env = {}) {
  const r = spawnSync('python3', [HOOK], {
    input: typeof input === 'string' ? input : JSON.stringify(input),
    env: { ...process.env, LANE_ORCH_FILE: orqFile, SUPABASE_CONFIRM_GATE_LOG: logFile, SUPABASE_CONFIRM_GATE_STATE: state, ...env },
    encoding: 'utf8',
  });
  return { code: r.status, out: (r.stdout || '').trim() };
}

const ACCEPT = { hookSpecificOutput: { hookEventName: 'Elicitation', action: 'accept', content: {} } };
const caixa = (sc, over) => run(event(sc, over), sc.state);
// Cada caixa respondida grava uma linha; a última diz POR QUE ele não respondeu, para o caso não passar por
// outro motivo.
const ultimoLog = () => JSON.parse(readFileSync(logFile, 'utf8').trim().split('\n').at(-1));

test('A: aceita a chamada registrada no PreToolUse que ainda não está no transcript', () => {
  const sc = cenario();
  assert.equal(readFileSync(sc.transcript, 'utf8').includes('"toolu_ok"'), false, 'a pendente não está no transcript');
  const r = caixa(sc);
  assert.equal(r.code, 0);
  assert.deepEqual(JSON.parse(r.out), ACCEPT, 'evento documentado, sem tool_name nem tool_use_id');
  const semModo = event(sc);
  delete semModo.mode;
  assert.deepEqual(JSON.parse(run(semModo, sc.state).out), ACCEPT, 'mode ausente vale como form');
  // A cópia de usuário do portão roda no mesmo evento: a mesma chamada registrada duas vezes é uma só.
  preToolUse(sc.state, 'toolu_ok');
  assert.deepEqual(JSON.parse(caixa(sc).out), ACCEPT, 'a mesma chamada registrada duas vezes conta uma vez');
});

test('A: o registro tem o SQL da chamada, fica só para o dono e não muda a decisão do portão', () => {
  const state = fresh('state');
  const r = preToolUse(state, 'toolu_ok');
  assert.equal(r.code, 0);
  assert.equal(r.decision, null, 'orquestradora com a fila livre: o portão continua sem se manifestar');
  const file = join(state, `${ORQ}.jsonl`);
  const recs = readFileSync(file, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  assert.equal(recs.length, 1);
  assert.equal(recs[0].tool_use_id, 'toolu_ok');
  assert.equal(recs[0].name, 'm_toolu_ok');
  assert.equal(recs[0].query, MIGRATIONS.toolu_ok);
  assert.ok(recs[0].keys.includes('tool_input'), 'guarda as chaves do evento PreToolUse');
  assert.equal(statSync(file).mode & 0o077, 0, 'arquivo sem acesso de grupo nem de outros');
});

test('A: com tool_use_id no evento, aceita a chamada registrada com esse id', () => {
  const sc = cenario({ pendentes: ['toolu_ok', 'toolu_delete'] });
  for (const tool_name of ['mcp__supabase__apply_migration', 'apply_migration']) {
    const r = caixa(sc, { tool_name, tool_use_id: 'toolu_ok' });
    assert.equal(r.code, 0);
    assert.deepEqual(JSON.parse(r.out), ACCEPT, `aceita com tool_name=${tool_name}`);
  }
});

test('B: qualquer condição faltando, a caixa fica para a pessoa', () => {
  const sc = cenario();
  const vencido = fresh('state');
  mkdirSync(vencido);
  writeFileSync(join(vencido, `${ORQ}.jsonl`), JSON.stringify({
    ts: Date.now() / 1000 - 31 * 60, tool_use_id: 'toolu_ok', name: 'm_toolu_ok', query: MIGRATIONS.toolu_ok,
  }) + '\n');
  const casos = {
    'sessão que não é a orquestradora': [sc, { session_id: 'outra-sessao' }, /not the designated orchestrator/],
    'evento que nomeia execute_sql': [sc, { tool_name: 'mcp__supabase__execute_sql' }, /tool is not apply_migration/],
    'outro servidor': [sc, { mcp_server_name: 'outro' }, /server is not supabase/],
    'outro projeto': [sc, { message: MSG.replace('ldrfrvwhxsmgaabwmaik', 'outroprojeto') }, /does not name this project/],
    'caixa pedindo campo': [sc, { requested_schema: { type: 'object', properties: { motivo: { type: 'string' } }, required: ['motivo'] } }, /asks for fields/],
    'caixa de URL': [sc, { mode: 'url', url: 'https://example.invalid/auth' }, /not a form/],
    'tool_use_id sem registro': [sc, { tool_use_id: 'toolu_inexistente' }, /no record for the tool_use_id/],
    'nada registrado': [{ state: fresh('state'), transcript: sc.transcript }, {}, /no apply_migration recorded/],
    'só chamadas que já terminaram': [cenario({ pendentes: [], terminadas: [...ANTIGAS, 'toolu_ok'] }), {}, /^0 pending/],
    'duas pendentes': [cenario({ pendentes: ['toolu_delete', 'toolu_ok'] }), {}, /^2 pending/],
    'registro vencido': [{ state: vencido, transcript: sc.transcript }, {}, /^0 pending/],
    'transcript que não existe': [sc, { transcript_path: join(base, 'nao-existe.jsonl') }, /transcript not readable/],
    'outro evento': [sc, { hook_event_name: 'PreToolUse' }, /not an Elicitation event/],
  };
  for (const [nome, [cen, over, motivo]] of Object.entries(casos)) {
    const r = run(event(cen, over), cen.state);
    assert.equal(r.code, 0, nome);
    assert.equal(r.out, '', `${nome}: não pode responder`);
    assert.match(ultimoLog().reason, motivo, `${nome}: pelo motivo certo`);
  }
  const semOrq = run(event(sc), sc.state, { LANE_ORCH_FILE: join(base, 'nao-existe') });
  assert.equal(semOrq.out, '', 'sem orquestradora designada, ninguém responde');
  assert.match(ultimoLog().reason, /not the designated orchestrator/, 'sem orquestradora: pelo motivo certo');
});

test('B: o PreToolUse só registra apply_migration da orquestradora neste projeto', () => {
  const state = fresh('state');
  const lane = preToolUse(state, 'toolu_lane', { session: 'lane-2222' });
  assert.equal(lane.decision?.permissionDecision, 'deny', 'sessão que não é a orquestradora continua negada');
  preToolUse(state, 'toolu_sql', { tool: 'mcp__supabase__execute_sql', input: { query: 'UPDATE public.x SET y = 1 WHERE z = 2' } });
  preToolUse(state, 'toolu_outro', {
    tool: 'mcp__claude_ai_Supabase__apply_migration',
    input: { project_id: 'outroprojeto', name: 'm', query: 'SELECT 1;' },
  });
  assert.equal(existsSync(join(state, 'lane-2222.jsonl')), false, 'a lane não deixa registro');
  assert.equal(existsSync(join(state, `${ORQ}.jsonl`)), false, 'execute_sql e outro projeto não deixam registro');
});

test('B: sem conseguir registrar, o PreToolUse nega a chamada', () => {
  const arquivo = fresh('arquivo');
  writeFileSync(arquivo, 'não é diretório');
  const r = preToolUse(join(arquivo, 'state'), 'toolu_ok');
  assert.equal(r.code, 0);
  assert.equal(r.decision?.permissionDecision, 'deny', 'registro impossível nega o apply_migration');
  assert.match(r.decision.permissionDecisionReason, /REGISTRAR/);
});

test('C: migration que apaga dado fica para a pessoa', () => {
  for (const id of Object.keys(MIGRATIONS).filter((k) => k !== 'toolu_ok')) {
    const sc = cenario({ pendentes: [id] });
    const r = caixa(sc);
    assert.equal(r.code, 0, id);
    assert.equal(r.out, '', `${id}: apaga dado, não pode responder`);
    const l = ultimoLog();
    assert.equal(l.migration, `m_${id}`, `${id}: achou a migration pendente`);
    assert.match(l.reason, /deletes data/, `${id}: recusou porque apaga dado`);
  }
});

test('D: nunca sai com código diferente de 0 e registra a decisão', () => {
  const state = fresh('state');
  for (const lixo of ['', 'não é json', '[1,2]', '{"hook_event_name": 7}']) {
    const r = run(lixo, state);
    assert.equal(r.code, 0, `entrada ${JSON.stringify(lixo)}`);
    assert.equal(r.out, '');
  }
  caixa(cenario());
  caixa(cenario({ pendentes: ['toolu_delete'] }));
  const linhas = readFileSync(logFile, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  const aceite = linhas.find((l) => l.decision === 'accept' && l.migration === 'm_toolu_ok');
  assert.ok(aceite, 'registra o aceite');
  assert.ok(linhas.some((l) => l.decision === 'ask' && l.migration === 'm_toolu_delete' && /deletes data/.test(l.reason)), 'registra a recusa com o motivo');
  assert.ok(Array.isArray(aceite.keys) && aceite.keys.includes('mcp_server_name') && aceite.keys.includes('message'), 'registra as chaves do evento');
  assert.match(aceite.message_start, /^This SQL includes destructive operations/, 'registra o começo da mensagem');
});

test('E: registrado no settings, com o portão de escrita antes da chamada', () => {
  assert.ok(existsSync(HOOK), 'o script existe');
  const hooks = JSON.parse(readFileSync(join(ROOT, '.claude/settings.json'), 'utf8')).hooks;
  const el = hooks.Elicitation || [];
  assert.equal(el.length, 1, 'uma entrada de Elicitation');
  assert.equal(el[0].matcher, 'supabase', 'só o servidor supabase');
  assert.match(el[0].hooks[0].command, /\.claude\/hooks\/supabase-confirm-gate\.py/);
  const gate = (hooks.PreToolUse || []).find((e) => /apply_migration/.test(e.matcher || ''));
  assert.ok(gate && /db-write-gate\.py/.test(gate.hooks[0].command), 'o portão que deixa o registro roda antes da chamada');
});
