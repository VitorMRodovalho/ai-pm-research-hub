# Handoff - #1656, uma escala no contrato de presença (10/08/2026)

> Arranque desta sessão: `docs/planning/2026-08-10_PROMPT_ARRANQUE_ONDA1_1656.md`.
> Handoff anterior: `docs/planning/2026-08-09_handoff_onda1_1653_1660_presenca.md`.

## Regra zero, de novo

Todo número aqui foi medido em **10/08/2026** e alguns se movem sozinhos (o conjunto de eventos
passados cresce todo dia). Re-medir com tool call na mesma volta em que o número entrar numa
decisão, num commit, numa issue ou numa pergunta ao PM.

---

## Decisões do PM nesta sessão

1. **Escala canônica: percentual 0-100, com o nome declarando a escala (`*_pct`).** As primitivas
   (`get_attendance_rate`, `get_attendance_engagement_rate`, `avg_rate`) continuam fração 0-1 -
   contrato que `p277-419-m3b` já afirmava.
2. **Alcance: todas as RPCs de exibição** (13, não as 6 que a issue listava).
3. **Migração aditiva**: a chave nova sai ao lado da velha, e a limpeza vira uma filha.
4. **O contrato do #1657 entra nas outras duas grades nesta mesma migration.**

## O achado que mudou o enquadramento da issue

A issue descreve "duas escalas ao acaso". Medindo, a convenção **já existia e estava testada**:
`*_pct` = 0-100, `*_rate` = fração. O defeito era que **8 RPCs publicavam número de exibição em
fração sob nome `_rate`**, obrigando 12 arquivos de front a multiplicar por 100, e **2**
(`get_tribe_stats`, `get_initiative_stats`) publicavam percentual sob o mesmo nome `_rate` - o par
que sustentava o coalesce `rate <= 1`.

A varredura por **chave publicada** (`regexp_matches(prosrc, '''([a-z_]*(?:rate|pct))''')`) achou
**13** funções; a varredura por nome de função tinha achado 12 e deixado `get_attendance_grid` de
fora, que é justamente a que serve a tela `/attendance`. E o coalesce não estava em 1 sítio: eram
**4**.

## Antes e depois, na mesma query

87 ativos, **66 comparáveis**, chamador impersonado por `request.jwt.claim.sub`:

| | chave velha `rate` | chave nova `rate_pct` |
|---|---:|---:|
| divergentes (de 66) | **27** | **0** |
| delta máximo | 0,50 pp | **0,0 pp** |

As duas colunas saem da **mesma execução**, então o "antes" não pode ter se movido entre as medições.

⚠️ Na primeira tentativa a medição devolveu **`comparaveis = 0`** - verde por vacuidade. A causa era
minha query, não a migration: o CTE que faz `set_config` não tem ordem de avaliação garantida em
relação aos CTEs que chamam as RPCs. Com `AS MATERIALIZED` e a dependência explícita
(`WHERE (SELECT count(*) FROM imp) = 1`), voltou a 66. **Conferir a contagem da população antes de
ler qualquer taxa.**

## O #1657 chegava a UMA das três grades

