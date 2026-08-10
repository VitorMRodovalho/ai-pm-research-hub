# Handoff - #1655 (fatia), a grade ganhou linha para quem nao tem tribo (10/08/2026)

> Arranque desta sessao: `docs/planning/2026-08-11_PROMPT_ARRANQUE_ONDA1_1655_1710.md`.
> Handoff anterior: `docs/planning/2026-08-10_handoff_1656_escala_unica_presenca.md`.

## Regra zero, de novo

Todo numero aqui foi medido em **10/08/2026** e varios se movem sozinhos. Re-medir com tool
call na mesma volta em que o numero entrar numa decisao, num commit, numa issue ou numa
pergunta ao PM.

---

## Decisao do PM nesta sessao

**Alcance da fatia do #1655: as duas correcoes de RPC**, sem tocar na unificacao dos 4
componentes. A opcao foi levada com as duas causas ja medidas e a consequencia de taxa
declarada.

## O achado que mudou o enquadramento

O handoff anterior dizia que a divergencia selo x grade tinha **uma** causa (`tribe_id IS
NULL`). Medindo, sao **duas**, e a segunda e maior:

| causa | celulas | pessoas |
|---|---:|---:|
| `tribe_id IS NULL` (sem grupo onde aparecer) | 13 | 3 |
| 1 evento `geral` com `initiative_id` derrubado pelo filtro | 66 | 66 |
| **total so no selo, no ciclo** | **79** | **69** |

A segunda causa e o outro sintoma que o **proprio corpo do #1655 ja descrevia** ("a grade da
tribo derruba um evento `geral` que o painel conta"). A varredura anterior nao a viu porque
comparou as coortes **sem aplicar o filtro de eventos da grade**.

E o defeito 1 era pior do que "falta uma linha": a funcao publicava `summary.total_members =
83` e renderizava **66** no corpo. **17 pessoas entravam na taxa do painel e nao tinham linha
em grade nenhuma.**

⚠️ **O front ja tinha a superficie, e ela era INERTE por construcao.** `AttendanceGridTab.tsx`
montava um grupo "Cross-functional" a partir de `orphanRows`, mas as linhas sao achatadas de
`data.tribes[].members[]`: nenhuma podia ficar fora do `tribeMap`, entao o ramo nunca
disparava. Uma defesa sem consumidor que parecia cobertura. **A correcao era na RPC, nao no
componente** - e por isso unificar as 4 grades (o #1655 como escrito) nao entregaria o
pre-requisito do #1710.

## Antes e depois, mesma query

Chamador admin impersonado por `request.jwt.claim.sub`, com `AS MATERIALIZED` e dependencia
explicita.

| medida | antes | depois |
|---|---:|---:|
| `summary.total_members` | 83 | 83 |
| pessoas renderizadas no corpo | 66 | **83** |
| grupos na grade | 12 | 13 |
| ativos sem tribo com linha | **0 de 17** | **17 de 17** |
| coorte do selo sem tribo com linha | **0 de 3** | **3 de 3** |
| evento `geral` com `initiative_id` na grade | nao | **sim** |
| eventos na grade | 222 | 223 |
| `summary.overall_rate_pct` | 59,3 | 61,0 |

**A taxa se move, e foi decidido.** Das 66 que ja apareciam: **33 subiram, 16 desceram, 17
ficaram iguais**; maior alta **+20,0 pp**, maior queda **-16,7 pp**; media **74,46 -> 74,95**.
Sobe para quem esteve no evento e desce para quem nao esteve, porque `unrecorded` permanece no
denominador (opcao (a), decidida no #1656).

⚠️ **Correcao registrada:** ao levar a decisao ao PM, a estimativa dada foi "36 mudariam, media
78,4 -> 80,0". Aquilo era **simulacao** sobre o subconjunto com presenca registrada (49
pessoas, +1 no numerador e no denominador). O evento e `geral` e entra no denominador de
**todos** os elegiveis, entao o efeito real e mais amplo. Simulacao nao e medicao, e a
diferenca apareceu exatamente na direcao do sinal.

## As 17 pessoas que ganharam linha entram com media 6,8%

Nao e falta: sao **140 celulas `unrecorded`, nenhuma com registro real**, e 11 `present`, todas
com registro. A grade inteira segue com **0 celulas `absent`** - o contrato do #1657 nao foi
tocado. O numero baixo e a **ausencia de superficie ficando visivel**: ninguem nunca teve tela
onde marca-las.

🟡 **Item para o PM:** a coluna de taxa nao diz isso na tela. E material do item 3 do #1656
(nomear as tres semanticas), que continua aberto.

## O gate que a mudanca obrigou

Afrouxar o filtro por tipo tiraria a contencao de ADR-0105, que era **efeito colateral** dele -
e era a justificativa do allowlist do #785 (`_audit_secdef_initiative_reader_gates` marca
`references_gate` por regex sobre `prosrc`, inclusive dentro de comentario). `grid_events`
passa a chamar `public.rls_can_see_initiative(e.initiative_id)`, o gate canonico, que nao
depende do tipo do evento e cobre tambem os `tribo` que o filtro antigo ja deixava passar.
`get_attendance_grid` **saiu do allowlist do #785**.

