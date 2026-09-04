-- #2159 achado 3 - `accessor_id` nulo em `pii_access_log` era AMBIGUO entre duas coisas muito
-- diferentes: "nao ha pessoa, o fluxo e automatico" e "houve pessoa e ninguem registrou quem".
-- Como relatorio por responsavel filtra por accessor, as duas somem do relatorio igual, e por isso
-- 7.592 leituras de PII nao tinham dono em lugar nenhum.
--
-- MEDIDO EM 04/09/2026, varredura da tabela INTEIRA (nao amostra), com controle positivo na mesma
-- consulta — os contextos com accessor preenchido provam que a leitura enxerga:
--
--     contexto                            total   sem accessor
--     reconcile_initiative_drive_access   7.102          7.102   (100%)
--     audit_drive_offboarding_access        490            490   (100%)
--     (todos os outros 16 contextos)     27.914              0   (0%)
--
-- Exatamente DOIS contextos tem accessor nulo, e ambos sao 100% nulos. NENHUM contexto mistura os
-- dois casos. E por isso que o backfill abaixo pode classificar sem heuristica: nao ha zona cinzenta.
--
-- POR QUE O DEFAULT VEM DE TRIGGER E NAO DE `DEFAULT` DE COLUNA. Um `DEFAULT 'unknown'` nao
-- distingue "o escritor nao declarou" de "o escritor declarou 'unknown'", e um `DEFAULT 'human'`
-- mentiria por omissao. O trigger distingue: valor declarado passa intacto, ausencia de valor e
-- classificada. Essa distincao E a coluna — sem ela, `actor_kind` seria `accessor_id IS NULL`
-- renomeado, isto e, o mesmo sinal com outro nome e zero informacao nova.
--
-- POR QUE AUSENCIA DE DECLARACAO VIRA `unknown` E NAO `automation`. Presumir automacao quando nao
-- ha pessoa abencoaria em silencio exatamente a linha inatribuivel que esta coluna existe para
-- tornar visivel. Um fluxo automatico legitimo DECLARA, e sai de `unknown` por ato, nao por sorte.
--
-- METADE DE BANCO, DE PROPOSITO. Os dois escritores automaticos de hoje NAO sao funcoes de banco
-- (a busca em `pg_proc` por esses nomes volta vazia): sao Edge Functions gravando por PostgREST.
-- Fazer as duas metades numa PR so juntaria dois veiculos de deploy numa mudanca que so parece
-- atomica. Esta migration entrega a metade RECEPTORA; ate as EFs declararem, as linhas novas delas
-- caem em `unknown`, que e o sinal honesto e o gatilho da conversa seguinte.
--
-- NAO HA RATCHET SOBRE `unknown` NESTA PR, pelo mesmo motivo: o contador vai subir por desenho ate
-- a metade escritora chegar, e um portao que reprova por desenho vira portao que se aprende a
-- ignorar. O teste que acompanha registra a LINHA DE BASE (`unknown` = 0 no momento de aplicar) e
-- afirma a classificacao do trigger; o ratchet entra quando as EFs declararem.

ALTER TABLE public.pii_access_log ADD COLUMN IF NOT EXISTS actor_kind text;

UPDATE public.pii_access_log
   SET actor_kind = 'automation'
 WHERE actor_kind IS NULL
   AND accessor_id IS NULL
   AND context IN ('reconcile_initiative_drive_access', 'audit_drive_offboarding_access');

UPDATE public.pii_access_log
   SET actor_kind = 'human'
 WHERE actor_kind IS NULL
   AND accessor_id IS NOT NULL;

-- O que sobrar e honestamente desconhecido: sem accessor e sem origem automatica nomeada.
UPDATE public.pii_access_log SET actor_kind = 'unknown' WHERE actor_kind IS NULL;

CREATE OR REPLACE FUNCTION public.trg_pii_access_log_actor_kind()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Quem declara, manda. O objetivo desta coluna e obrigar a DECLARAR origem, entao um valor
  -- explicito do escritor nunca e sobrescrito.
  IF NEW.actor_kind IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Sem declaracao: ha pessoa resolvida, entao e humano.
  IF NEW.accessor_id IS NOT NULL THEN
    NEW.actor_kind := 'human';
    RETURN NEW;
  END IF;

  -- Sem declaracao E sem pessoa. NAO se presume automacao: presumir aqui seria abencoar em
  -- silencio exatamente a linha inatribuivel que esta coluna existe para tornar visivel. Um
  -- caminho automatico legitimo declara 'automation' e sai de 'unknown'.
  NEW.actor_kind := 'unknown';
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_pii_access_log_actor_kind ON public.pii_access_log;
CREATE TRIGGER trg_pii_access_log_actor_kind
BEFORE INSERT ON public.pii_access_log
FOR EACH ROW EXECUTE FUNCTION public.trg_pii_access_log_actor_kind();

ALTER TABLE public.pii_access_log ALTER COLUMN actor_kind SET NOT NULL;

ALTER TABLE public.pii_access_log DROP CONSTRAINT IF EXISTS pii_access_log_actor_kind_check;
ALTER TABLE public.pii_access_log ADD CONSTRAINT pii_access_log_actor_kind_check
  CHECK (actor_kind IN ('human', 'automation', 'unknown'));

CREATE INDEX IF NOT EXISTS idx_pii_access_log_actor_kind
  ON public.pii_access_log (actor_kind, accessed_at DESC);

COMMENT ON COLUMN public.pii_access_log.actor_kind IS
  '#2159 achado 3: separa "nao ha pessoa" de "ninguem registrou quem foi". accessor_id nulo era '
  'ambiguo entre os dois, e por isso 7.592 leituras de PII sumiam de qualquer relatorio por '
  'responsavel. human = pessoa resolvida; automation = fluxo automatico que DECLAROU ser; '
  'unknown = escreveu sem accessor e sem declarar, que e o caso a caçar. O default vem do trigger '
  'trg_pii_access_log_actor_kind, nao de um DEFAULT de coluna, porque o trigger distingue '
  '"nao declarou" de "declarou".';
