/**
 * Hook que responde a caixa de confirmação do Supabase para apply_migration (#2477, #2830).
 *
 * Desde a 0.13.0 do servidor MCP do Supabase, SQL que o classificador deles chama de destrutivo (DROP,
 * DELETE, TRUNCATE, remoção de coluna, UPDATE sem WHERE) pede confirmação ao cliente. Decisão do GP,
 * 06/10/2026: a sessão orquestradora responde essa caixa, menos quando a migration apaga dado; aí a caixa
 * fica para uma pessoa.
 *
 * #2830: até 29/10/2026 este guard montava o evento com tool_name e tool_use_id, que a entrada documentada
 * do evento Elicitation não traz (code.claude.com/docs/en/hooks, "Elicitation input"). O guard ficava verde
 * e o hook nunca aceitou de verdade: 55 de 55 decisões no log eram "tool is not apply_migration". O evento
 * padrão aqui é o DOCUMENTADO; o formato com tool_name/tool_use_id fica só como compatibilidade.
 *
 * O QUE ESTE GUARD AFIRMA, rodando o hook de verdade (python3) com transcripts sintéticos:
 *   A. aceita só com tudo junto: servidor supabase, caixa de formulário sem campo, este projeto, sessão
 *      orquestradora, UMA chamada apply_migration pendente no transcript e migration que não apaga dado
 *      fora de função; com tool_name/tool_use_id no evento, também aceita;
 *   B. qualquer condição faltando, ele não responde (a caixa aparece), inclusive sem chamada pendente,
 *      com duas pendentes, com a pendente sendo execute_sql e com modo diferente de form;
 *   C. migration que apaga dado no nível de cima, ou num bloco DO, fica para a pessoa;
 *   D. nunca sai com código diferente de 0 (o código 2 recusaria a caixa) e registra a decisão, com as
 *      chaves do evento e o começo da mensagem;
 *   E. está registrado no .claude/settings.json, e o portão de escrita no banco continua lá.
 *
 * Hermético: python3 e arquivos temporários; sem banco e sem rede.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ROOT = process.cwd();
const HOOK = join(ROOT, '.claude/hooks/supabase-confirm-gate.py');
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

// Linhas no formato do transcript do Claude Code: a chamada é uma tool_use numa mensagem do assistente e a
// resposta é uma tool_result numa mensagem do usuário, ligadas pelo id.
const useLine = (id, name = 'mcp__supabase__apply_migration') => JSON.stringify({
  type: 'assistant',
  message: { role: 'assistant', content: [{ type: 'tool_use', id, name, input: { name: `m_${id}`, query: MIGRATIONS[id.replace(/^old_/, '')] ?? 'SELECT 1;' } }] },
});
const resultLine = (id) => JSON.stringify({
  type: 'user',
  message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: id, content: 'ok' }] },
});

let n = 0;
function transcriptWith(lines) {
  const path = join(base, `transcript-${n++}.jsonl`);
  writeFileSync(path, lines.join('\n') + '\n');
  return path;
}

// Histórico com chamadas antigas já respondidas, inclusive uma que apagava dado, e a chamada pendente no fim.
const respondidas = Object.keys(MIGRATIONS).filter((k) => k !== 'toolu_ok').flatMap((id) => [useLine(`old_${id}`), resultLine(`old_${id}`)]);
const pendente = (id) => transcriptWith([...respondidas, useLine(id)]);
const T_OK = pendente('toolu_ok');

const MSG = 'This SQL includes destructive operations (DROP, DELETE, TRUNCATE or UPDATE without WHERE).\n'
  + 'It may permanently remove data, tables, schemas or other objects.\n'
  + 'Apply the migration to project ldrfrvwhxsmgaabwmaik?';

// Entrada documentada do evento Elicitation: campos comuns + mcp_server_name, message, mode,
// elicitation_id, requested_schema. Sem tool_name e sem tool_use_id.
function event(over = {}) {
  return {
    session_id: ORQ,
    transcript_path: T_OK,
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

function run(input) {
  const r = spawnSync('python3', [HOOK], {
    input: typeof input === 'string' ? input : JSON.stringify(input),
    env: { ...process.env, LANE_ORCH_FILE: orqFile, SUPABASE_CONFIRM_GATE_LOG: logFile },
    encoding: 'utf8',
  });
  return { code: r.status, out: (r.stdout || '').trim() };
}

const ACCEPT = { hookSpecificOutput: { hookEventName: 'Elicitation', action: 'accept', content: {} } };

test('A: aceita com o evento documentado e uma chamada pendente', () => {
  const r = run(event());
  assert.equal(r.code, 0);
  assert.deepEqual(JSON.parse(r.out), ACCEPT, 'evento documentado, sem tool_name nem tool_use_id');
  const semModo = event();
  delete semModo.mode;
  assert.deepEqual(JSON.parse(run(semModo).out), ACCEPT, 'mode ausente vale como form');
});

test('A: com tool_name e tool_use_id no evento, também aceita', () => {
  const t = transcriptWith([useLine('toolu_ok'), resultLine('toolu_ok')]);
  for (const tool_name of ['mcp__supabase__apply_migration', 'apply_migration']) {
    const r = run(event({ transcript_path: t, tool_name, tool_use_id: 'toolu_ok' }));
    assert.equal(r.code, 0);
    assert.deepEqual(JSON.parse(r.out), ACCEPT, `aceita com tool_name=${tool_name}`);
  }
});

test('B: qualquer condição faltando, a caixa fica para a pessoa', () => {
  const casos = {
    'sessão que não é a orquestradora': { session_id: 'outra-sessao' },
    'evento que nomeia execute_sql': { tool_name: 'mcp__supabase__execute_sql' },
    'outro servidor': { mcp_server_name: 'outro' },
    'outro projeto': { message: MSG.replace('ldrfrvwhxsmgaabwmaik', 'outroprojeto') },
    'caixa pedindo campo': { requested_schema: { type: 'object', properties: { motivo: { type: 'string' } }, required: ['motivo'] } },
    'caixa de URL': { mode: 'url', url: 'https://example.invalid/auth' },
    'tool_use_id fora do transcript': { tool_use_id: 'toolu_inexistente' },
    'nenhuma chamada pendente': { transcript_path: transcriptWith([...respondidas, useLine('toolu_ok'), resultLine('toolu_ok')]) },
    'duas chamadas pendentes': { transcript_path: transcriptWith([...respondidas, useLine('toolu_delete'), useLine('toolu_ok')]) },
    'a pendente é execute_sql': { transcript_path: transcriptWith([...respondidas, useLine('toolu_ok'), resultLine('toolu_ok'), useLine('toolu_x', 'mcp__supabase__execute_sql')]) },
    'transcript que não existe': { transcript_path: join(base, 'nao-existe.jsonl') },
    'outro evento': { hook_event_name: 'PreToolUse' },
  };
  for (const [nome, over] of Object.entries(casos)) {
    const r = run(event(over));
    assert.equal(r.code, 0, nome);
    assert.equal(r.out, '', `${nome}: não pode responder`);
  }
  const semOrq = spawnSync('python3', [HOOK], {
    input: JSON.stringify(event()),
    env: { ...process.env, LANE_ORCH_FILE: join(base, 'nao-existe'), SUPABASE_CONFIRM_GATE_LOG: logFile },
    encoding: 'utf8',
  });
  assert.equal(semOrq.stdout.trim(), '', 'sem orquestradora designada, ninguém responde');
});

test('C: migration que apaga dado fica para a pessoa', () => {
  for (const id of Object.keys(MIGRATIONS).filter((k) => k !== 'toolu_ok')) {
    const r = run(event({ transcript_path: pendente(id) }));
    assert.equal(r.code, 0, id);
    assert.equal(r.out, '', `${id}: apaga dado, não pode responder`);
  }
});

test('D: nunca sai com código diferente de 0 e registra a decisão', () => {
  for (const lixo of ['', 'não é json', '[1,2]', '{"hook_event_name": 7}']) {
    const r = run(lixo);
    assert.equal(r.code, 0, `entrada ${JSON.stringify(lixo)}`);
    assert.equal(r.out, '');
  }
  run(event());
  run(event({ transcript_path: pendente('toolu_delete') }));
  const linhas = readFileSync(logFile, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  const aceite = linhas.find((l) => l.decision === 'accept' && l.migration === 'm_toolu_ok');
  assert.ok(aceite, 'registra o aceite');
  assert.ok(linhas.some((l) => l.decision === 'ask' && l.migration === 'm_toolu_delete' && /deletes data/.test(l.reason)), 'registra a recusa com o motivo');
  assert.ok(Array.isArray(aceite.keys) && aceite.keys.includes('mcp_server_name') && aceite.keys.includes('message'), 'registra as chaves do evento');
  assert.match(aceite.message_start, /^This SQL includes destructive operations/, 'registra o começo da mensagem');
});

test('E: registrado no settings, sem tirar o portão de escrita no banco', () => {
  assert.ok(existsSync(HOOK), 'o script existe');
  const hooks = JSON.parse(readFileSync(join(ROOT, '.claude/settings.json'), 'utf8')).hooks;
  const el = hooks.Elicitation || [];
  assert.equal(el.length, 1, 'uma entrada de Elicitation');
  assert.equal(el[0].matcher, 'supabase', 'só o servidor supabase');
  assert.match(el[0].hooks[0].command, /\.claude\/hooks\/supabase-confirm-gate\.py/);
  const gate = (hooks.PreToolUse || []).find((e) => /apply_migration/.test(e.matcher || ''));
  assert.ok(gate && /db-write-gate\.py/.test(gate.hooks[0].command), 'o portão de escrita continua antes da chamada');
});
