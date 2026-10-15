/**
 * #2699 (parte 2) — telas de documento que falhavam em silêncio.
 *
 * Auditoria de 15/10/2026: além do Termo, quatro superfícies de documento diziam "ok" ou nada
 * quando a ação não acontecia:
 *  - /gamification: "Revogar" chamava `revoke_certificate`, que não existe no banco, e mostrava
 *    "Revogado". O botão sai (decisão do GP) até existir uma revogação de verdade.
 *  - /gamification: publicar e editar ignoravam o `{error}` que `update_certificate` devolve com
 *    HTTP 200; o PDF inline saía em silêncio com a aba bloqueada; o download engolia a falha.
 *  - /admin/certificates: falha do PDF virava rejeição solta, sem aviso.
 *  - Contra-assinatura em lote: só a contagem chegava; a seleção era limpa e o motivo, perdido.
 *
 * Os guards amarram CONDIÇÃO a RESULTADO dentro do bloco que decide (CLAUDE.md, 17/09).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => maskJsComments(readFileSync(join(ROOT, p), 'utf8'));
const GAM = read('src/pages/gamification.astro');
const ADM = read('src/pages/admin/certificates.astro');
const VAP = read('src/components/admin/VolunteerAgreementPanel.tsx');

function caseBlock(src, name) {
  const m = src.match(new RegExp(`case '${name}': \\{([\\s\\S]*?)\\n      \\}`));
  return m ? m[1] : '';
}

test('#2699 gamification: nenhum caminho chama a revogação inexistente', () => {
  assert.doesNotMatch(GAM, /revoke_certificate/, 'revoke_certificate não existe no banco');
  assert.doesNotMatch(GAM, /data-action="revoke-cert"/, 'o botão que não revoga nada voltou');
  assert.doesNotMatch(GAM, /case 'revoke-cert'/, 'o handler que dizia "Revogado" voltou');
});

test('#2699 gamification: publicar só diz "publicado" se o RPC não devolveu erro', () => {
  const block = caseBlock(GAM, 'publish-cert');
  assert.ok(block, 'case publish-cert ausente');
  assert.match(block,
    /if \(pubErr \|\| pub\?\.error\) \{ toast\([^)]*'error'\); break; \}\s+toast\(I\.certIssued/,
    'o erro do RPC tem de sair antes do toast de sucesso');
});

test('#2699 gamification: editar lê o {error} do corpo, não só o da rede', () => {
  assert.match(GAM,
    /if \(error \|\| upd\?\.error\) \{ toast\([^)]*'error'\); return; \}\s+toast\(I\.certUpdated/,
    'update_certificate devolve {error} com HTTP 200');
});

test('#2699 gamification: download avisa a falha e a aba bloqueada', () => {
  const block = caseBlock(GAM, 'download-cert');
  assert.match(block, /catch \(e\) \{[^}]*toast\(I\.certDownloadError, 'error'\); \}/,
    'catch vazio no download voltou');
  assert.match(GAM,
    /const w = window\.open\('', '_blank'\);\s+if \(!w\) \{ showBlockedTabNotice\(URL\.createObjectURL\(new Blob\(\[html\]/,
    'aba bloqueada tem de virar aviso com link para o mesmo documento');
  assert.doesNotMatch(GAM, /if \(!w\) return;/, 'a saída silenciosa voltou');
});

test('#2699 admin/certificates: toda falha de PDF chega a quem clicou', () => {
  assert.match(ADM, /const pdfFailed = \(err: unknown\) => \{[^}]*toast\?\.\(t\('certificates\.downloadError', lang\), 'error'\);/,
    'pdfFailed tem de virar toast');
  const calls = ADM.match(/catch \(err\) \{ pdfFailed\(err\); \}/g) || [];
  assert.equal(calls.length, 4, 'individual, pendente e os dois lotes têm de passar por pdfFailed');
  assert.match(ADM, /if \(!cert\) \{ pdfFailed\(/, 'certificado fora da lista não pode sair calado');
  assert.match(ADM, /if \(error \|\| !data\) throw error/, 'a busca do pendente tem de olhar o erro');
});

test('#2699 contra-assinatura em lote: falhas mostram motivo e ficam selecionadas', () => {
  assert.match(VAP, /const failedResults = \(\(data\?\.results \?\? \[\]\) as any\[\]\)\.filter\(\(r\) => !r\?\.result\?\.success\);/,
    'as falhas têm de vir de `results`');
  assert.match(VAP, /failed > 0 \? `\$\{summary\} \$\{t\.bulkFailedReasons\.replace\('\{reasons\}', reasons\.join\(', '\)\)\}`/,
    'o motivo tem de chegar ao toast');
  assert.match(VAP, /setSelectedIds\(new Set\(failedResults\.map\(\(r\) => String\(r\.id\)\)\)\);/,
    'os que falharam têm de continuar selecionados');
  const keys = VAP.match(/bulkFailedReasons: '/g) || [];
  assert.equal(keys.length, 3, 'a chave nova tem de existir nos 3 idiomas do painel');
});
