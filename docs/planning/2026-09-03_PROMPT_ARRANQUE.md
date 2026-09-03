# Arranque 03/09/2026 — o que ler, o que re-medir, o que decidir

> **Nada aqui é medição.** Foi carimbado no fim de 02/09 e envelhece sozinho.
> Antes de qualquer decisão, rode os quatro comandos da seção seguinte.

## Primeiro: re-meça (4 comandos, ~15s)

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh run list --limit 10 --json headSha,conclusion,status,name
gh issue list --state open --limit 30
```

Estado ao encerrar 02/09, para você comparar e **não** para acreditar:
`main 4093f1c0` · fila 0 PRs · PROD-AHEAD fechado (12 migrations de 02/09 no banco, 12 na main).

## ⚠️ Antes de mergear ou pushar qualquer coisa

**A janela de bypass está em 2 de 2** (#2157). Os dois eventos: o arranque de 30/08 e o handoff que
eu pushei direto em 02/09. A política (`.claude/rules/bypass-protocol.md`) pede pausar merges quando
o limiar é atingido, e **um terceiro push direto na main ultrapassa**.

Consequência prática: **tudo por PR, inclusive handoff e planning.** O audit roda segunda 10:00 UTC.

## Contexto que não está no código

Esta sessão fechou as **cinco** decisões que o handoff da manhã de 02/09 deixou com o dono. Duas
**mudaram de natureza** ao serem medidas, e é o tipo de coisa que se perde entre sessões:

- *"`current_version_id` não avança na publicação"* era **falso**. Quem move o ponteiro é o trigger
  que dispara no **LOCK**, e 20 das 44 versões lacradas não têm `published_at`. Contra `locked_at`:
  0 incoerentes em 22 documentos. E o rótulo `v0` é **deliberado** (#632) — quem estava desatualizado
  era a coluna `version`, o lado oposto do que se supunha.
- *"consertar o `vep_sync` para regravar"* perdeu a premissa: **não existe `vep_sync` automático.**
  Quem grava são RPCs da UI que exigem `filiacao_director`/`manage_member` e vedam auto-verificação.
  Um cron gravaria verificação **sem verificador** — mudança de política, não conserto.

## O que espera decisão sua (nenhuma tem relógio)

1. **#2158 — `reserve` na Agenda Viva do MCP.** Duas perguntas travam a implementação: reservar para
   si mesmo deve pedir `manage_event` como as outras ações (provavelmente não)? E reservar para
   terceiro — líder reservando pela tribo — é o mesmo caminho?
2. **#2159 — auditoria de PII.** `mcp_usage_log.auth_user_id` está em 0 de 2.862: **preencher ou
   remover**? Manter coluna morta que descreve a pergunta é a pior das três opções.
3. **#2152 — o cron diário.** `v4_notify_expiring_affiliations` (9h) hoje só notifica expiração.
   Passa também a avisar a divergência com o VEP?
4. **#2153 — imagem do card do LinkedIn.** Decidido "fica na fila" em 02/09; está aqui só para não
   sumir.

## Pendência que NÃO é decisão — verifique cedo

**A pós-condição do deploy da EF nunca foi verificada.** `sync-comms-metrics` foi de v45 → v46 em
02/09. O verde do deploy prova que o código subiu, **não** que o extrator funciona contra a API real
do LinkedIn. A pós-condição honesta:

```sql
SELECT count(*) AS linhas, count(caption) AS com_caption
FROM comms_media_items WHERE channel = 'linkedin';
```

Era **50 linhas / 1 caption** em 02/09. Tem de **subir de 1** depois do primeiro sync com a v46. Se
não subiu, o defeito é outro e a #2142 não fechou de fato.

## Prazos vivos

- **08/09** — publicação do webinar (lane `.wt-campanha`)
- **10/09** — Reunião Geral (é a pauta do pedido que gerou a #2158)
- **11/09** — aprovação do TAP do Grupo de Estudos CPMAI (lane `.wt-cpmai`)

## Lanes

`lane-video-shorts-21` (`.wt-campanha`) e `ai-pm-research-hub-0b`: sem PR, sem migration, sem
trabalho em voo ao encerrar. As duas se retrataram de achados próprios em 02/09 depois de re-medir,
e as duas liberaram a fila explicitamente.

## A regra da sessão, que vale para a próxima

> **Presença não é efeito — e em quase todos os casos EXISTIA uma verificação, e ela passava.**

Seis instâncias em um dia, registradas na #588: guard afirmando a *linha* do REVOKE enquanto `anon`
executava; guard afirmando 5 portões contra 3 reais; `replace` casando 0 vezes com o JSON ainda
válido; injeção de defeito "reprovando" em 22ms no `import`; controle negativo batendo no `NOT NULL`
antes de alcançar o CHECK; chamada ao helper não casando o regex que a isentaria.

O corolário prático: **conte, não confira presença.** E quando um controle passar, pergunte se ele
*tinha como* falhar.
