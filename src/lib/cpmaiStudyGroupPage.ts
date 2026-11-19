// Página pública /grupo-de-estudos-cpmai (1ª turma do Grupo de Estudos PMI-CPMAI).
// Só conteúdo estático: nada aqui é lido do banco. Os textos moram nos 3 dicionários, sob `cpmaiGroupPage.*`.
//
// SYMPLA_URL é a ÚNICA chave de abertura das inscrições: enquanto for null, a página mostra a data de abertura
// e nenhum botão; quando receber o endereço do evento no Sympla, a página passa a mostrar o botão. Preço e lote
// nunca entram no site: eles ficam no Sympla. O guard tests/contracts/grupo-de-estudos-cpmai-pagina-publica.test.mjs
// acompanha os dois ramos.
export const SYMPLA_URL: string | null = null;

/** Etapas oficiais da certificação, na página do PMI. */
export const PMI_CPMAI_STEPS_URL = 'https://www.pmi.org/certifications/ai-project-management-cpmai';

/** Vagas de voluntariado da equipe do grupo, no portal de voluntários do PMI. */
export const VOLUNTEER_OPENINGS: ReadonlyArray<{ labelKey: string; href: string }> = [
  { labelKey: 'cpmaiGroupPage.team.facilitator', href: 'https://volunteer.pmi.org/opportunities/76631' },
  { labelKey: 'cpmaiGroupPage.team.curation', href: 'https://volunteer.pmi.org/opportunities/76663' },
  { labelKey: 'cpmaiGroupPage.team.reviewer', href: 'https://volunteer.pmi.org/opportunities/76662' },
  { labelKey: 'cpmaiGroupPage.team.support', href: 'https://volunteer.pmi.org/opportunities/76664' },
];
