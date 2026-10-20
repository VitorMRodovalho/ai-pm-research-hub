// #2738 (decisão do GP, 19/10/2026): aviso "Em breve" do Grupo de Estudos PMI-CPMAI na home.
// O grupo abre em 05/11/2026, e o aviso some depois desse dia, no fim do dia pelo horário de Brasília
// (UTC−3; o Brasil não tem horário de verão desde 2019). Esta é a ÚNICA data do aviso: quem a mudar
// muda aqui, e o guard tests/contracts/2738-aviso-grupo-cpmai.test.mjs acompanha os dois lados do limite.
// Só texto: a iniciativa é confidencial e nada dela é lido do banco.
export const CPMAI_STUDY_GROUP_NOTICE_UNTIL = new Date('2026-11-06T00:00:00-03:00');

export function isCpmaiStudyGroupNoticeVisible(now: Date = new Date()): boolean {
  return now.getTime() < CPMAI_STUDY_GROUP_NOTICE_UNTIL.getTime();
}
