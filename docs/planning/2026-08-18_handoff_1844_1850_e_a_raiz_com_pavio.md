# Handoff de 18/08: o CI que sobrevive à saturação, e a raiz do #1834 com pavio de 27 horas

> Sessão de 11:45 a 18:50 UTC. Todo número foi medido nesse intervalo. **Re-medir antes de usar.**
> Continua o handoff da madrugada: `docs/planning/2026-08-17_handoff_noite_1838_fechado_1834_reatribuido.md`

## Estado

`main` em **`8934564a`**. **Duas PRs abertas:** #1851 (conserto do CI, 8 verdes e 2 rodando) e
**#1849** (atualização do arranque, **travada** pelo mesmo defeito que ela documenta). Issues
abertas: **209**. Bypass: **1 de 2** na janela.

---

## O que fechou

- **#1845 mergeada sem bypass, 12 de 12 verde** — as 6 RPCs do #1838 destravadas, com leitura para
  qualquer papel do comitê e **escrita só para `evaluator`/`lead`**.
- **#1847 mergeada** — o arranque de 18/08.
- **#1834 fechada e retitulada** para *"status de candidatura sem carimbo próprio nem histórico, e
  escrita direta sem rastro"*. Item 1 entregue; **item 2 virou a #1848**.
- **Reparo 1 de 3 do #1850** aplicado (ver abaixo).

---

## 🔴 O achado da sessão: #1850 é a raiz do #1834, com pavio de 27 horas

Rodando o job de invariantes para validar o conserto do CI,
`U_active_person_has_primary_chapter_affiliation` passou de **0 para 1**. Eu havia medido 0 várias
vezes no mesmo dia.

### A cadeia, elo por elo

1. **17/08 13:04:19** — a candidatura virou `approved` dentro da janela das **152 linhas
   pré-existentes** escritas por **SQL direto com `service_role`**, a mesma da #1834.
2. **A aprovação não foi auditada.** A candidatura tem 4 linhas em `admin_audit_log`, todas de 04/08
   e 06/08, de convite. **Nenhuma da decisão.**
3. **Por isso a afiliação nunca foi semeada.** Só **uma** função escreve
   `member_chapter_affiliations` (`upsert_chapter_affiliation`), e ela tem **dois** chamadores:
   `set_my_entry_chapter` e **`approve_selection_application`**. Pular a canônica pula a semeadura.
4. **18/08 15:24:51** — a pessoa assinou o termo. O engajamento ficou ativo e
   `sync_operational_role_cache` recomputou o papel de `guest` para `researcher`, porque **o papel é
   CACHE derivado dos engajamentos**, não ato administrativo.
5. A promoção **removeu a exclusão** do invariante, e ele acendeu — **27 horas depois** do defeito.

### Duas correções que isso impõe

📌 **O #1834 listava TRÊS garantias que o bypass pula. São QUATRO** — a afiliação de capítulo é a
quarta, e passou despercebida porque só detona quando um ato sem relação remove a exclusão.

📌 **O trigger de histórico da PR #1843 tornou o bypass VISÍVEL, e não o tornou inofensivo.** Ele
registra a transição; não restaura o que a canônica teria feito. **Detectar não é reparar** — e eu
não fiz essa distinção quando entreguei.

### População em risco: 3 de 89, e uma ainda não detonou

| | candidaturas |
|---|---|
| aprovadas na janela de 17/08, com membro resolvido | **89** |
| **sem nenhuma afiliação de capítulo** | **3** |
| já promovidas (não-`guest`) | **2** |
| ainda `guest` — **pavio aceso** | **1** |

🔴 **No dia em que a terceira assinar o termo, o invariante acende de novo** — mesmo caminho, mesmo
atraso, provavelmente na PR de outra pessoa, e vai parecer flake sem ser.

### Reparo: 1 de 3, por decisão do PM

⚖️ **Decidido:** reparar **só** o caso de procedência verificada.

| caso | procedência | ação |
|---|---|---|
| `member_chapter = PMI-GO` | certificado emitido, **`affiliation_unverified = false`** | ✅ **reparado** |
| `member_chapter = PMI-DF` | certificado emitido, **`affiliation_unverified = true`** | ⏸️ **não** — semear tornaria alegação não verificada a fonte de verdade. **É esta que mantém o CI vermelho.** |
| ainda `guest` | **sem certificado** | ⏸️ **não** — não há fonte |

Reparo aplicado: `upsert_chapter_affiliation(person_id, 'PMI-GO', 'admin_import', true)`.
**Antes:** 0 afiliações, `members.chapter = 'Outro'`. **Depois:** 1 afiliação (`GO`, primária),
`members.chapter = 'PMI-GO'`. ⚠️ **Mudança visível** no perfil da pessoa.

⚠️ **`upsert_chapter_affiliation` NÃO audita.** O comentário na #1850 é o único rastro do reparo.

🔴 **A violação segue em 1, de propósito.** Quem violava nunca foi a reparada: o invariante exclui
capítulo fora do registro, e o dela era `Outro`.

