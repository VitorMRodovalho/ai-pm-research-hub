-- #1423 — `members.initiative_id` ficava apontando para a tribo ANTERIOR depois de uma
-- transferência, e o gate de consistência derrubava CI de PR que não tinha nada com isso.
--
-- A ISSUE DESCREVE OUTRO CAMINHO, E ELE JÁ ESTÁ COBERTO
-- O texto original fala de `manage_initiative_engagement` action=remove "apagando" a linha de
-- engagement. Medido hoje: aquele caminho faz `UPDATE ... SET status='expired'`, não DELETE, e o
-- trigger `trg_sync_member_initiative_from_engagement` dispara em `UPDATE OF status`. Ou seja, o
-- caso original está tratado — e a rederivação para iniciativas NÃO-tribo existe e funciona.
--
-- A CAUSA REAL É UMA ASSIMETRIA ENTRE OS DOIS CAMPOS DA MESMA PONTE
-- Numa transferência entre tribos de pesquisa, três coisas acontecem em sequência:
--
--   1. o engajamento NOVO fica `active`
--      · `_sync_tribe_id_from_engagement` grava `tribe_id` da tribo nova, INCONDICIONALMENTE
--      · `_sync_member_initiative_from_engagement` tenta gravar `initiative_id`, mas só
--        `WHERE initiative_id IS NULL` — e numa transferência ele NÃO está nulo: aponta para a
--        tribo anterior. Não faz nada.
--   2. o engajamento ANTIGO expira
--      · o caminho de limpeza só age quando NÃO resta engajamento ativo de tribo. Numa
--        transferência resta (o novo). Não faz nada.
--
-- Resultado: `tribe_id` novo, `initiative_id` velho. Foi exatamente o estado medido em 07/08 no
-- único membro órfão da base, e a transferência dele tinha acontecido no mesmo dia.
--
-- Nenhum dos dois triggers está errado isolado. O defeito é que `tribe_id` é tratado como
-- "sempre a tribo atual" e `initiative_id` como "primeira que chegar, nunca sobrescrever". Numa
-- ponte que deveria representar a MESMA coisa, uma regra é de atualização e a outra é de
-- inicialização.
--
-- A CORREÇÃO, E POR QUE ELA VAI NESTE TRIGGER
-- `_sync_member_initiative_from_engagement` já declara, em comentário, que research_tribe é
-- "owned by `_sync_tribe_id_from_engagement`". Este trigger já escreve `initiative_id` no caminho
-- de LIMPEZA (zera quando a pessoa sai da última tribo). Faltava escrevê-lo no caminho de SET.
-- Ou seja: o dono já era este; ele só cuidava de metade do ciclo de vida.
--
-- ⚠️ O CUIDADO QUE PRESERVA O COMPORTAMENTO ANTIGO
-- Sobrescrever `initiative_id` sempre seria regressão: uma iniciativa NÃO-tribo (grupo de estudo,
-- workgroup) pode ser a primária por escolha, e o `IS NULL` original existia para não atropelá-la.
-- Por isso o `CASE` só sobrescreve quando o valor atual é NULL **ou** é ele mesmo uma
-- research_tribe — que é precisamente o caso da transferência.
--
-- Refs #1423, #1270, #1269, #1273

CREATE OR REPLACE FUNCTION public._sync_tribe_id_from_engagement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_legacy_tribe_id integer;
  v_member_id uuid;
BEGIN
  SELECT i.legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives i
  WHERE i.id = NEW.initiative_id AND i.kind = 'research_tribe';

  IF v_legacy_tribe_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.person_id = NEW.person_id;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- SET simétrico ao CLEAR: só membresia de tribo (kind='volunteer') popula tribe_id.
  -- observer/speaker/etc. NÃO são membros de tribo e não devem setar o cache.
  IF NEW.status = 'active' AND NEW.kind = 'volunteer' THEN
    UPDATE public.members m
       SET tribe_id = v_legacy_tribe_id,
           -- #1423: o initiative_id passa a ACOMPANHAR o tribe_id. Antes, o outro trigger só o
           -- escrevia `WHERE initiative_id IS NULL`, então numa transferência ele ficava na tribo
           -- anterior enquanto tribe_id já era a nova. Sobrescreve apenas quando está NULL ou
           -- quando aponta para uma research_tribe — uma iniciativa não-tribo é primária por
           -- escolha e continua intocada.
           initiative_id = CASE
             WHEN m.initiative_id IS NULL
                  OR EXISTS (
                    SELECT 1 FROM public.initiatives i2
                    WHERE i2.id = m.initiative_id AND i2.kind = 'research_tribe'
                  )
               THEN NEW.initiative_id
             ELSE m.initiative_id
           END
     WHERE m.id = v_member_id
       AND (
         m.tribe_id IS DISTINCT FROM v_legacy_tribe_id
         OR m.initiative_id IS DISTINCT FROM NEW.initiative_id
       );
    RETURN NULL;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND NEW.status <> 'active' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.engagements e2
      JOIN public.initiatives i2 ON i2.id = e2.initiative_id AND i2.kind = 'research_tribe'
      WHERE e2.person_id = NEW.person_id
        AND e2.kind = 'volunteer'
        AND e2.status = 'active'
        AND e2.id <> NEW.id
    ) THEN
      UPDATE public.members m
         SET tribe_id = NULL,
             initiative_id = CASE
               WHEN m.initiative_id IN (SELECT id FROM public.initiatives WHERE kind = 'research_tribe')
                 THEN NULL
               ELSE m.initiative_id
             END
       WHERE m.id = v_member_id
         AND (
           m.tribe_id IS NOT NULL
           OR m.initiative_id IN (SELECT id FROM public.initiatives WHERE kind = 'research_tribe')
         );
    END IF;
  END IF;

  RETURN NULL;
END; $function$;
