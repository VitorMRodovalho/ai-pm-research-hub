-- #1537 fase 2b — 'orphan': o veredito humano sobre as 42 que não resolvem em lugar nenhum.
--
-- Decisão do PM em 30/07/2026, depois da investigação da fase 2a: **manter as 42 e documentar**. Elas podem
-- ser mérito legítimo cujo alvo foi apagado no refactor Domain Model V4 (concluído 13/04/2026), e mérito de
-- trabalho concluído é imutável. Apagar sob incerteza tira de quem fez; manter sob incerteza deixa 440 pts a
-- mais numa base da ordem de 8,6 mil. O erro barato é manter.
--
-- O PROBLEMA QUE ESSA DECISÃO CRIA, e a razão desta migration existir:
--
-- Enquanto as 42 seguirem com `ref_kind IS NULL`, o balde NULL passa a guardar DUAS coisas outra vez:
--   (a) "investigada, alvo confirmadamente inexistente, mérito preservado por decisão"  <- as 42
--   (b) "não classificada, ninguém olhou ainda"                                          <- órfã nova
-- Que é exatamente o vício do `ref_id` polimórfico se reinstalando um nível acima — e o arco inteiro do
-- #1537 existe para matar esse vício, não para movê-lo de lugar. Pior: com o ratchet em 42, uma órfã NOVA
-- se esconde atrás do teto até que o total passe de 42, e ninguém acende.
--
-- Com 'orphan' separado:
--   NULL     volta a significar UMA coisa (não classificada) e o ratchet vira ZERO ESTRITO
--   'orphan' significa revisada + alvo inexistente + mérito mantido
-- Uma órfã nova nasce NULL e acende o guard NO MESMO DIA, em vez de envelhecer em silêncio.
--
-- ⚠️ O trigger derivador NÃO atribui 'orphan' sozinho, de propósito: 'orphan' é veredito humano, não
-- resultado de lookup falho. Se o trigger pudesse concedê-lo, "revisada" viraria sinônimo de "não achei", e
-- a distinção que esta migration compra se perderia na primeira linha nova.
--
-- ⚠️ As 42 são marcadas pelos IDs EXATOS, nunca por predicado (`ref_kind IS NULL AND ref_id IS NOT NULL`).
-- Um predicado absorveria em silêncio qualquer órfã que chegue entre a medição e o apply — exatamente a
-- linha que o guard deveria acender. Contagem medida em produção em 30/07/2026: 42 linhas, 440 pontos,
-- 26 membros distintos (40 de `attendance` = #1534, mais 2 de `curation_doc_authored`).

ALTER TABLE public.gamification_points DROP CONSTRAINT IF EXISTS gamification_points_ref_kind_check;
ALTER TABLE public.gamification_points ADD CONSTRAINT gamification_points_ref_kind_check
  CHECK (ref_kind IS NULL OR ref_kind IN (
    'none','attendance','event','document_version','board_item','event_showcase',
    'meeting_artifact','meeting_action_item','event_agenda_block','champion_award',
    'approval_signoff','document_comment','initiative','orphan'));

COMMENT ON COLUMN public.gamification_points.ref_kind IS
  'Discriminador do ref_id polimórfico (#1537). ''none'' = categoria sem referência por natureza; '
  'nome da tabela = referência resolvida; ''orphan'' = revisada por humano, alvo inexistente, mérito '
  'preservado por decisão (#1534); NULL = NÃO CLASSIFICADO, e o guard exige que seja zero. '
  'Preenchido pelo trigger trg_gamification_points_ref_kind, que NUNCA atribui ''orphan'' sozinho.';

UPDATE public.gamification_points SET ref_kind = 'orphan'
WHERE id IN (
  '01742962-2281-4bed-8272-79e5891a61a0','06a06155-f269-4070-bbde-10cd8246690c',
  '0cd30b6d-550e-4bd4-8fc8-811f586e789d','0f3b0705-a291-4f72-ad5f-87beeb680a6e',
  '0f5639ce-b431-42eb-b233-32c88f2b1777','14f1d061-16ad-4567-9964-bc955b6f6d56',
  '1e21495c-4230-4627-b6dc-c7edf2fea48e','2d771c1c-d545-44d4-bafa-3312ad0ea775',
  '322e806b-ca1e-4128-820e-d9dcc8e7701b','3290fb4a-f73c-4c80-9b6c-e07aebb9d8f0',
  '3849bc64-6268-4665-8e3a-c30c7e362914','3866d269-7f05-49b2-a49a-e720897e5858',
  '3cae18f8-d80d-4dcf-beef-97e9e6c34ac8','3fa8481a-c756-4544-a0f9-92bae545f3ac',
  '4ae1d08c-cc93-49dc-a3d2-18798338e33f','4d18dd5d-2ad7-46b7-9c95-3ce3fb4c7f53',
  '56315425-2f8c-4d4d-9677-5e28f9cfaa2c','570fc011-a58a-4622-be2f-9eca3cdb5664',
  '5bdeafac-cef4-420e-a1f1-666761c00adf','7569ecd7-4178-4492-95d8-6d3fb5bdefdb',
  '75de9c5a-4943-41be-a32c-b88acff223fb','7add6d23-78b8-427d-b97e-5bff4493a227',
  '7b054876-6eac-4103-aa40-f3a579a25bd4','81643625-4872-429a-9195-575af6a85bc7',
  '8805dedb-5872-426b-8a04-3eeacd50e5d4','8c86d5c4-a207-42ce-9377-6b019c8240ed',
  '92cf8e3a-426e-4202-8fe4-64f5f7e0fa01','9910d3d6-cec1-4bc4-9339-2d146ce3b90a',
  'afabae34-f689-4863-9799-d231517cb316','b1ebc12e-a706-456b-ae88-353af160a532',
  'bb5820f8-c51a-4f4a-b787-12e1cb8341f5','bc982bae-a184-42ed-b214-c03951dde209',
  'c9d2316f-26b4-438e-b76f-0eb8015bf4c7','ca0a1209-7afd-4873-adf0-ff24a3a2d869',
  'ca3e36b0-7a9a-4bef-ac4a-22d3768f82e7','dde0dfe2-0ccd-44f9-9442-cf6995e4f538',
  'e25b845d-4c37-4b3e-a72d-d96a6f9e67f3','e6db1fed-9115-479b-9ca8-c54c337612be',
  'e7b765f8-6586-4c30-a427-45895d4bd7eb','f0c26acb-8cc1-4ca8-aa5e-cc6f72e06337',
  'f3882965-b50e-4084-aa68-6d6b37a34767','f4461b25-88d7-421e-93a5-cc0d869c6f66'
) AND ref_kind IS NULL;
