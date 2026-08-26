# Prompt de arranque - main, depois da noite de 25/08

Copie o bloco abaixo como primeira mensagem da nova sessao.
Escrito 25/08 22:56 BRT. Substitui o `2026-08-26_PROMPT_ARRANQUE.md`, que ja foi consumido.

---

Leia `MEMORY.md`, depois `docs/planning/2026-08-25_handoff_noite_1987_adr0023_e_fila_cruzada.md`.
⚠️ **Aquele handoff parou no meio da noite.** O que veio depois esta so aqui e nas issues.

**Estado medido em 25/08 22:56 BRT:** main `de8757f3`, **fila VAZIA**, zero bypass, arvore limpa,
CI da main verde (deploy incluido). Nao ha merge pendente.

## O que a noite entregou depois do handoff

- **#1991** fechou a **#1987** (Amendment C do ADR-0023: a duplicacao da escada e DELIBERADA).
- **#1992** fechou a **#1990** (`manage_event` resourceless).
- **#1993** levou o handoff e tirou a T6 de `RULES_IN_TRANSITION`.
- **4 aprovados foram notificados** por decisao do PM, e o e-mail saiu (00:55, 47s de atraso).
- **`pmi_id` do Rogerio Peixoto corrigido** de `85729` para `853729`, com auditoria propria.
- **Colheita de licoes registrada na #588** (`[LL]`), em 7 licoes agrupadas por onde mudam o framework.

## Cinco issues novas, todas com numero medido no corpo

| # | gancho |
|---|---|
| **#1998** | `plat_keys` exige `legal_basis='contract'` e **44 pessoas sao `consent`**: a tela acusa 5 que TEM contrato, e o denominador do painel esta subcontado |
| **#1997** | 9 de 20 sem `auth_id`. O Farhad e **lider**, tem 16 passos atribuidos, 0 feitos, e **nenhuma conta** |
| **#1995** | admin nao tem onde ver alocacao x termo x onboarding. O denominador do onboarding **varia por template** (3, 6, 7, 12 e 16 passos observados) |
| **#1996** | `No Memberships` do PMI vira `NULL`: negativa definitiva indistinguivel de "nao medi". **40 candidaturas** buscaram e vieram vazias |
| **#1999** | editar membro tem 2 RPCs com garantias diferentes, e a tela de lista grava `is_superadmin` **direto na tabela**, sem auditoria |

## Proximo passo sugerido

**#1998 primeiro.** Uma mudanca de predicado conserta 5 falsos positivos **e** o denominador do painel.
Antes/depois medivel, causa ja isolada, escopo pequeno.

⚠️ **Envolve `CREATE OR REPLACE FUNCTION`, entao entra na fila de serializacao.** A outra lane tem
worktree aberto em `/home/vitormrodovalho/projects/.wt-can-anywhere`. **Combine a ordem antes de
aplicar DDL**, ou repete o impasse cruzado que custou a noite de 24/08 e a de 25/08.

Depois: **#1997** (tem gente esperando), **#1995** (maior valor, mas e feature de verdade), **#1996**
(ingestao + backfill dos 40), **#1999** (higiene, sem pressa).

## ⚠️ O item humano desconfortavel

O e-mail que enviamos aos 4 manda **acessar `/onboarding`**. O Farhad **nao tem conta** e nao consegue
abrir essa tela. A medicao que expos isso veio DEPOIS do envio. Se ele responder ao e-mail ha caminho;
se nao, ele fica cobrado sem saida. **Ele tambem tem duas candidaturas, uma `approved` e uma
`rejected`** - confira qual vale antes de criar o acesso.

Medido 2h depois do envio: **0 de 4 leram**. Nao conclua nada disso ainda, e cedo.

## O que tem relogio

- ⏰ **27/08 08h40 BRT: o selo de presenca grava** (#1948). Decisao mantida: gravar as 77 e corrigir
  depois, em **3 passos, ou os tres ou nenhum**. Efeito 77 → 66. O cron dispara sozinho.
- 🆕 `operational-role-reconcile-daily` (`jobid 90`, `4 0 * * *`) rodou pela primeira vez em 25/08
  21:04 BRT. Confira `admin_audit_log` por `members.operational_role_reconciled`: ele **so grava
  quando houve mudanca ou erro**, entao **ausencia de linha e o esperado**.
- ⏳ Radar Tecnologico 13/07 segue o unico item de presenca aberto.
- ⏰ **28/08** funil · **09/09** retencao · **30/09** anonimizacao.

## Numeros que SE MOVEM, nao recite

Medidos 25/08 22:56 BRT, e dois ja tinham mudado em poucas horas:

| medida | valor | observacao |
|---|---:|---|
| `volunteer` ativo com `legal_basis='contract'` | **73** | era 71 as ~21h |
| idem, `consent` | **44** | |
| ativos sem tribo | **30** | era 28 as ~21h |
| A3 violacoes | **0** | |
| backlog | **66 high · 130 medium · 58 low · 3 sem prioridade** (257) | |

⚠️ **`gh issue list --limit N` trunca em silencio.** Com `--limit 200` o backlog "deu" 62/97/38, que e
o teto do comando, nao o backlog. Use limite acima do total conhecido e confira se bateu no teto.

## Armadilhas medidas na noite de 25/08

- **Guard de CODIGO verde deixa o DOC normativo apodrecer.** O ADR-0023 listava 11 degraus contra 12
  vivos por 3 meses, com a CI verde o tempo todo, porque nenhum guard le `.md`.
- **Injecao que erra o alvo prova o CONTRARIO.** Injetar fora da lista que o guard percorre da verde,
  e verde ali quase foi lido como "a assercao nao pega".
- **Uma assercao para duas causas mente numa delas**, e a mensagem empurra para afrouxar gate correto.
- **Script de edicao atomico POR ARQUIVO nao e atomico ENTRE arquivos**: o primeiro ja gravou quando o
  segundo abortou por acento no ancora. Asserte TODOS os alvos antes de QUALQUER escrita.
- **Namespace de memoria e compartilhado entre lanes**: as duas gravaram a mesma licao com nomes
  diferentes. Procure por CONTEUDO antes de criar arquivo novo.
- **Detector apontado para o sintoma:** vigiei "a main andar" quando o que travava era a **decisao de
  mergear**. Vigie a PR virar `CLEAN`.
- **Modo de entrega decide se o aviso ALCANCA.** `digest_weekly` e in-app: para quem nao tem conta,
  nunca chega, e o contador de "avisado" sobe do mesmo jeito.

## Higiene

`MEMORY.md` em **24.733** de 24.985 (folga **252**, era 865 no inicio do dia). **Aperta.** A proxima
sessao que gravar duas licoes com ponteiro estoura. O mecanismo: encurtar linha do READ-FIRST para
gancho e mandar o integral para o arquivo-topico ou para `MEMORY_ARCHIVE_INDEX.md`. As licoes desta
noite entraram todas em arquivos-topico **existentes**, com zero linha nova de indice.