Medido: a unica iniciativa `visibility='confidential'` tem 10 eventos, todos `1on1`, tipo que a
whitelist da grade ja excluia. A contencao antiga funcionava **por dado**, nao por estrutura.

## Como a migration foi construida (o metodo)

- corpo vivo x captura anterior por md5 **antes de tocar**: batendo (`c99e23aa...`, 10.103 bytes);
- **8 ancoras**, cada uma obrigada a casar exatamente **uma vez**, senao o script aborta;
- **prova de reversao**: desfazer as substituicoes reproduz o texto original byte a byte;
- depois de aplicar, md5 do corpo vivo == arquivo local (`e989bb80...`): **sem deriva de
  transcricao** (o `apply_migration` exige colar o SQL, e essa e a prova de que colou certo).

⚠️ **O extrator do bloco tem de ler o delimitador do proprio texto.** A primeira versao assumiu
`$$` e o arquivo usa `$function$`: o corte engoliu 4 funcoes seguintes. O tell foi contar
`CREATE OR REPLACE FUNCTION` no bloco extraido (**5** para 1 funcao).

✅ **Fantasma de tracking resolvido sem tocar na tabela:** o `apply_migration` registrou
`20260810140903`; bastou **renomear o arquivo local** para esse timestamp. Preserva os
`statements` de graca e nao mexe em `supabase_migrations.schema_migrations`. Melhor que o
`UPDATE` da ultima fantasma, e muito melhor que `DELETE`+`INSERT`.

## Guard

`tests/contracts/1655-grade-sem-tribo-e-evento-org-wide.test.mjs`, **9 testes** em 3 camadas:

- **A** estatica sobre a captura mais recente, ponteiro **derivado** de `loadLatestCaptures()`,
  comentarios fora antes de assertar, e **cada afirmacao com a inversa** (a forma antiga tem de
  ter sumido). Inclui a contagem exata dos **4** escopos `IS NOT DISTINCT FROM`: com igualdade
  simples o grupo sintetico apareceria vazio, que e verde por vacuidade.
- **A'** md5 do corpo **vivo** contra essa mesma captura.
- **B** front, com **controle positivo** (se `bestTribe` sumir do arquivo, o scanner acusa).
- **C** o gate exercido no vivo **nos dois sentidos**, com controle positivo (iniciativa aberta
  tem de **passar**) e recusa explicita quando a populacao confidencial for zero, para o teste
  nao passar por vacuidade.

**Mutacao verificada:** tirar o filtro do sentinel em `bestTribe` deixa a camada B vermelha.

## Estado - FECHADO (a fatia)

- **PR #1720 mergeada**, `main` em **`beaaab1f`**. CI: **7 de 7 runs verdes** na PR. Branch
  deletado. **Nenhum evento de bypass.**
- **Front deployado** (`Deploy to Cloudflare Workers` verde na main). Verificado **no bundle
  servido**: os dois caminhos novos estao vivos (`tribe_id!==<sentinel>` no `bestTribe` e
  `tribe_id===<sentinel>` na traducao do grupo).
  ⚠️ A primeira verificacao mediu no lugar errado: `curl` sem `Accept` no caminho do asset
  devolveu **HTML**, nao o JS, e a busca pela string deu 0. Conferir `content-type` antes de
  ler ausencia como fato.
