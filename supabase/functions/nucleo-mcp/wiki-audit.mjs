// #2495 (ADR-0129, emenda 2, item 5): até o Comitê de Curadoria auditar, a página publicada pela
// liderança da tribo mostra "publicada pela tribo, auditoria pendente" a quem lê E ao assistente. A tela
// já mostra o selo; este módulo é a metade do assistente. Fica num arquivo próprio para o teste de
// contrato EXECUTAR a regra, em vez de procurar a frase no código.

export const WIKI_AUDIT_PENDING_NOTICE =
  "Publicada pela liderança da tribo, com auditoria do Comitê de Curadoria pendente (ADR-0129). " +
  "Ao citar esta página, diga que ela ainda não foi auditada.";

/** Acrescenta `audit_notice` a cada página com auditoria pendente. Aceita uma linha ou uma lista. */
export function withWikiAuditNotice(data) {
  const mark = (row) =>
    row && typeof row === "object" && row.audit_status === "pending"
      ? { ...row, audit_notice: WIKI_AUDIT_PENDING_NOTICE }
      : row;
  return Array.isArray(data) ? data.map(mark) : mark(data);
}
