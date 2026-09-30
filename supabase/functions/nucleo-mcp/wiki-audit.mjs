// #2495 (ADR-0129, emenda 2, item 5): até o Comitê de Curadoria auditar, a página publicada pela
// liderança da tribo mostra "publicada pela tribo, auditoria pendente" a quem lê E ao assistente. A tela
// já mostra o selo; este módulo é a metade do assistente. Fica num arquivo próprio para o teste de
// contrato EXECUTAR a regra, em vez de procurar a frase no código.

export const WIKI_AUDIT_PENDING_NOTICE =
  "Publicada pela liderança da tribo, com auditoria do Comitê de Curadoria pendente (ADR-0129). " +
  "Ao citar esta página, diga que ela ainda não foi auditada.";

// ADR-0132: a página marcada como síntese de IA diz isso a quem lê pelo assistente, como o selo diz na tela.
export const WIKI_AI_SYNTHESIS_NOTICE =
  "Conteúdo marcado como síntese produzida por IA (ADR-0132), não como fonte primária. " +
  "Ao citar esta página, diga que é uma síntese de IA.";

/**
 * Acrescenta `audit_notice` a cada página com auditoria pendente e `epistemic_notice` a cada página
 * marcada como síntese de IA. Aceita uma linha ou uma lista.
 */
export function withWikiAuditNotice(data) {
  const mark = (row) => {
    if (!row || typeof row !== "object") return row;
    let out = row;
    if (row.audit_status === "pending") out = { ...out, audit_notice: WIKI_AUDIT_PENDING_NOTICE };
    if (row.epistemic_label === "sintese_ia") out = { ...out, epistemic_notice: WIKI_AI_SYNTHESIS_NOTICE };
    return out;
  };
  return Array.isArray(data) ? data.map(mark) : mark(data);
}
