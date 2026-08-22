# Handoff 22/08 (tarde) — a main reparada, e o guard que mede texto morto

**Sessão:** 22/08, a partir do handoff da madrugada. `main` saiu de `a3c2f116`, chegou em `384386d4`.
**Fila:** entrou vazia, saiu vazia. **2 PRs, zero bypass.**

---

## 1. A primeira coisa que fiz foi derrubar a urgência do handoff anterior

O handoff da madrugada abria com **"AÇÃO PENDENTE E URGENTE"**: o commit `9e15d73c` não estaria
em nenhum remoto, e a DDL viva em produção existiria em **um único disco**.

Medi antes de agir. `git branch -a --contains 9e15d73c` devolvia
`origin/lane/video-reunioes-e-shorts`. O remoto estava em `f0d8eafb`, que o **contém**. A
afirmação era falsa quando foi escrita, e a urgência não existia.

Depois disso a lane teve o histórico **reescrito** (`ae937c4b`) e aí sim `9e15d73c` morreu -
sucessor `3d4bd280`, mesmo assunto, mesmo conteúdo. **Duas afirmações diferentes, mesmo sintoma
aparente.** Anotado na #1934.

---

## 2. O que estava realmente quebrado: a main, em dois checks

| check | antes | depois |
|---|---|---|
| `Schema Invariants (ADR-0012 B10)` | `fail 3` de 76 | **success** |
| `DB Types Drift (#1410)` | `can_org`/`can_org_by_member` ausentes | **success** |

Causa única: **três versões vivas em `schema_migrations` sem `.sql` na main** -
`20260822032921`, `20260822033913`, `20260822120649`. O handoff anterior falava em **duas**; eram
três. A terceira entrou às 12:06 daquele mesmo dia, depois de o handoff ser escrito.

O portão required estava **verde** o tempo todo: a A2 (#1914) fez o trabalho dela e a fila nunca
congelou. Isto reparou o **relatório**, não um bloqueio.

Landou em **#1931** (`3e4ac649`). Main verde de ponta a ponta, deploy incluído.

---

## 3. O cabeçalho que não podia entrar na main

O terceiro arquivo se chamava `..._ghsa_jpq5_...` e suas **29 primeiras linhas** transcreviam a
**cláusula SQL exata** do buraco cuja **correção de raiz continua aberta**, num advisory ainda em
**draft**. Repositório público.

Renomeei o arquivo e reescrevi o cabeçalho. Por que isso é inerte para os guards, verificado e não
presumido:

- **ADR-0097 casa por VERSÃO**, nunca por nome (`base.split('_')[0]`, `rpc-migration-coverage.test.mjs:303`).
- **O cabeçalho fica fora de qualquer bloco `CREATE FUNCTION`** (o primeiro começa na linha 36),
  logo não entra no `prosrc` que o Phase C mede.
- **Prova:** `md5` do trecho `CREATE FUNCTION` em diante é **idêntico** ao da lane
  (`6d0c693ed12c193948100746e2fd36bb`), e o Phase C passou.

**Resíduo, e é decisão do PM:** sobra 1 ocorrência de `GHSA-jpq5` (ID parcial) num comentário
**dentro** de `board_write_authority`, descrevendo comportamento **já corrigido**. Tirá-la exige
re-aplicar a função em produção, porque `board_write_authority` **não** está no allowlist do
Phase C: editar o comentário criaria drift novo. Achei o preço alto e parei.

⚠️ **Antes de mergear a lane: apagar a cópia dela de `20260822120649`.** Senão a main fica com
**dois arquivos para a mesma versão** e o Phase C passa a ter dois candidatos para as mesmas 6
funções.

---

## 4. Três armadilhas que quase passaram

**(a) O primeiro verde que tirei era vazio.** `npm run test:contracts:db` deu **`fail 0`** - e as
três que eu queria medir apareceram com `﹣`, não `✔`. Foram **puladas**. Pós-A2 elas só rodam com
`DATA_INVARIANT_GATE=1`. Com a variável: **76/76, zero skip**, o mesmo número que a CI roda.
📌 **Confira o TOTAL, não o `fail`.** 72 contra 76 era o sinal.

**(b) A CLI local não é a CLI da CI.** `npm run db:types` usa a que estiver instalada (**2.115.0**);
`gen-types-drift.yml` pina **2.109.0**. Gerar com a errada produz **drift falso**. Gerei com
`npx supabase@2.109.0` e o diff saiu **+8 linhas**, só as duas funções novas.

**(c) Landar a captura deixou 4 testes estruturais vermelhos, e os 4 estavam certos.**
`rpc-acl.test.mjs` casava o literal `can_by_member`, e **`can_org_by_member` não o contém**: o
guard reprovava porque a migration tornou o portão **mais estrito**. Ampliei para
`can(?:_org)?_by_member` e **injetei o defeito para provar que não afrouxei** - removendo o portão
de `admin_get_member_details`, reprova em 2 testes. Verde sem essa prova não valeria nada.

---

## 5. O achado da rodada: 95 guards medem texto que a produção não executa (#1932)

Eu ia reportar que `admin_list_member_consents` não tinha guard. **Estava errado** - tem, o
`568-consent-records-lgpd-read.test.mjs`. Concluí ausência por procurar só na lista `LGPD_RPCS`,
num arquivo. Mesma classe da #1926, de novo.

E a verificação virou o achado. Aquele guard lê um **arquivo de migration fixado**
(`20260805000130_...`), não a captura mais recente. Ele afirma
`IF NOT public.can_by_member(v_caller_id, 'view_pii')` com a mensagem *"admin read gated on
view_pii"* - **linha que a produção não executa mais**. Segue verde. Se a migration tivesse
**afrouxado** o portão, teria ficado verde igual.

| medida | valor |
|---|---|
| testes que fixam migration por caminho | **294** |
| pares (guard, função) com definição mais nova em migration POSTERIOR | **160** |
| guards distintos nessa condição | **95** |

**Não são 160 buracos** - são 160 pontos sem contato com a definição vigente. Fixar não é errado
para "esta migration entregou X"; é errado para afirmar **invariante corrente** de
segurança/LGPD/autoridade. Recomendação na issue: guard-do-guard primeiro (barato, produz a lista
exata), depois migrar por lote começando por PII/autoridade.

---

## 6. O que fica em aberto

| item | estado |
|---|---|
| **#1932** | novo. 95 guards fixados em captura vencida |
| **#1925** | **decisão do PM**, inalterada. `check_schema_invariants` no required depende de `CURRENT_DATE` |
| **#1910** | a classe segue aberta; a instância de 22/08 está fechada |
| **resíduo `GHSA-jpq5`** | 1 ocorrência dentro de `board_write_authority`; sair exige re-aplicar a função |
| **lane de vídeo** | `ae937c4b`, 15 commits, sem PR, CI nunca rodou. Apagar a cópia de `20260822120649` antes de mergear |
| **#1710** | vence 24/08, **re-medir em 23/08** |

---

## 7. Lições gravadas na memória

- `reference-invariante-de-dado-so-conta-com-data-invariant-gate` (nova) - `fail 0` local não prova
  invariante nenhuma sem `DATA_INVARIANT_GATE=1`.
- `reference-guard-fixado-em-migration-afirma-texto-morto` (nova) - cobertura tem **duas**
  perguntas: existe guard, e ele aponta para a captura mais nova?
- `reference-db-types-faz-no-op-silencioso-...` (atualizada) - o script **não pina** a versão da
  CLI; leia o pin do workflow antes de gerar.
