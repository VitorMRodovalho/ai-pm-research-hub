# Prompt de arranque - proxima sessao (Wave 2, pos #1170 100% fechado, 2026-07-21)

> Cole o bloco abaixo como primeira mensagem da proxima sessao. Antes de agir: ler MEMORY.md,
> `git fetch`, e re-aterrar TODO numero ao vivo (grounding obrigatorio do CLAUDE.md). Os valores
> aqui sao do fechamento de 21/07 e podem ter mudado.

---

Sessao de trabalho no ai-pm-research-hub. Regras da casa: DDL so via apply_migration byte-igual
ao arquivo + migration repair + NOTIFY + deletar os phantom rows que o apply_migration MCP cria
(1 phantom POR chamada apply; usam data REAL `20260721HHMMSS`, que ordena ANTES do sintetico
`20260805NNNNNN` - checar por prefixo de data real, NUNCA por `>= head`, e deletar por versao
exata `IN (...)`, nunca LIKE); NAO aplicar 2a DDL enquanto a 1a PR nao mergeou (serializar); merge
so na sessao main (exceto autorizacao explicita do owner); sem em-dash em entregaveis; Assisted-By
nunca Co-Authored-By; 1 agente de conselho por subacao.

## Contexto (fechamento 2026-07-21)

`main ≡ prod` (HEAD `171b721a`). Sessao anterior FECHOU o residuo do #1170: o "chamador rogue" do
`arm9_inactivity_alert` era o PROPRIO contract test `detect-inactive-members-non-dry-run` (test #3,
helper `threshold=0`), escrevendo na prod porque `Prefer: tx=rollback` NAO desfaz INSERT de funcao
SECURITY DEFINER nesse Supabase (classe do #231). Prova: 4216 arm9, 100% titulados "0 dias" (so o
helper produz), correlacao com runs do ci.yml, buraco noturno = expediente, 1o row anterior ao 1o
cron. Fix (PR#1458, merged `171b721a`): o teste limpa o que cria (janela ancorada no tempo do
servidor) + asserçao de residuo zero; 4214 arm9 historicos deletados (2367 nao-lidos nos 2 admins);
prod em `arm9_total = 0`. Licao registrada na [LL] #588. Memoria:
`reference-tx-rollback-not-honored-secdef-pollutes-prod`.

