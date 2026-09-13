-- #2245 — a FONTE das cinco chaves fora do catalogo, e o portao que impede a terceira volta.
--
-- HISTORIA CURTA, e ela e o argumento inteiro desta migration. Em 02/09 a decisao 3 da #2131 apagou
-- 145 linhas de 29 pessoas e deixou o estado em ZERO chaves fora do catalogo. Oito dias depois, em
-- 10/09 00:28, as duas primeiras pessoas aprovadas recriaram o defeito inteiro: 10 linhas, 2 pessoas.
--
-- A migration de 02/09 e exemplar no metodo (mediu antes, conferiu FK e triggers, afirmou a
-- pos-condicao). O que faltou nao foi cuidado, foi ALCANCE: ela tratou `onboarding_progress` como a
-- coisa a limpar, quando `onboarding_progress` era o EFEITO. A pergunta que teria pego isso e "quem
-- ESCREVE estas linhas, e essa fonte muda com a limpeza?".
--
-- A FONTE: `approve_selection_application` semeia a jornada de DUAS origens. A primeira le o
-- catalogo `onboarding_steps` e esta certa. A segunda le um JSONB por ciclo
-- (`selection_cycles.onboarding_steps`), sem catalogo, sem rotulo, sem ordem e sem validacao.
--
-- MEDIDO EM 13/09, e este numero e o que autoriza o passo 1 abaixo: o JSONB dos ciclos contem
-- EXATAMENTE as cinco chaves orfas e NADA MAIS (`accept_terms`, `join_whatsapp`, `kick_off`,
-- `platform_access`, `profile_complete`), nos tres ciclos, inclusive no aberto. Ou seja, aquele
-- caminho de semeadura so produz orfa.
--
-- O DESTINO DE CADA CHAVE, ratificado pelo dono em 13/09 sobre o mapa que a #2131 ja tinha proposto:
--   profile_complete -> complete_profile
--   accept_terms     -> volunteer_term
--   kick_off         -> first_meeting
--   platform_access  -> descartada, nao tem contraparte
--   join_whatsapp    -> so volta pelo CATALOGO se for virar etapa de verdade
--
-- ⚠️ E AQUI A OPERACAO NAO E O QUE O MAPA SUGERE. O mapa descreve o SIGNIFICADO de cada chave, mas
-- renomear e IMPOSSIVEL: medido, cada uma das 2 pessoas tem 12 linhas — 7 vindas do catalogo (a
-- fonte certa) mais as 5 orfas — e entre as 7 ja estao `complete_profile`, `volunteer_term` e
-- `first_meeting`, todas `pending`. Com `uq_onboarding_member_step UNIQUE (member_id, step_key)`, um
-- UPDATE de `profile_complete` para `complete_profile` violaria a unica.
--
-- Entao a operacao e APAGAR, e nada se perde: as cinco chaves tem ZERO conclusoes em toda a historia
-- (medido na propria migration de 02/09 antes de apagar, e de novo hoje), e as 10 linhas atuais estao
-- todas `pending`, com a contraparte do catalogo ja existindo no MESMO estado.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. A FONTE: o JSONB por ciclo passa a conter so o que o catalogo conhece
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Filtrado pelo CATALOGO, nao por uma lista das cinco escrita aqui. Uma lista literal envelheceria:
-- uma sexta chave fora do catalogo entrando amanha passaria por este filtro sem ser vista.
UPDATE public.selection_cycles sc
SET onboarding_steps = COALESCE((
      SELECT jsonb_agg(step)
      FROM jsonb_array_elements(sc.onboarding_steps) AS step
      WHERE EXISTS (SELECT 1 FROM public.onboarding_steps t WHERE t.id = step->>'key')
    ), '[]'::jsonb)
WHERE sc.onboarding_steps IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(sc.onboarding_steps) AS step
    WHERE NOT EXISTS (SELECT 1 FROM public.onboarding_steps t WHERE t.id = step->>'key')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. O EFEITO: as linhas que a fonte ja produziu
-- ─────────────────────────────────────────────────────────────────────────────
DELETE FROM public.onboarding_progress op
WHERE NOT EXISTS (SELECT 1 FROM public.onboarding_steps t WHERE t.id = op.step_key);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. O PORTAO: contencao por ESTRUTURA, nao por dado
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Os passos 1 e 2 consertam o que existe. So o passo 3 fecha a CLASSE: enquanto `step_key` for texto
-- livre, qualquer caminho de escrita futuro — outro JSONB, outro seed, um INSERT por service_role —
-- reintroduz o defeito, e a unica defesa seria um teste que o pega uma PR depois.
--
-- Depois do passo 2, ZERO linhas violam esta FK (medido: as 10 orfas eram as unicas).
--
-- ⚠️ CONSEQUENCIA CONHECIDA E ACEITA (decisao do dono, 13/09): `seed_pre_onboarding_steps` escreve um
-- TERCEIRO vocabulario (`create_account`, `setup_credly`, `explore_platform`, `read_blog`,
-- `start_pmi_certs`), tambem fora do catalogo, e passaria a FALHAR se alguem a chamasse. Hoje ela tem
-- 0 linhas e NENHUM chamador — o unico lugar que a menciona, `get_application_onboarding_pct`, so a
-- cita em comentario, e o teste #1997 ja afirma "nao tem chamador". Falhar alto e o desfecho certo
-- para uma funcao que so sabe escrever orfa.
--
-- Sem ON DELETE CASCADE de proposito: apagar um passo do catalogo NAO pode apagar em silencio o
-- progresso de quem ja o cumpriu. O RESTRICT padrao obriga a decisao a ser explicita.
ALTER TABLE public.onboarding_progress
  DROP CONSTRAINT IF EXISTS onboarding_progress_step_key_fkey;
ALTER TABLE public.onboarding_progress
  ADD CONSTRAINT onboarding_progress_step_key_fkey
  FOREIGN KEY (step_key) REFERENCES public.onboarding_steps(id);

COMMENT ON CONSTRAINT onboarding_progress_step_key_fkey ON public.onboarding_progress IS
  '#2245 — o catalogo onboarding_steps e obrigatorio por ESTRUTURA. Antes desta FK, step_key era texto livre e o JSONB por ciclo de selection_cycles semeava chaves que o catalogo nao conhece: sem rotulo, sem ordem, impossiveis de concluir, e contando contra a pessoa em denominador cru (#1875). Apagar as linhas sem fechar a fonte fez o defeito voltar em 8 dias (#2131 decisao 3 -> #2245).';
