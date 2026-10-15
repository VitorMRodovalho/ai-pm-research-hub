/**
 * #2704 — o front não pode dizer "ok" quando a RPC recusou NO CORPO.
 *
 * Funções que gravam e devolvem `{error}`/`{success:false}` com HTTP 200: o supabase-js só preenche
 * `error` em falha de transporte, então a tela que testa só `error` mostra sucesso numa recusa.
 * A #2699 achou três telas assim; esta varredura cobre o front inteiro.
 *
 * Regra: toda chamada a uma dessas funções passa por `rpcChecked`, ou lê o erro do corpo amarrado
 * à variável que recebeu o resultado. A lista de exceções está vazia desde a PR-B e só diminui:
 * chamada nova fora da regra reprova, e exceção que deixou de ser necessária também.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { bodyErrorWriters, scanUncheckedCalls, readsBodyError } from '../helpers/rpc-body-error-scan.mjs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();

// Zerada na PR-B da #2704. Exceção nova precisa de motivo escrito ao lado; uma linha por chamada,
// `arquivo|função#ordem`. A lista só diminui.
const EXCECOES = [];

const TARGETS = bodyErrorWriters(ROOT);

test('#2704 a classificação enxerga as funções que gravam e recusam no corpo', () => {
  // Controle contra vacuidade: se o parser de migrations quebrar, o conjunto esvazia e tudo passa.
  assert.ok(TARGETS.size >= 100, `só ${TARGETS.size} funções classificadas`);
  for (const fn of ['admin_resolve_anomaly', 'delete_partner_attachment', 'mark_interview_status', 'confirm_agenda_block']) {
    assert.ok(TARGETS.has(fn), `${fn} grava e devolve {error}; a classificação perdeu`);
  }
});

test('#2704 nenhuma chamada nova ignora a recusa do corpo, e a lista de exceções só diminui', () => {
  const { offenders, checked } = scanUncheckedCalls(ROOT, TARGETS);
  assert.ok(checked >= 50, `só ${checked} chamadas conformes achadas: a varredura parou de ver o front`);
  const novos = offenders.filter((o) => !EXCECOES.includes(o));
  assert.deepEqual(novos, [],
    'chamada a RPC que recusa no corpo sem ler o erro: use rpcChecked (src/lib/rpc-checked.ts) ou leia data?.error');
  const vencidas = EXCECOES.filter((e) => !offenders.includes(e));
  assert.deepEqual(vencidas, [], 'estas exceções já não são necessárias: tire-as da lista');
});

test('#2704 controle: a varredura reprova `if (error)` sozinho e aprova a leitura amarrada', () => {
  const dir = mkdtempSync(join(tmpdir(), 'g2704-'));
  mkdirSync(join(dir, 'src'));
  mkdirSync(join(dir, 'supabase/migrations'), { recursive: true });
  writeFileSync(join(dir, 'supabase/migrations/20990101000000_x.sql'),
    "CREATE OR REPLACE FUNCTION public.f_alvo(p uuid) RETURNS jsonb LANGUAGE plpgsql AS $$\n" +
    "BEGIN IF p IS NULL THEN RETURN jsonb_build_object('error','x'); END IF;\n" +
    "UPDATE public.t SET a = 1 WHERE id = p; RETURN jsonb_build_object('success', true); END $$;\n" +
    "CREATE OR REPLACE FUNCTION public.f_leitura(p uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('error','x') $$;\n");
  writeFileSync(join(dir, 'src/a.ts'), [
    "async function ruim(sb) { const { error } = await sb.rpc('f_alvo', { p: 1 }); if (error) return; ok(); }",
    "async function boa(sb) { const { data, error } = await sb.rpc('f_alvo', { p: 1 }); if (error || data?.error) return; }",
    "async function outra(sb) { const { data: d } = await sb.rpc('f_alvo', {}); if (data?.error) return; }",
    "async function res(sb) { const r = await sb.rpc('f_alvo', {}); if (r.error || r.data?.error) return; }",
    "async function leitura(sb) { const { error } = await sb.rpc('f_leitura', {}); }",
    "async function log(sb) { const { data, error } = await sb.rpc('f_alvo', {}); if (error) console.error(data?.error); ok(); }",
  ].join('\n'));
  const t = bodyErrorWriters(dir);
  assert.deepEqual([...t], ['f_alvo'], 'só a função que GRAVA e recusa no corpo é alvo');
  const { offenders, checked } = scanUncheckedCalls(dir, t);
  // `outra` lê `data`, mas o resultado está em `d`: a leitura tem de ser da MESMA variável.
  // `log` lê `data?.error` só dentro da mensagem: não decide nada, então não conta.
  assert.deepEqual(offenders, ['src/a.ts|f_alvo#1', 'src/a.ts|f_alvo#3', 'src/a.ts|f_alvo#5']);
  assert.equal(checked, 2);
});

test('#2704 rpcChecked lança na recusa do corpo e na falha de rede', async () => {
  const { rpcChecked, rpcBodyError } = await import('../../src/lib/rpc-checked.ts');
  const sb = (resp) => ({ rpc: async () => resp });
  assert.deepEqual(await rpcChecked(sb({ data: { success: true, n: 1 }, error: null }), 'f'), { success: true, n: 1 });
  await assert.rejects(rpcChecked(sb({ data: { error: 'access_denied' }, error: null }), 'f'), /access_denied/);
  await assert.rejects(rpcChecked(sb({ data: { success: false, reason: 'gone' }, error: null }), 'f'), /gone/);
  await assert.rejects(rpcChecked(sb({ data: { ok: false }, error: null }), 'f'), /action_failed/);
  await assert.rejects(rpcChecked(sb({ data: null, error: new Error('net') }), 'f'), /net/);
  assert.equal(rpcBodyError([{ error: 'x' }]), null, 'lista de linhas não é recusa');
  assert.equal(rpcBodyError({ success: true, error: null }), null);
});

test('#2704 parceiros: o registro do anexo sai ANTES do arquivo', () => {
  const src = maskJsComments(readFileSync(join(ROOT, 'src/components/islands/PartnerPipelineIsland.tsx'), 'utf8'));
  assert.match(src,
    /await rpcChecked\(sb, 'delete_partner_attachment', \{ p_attachment_id: att\.id \}\);\s+const \{ error: rmErr \} = await sb\.storage\.from\('partner-attachments'\)\.remove\(\[att\.file_url\]\);/,
    'apagar o arquivo antes da RPC deixa o registro órfão quando ela recusa');
});

test('#2704 controle do leitor: forma de alias `const data = res.data`', () => {
  const src = "const res = await sb.rpc('f', {});\nif (res.error) return;\nconst data = res.data as any;\nif (data?.error) return;";
  assert.equal(readsBodyError(src, src.indexOf('.rpc(')), true);
  const sem = "const res = await sb.rpc('f', {});\nif (res.error) return;\nconst data = res.data as any;\nshow(data);";
  assert.equal(readsBodyError(sem, sem.indexOf('.rpc(')), false);
});

test('#2704 agenda viva: o `run` passa pelo rpcChecked antes do toast de sucesso', () => {
  // A varredura não vê chamada com nome em variável; este wrapper é o caso conhecido.
  const src = maskJsComments(readFileSync(join(ROOT, 'src/components/admin/AdminAgendaVivaPanel.tsx'), 'utf8'));
  assert.match(src,
    /const run = async \(key: string, fn: string, args: Record<string, unknown>, okMsg: string\) => \{[\s\S]{0,120}?try \{\s+await rpcChecked\(sb, fn, args\);\s+toast\(okMsg\);/,
    'o run da Agenda Viva voltou a confiar só no erro de rede');
  const calls = src.match(/run\([^,]+, '(confirm_agenda_block|confirm_event_blocks|revoke_agenda_block_xp|cancel_agenda_block)'/g) || [];
  assert.equal(calls.length, 4, 'as quatro ações da Agenda Viva têm de passar pelo run');
});