| grade | células `absent` antes | com linha real de falta | membros | detractor / at_risk |
|---|---:|---:|---:|---:|
| `get_tribe_attendance_grid` | 0 (o #1657 já valia) | 0 | 0 | 0 / 0 |
| `get_attendance_grid` (tela `/attendance`) | **97** | **0** | **50** | **2 / 6** |
| `get_initiative_attendance_grid` | **33** | **0** | **5** | 0 / 0 |

Depois: **0 `absent`**, 130 `unrecorded`, detractor/at_risk **0 / 0** nas três.

**A taxa não mudou**, e a prova é estrutural e medida: as 130 células migraram inteiras de `absent`
para `unrecorded`, e o denominador decidido (opção (a)) contém as duas. `absent` foi de 97 → 0 e
`unrecorded` de 0 → 97; mesmo conjunto.

## Como a migration foi construída (o método, não o resultado)

- corpo vivo × captura de migration por **md5 antes de tocar**: 13/13 batendo;
- **26 âncoras**, cada uma obrigada a casar exatamente **uma vez**, senão o script aborta;
- **prova de reversão**: desfazer as substituições reproduz o texto original byte a byte;
- as duas gamificações (≈220 linhas, 1 linha de mudança) foram aplicadas por `DO` + `RAISE` sobre
  `pg_get_functiondef`, em vez de reescritas;
- md5 vivo × arquivo local depois de aplicar: 13/13 sem drift.

⚠️ **Armadilha nova, e cara:** o extrator de blocos cortava o statement "até o próximo `;`". As
migrations de captura em massa (`20260681000000_p176_phase_b_drift_capture...`) são dump cru de
`pg_get_functiondef` e **não terminam os statements com `;`** - o corte engoliu metade da função
seguinte (`export_audit_log_csv` apareceu no meio do bloco de `exec_all_tribes_summary`). O tell foi
contar `CREATE OR REPLACE FUNCTION` no arquivo gerado: **14 para 13 funções**. O statement termina no
fechamento do delimitador `$$`; o `;` é opcional.

## Guard

`tests/contracts/1656-escala-unica-presenca.test.mjs`, 8 testes em três camadas:

- **A** estática sobre a captura mais recente, com ponteiro **derivado** de `loadLatestCaptures()`;
  comentários removidos antes de assertar.
- **A'** md5 do corpo **vivo** contra essa mesma captura - sem isso, A fica verde com o contrato
  removido do banco.
- **B** varredura do front (nenhuma `*_pct` multiplicada por 100; o coalesce não volta), com
  **controle positivo**. A primeira versão do regex acusava `const progressPct = (feitos/total)*100`,
  que é fração local e não chave do contrato - o controle positivo é o que separa "não achou porque
  não tem" de "não achou porque está inerte".
- **C** faixa medida no vivo onde o `service_role` alcança. As grades são gateadas em `auth.uid()`,
  então o `service_role` **não** as alcança: essa parte fica coberta por A + A'.

## Estado - FECHADO

- **PR #1716 mergeada e deployada.** `main` em **`f3657592`**, os **7 runs verdes** (inclusive
  `Deploy to Cloudflare Workers`). Branch deletado.
- **EF `nucleo-mcp` deployada** (só a descrição de uma tool) e verificada **no vivo**: a chamada MCP
  `attendance_report scope='cycle'` devolve `attendance_pct` ao lado de `attendance_rate`.
- Migration registrada como `20260810120000`; as **6 linhas fantasma** das chamadas de
  `apply_migration` foram apagadas; `NOTIFY pgrst` enviado.
- `npm test`: **6637 testes, 0 fail, 1 skip**. `check_schema_invariants()`: **43** invariantes,
  **0** violadas. Nenhum evento de bypass (merge saiu com CI verde).

### Quatro guards do repo estavam ancorados na FORMA, não no comportamento

Todos ficaram vermelhos por trabalho correto; **nenhum** apontava defeito nesta mudança. Custaram
cerca de uma rodada de suíte cada até separar "defeito meu" de "guard desatualizado":

| guard | congelava | correção |
|---|---|---|
| `p599-600` | `20260805000480` como "a" captura de `get_initiative_gamification` | ponteiro derivado de `loadLatestCaptures()` (**3º** caso desta classe) |
| `p277-419-m3-pr5b` | a expressão literal `Math.round(a.engagement.avg_rate * 100)` | afirma a nova forma **e** a inversa |
| `p277-419-m3-pr4` | `attendance_rate: Math.round(it.attendance_rate * 100)` | afirma a **ausência do clamp**, que era o ponto do teste |
| `577` | `sortKey="attendance_rate"` | a coluna continua sempre visível; mudou o nome da chave |

Mais o `ADR-0097 empty-statements`, esse **defeito meu**: apagar as 6 fantasmas e inserir a linha
certa à mão deixa `statements` NULL. Preenchido com `pg_get_functiondef` das 13 funções (83.666
bytes). ⚠️ **Melhor da próxima vez:** `UPDATE` a versão da ÚLTIMA fantasma em vez de
`DELETE`+`INSERT` — preserva os statements de graça.

**A lição vale mais que as correções:** um predicado que congela a *expressão* cobra pedágio em toda
mudança correta e não protege nada que a asserção de comportamento já não proteja.

## O que sobra da #1656 (a issue NÃO fecha com esta PR)

