/**
 * Contract: #1498 — atividade SEM RESPONSÁVEL só é concluída por quem pertence à iniciativa.
 *
 * O ramo `v_item.assigned_to IS NULL` de `complete_checklist_item` liberava qualquer membro
 * autenticado sem checar escopo algum de board: dava para concluir atividade sem responsável
 * em board de outra tribo. Medido em 2026-07-28, antes do aperto: 207 atividades abertas nessa
 * condição, espalhadas por 12 dos 18 boards.
 *
 * A decisão (ratificada pelo dono em 2026-07-28) foi exigir PERTENCIMENTO À INICIATIVA, e não
 * `write_board`, para preservar o uso legítimo de atividade coletiva do card pelo pesquisador
 * comum. Medido no histórico: das 39 conclusões de atividade sem responsável já ocorridas,
 * 36 foram de quem tinha engagement ativo na iniciativa.
 *
 * NOTA de método (duas, ambas mordem aqui):
 *
 * 1. O SQL é lido COM OS COMENTÁRIOS REMOVIDOS. O cabeçalho da migration cita a expressão
 *    ANTIGA (`... OR v_item.assigned_to IS NULL`) em prosa, mas o extrator começa no
 *    `CREATE OR REPLACE`, então hoje quem alcança as asserções é só comentário DE DENTRO do
 *    corpo — e o corpo tem um, citando o símbolo vigiado. A remoção é o que impede um
 *    comentário futuro de satisfazer o regex no lugar do código vivo; o teste
 *    `o extrator descarta comentário de dentro do corpo` prova o mecanismo, senão esta
 *    defesa seria só declarada.
 *
 * 2. A asserção de null-safety não é decorativa. Com `assigned_to` NULL, a comparação
 *    `v_item.assigned_to = v_caller.id` avalia NULL; sem o `coalesce`, `NULL OR false` = NULL,
 *    e `IF NOT ... THEN RAISE` não dispara com condição NULL. O gate voltaria a liberar
 *    silenciosamente justamente o caso que esta migration fecha.
 *
 * Estático (sempre roda, sem depender de credencial de DB) + defesa prospectiva.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX_MIGRATION = '20260805000492_1498_unassigned_activity_requires_initiative_membership.sql';

/** Remove comentários de linha e de bloco do SQL para que asserções nunca casem com prosa. */
function stripSqlComments(sql) {
  return sql.replace(/\/\*[\s\S]*?\*\//g, '').replace(/--[^\n]*/g, '');
}

/** Extrai o corpo de complete_checklist_item, já sem comentários. */
function rpcBlock(sql) {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.complete_checklist_item\s*\([\s\S]*?\$function\$[\s\S]*?\$function\$/i;
  return stripSqlComments(sql).match(re)?.[0] || '';
}

/** Todas as migrations que redefinem a RPC, em ordem cronológica. */
function capturesInOrder() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((file) => ({ file, block: rpcBlock(readFileSync(resolve(MIGRATIONS_DIR, file), 'utf8')) }))
    .filter((c) => c.block);
}

/** O ramo sem-responsável tem de estar conjugado com o pertencimento. */
const UNASSIGNED_REQUIRES_MEMBERSHIP =
  /v_item\.assigned_to\s+IS\s+NULL\s+AND\s+v_is_initiative_member/i;

// ── A captura vigente ────────────────────────────────────────────────────────

test('1498: a migration do fix existe e redefine a RPC', () => {
  const files = readdirSync(MIGRATIONS_DIR);
  assert.ok(files.includes(FIX_MIGRATION), `${FIX_MIGRATION} deve estar no registro de migrations`);
  assert.ok(rpcBlock(readFileSync(resolve(MIGRATIONS_DIR, FIX_MIGRATION), 'utf8')),
    'a migration do #1498 deve conter o CREATE OR REPLACE de complete_checklist_item');
});

test('1498: o extrator descarta comentario de dentro do corpo', () => {
  // Sem isto, um comentário futuro dentro da função poderia satisfazer os regexes abaixo
  // enquanto o código vivo já teria perdido a conjunção.
  const forjado = [
    'CREATE OR REPLACE FUNCTION public.complete_checklist_item(p_checklist_item_id uuid)',
    'AS $function$',
    'BEGIN',
    '  -- v_item.assigned_to IS NULL AND v_is_initiative_member (removido em refatoracao)',
    '  v_is_activity_owner := true;',
    'END;',
    '$function$',
  ].join('\n');
  assert.doesNotMatch(rpcBlock(forjado), UNASSIGNED_REQUIRES_MEMBERSHIP,
    'a conjunção citada em comentário nao pode contar como codigo vivo');
});

test('1498: atividade sem responsavel exige pertencimento, nao basta estar autenticado', () => {
  const block = rpcBlock(readFileSync(resolve(MIGRATIONS_DIR, FIX_MIGRATION), 'utf8'));
  assert.match(block, UNASSIGNED_REQUIRES_MEMBERSHIP,
    'o ramo assigned_to IS NULL deve estar conjugado com v_is_initiative_member');
  assert.doesNotMatch(block, /v_item\.assigned_to\s*=\s*v_caller\.id\s*OR\s*v_item\.assigned_to\s+IS\s+NULL/i,
    'o ramo IS NULL nao pode voltar a liberar sozinho');
});

test('1498: o pertencimento e escopado a INICIATIVA DO BOARD e a engagement ativo', () => {
  const block = rpcBlock(readFileSync(resolve(MIGRATIONS_DIR, FIX_MIGRATION), 'utf8'));
  const decl = block.match(/v_is_initiative_member\s*:=[\s\S]*?\);/)?.[0] || '';
  assert.ok(decl, 'v_is_initiative_member deve ser derivado no corpo da funcao');

  assert.match(decl, /public\.auth_engagements/i,
    'a fonte deve ser a view auth_engagements, a mesma que rls_can_see_initiative consulta');
  assert.match(decl, /ae\.initiative_id\s*=\s*v_board\.initiative_id/i,
    'o pertencimento deve ser escopado a iniciativa DO BOARD, nao a qualquer iniciativa');
  assert.match(decl, /ae\.auth_id\s*=\s*auth\.uid\(\)/i,
    'o pertencimento deve ser do chamador');
  assert.match(decl, /ae\.status\s*=\s*'active'/i,
    "a view expoe 'suspended' tambem, entao o filtro de status ativo e obrigatorio");
  assert.match(decl, /v_board\.initiative_id\s+IS\s+NOT\s+NULL/i,
    'board sem iniciativa nao pode cair em pertencimento indefinido');
});

