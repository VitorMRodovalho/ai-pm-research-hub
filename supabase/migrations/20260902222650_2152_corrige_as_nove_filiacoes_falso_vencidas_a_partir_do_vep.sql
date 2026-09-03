-- WHAT: grava uma verificacao NOVA para os membros cuja ultima verificacao diz "vencida" enquanto
--       o VEP informa filiacao ativa. Nada e apagado nem editado: a tabela e append-only e o leitor
--       toma a mais recente por member_id, entao corrigir e ACRESCENTAR.
--
-- WHY:  medido em 02/09/2026, sobre os 69 membros que tem AS DUAS fontes:
--
--         batem ................................. 60
--         falso "vencida" (VEP diz ativa) .......  9   <- alvo
--         falso "em dia"  (VEP diz vencida) .....  0
--
--       O erro e UNIDIRECIONAL, 9 a 0. Isso descarta ruido aleatorio: se fosse imprecisao de
--       leitura, haveria divergencia nos dois sentidos. E os 9 sao todos `is_active = true`, ou
--       seja, voluntarios ativos exibidos como irregulares na tela de filiacao.
--
-- A CAUSA (segue aberta, e o conserto de origem e outro): `vep_sync` grava a verificacao uma vez e
--       NUNCA a reescreve quando o VEP passa a informar vencimento novo. 8 das 9 sao do mesmo lote
--       de 13/07/2026 e a defasagem e de exatamente 365 dias: sao pessoas que renovaram por mais um
--       ano depois daquela verificacao. O numero cresce sozinho, porque toda verificacao envelhece
--       um ano e nada a atualiza.
--
-- POR QUE A DATA DO VEP NAO EXIGE ESCOLHA, e eu cheguei a achar que exigia: cada pessoa tem entre
--       2 e 4 memberships no VEP (PMI Global mais um ou mais capitulos). Medido
--       `count(DISTINCT expiryDate)` por pessoa: **1** nas nove. Todos os memberships de uma mesma
--       pessoa expiram na mesma data, entao nao ha ambiguidade entre a data do Global e a do
--       capitulo.
--
-- E UMA LEITURA MINHA QUE ESTAVA ERRADA, registrada para nao se repetir: sondando
--       `pmi_memberships->1->>'chapterName'` eu conclui que Blenda (PMI-MG) e Thayanne (PMI-GO)
--       estavam em capitulos divergentes (Sao Paulo e Ceara). Estavam nao: o array lista VARIOS
--       capitulos e o indice 1 nao e "o capitulo da pessoa". Abrindo o array inteiro, Blenda tem 4
--       memberships INCLUINDO Minas Gerais e Thayanne tem 3 INCLUINDO Goias. As nove batem com o
--       capitulo registrado. Indice fixo em array multi-valorado devolve o vizinho.
--
-- `verified_by_member_id` FICA NULL de proposito: nao houve pessoa verificando. Preencher com quem
--       rodou a migration atribuiria a alguem um ato de verificacao que ele nao praticou.
--
-- `method` = 'vep_sync' porque a FONTE do dado e o VEP, lido em 02/09. O CHECK admite
--       ('vep_sync','sede_manual','self_attested') e nenhum outro descreveria melhor a origem.
--
-- ROLLBACK: apagar as linhas cujo `source_ref` = 'issue:2152-correcao-falso-vencida'. Como a tabela
--       e append-only e o leitor toma a mais recente, apagar essas restaura o estado anterior.
--
-- CROSS-REF: #2152

-- 1. Uma verificacao nova por membro afetado, com a data que o VEP informa.
INSERT INTO public.member_affiliation_verifications
  (member_id, chapter_verified, membership_active, membership_expires_on, method, source_ref, verification_obs)
SELECT a.member_id,
       a.chapter,
       true,
       a.vep_expira,
       'vep_sync',
       'issue:2152-correcao-falso-vencida',
       'Correcao #2152: a verificacao anterior (' || a.antiga::text || ') ficou congelada no '
       || 'vencimento antigo enquanto o VEP passou a informar ' || a.vep_expira::text
       || '. Gravada a partir do VEP lido em ' || a.vep_visto::text || '.'
