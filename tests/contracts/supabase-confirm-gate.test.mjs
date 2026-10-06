/**
 * Hook que responde a caixa de confirmação do Supabase para apply_migration (#2477).
 *
 * Desde a 0.13.0 do servidor MCP do Supabase, SQL que o classificador deles chama de destrutivo (DROP,
 * DELETE, TRUNCATE, remoção de coluna, UPDATE sem WHERE) pede confirmação ao cliente. Decisão do GP,
 * 06/10/2026: a sessão orquestradora responde essa caixa, menos quando a migration apaga dado; aí a caixa
 * fica para uma pessoa.
 *
 * O QUE ESTE GUARD AFIRMA, rodando o hook de verdade (python3) com um transcript sintético:
 *   A. aceita só com tudo junto: servidor supabase, apply_migration, este projeto, caixa sem campo,
 *      sessão orquestradora e migration que não apaga dado fora de função;
 *   B. qualquer condição faltando, ele não responde (a caixa aparece);
 *   C. migration que apaga dado no nível de cima, ou num bloco DO, fica para a pessoa;
 *   D. nunca sai com código diferente de 0 (o código 2 recusaria a caixa) e registra a decisão;
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

const transcript = join(base, 'transcript.jsonl');
writeFileSync(
  transcript,
  Object.entries(MIGRATIONS)
    .map(([id, query]) => JSON.stringify({
      type: 'assistant',
      message: { role: 'assistant', content: [{ type: 'tool_use', id, name: 'mcp__supabase__apply_migration', input: { name: `m_${id}`, query } }] },
    }))
    .join('\n') + '\n',
);

const MSG = 'This SQL includes destructive operations (DROP, DELETE, TRUNCATE or UPDATE without WHERE).\n'
  + 'It may permanently remove data, tables, schemas or other objects.\n'
  + 'Apply the migration to project ldrfrvwhxsmgaabwmaik?';

function event(over = {}) {
  return {
    session_id: ORQ,
    transcript_path: transcript,
    cwd: ROOT,
    hook_event_name: 'Elicitation',
    mcp_server_name: 'supabase',
    tool_name: 'mcp__supabase__apply_migration',
    tool_use_id: 'toolu_ok',
    message: MSG,
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

test('A: aceita com todas as condições juntas', () => {
  for (const tool_name of ['mcp__supabase__apply_migration', 'apply_migration']) {
    const r = run(event({ tool_name }));
    assert.equal(r.code, 0);
    assert.deepEqual(JSON.parse(r.out), ACCEPT, `aceita com tool_name=${tool_name}`);
  }
});

test('B: qualquer condição faltando, a caixa fica para a pessoa', () => {
  const casos = {
    'sessão que não é a orquestradora': { session_id: 'outra-sessao' },
    'execute_sql': { tool_name: 'mcp__supabase__execute_sql' },
    'outro servidor': { mcp_server_name: 'outro' },
    'outro projeto': { message: MSG.replace('ldrfrvwhxsmgaabwmaik', 'outroprojeto') },
    'caixa pedindo campo': { requested_schema: { type: 'object', properties: { motivo: { type: 'string' } }, required: ['motivo'] } },
    'chamada fora do transcript': { tool_use_id: 'toolu_inexistente' },
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
    const r = run(event({ tool_use_id: id }));
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
  run(event({ tool_use_id: 'toolu_delete' }));
  const linhas = readFileSync(logFile, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  assert.ok(linhas.some((l) => l.decision === 'accept' && l.migration === 'm_toolu_ok'), 'registra o aceite');
  assert.ok(linhas.some((l) => l.decision === 'ask' && /apaga|deletes data/.test(l.reason)), 'registra a recusa com o motivo');
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