📌 **Três tabelas, duas convenções para o mesmo conceito:** `chapter_registry.chapter_code` e
`member_chapter_affiliations.chapter_code` usam **`GO`, `DF`** (sem prefixo);
`members.chapter` usa **`PMI-DF`, `Outro`**. Foi por isso que minha primeira reconstrução do
predicado devolveu **zero linhas** enquanto o invariante contava 1 — comparei formatos diferentes, e
quase concluí que a violação era fantasma.

---

## PR #1851 — o CI passa a sobreviver à saturação

| chamada de `check_schema_invariants()` | tempo | resultado |
|---|---|---|
| SQL puro | **2,53 s** | — |
| PostgREST, 1ª | **60,9 s** | `PGRST003` |
| PostgREST, 2ª | **33,3 s** | sucesso |
| PostgREST, 3ª | **49,1 s** | sucesso |

A diferença inteira é **fila de pool**. Em repouso o PostgREST tem 6 conexões ociosas; sob carga
chegou a **15 ativas**, e ele desiste sozinho em ~61 s.

O conserto: helper com limite de espera e retentativa **apenas** em `PGRST003`, mais
`--test-concurrency=1` no `test:contracts:db` (a suíte irmã já tinha). **Efeito medido:**
`log-retention` foi de vermelho para **5/5**, com dois testes passando em **109 s e 116 s** — a 1ª
tentativa estourou e a 2ª funcionou.

### Dois números que eu errei e corrigi antes de enviar

1. ⚠️ **O limite.** Comecei com **20 s**, e uma chamada **saudável** leva **33 a 49 s**. Abortaria
   chamadas boas, trocando defeito de infraestrutura por defeito fabricado. Ficou **75 s**, acima
   dos ~61 s do PostgREST — abaixo disso o cliente aborta antes e **perde o sinal retentável**.
2. ⚠️ **O teto do job.** Baixei de 95 para 30 min e **reverti antes de commitar**: a premissa era
   "nenhuma saudável passou de 18 min", e **a retentativa deste PR invalida a premissa**, porque os
   dois arquivos rodam também na suíte grande. As duas mudanças juntas **matariam a corrida**.

### O que a #1851 NÃO resolve

A **causa** da saturação segue não identificada. A suíte roda contra **produção** e divide o pool
com tráfego real. A PR faz o CI **sobreviver**; não elimina. As saídas que atacam o mecanismo
(limitar concorrência de requisições, ou subir o `db-pool`) seguem abertas na #1844.

---

## Duas correções que publiquei na #1844

Registradas porque descartar errado é pior que não descartar:

1. 🔴 **"Não é pool travado" estava ERRADO.** Usei `pg_stat_activity`, que vê **backends do
   Postgres**, quando a pergunta era sobre a **fila do pooler**. Camadas diferentes: snapshot limpo
   da camada de baixo **não é evidência** sobre a de cima.
2. 🔴 **"É colisão de lane" também estava errado.** Identifiquei um contribuinte real e o tratei
   como **causa** sem testar o contrafactual. Rodei o job sozinho e ele falhou igual. O teste era
   barato e eu só o fiz depois. **Antes de propor conserto para uma concorrência, remova a
   concorrência e veja se o sintoma some.**

⚠️ E o experimento "solo" tinha um vício: rodei o `check-invariants` **1 minuto depois** de cancelar
um `validate` de 95 minutos, cujas requisições em voo não somem na hora.

---

## Próxima sessão

1. 🔴 **A entrevista de 18/08 23:00 UTC** — conferir se aconteceu e **marcar desfecho**. A de
   **19/08 21:30** é a seguinte. ⚠️ `mark` carimba `conducted_at` com a hora do REGISTRO.
2. **PR #1851** — mergear se verde. É a que melhora o CI de todas as outras.
3. **PR #1849** — travada pelo próprio defeito. Depois da #1851, re-rodar e mergear. Custo de
   ficar parada é baixo: o `MEMORY.md` já contradiz o ITEM 6 velho.
4. ⚖️ **#1850, duas decisões suas:** existe fluxo de verificação de afiliação (há o flag
   `affiliation_unverified`), ou o caminho é falar com a pessoa? E a `guest` sem certificado, qual
   fonte?
5. **23/08: re-medir o #1710** pelos dois caminhos (prazo 24/08, e a 3ª entrevista é no mesmo dia).
6. **#1848** ampliada pela #1850: detectar no ato da gravação **toda** garantia da canônica que o
   bypass pulou — a afiliação é a quarta.
7. Segue: funil (28/08), **#588 `[LL]` parado há 70 dias**, **#92** (118 dias, raiz da #1614),
   as 18 sem onda.

## Achados sem issue, que somem se ninguém abrir

- `mark` carimba `conducted_at` com a hora do **registro**: **16 de 99** já divergem, máx. **64 dias**.
- O envelope do `mark` relata `application_status` que **não gravou**.
- **`upsert_chapter_affiliation` não audita**, sendo a única porta de escrita da tabela que ancora a
  derivação de capítulo.
- **Duas convenções de código de capítulo** em três tabelas.