test('1498: a posse da atividade e null-safe (NULL nao pode atravessar o gate)', () => {
  const block = rpcBlock(readFileSync(resolve(MIGRATIONS_DIR, FIX_MIGRATION), 'utf8'));
  const decl = block.match(/v_is_activity_owner\s*:=[\s\S]*?;/)?.[0] || '';
  assert.ok(decl, 'v_is_activity_owner deve ser derivado no corpo da funcao');
  assert.match(decl, /coalesce\(\s*v_item\.assigned_to\s*=\s*v_caller\.id\s*,\s*false\s*\)/i,
    'sem coalesce, assigned_to NULL produz gate NULL e o RAISE nao dispara');
});

// ── Defesa prospectiva ───────────────────────────────────────────────────────

test('1498: nenhuma migration posterior reabre o ramo sem responsavel', () => {
  const captures = capturesInOrder();
  const idx = captures.findIndex((c) => c.file === FIX_MIGRATION);
  assert.ok(idx >= 0, 'a migration do #1498 deve estar entre as capturas da RPC');

  for (const { file, block } of captures.slice(idx)) {
    assert.match(block, UNASSIGNED_REQUIRES_MEMBERSHIP,
      `${file} redefine complete_checklist_item sem exigir pertencimento a iniciativa (#1498)`);
  }
});