Entregues os itens 1 e 2 do "Correção esperada". Continuam abertos:

3. **nomear as três semânticas na tela** (engajamento × confiabilidade × combinada). É o item que
   responde à pergunta que originou a issue; sem ele, duas telas continuam mostrando números
   diferentes sem dizer que são perguntas diferentes.
4. **decidir o destino de `get_attendance_rate`** (a única sem elegibilidade).
5. **unificar "faltas consecutivas"** numa fonte só.

Mais a **limpeza**: remover `rate` / `overall_rate` / `avg_rate` / `attendance_rate` do jsonb depois
que este front estiver deployado.

## Achados colaterais registrados

- **Quarta fonte da métrica:** `src/pages/profile.astro` (linhas 1015 e 1385) calcula a própria taxa
  a partir de contagens locais, sem passar por nenhuma RPC. Fora do alcance deste contrato; material
  para o #1655.
- **`exec_all_tribes_summary` não tem consumidor** - nem em `src/`, nem em `supabase/functions/`.
  Recebeu a chave nova por consistência de contrato, mas é candidata a remoção. Declarar qual dos
  três casos é (imunidade, capacidade ausente ou contorno) antes de decidir.
- **`get_initiative_stats.attendance_pct`** carrega a fórmula antiga (`presenças / (membros ×
  eventos)`, 0 casas), que **não** é engajamento. A escala foi corrigida; a semântica é o item 3.

---

# Arranque do #1710 - a medição já foi feita, e ela mudou a ordem

**Passo 1 executado em 10/08** (o passo que a issue pede antes de qualquer código): as duas coortes
divergem, e a causa **não é** a que a issue supunha.

| medida (ciclo corrente) | valor |
|---|---:|
| eventos passados elegíveis | 53 |
| células da coorte do **selo** × da **grade** | 502 × 503 |
| **só no selo** (marcaria quem a grade não mostra) | **13 células, 3 pessoas** |
| **só na grade** (o selo nunca alcança) | **14 células, 2 pessoas** |
| eventos selados na base | **0 de 306** |

**A divergência é de superfície, não de regra.** Em todas as quatro fatias a causa é
`tribe_id IS NULL`:

- **só no selo:** `manager` + `researcher`, no ciclo, **sem tribo**. Elegíveis a `geral` e
  `lideranca` por `_attendance_eligible_events`, mas a grade é indexada por tribo.
- **só na grade:** `alumni`, fora do ciclo, sem tribo. Entram pelo ramo histórico da grade e o selo
  corretamente não os alcança - seguem `unrecorded` para sempre, o que está **certo**.

🔴 **O achado que muda o plano:** essas 3 pessoas são invisíveis em **TODA** grade - **0 de 3**
aparecem em `get_attendance_grid` (a geral também agrupa por `tribes[]`). O selo as alcança e o
painel as conta. Expor o botão hoje grava falta para quem nunca teve superfície onde ser marcado -
**pior que o defeito que o #1657 tirou**, porque ali a acusação era inferida e reversível pelo
registro, e aqui seria materializada e sem tela onde corrigir.

## Decisões do PM (10/08)

1. **Dar superfície primeiro.** O #1655 (linha na grade para quem não tem tribo) vira
   **pré-requisito** do #1710, não sucessor. Ordem nova: **#1655 -> #1710 -> #1654 -> #1218**.
2. **O selo é AUTOMÁTICO, com janela e aviso** a quem será marcado.

⚠️ **Consequência técnica da decisão 2, registrada na mesma volta:** no manual há um humano lendo
"isto vai gravar N faltas" por evento; no cron não há. Um erro de coorte que no manual é pontual, no
automático se propaga pelos **306** eventos de uma vez, e **não existe `unseal`**. Por isso a
decisão 1 deixa de ser preferência e vira **condição de segurança**, e o escopo do #1710 precisa
incluir:

- **dry-run**: uma rodada em que o cron **reporta** o que faria, sem escrever;
- **caminho de reversão** por evento (a RPC não tem);
- a janela (N dias) e o aviso prévio, que a issue já pedia.

## Pendências que não mudaram

- Reescrita de histórico (PII), **#334**, Onda 0.5, Dependabot: sem mudança.
