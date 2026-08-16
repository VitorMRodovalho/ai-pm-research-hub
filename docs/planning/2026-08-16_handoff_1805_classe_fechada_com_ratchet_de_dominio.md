# Handoff — 16/08/2026: o #1805 fechou, e a classe ganhou um ratchet de domínio

> Sessão anterior: `docs/planning/2026-08-16_handoff_1801_classe_fechada_com_ratchet.md`
> Arranque desta: `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_1805_E_1780.md`
> Arranque da próxima: `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_1780_E_DIVIDA.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

⚠️ **Todo número abaixo foi medido em 16/08 e vários se movem sozinhos. Re-meça, não recite.**

## Estado ao fechar

`main` em **`924b7efd`** (PR **#1807**, squash, **12/12 checks verdes, sem `--admin`**).
Duas migrations aplicadas e verificadas: **`20260816040023`** e **`20260816040153`**.
**Zero PRs abertas no início. Zero alertas Dependabot. Zero bypass na janela de 7 dias.**

| issue | desfecho |
|---|---|
| **#1805** | **FECHADA** — os 3 casos da issue mais **1 que não estava na lista de ninguém** |

---

## A triagem mudou o tamanho e a natureza do problema

A issue nomeava 3 funções. A varredura saiu do **catálogo**, não da lista, e achou **4**.

E mudou a leitura de dois casos que a issue classificava como cosméticos. O predicado
`status IN ('open','active')` do relatório de consistência tem `'active'` **morto**, então valia
`status = 'open'` sozinho — e o comentário vivo do código dizia querer *"never alarm on closed
cycles"*. Só que entre `open` e `closed` o domínio tem **`evaluation`, `interview`, `decision`**,
que não são fechados e ficavam **fora do escopo inteiro**.

📌 **B e C eram o mesmo defeito**, não dois defeitos cosméticos: a intenção declarada era "ciclo em
andamento" e a implementação efetiva era "ciclo aberto".

---

## Antes → depois, por ensaio em transação abortada (o GP avança o ciclo)

Não é inspeção estática: é `UPDATE` no ciclo seguido de `RAISE EXCEPTION`, que aborta e devolve.

| cenário ensaiado | antes | depois |
|---|---:|---:|
| PERT — ciclo em `applications_open` | **0** ciclos | **1** |
| calibração semanal — ciclo em `evaluation` | **2** ciclos | **3** |
| consistência diária — ciclo em `evaluation` | **0** candidaturas | **81** |

Os três crons estão **ativos**: `recompute-pert-cutoffs-weekly` (seg 13:00 UTC),
`compute-ai-calibration-weekly` (seg 14:00 UTC), `selection-consistency-check-daily` (13:30 UTC).

⏰ **O gatilho é iminente, não hipotético:** `cycle4-2026` está `status='open'` com
`phase='evaluating'` e **45 candidaturas pontuadas**. No dia em que o GP avançar o *status*, as três
superfícies acima mudavam de lado.

---

## A quarta função, e por que ela não estava na lista

**`approve_selection_application`** comparava `role_applied` com `'coordinator'`, que não existe no
domínio (`researcher`, `leader`, `both`, `manager`). Ramo morto puro, **efeito zero** — os ramos
anteriores já cobriam `leader` e `researcher`, e `manager` segue coberto.

📌 Foi **separada em migration própria de propósito**: é a única função do caminho crítico de
aprovação, e uma correção cosmética não viaja junto com mudança de predicado. 137 `researcher`,
33 `leader`, 0 `both` hoje.

📌 **`both` NÃO ganhou ramo.** Cai no `ELSE` e vira `researcher`, como sempre caiu. Mudar isso é
decisão de produto, não limpeza de literal morto.

---

## O ratchet, e o alcance que ele NÃO tem

`_audit_state_literal_domain()` acha literal comparado a coluna cujo domínio é fixado por CHECK
quando o literal não está no domínio. Derivado do catálogo, não de lista de nomes.

**A condição de solidez é o dono único.** A ambiguidade de alias é sobre a **tabela**, e o nome da
coluna está no texto: quando o nome pertence a **uma única tabela** em `public`, alias nenhum muda a
resposta. São **91** colunas de estado nessa condição.

⚠️ **`status` fica FORA, declaradamente.** Existe em ~50 tabelas com domínios próprios; a varredura
textual devolveu **58 candidatos**, quase todos com o literal pertencendo a uma tabela vizinha. Os
dois casos de `status` desta issue entraram por **leitura do corpo**, e têm assert de texto no teste
em vez de ratchet. **Quem for varrer essa metade precisa resolver alias por consulta.**

**Linha de base ZERO, sem exceção a manter.** Cobertura medida: **262 pares, 38 colunas, 151
funções**. Provado não-cego: violação plantada em transação abortada levou 0 → 1, acusada como
`_tmp_1805_prova_do_guard.phase = open_apps`, e **nada persistiu**.

📌 O guard devolve **todos** os pares examinados com um booleano, não só as violações — senão lista
vazia seria indistinguível de guard cego.

---

## 🔔 Achado de passagem que a correção NÃO resolve

O cron de consistência avisa os **leads** do comitê dos ciclos em andamento. Medido hoje:
**3 leads na plataforma inteira, todos em ciclos FECHADOS**, e o `cycle4-2026` (o aberto, com 81
candidaturas) tem **zero**.

⚠️ Ou seja: mesmo com o escopo corrigido, **o alerta continua sem destinatário** até alguém receber
`role='lead'` no ciclo ativo. Isto é dado, não código — **decisão do PM**, e não entrou nesta PR.

---

## Os tropeços da sessão, que valem mais que o patch

1. 🔴 **O verificador leu a MINHA migration como "captura mais recente".** Extraí as capturas do
   repositório para diffar contra o corpo vivo, e o diff veio **vazio** — porque eu já havia escrito
   o arquivo novo em `supabase/migrations/`, e ele ordena por último. Um verificador que lê o
   diretório inteiro **inclui o artefato que está sendo verificado**. Corrigido com exclusão
   explícita do arquivo em teste.
2. ⚠️ **`replace_all` casa a string, não a intenção.** `selection_consistency_report` tinha **6**
   ocorrências do predicado; cinco com 4 espaços de indentação e **uma com 2**. A substituição em
   massa pegou 5 e ficou calada sobre a sexta. Só o diff contra o original mostrou. O teste agora
   **conta as 7 ocorrências** (6 no relatório + 1 no cron) em vez de checar presença.
3. 📌 **Não transcrevi corpo de função nenhum.** Os 5 corpos vivos foram provados idênticos às
   capturas do repositório por md5 normalizado, editados **como arquivo**, e a migration foi montada
   por concatenação. A transcrição ficou restrita à chamada do `apply_migration`, e foi conferida
   depois: **drift definitivo 0, suspeito 0, órfão 0**.
4. 📌 **Dividir a migration em duas reduziu o raio.** A parte 2 é 45% do texto e tem efeito
   comportamental zero; isolá-la manteve o caminho crítico de aprovação fora do alcance de um erro
   de transcrição na parte 1.

---

## Conferência

- **Drift após as duas migrations: `drifted_definite=0`, `drifted_suspect=0`, `orphans_true=0`** (1197 funções vivas).
- Teste novo: **9/9, zero skips**, com `.env`. Registrado nas **duas** whitelists.
- Suíte offline: **6428 testes, 0 falhas**, 713 skip (portão de DB), 52,7 s.
- Build verde (5m47s). `lint:client-scripts` verde. `npm run db:types` regenerado (a RPC nova entra).
- Arquivos locais renomeados para os timestamps de tracking; **sem fantasma, sem `migration repair`**.

---

## Aberto ao fechar

**#1710** (véspera 23/08, prazo 24/08 — re-medir pelos DOIS caminhos) · resto do **EPIC #1780** ·
**#1586** e o **funil de 28/08**, que só fecham com uso real · **#1592** · a metade `status` desta
classe, que segue sem varredura honesta · o alerta de consistência sem destinatário.
