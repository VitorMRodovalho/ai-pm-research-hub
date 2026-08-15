-- #1779: apagada a assinatura que carregava o segundo sentido, e o nome passa a significar uma coisa
--
-- Segunda e ultima etapa da implantacao sem janela quebrada. A primeira migration criou
-- get_board_lifecycle_log e deixou get_board_activities(uuid, integer) viva; a EF foi implantada
-- apontando para o nome novo (ef_version 2.101.0, conferida em /health ANTES desta migration
-- rodar). So agora a velha sai.
--
-- Depois daqui, `SELECT count(*) FROM pg_proc WHERE proname = 'get_board_activities'` devolve 1: a
-- das TAREFAS, que e o sentido que o produto usa quando diz "atividade". O contrato do #1779 trava
-- essa contagem, porque foi a duplicidade, e nao a assinatura em si, que fez o MCP pegar o log
-- quando queria as tarefas.
--
-- DROP, e nao CREATE OR REPLACE: muda numero e tipo de parametro (GC-097).

DROP FUNCTION IF EXISTS public.get_board_activities(uuid, integer);

COMMENT ON FUNCTION public.get_board_activities(uuid, uuid, text, text) IS
  '#1779: atividades (linhas de checklist) de TODOS os cards de um board, agregadas, com filtros de '
  'responsavel, status e prazo. Unico sentido do nome desde o #1779, quando o log de ciclo de vida '
  'virou get_board_lifecycle_log. Envelope: {activities, total, completed, pending}.';
