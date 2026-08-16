# Handoff — #1822, a coluna de estado sem domínio declarado

> Sessão de 16/08/2026, noite. Anterior: `2026-08-16_handoff_1812_1813_retencao_e_destinatario.md`.
> Arranque que a originou: `2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_905_E_1780.md` (ITEM 4).

---

## O que entrou

**#1822 fechada pela PR #1823.** Migration `20260816225830`, aplicada com **zero PRs abertas**.
Entra `_audit_undeclared_state_domain()`, o terceiro ratchet da classe do #1805 / #1809 — e o único que
**não olha para função nenhuma**. Olha para o catálogo.

O PR **não declara domínio em coluna alguma**. Mede, fixa a base e impede que ela cresça.

## Como apareceu, que é a parte que vale guardar

O ITEM 4 do arranque mandava, se fosse atacar o resto da classe, começar medindo. Medido:

**O ponto cego declarado do #1809 tem 377 pares (função, coluna) em 294 funções**, contra 491 cobertos.
Ele se decompõe em:

| fatia | pares | o que é |
|---|---|---|
| nenhuma relação com domínio | 91 | já inerte, o `WHERE` final não produz linha |
| **uma só relação com domínio** | **48** | parecia recuperável sem parser |
| 2+ relações com domínio | **238** | ambiguidade real |

**O atalho dos 48 está morto, e a prova é dura.** Relaxar o `solo` para contar só relações que carregam
domínio devolveu **51 violações e zero defeitos**. A resolução por `min(reloid)` atribui o literal à
tabela errada: `type = 'selection_approved'` foi debitado de `certificates`, e `kind = 'volunteer'` de
`member_emails`. A causa foi conferida no catálogo em vez de suposta — `notifications.type` e
`engagements.kind` **não têm `CHECK` nenhum**, então sobrava só o homônimo com domínio para levar a culpa.

O `count(DISTINCT reloid) = 1` do #1809 é **justamente o que protege contra isso**: ele conta todas as
relações, não só as com domínio, e é por isso que a função ambígua sai da cobertura em vez de ser
resolvida errado. **O resto daquela classe só sai por resolução por STATEMENT mesmo** — 238 pares.

E a medição expôs a terceira face: onde **não há domínio declarado**, nenhum dos dois ratchets alcança.

## Números, todos medidos em 16/08/2026

| fatia | colunas |
|---|---|
| examinadas | **270** |
| com domínio declarado | 208 |
| sem domínio, declaradas por `FK` | 6 |
| **base do ratchet** | **56** (44 tabelas) |

Universo derivado do catálogo, nunca de lista de nomes: coluna textual (`text`/`varchar`/`bpchar`) de
tabela `public` (`relkind` `r`/`p`) cujo **nome** carrega domínio em pelo menos uma tabela — 123 nomes.

Amostra do que está sem guarda, com a forma do dado:

| coluna | linhas | valores distintos |
|---|---|---|
| `notifications.type` | 6.671 | 56 |
| `gamification_points.category` | 3.170 | 27 |
| `persons.state` | 129 | 22 |
| `members.state` | 128 | 20 |
| `volunteer_applications.state` | 143 | 14 |
| `campaign_recipients.status` | 848 | 1 |

## Três decisões de predicado, todas medidas

1. **Domínio conta nas DUAS formas que o Postgres imprime.** A igualdade simples a um literal é domínio
   de tamanho 1: `event_guest_certificates.type` é `CHECK ((type = 'event_participation'))` e saía da
   base indevidamente. Só `= ANY (ARRAY[...])` não basta.
2. **`CHECK` que restringe FORMA ou CONDIÇÃO não é domínio.** `admin_audit_log.action` tem regex de
   formato mais comprimento — é por isso que a varredura do #1812 pôde escrever `data_retention.sweep`
   à vontade — e `engagements.kind` tem duas condicionais que citam kinds sem limitar o conjunto.
   Excluir por "tem `CHECK` qualquer" tirava 4 colunas da base sem nada estar declarado.
3. **O trigger de tabela é devolvido, mas NÃO entra no predicado.** Trigger é sinal de tabela, não de
   coluna, e não prova que aquela coluna é validada. Se contasse, a base cairia quando a tabela ganhasse
   um trigger não relacionado — progresso aparente sem nada guardado. 21 das 56 estão nessa situação.
   (A primeira contagem desta sessão foi 34 justamente por incluir esse sinal; a base honesta é 56.)

## Provas

- **O guard fica vermelho**, em transação abortada: base **56 → 58** ao plantar tabela com `status` e
  `visibility` (+2 exatos), e **58 → 57** ao declarar domínio em `pilots.status`, que sai da base. Nada
  persistiu (`to_regclass` nulo, base de volta a 56).
- **Lista vazia é distinguível de cegueira**: devolve as 270 examinadas com booleano, e o teste assere
  piso de cobertura (≥240 examinadas, ≥180 com domínio, ≥100 nomes).
- **Drift `0/0/0`** depois de aplicar; `live_count` 1201 → 1202, zero órfãos.
- Suíte offline **6482 testes, 0 falhas**; arquivo novo com `.env` **8/8, zero skips**; build `Complete!`.
- **43 invariantes, zero violações** (medido no início da sessão).

## Aberto, para a próxima

- **A triagem das 56 é decisão do PM.** Nem todas devem ganhar `CHECK`: algumas são legitimamente
  abertas (`admin_audit_log.action` é vocabulário que cresce), e declarar domínio sobre dado vivo tem
  risco próprio — a primeira tentativa do ensaio bateu em linha de `pilots` fora do domínio, que é a
  lição do #1587 em miniatura. A lista das 56 sai de `_audit_undeclared_state_domain()`.
- **O resto da classe do #1805/#1809 são os 238 pares**, e exige resolver por STATEMENT (qual tabela
  cada `UPDATE`/`DELETE`/`FROM` alcança). O atalho barato já foi ensaiado e não existe.
- 📌 **A varredura `data-retention-sweep-daily` estreia às 04:25 UTC de 17/08** e ainda não tinha
  rodado quando esta sessão fechou. Conferir: `get_lgpd_cron_health` impersonado sai de `never_ran:true`,
  e `admin_audit_log` ganha linha `action = 'data_retention.sweep'` com `affected_total = 0` (nenhuma
  política morde antes de 09/09). Falha só pinta o painel de vermelho depois de **2 dias**.
- Os demais itens do arranque seguem como estavam: **#1710** re-medir em 23/08 (prazo 24/08), o portão
  legal **R1–R5 do SPEC #905** (prazo 30/09) é decisão de fora da engenharia, **#1814** sem urgência
  (primeira mordida 2028), e o resto do **EPIC #1780**.