FROM (
  SELECT DISTINCT ON (m.id)
         m.id AS member_id, m.chapter,
         to_date(sa.pmi_memberships->0->>'expiryDate','DD Mon YYYY') AS vep_expira,
         sa.vep_last_seen_at::date AS vep_visto,
         uv.membership_expires_on AS antiga
  FROM public.members m
  JOIN public.selection_applications sa ON lower(sa.email) = lower(m.email)
  JOIN LATERAL (
    SELECT membership_expires_on
    FROM public.member_affiliation_verifications v
    WHERE v.member_id = m.id
    ORDER BY v.created_at DESC LIMIT 1
  ) uv ON true
  WHERE sa.pmi_memberships IS NOT NULL
    AND jsonb_array_length(sa.pmi_memberships) > 0
    AND uv.membership_expires_on < CURRENT_DATE
    AND to_date(sa.pmi_memberships->0->>'expiryDate','DD Mon YYYY') >= CURRENT_DATE
  ORDER BY m.id, sa.created_at DESC
) a;

-- 2. POS-CONDICOES.
DO $$
DECLARE
  v_inseridas   int;
  v_restantes   int;
  v_falso_ok    int;
  v_total_pares int;
BEGIN
  SELECT count(*) INTO v_inseridas
    FROM public.member_affiliation_verifications
   WHERE source_ref = 'issue:2152-correcao-falso-vencida';
  IF v_inseridas <> 9 THEN
    RAISE EXCEPTION 'POS-CONDICAO: inseri % linhas, esperava exatamente 9', v_inseridas;
  END IF;

  -- 2a. Nenhum falso "vencida" sobra, medido pela MESMA consulta que achou os 9.
  WITH uv AS (
    SELECT DISTINCT ON (member_id) member_id, membership_expires_on
    FROM public.member_affiliation_verifications ORDER BY member_id, created_at DESC
  ), vep AS (
    SELECT DISTINCT ON (m.id) m.id AS member_id,
           to_date(sa.pmi_memberships->0->>'expiryDate','DD Mon YYYY') AS vep_expira
    FROM public.members m JOIN public.selection_applications sa ON lower(sa.email)=lower(m.email)
    WHERE sa.pmi_memberships IS NOT NULL AND jsonb_array_length(sa.pmi_memberships)>0
    ORDER BY m.id, sa.created_at DESC
  )
  SELECT count(*) FILTER (WHERE uv.membership_expires_on < CURRENT_DATE AND p.vep_expira >= CURRENT_DATE),
         count(*) FILTER (WHERE uv.membership_expires_on >= CURRENT_DATE AND p.vep_expira < CURRENT_DATE),
         count(*)
    INTO v_restantes, v_falso_ok, v_total_pares
    FROM uv JOIN vep p ON p.member_id = uv.member_id;

  IF v_restantes <> 0 THEN
    RAISE EXCEPTION 'POS-CONDICAO: ainda restam % falso-vencidas', v_restantes;
  END IF;

  -- 2b. CONTROLE DE ESCOPO NA OUTRA PONTA: a correcao nao pode ter criado o erro inverso, marcando
  --     alguem como em dia contra um VEP que diz vencido. Era 0 antes; tem de continuar 0.
  IF v_falso_ok <> 0 THEN
    RAISE EXCEPTION 'CONTROLE: a correcao criou % falso-em-dia, que era 0 antes', v_falso_ok;
  END IF;

  -- 2c. CONTROLE DE VACUIDADE: o denominador nao pode ter encolhido. Se a consulta parasse de casar
  --     pares, 2a passaria por ausencia de dado em vez de por ausencia de defeito.
  IF v_total_pares <> 69 THEN
    RAISE EXCEPTION 'CONTROLE: o denominador mudou de 69 para %, a medicao nao e comparavel', v_total_pares;
  END IF;
END $$;