- Migration registrada como `20260810140903`; `NOTIFY pgrst` enviado.
- `npm test`: **6646 testes, 0 fail, 1 skip** (eram 6637 antes dos 9 novos).
  `check_schema_invariants()`: **43** invariantes, **0** violadas.

---

# Arranque do #1710 - o pre-requisito caiu

**Re-medido depois do DDL**, ciclo corrente, 53 eventos:

| medida | antes da #1720 | depois |
|---|---:|---:|
| celulas **so no selo** (marcaria quem a grade nao mostra) | **13, em 3 pessoas** | **0** |
| celulas do selo | 502 | 502 |
| celulas renderizadas pela grade, no ciclo | 423 | 640 |
| celulas **so na grade** (o selo nunca alcanca) | 0 | 138, em 16 pessoas |

**Nao existe mais ninguem que o selo marcaria e a grade nao mostra.** O "Cuidados" do #1710
pedia exatamente essa conferencia antes de expor o botao, e agora ela passa.

As 138 celulas / 16 pessoas na outra direcao sao gente que a grade mostra e o selo **nao**
alcanca (fora de `current_cycle_active` ou fora dos tiers `researcher`/`tribe_leader`/
`manager`). Seguem `unrecorded` para sempre, que e a direcao segura. Nao mexer.

## Estado da base (10/08, re-medir)

| medida | valor |
|---|---:|
| membros ativos | 87 |
| ciclo corrente | `cycle_4` |
| linhas em `attendance` | 2.020 |
| faltas simples (`present=false`, nao justificadas) | 3 |
| **eventos passados elegiveis** | **301** |
| eventos com `roster_sealed_at` | **0** |
| linhas criadas pelo selo | **0** |
| celulas `absent` na grade geral | **0** |

⚠️ O handoff anterior falava em **306**; hoje a mesma contagem (nao cancelados, tipos de
presenca, `date < CURRENT_DATE`) da **301**. O numero se move nos dois sentidos - re-medir.

## Escopo, com a decisao do PM de 10/08

O selo e **automatico, com janela e aviso**. No fluxo manual ha um humano lendo "isto vai
gravar N faltas" por evento; no cron nao ha. Um erro de coorte que no manual e pontual, no
automatico se propaga pelos **301** eventos de uma vez, e **nao existe `unseal`**. Por isso:

- [ ] **dry-run**: rodada em que o cron **reporta** o que faria, sem escrever
- [ ] **caminho de reversao** por evento (a RPC nao tem)
- [ ] janela (N dias) e aviso previo a quem sera marcado
- [ ] superficie para selar, com confirmacao dizendo quantas faltas serao materializadas
- [ ] a grade mostra se o evento esta selado, e desde quando
- [ ] tool MCP para selar, na familia do #1588
- [ ] contagem de eventos selados publicada depois de uma semana

`seal_event_attendance(p_event_id)` esta viva, gateada em `manage_event`, idempotente
(`ON CONFLICT DO NOTHING`), e escreve `present=false` com `marked_by` do executor e
`notes = '[roster_seal] ...'` - esse carimbo e o que permite contar e reverter.

## Depois do #1710

1. **#1654** - fixar a coluna de nome nas 6 tabelas de presenca com scroll horizontal.
2. **#1218** - presenca orfa na reuniao de 08/07, residuo da Onda 0.
3. **#1655 continua aberta**: a unificacao dos 4 componentes (os 5 itens do "Correcao
   esperada"), mais o item novo registrado na issue - `src/pages/profile.astro` (1015, 1385)
   calcula a propria taxa de contagens locais, sem RPC.
4. **#1656 continua aberta** com 3 dos 5 itens: nomear as tres semanticas na tela, destino de
   `get_attendance_rate`, unificar "faltas consecutivas", mais a limpeza da chave velha.
5. **#1652** (epica) fecha quando as filhas fecharem.

## Pendencias que nao mudaram

- Reescrita de historico (PII), **#334**, Onda 0.5, Dependabot: sem mudanca.
- **`exec_all_tribes_summary` segue sem consumidor** algum.
