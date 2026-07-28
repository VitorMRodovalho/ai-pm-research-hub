/**
 * Contract: #1496 — o gate de conclusão de atividade no CLIENTE espelha o do SERVIDOR.
 *
 * Reportado por uma tribo em 2026-07-27: pesquisador não conseguia marcar como concluída a
 * atividade que estava no nome dele, na tela de detalhe do card, embora a MESMA operação
 * funcionasse pela aba Atividades. Causa: `CardDetail.tsx` travava o checkbox por posse do
 * CARD (`canEdit`), enquanto `complete_checklist_item` autoriza por posse da ATIVIDADE
 * (`v_is_activity_owner := v_item.assigned_to = v_caller.id`). O cliente negava exatamente
 * quem o servidor autoriza, e `BoardActivitiesView` (sem gate no cliente) dava a resposta
 * oposta na mesma plataforma.
 *
 * Este teste trava as DUAS pontas para que uma refatoração não reabra o buraco em silêncio,
 * que é o padrão já observado no projeto (gate válido numa superfície e ausente noutra).
 *
 * NOTA de método: o código-fonte do cliente é lido COM OS COMENTÁRIOS REMOVIDOS antes de
 * qualquer asserção. Os comentários deste fix citam literalmente `assigned_to` e o nome da
 * RPC, e um regex ingênuo casaria com a explicação em vez de com o código vivo.
 *
 * Estático (sempre roda, sem depender de credencial de DB) + defesa prospectiva.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const RPC_CAPTURE = '20260513020000_adr0011_v3_to_v4_writers_batch2.sql';
const CARD_DETAIL = resolve(ROOT, 'src/components/board/CardDetail.tsx');
const PICKER = resolve(ROOT, 'src/components/board/MemberPickerMulti.tsx');

/** Remove comentários de linha e de bloco para que asserções nunca casem com prosa. */
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}

function readCode(path) {
  assert.ok(existsSync(path), `arquivo deve existir: ${path}`);
  return stripComments(readFileSync(path, 'utf8'));
}

/** Extrai o corpo de complete_checklist_item de um arquivo de migration. */
function rpcBlock(sql) {
  const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.complete_checklist_item\s*\([\s\S]*?\$function\$[\s\S]*?\$function\$/i;
  return sql.match(re)?.[0] || '';
}

/**
 * A posse da atividade tem de ser derivada de `assigned_to`, mas a expressão pode vir
 * envolvida por guarda de null-safety (o #1498 a envolveu em `coalesce(..., false)`).
 * O que esta asserção trava é a DERIVAÇÃO, não a formatação exata da linha.
 */
const ACTIVITY_OWNER_DERIVATION =
  /v_is_activity_owner\s*:=[^;]{0,60}?v_item\.assigned_to\s*=\s*v_caller\.id/i;

// ── Lado servidor ────────────────────────────────────────────────────────────

test('1496: servidor autoriza o DONO DA ATIVIDADE a concluir', () => {
  const block = rpcBlock(readFileSync(resolve(MIGRATIONS_DIR, RPC_CAPTURE), 'utf8'));
  assert.ok(block, 'bloco de complete_checklist_item deve estar capturado na migration');
  assert.match(block, ACTIVITY_OWNER_DERIVATION,
    'a posse da atividade deve ser derivada de board_item_checklists.assigned_to');
  assert.match(block, /NOT\s+v_is_activity_owner/i,
    'o gate deve consultar v_is_activity_owner antes de negar');
});

// ── Lado cliente ─────────────────────────────────────────────────────────────

test('1496: o checkbox de atividade NAO e travado pelo gate de card', () => {
  const code = readCode(CARD_DETAIL);
  assert.doesNotMatch(code, /disabled=\{!canEdit\}\s*\n?\s*className="w-4 h-4 rounded border/,
    'o checkbox do checklist nao pode voltar a usar disabled={!canEdit}');
  assert.match(code, /disabled=\{!canToggleActivity\(ci\)\}/,
    'o checkbox do checklist deve usar o gate por posse da atividade');
});

test('1496: canToggleActivity chaveia por assigned_to do item, nao por posse do card', () => {
  const code = readCode(CARD_DETAIL);
  const fn = code.match(/const\s+canToggleActivity\s*=[\s\S]*?;\n/)?.[0] || '';
  assert.ok(fn, 'canToggleActivity deve existir em CardDetail');
  assert.match(fn, /ci\.assigned_to\s*===\s*permissions\.member\.id/,
    'o gate deve comparar o responsavel da atividade com o membro logado');
});

test('1496: isCardAssignee le a MESMA fonte que renderiza os participantes', () => {
  const code = readCode(CARD_DETAIL);
  const decl = code.match(/const\s+isCardAssignee\s*=[\s\S]*?;\n/)?.[0] || '';
  assert.ok(decl, 'isCardAssignee deve existir em CardDetail');
  assert.match(decl, /itemAssignments\.some/,
    'a junção deve vir do state itemAssignments (get_item_assignments), a mesma fonte da UI');
  // NOTA (#1500, medido 2026-07-28): a justificativa original desta asserção era que
  // `get_board_by_domain` nao devolve `assignments`. Medido contra o corpo vivo: ela delega
  // para get_board desde 20260428180000 e o payload da rota de tribo traz `assignments` em
  // 8 de 8 itens. A asserção continua valendo por outro motivo — `itemAssignments` recarrega
  // apos o claim, a prop do board so mudaria com refetch do board inteiro — e nao por
  // divergencia de payload, que nao existe.
  assert.doesNotMatch(decl, /item\.assignments/,
    'isCardAssignee nao pode voltar a ler a prop item.assignments');
});

test('1496: participante consegue remover a PROPRIA atribuicao sem canAssign', () => {
  const code = readCode(PICKER);
  assert.match(code, /selfMemberId/,
    'MemberPickerMulti deve aceitar selfMemberId');
  assert.match(code, /const\s+canRemove\s*=\s*\(memberId[^)]*\)\s*=>\s*!disabled\s*\|\|/,
    'canRemove deve liberar remocao quando o alvo e o proprio membro');
  assert.match(code, /\{canRemove\(a\.member_id\)\s*&&/,
    'o botao de remover deve consultar canRemove, nao !disabled');

  const card = readCode(CARD_DETAIL);
  assert.match(card, /selfMemberId=\{permissions\.member\?\.id\s*\?\?\s*null\}/,
    'CardDetail deve repassar o membro logado ao picker');
});

// ── Defesa prospectiva ───────────────────────────────────────────────────────

test('1496: nenhuma migration posterior remove o ramo de dono-da-atividade', () => {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  const idx = all.indexOf(RPC_CAPTURE);
  assert.ok(idx >= 0, 'a migration de captura deve estar no registro');

  for (const file of all.slice(idx + 1)) {
    const block = rpcBlock(readFileSync(resolve(MIGRATIONS_DIR, file), 'utf8'));
    if (!block) continue;
    assert.match(block, ACTIVITY_OWNER_DERIVATION,
      `${file} redefine complete_checklist_item sem preservar a posse da atividade (#1496)`);
  }
});