Residuo opcional (DDL, deixado de fora): o helper `_test_detect_inactive_with_threshold` ainda faz
um `DELETE arm9 < 6 dias` amplo antes de inserir (heranca do #1170) - agora redundante e landmine
latente. Redesenho com subtransacao-abort (server-side, sem depender de tx=rollback nem deletar dado
de prod) seria a limpeza definitiva. Sessao dedicada se quiser.

Sessoes anteriores do dia (todas mergeadas, no MEMORY.md): A (#1450+#1445), B (#1424+#1423),
C (gamificacao #1448/#1449), D (#1004 LGPD C3->C4), E (#1170 dedup), F (#1170 residuo, esta).

## Fila desta sessao (prioridade)

1. **[VERIFICACAO, barato - SO A PARTIR DE SABADO 25/07] Pos-deploy do #1424.**
   O cap de e-mail so e exercitado no burst de sabado. Rodar (sab pos-12:00 UTC / domingo):
   - `SELECT count(*) FROM email_webhook_events WHERE event_type='email.sent' AND created_at::date='2026-07-25';`
     -> esperar <= ~90-95 (baseline anterior: 108-121).
   - `SELECT count(*) FROM notifications WHERE delivery_mode='transactional_immediate' AND email_sent_at IS NULL;`
     no domingo -> excedente adiado drenando, nao acumulando.
   - Sanidade: ninguem recebeu duplicata; digests ricos vs simples separados corretos.
   Se o cap estiver mordendo forte -> priorizar Fases C/D do #1424.

2. **[Wave 2 - proximo: #1008 (high)]** Ratificacao PMI-GO do nome "AI Community Day" +
   linguagem certificado/PDU. **E DECISAO HUMANA, nao codigo** (Presidencia PMI-GO + legal-counsel +
   c-level-advisor). Eu so preparo rascunhos. Blocker de divulgacao (parte do EPIC #1002). O evento
   16/07 ja passou, mas nome/PDU e recorrente p/ ACD futuros. **PERGUNTAR O RECORTE ANTES:** o que o
   owner quer produzido nesta sessao? Opcoes provaveis:
   - (a) Rascunho da consulta escrita a PMI-GO / PMI Latam (autorizacao do nome + referencia ao
     Standard sem parecer emissor + limites de PDU).
   - (b) Linguagem travada do certificado: "Certificado de participacao emitido pelo Nucleo IA & GP";
     NUNCA "concede N PDUs"; se aplicavel "PDU autodeclaravel conforme categoria do PMI CCR".
   - (c) Copy do convite/pagina enquadrando como "aftershow / extensao noturna" (slot 19-21h BRT),
     nunca "evento paralelo/oficial".
   Regras de comms: links via nucleoia.pmigo.org.br; sem em-dash; framing "iniciativa DOS capitulos
   do PMI, sediada no PMI-GO"; kit de marca BAIXADO do Drive (nao improvisar).

3. **[Wave 2 - proximo TECNICO se #1008 travar em decisao humana: #1152 (bug/governance)]**
   Mapear funcao->gate explicitamente. `_can_sign_gate` funde no gate `president_go` do
   `volunteer_term_template` duas funcoes distintas: Ivan (`legal_signer`, aprova a VERSAO do doc)
   e Lorena (`voluntariado_director`, assina a CONTRAPARTE da entidade em cada Termo executado,
   pos-aprovacao). O carve-out `voluntariado_director` dentro de `president_go` e a fusao indevida +
   cheiro de segregacao de funcoes. Achado 2: `committee_majority` e STUB (retorna false) e travaria
   o lock de `policy` no gate 1. Impacto do Achado 1: contornavel (threshold 1, Ivan assina a SEDE),
   mas corrigir a semantica antes de virar precedente. Pedido: documentar o mapa funcao->gate em
   `docs/reference/V4_AUTHORITY_MODEL.md` + refletir em `_can_sign_gate`. **ANTES de mexer em
   `engagement_kind_permissions` ou gates: rodar o procedimento de 4 etapas do V4_AUTHORITY_MODEL.md**
   (matriz capability->path) - auditoria mecanica de gates gera false positives (sediment p122e).
   Ler `pg_get_functiondef('_can_sign_gate')` e `resolve_default_gates` ao vivo antes de propor DDL.
   Refs: [[reference-volunteer-term-countersign-lorena]], [[reference-chapter-stakeholder-vs-focal]].

4. **[Wave 2 - restante]** #1358 (distinguir "stakeholder de capitulo" de "ponto focal do nucleo";
   `chapter_liaison` marcando diretores/VP como ponto focal) -> #1014 (convite signup direcionado p/
   aceitos sem conta, precisa SPEC) -> #485 (low: recorrencia flexivel + tz + GCal sync; decidir
   RRULE vs rows antes).

## Higiene / follow-ups vivos
- **#1170 residuo opcional (DDL):** redesenhar `_test_detect_inactive_with_threshold` com
  subtransacao-abort para tirar o `DELETE arm9 < 6 dias` amplo (landmine latente). So se quiser.
- **#1004 follow-up nao-LGPD:** 25 engagements terminados com `end_date` NULL (backfill opcional).
- **Leticia** pendente: reconectar em `/mcp/semantic` (client_id nao-UUID cacheado, fix client-side).
- **EPIC #1383** fecha a mao ~31/07 (wiki OK; falta so uso >= 2 semanas via `mcp_usage_log`).
- #1440 (rate-limit `/oauth/register`), #1403 (watch spec MCP 2026-07-28).
- Trap: `gh secret set` pelo shell `!` grava VAZIO - usar web UI. Branches: NUNCA deletar
  `legacy/original-main` / `work`.

## Lembretes de processo (CLAUDE.md)
- **Grounding**: todo numero em prompt de decisao / PR / commit / memoria vem de tool na MESMA volta.
- **Lane prepara, nao mergeia** - EXCETO autorizacao explicita do owner na sessao.
- **DDL**: `apply_migration` (nao `execute_sql`); `execute_sql` so p/ DML/read-only.
- **Phantom rows**: apos CADA apply_migration, checar `schema_migrations` por prefixo de data real
  (nao por `>= head` sintetico) e deletar por versao exata. N applies = N phantoms.
- **Testes DB-aware escrevem na PROD** (CI e `npm test` local usam a service_role do `.env`):
  qualquer teste que muta via RPC SECDEF DEVE limpar explicito (tx=rollback nao desfaz). Audit:
  `grep -rl "tx=rollback" tests/`. Ver [[reference-tx-rollback-not-honored-secdef-pollutes-prod]].
- **EF que manda e-mail = outward-facing**: nao deployar sem aval; deploy pelo Bash do Claude.
- Sem travessao longo em entregaveis.
