-- #1822 — a coluna de estado SEM DOMINIO DECLARADO.
--
-- Os ratchets do #1805 (_audit_state_literal_domain) e do #1809
-- (_audit_shared_state_literal_domain) provam que todo literal de estado escrito por uma funcao casa
-- com o dominio DECLARADO da coluna. Onde nao ha dominio declarado nao ha contra o que comparar, e o
-- par nao produz linha: um literal errado ali e silencioso para sempre.
--
-- Este auditor mede a outra direcao. Nao olha para funcao nenhuma; olha para o CATALOGO e pergunta
-- quais colunas de estado nao declaram dominio algum.

CREATE OR REPLACE FUNCTION public._audit_undeclared_state_domain()
RETURNS TABLE(
  tabela                 text,
  coluna                 text,
  tem_dominio_declarado  boolean,
  tem_fk                 boolean,
  tem_trigger_na_tabela  boolean,
  sem_dominio_declarado  boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH tabs AS MATERIALIZED (
    SELECT c.oid AS reloid, c.relname::text AS tbl, a.attname::text AS col, a.attnum
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    JOIN pg_type t ON t.oid = a.atttypid AND t.typname IN ('text', 'varchar', 'bpchar')
    WHERE c.relkind IN ('r', 'p')
  ),
  dominio AS MATERIALIZED (
    SELECT t.reloid, t.col
    FROM tabs t
    WHERE EXISTS (
      SELECT 1 FROM pg_constraint ct
      WHERE ct.conrelid = t.reloid AND ct.contype = 'c'
        AND ct.conkey = ARRAY[t.attnum]::int2[]
        AND (pg_get_constraintdef(ct.oid) ~ '= ANY \(ARRAY\['
          OR pg_get_constraintdef(ct.oid) ~ ('^CHECK \(\(' || t.col || ' = ''[^'']+''::text\)\)$'))
    )
  ),
  nomes AS MATERIALIZED (SELECT DISTINCT col FROM dominio),
  fk AS MATERIALIZED (
    SELECT DISTINCT t.reloid, t.col
    FROM tabs t
    WHERE EXISTS (
      SELECT 1 FROM pg_constraint c
      WHERE c.conrelid = t.reloid AND c.contype = 'f' AND t.attnum = ANY (c.conkey)
    )
  )
  SELECT t.tbl,
         t.col,
         EXISTS (SELECT 1 FROM dominio d WHERE d.reloid = t.reloid AND d.col = t.col),
         EXISTS (SELECT 1 FROM fk f WHERE f.reloid = t.reloid AND f.col = t.col),
         EXISTS (SELECT 1 FROM pg_trigger tg WHERE tg.tgrelid = t.reloid AND NOT tg.tgisinternal),
         NOT EXISTS (SELECT 1 FROM dominio d WHERE d.reloid = t.reloid AND d.col = t.col)
           AND NOT EXISTS (SELECT 1 FROM fk f WHERE f.reloid = t.reloid AND f.col = t.col)
  FROM tabs t
  JOIN nomes k ON k.col = t.col
  ORDER BY 6 DESC, 1, 2;
$function$;

COMMENT ON FUNCTION public._audit_undeclared_state_domain() IS
  'Ratchet do #1822, a terceira face da classe do #1805/#1809. Aqueles dois provam que o literal escrito por uma funcao casa com o dominio DECLARADO da coluna; este pergunta quais colunas de estado nao declaram dominio nenhum -- onde nao ha CHECK nao ha contra o que comparar, e nenhum dos dois alcanca. O universo e derivado do CATALOGO, nunca de lista de nomes: coluna textual de tabela public cujo NOME carrega dominio em pelo menos uma tabela. Dominio conta em duas formas, porque o Postgres imprime as duas: = ANY (ARRAY[...]) e a igualdade simples a um literal, que e dominio de tamanho 1 (event_guest_certificates.type era assim e saia da base indevidamente). CHECK que restringe FORMA ou CONDICAO nao conta como dominio: admin_audit_log.action tem regex de formato mais comprimento, e engagements.kind tem duas condicionais que citam kinds sem limitar o conjunto -- foi exatamente essa falta de CHECK que fez o ensaio do ponto cego do #1809 debitar kind = volunteer de member_emails. FK conta como dominio declarado por outro caminho (6 colunas, entre elas engagements.kind). O trigger de tabela e devolvido mas NAO entra no predicado: trigger e de tabela e nao de coluna, e nao prova que aquela coluna e validada -- se contasse, a base cairia quando a tabela ganhasse um trigger nao relacionado, mostrando progresso sem nada guardado. Devolve TODAS as colunas examinadas com o booleano, para que lista vazia seja distinguivel de guard cego.';

REVOKE ALL ON FUNCTION public._audit_undeclared_state_domain() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_undeclared_state_domain() TO service_role;
