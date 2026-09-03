# Handoff 02/09/2026 (tarde) — quatro decisões fechadas, e o padrão que atravessou o dia

> **Nada aqui é medição.** Carimbado no fim da sessão main de 02/09. Re-meça antes de decidir:
> `gh pr list --state open` e `gh run list --json headSha,conclusion` respondem em dois comandos.

## Estado ao encerrar

```
main ......... 4486c46a
fila ......... 0 PRs abertas
PROD-AHEAD ... FECHADO — 12 migrations de 02/09 no banco, 12 arquivos na main, listas idênticas
```

Esta sessão continuou o handoff da manhã (`..._nove_merges_main_verde_cinco_decisoes_pendentes.md`).
Das cinco decisões que esperavam o dono, **as cinco foram resolvidas** — duas delas mudando de
natureza depois da medição.

## O que entrou

| commit | o quê |
|---|---|
| `95dfd287` | `anon` perde EXECUTE em `get_comms_to_adoption_funnel` e `resolve_default_gates` (#2149/#2150) |
| `a1c94196` | `business_case` no CHECK com a cadeia da diretriz + acervo de PI corrigido (#2119/#2151/#2154) |
| `4486c46a` | recusa no lock, 9 filiações, a tela acusa o VEP, guard p262 removido (#2156) |

Cinco migrations aplicadas e verificadas por consulta **nova** depois de aplicar, sempre com
antes/depois nas duas pontas e com controle que **podia** ter falhado.

## As duas decisões que MUDARAM depois de medidas

**A decisão 4 do handoff da manhã se dissolveu.** Ela dizia "`current_version_id` não avança na
publicação". Quem move o ponteiro é `trg_sync_current_version_on_publish`, que dispara no **LOCK**,
e **20 das 44 versões lacradas não têm `published_at`**. Medido contra `locked_at`: 14 documentos
com o ponteiro na última lacrada, 8 sem lacrada e sem ponteiro, **0 incoerentes**. Não havia defeito
de ponteiro. E o `v0`, que parecia rótulo vazio, é **deliberado** (#632: *"documento aprovado entra
como v0 real; a numeração de trabalho não migra"*). Quem estava desatualizado era a coluna `version`
— o lado oposto do que se supunha. Corrigido.

**A decisão do "conserto de origem" da filiação perdeu a premissa.** Eu ia consertar o `vep_sync`
para regravar quando o `expiryDate` mudasse. **Não existe `vep_sync` automático:** quem grava são
`verify_member_affiliation` e `verify_member_affiliations_bulk`, RPCs chamadas pela UI que exigem
`filiacao_director` ou `manage_member` e vedam auto-verificação. Um cron gravaria verificação **sem
verificador**, contornando esse controle — mudança de política, não conserto. A decisão virou: a
tela sinaliza, o humano autorizado clica.

## O item 5 que a manhã tinha classificado errado

O guard `p262-312-w4a` era "dívida congelada, trimar por higiene". Medido: ele estava **verde
afirmando que `policy` tem 5 portões**, e produção tem **3**. Passava porque lia o texto de uma
migration imutável. Não era inerte — comprava silêncio. Removido; base do #1932 de 202 → 201.

## ESPERANDO DECISÃO SUA

Nenhuma tem relógio.

1. **#2153 — o card do LinkedIn não tem imagem.** `linkedin` tem **0 de 50** em `thumbnail_url` e
   **0 de 50** em `cached_image_url`; instagram tem 42 e 70 de 87, youtube 92 de 92. Nenhum caminho
   de escrita jamais produziu esses campos para o canal. Decidido "fica na fila" em 02/09 — está
   aqui só para não sumir.
2. **#2152 — implementar o sinal foi decidido e feito; falta decidir se o cron diário
   `v4_notify_expiring_affiliations` também passa a avisar a divergência.** Hoje ele só notifica
   expiração.

## Ação pendente que NÃO é decisão

**A pós-condição do deploy da EF não foi verificada.** `sync-comms-metrics` foi de **v45 → v46**
(a v45 era de 03h38 UTC, e o commit da legenda `51c2f8bf` é de 14h12 — 10h34 depois). O deploy
verde prova que o código subiu, **não** que o extrator funciona contra a API real. A pós-condição
honesta é `count(caption)` do LinkedIn **subir de 1**, e isso só acontece no próximo sync (cron de
madrugada). Verificar amanhã, ou disparar o sync com a fila livre.

## Issues abertas ao encerrar

| # | estado | o que é |
|---|---|---|
| #2149 | fechada | ACL das duas RPCs |
| #2155 | fechada | guard p262 que afirmava 5 portões contra 3 reais |
| #2151 | **aberta** | acervo limpo e gate aplicado; fica pelo registro |
| #2152 | **aberta** | as 9 corrigidas e o sinal na tela; falta decidir se o cron diário também avisa |
| #2153 | **aberta** | imagem do card do LinkedIn (0 de 50 em thumbnail e cache) |
| #2157 | **aberta** | meu push direto na main; janela de bypass em **2/2** |
| #2158 | **aberta** | Agenda Viva no MCP: falta `reserve` |
| #2159 | **aberta** | auditoria de PII: os dois logs existem e não se cruzam |

### As três que nasceram no fim da sessão

**#2157 — bypass no limiar.** Pushei o handoff direto na main sem PR. Conta como 1 evento; com o
arranque de 30/08, a janela de 7 dias está em **2 de 2**. A política pede pausar merges quando o
limiar é atingido, e **um terceiro push direto ultrapassa**. Handoff e planning vão por PR.

**#2158 — Agenda Viva no MCP não tem `reserve`.** Surgiu de um pedido real no grupo (reservar 10 min
na pauta da Geral de 10/09). Medido: `reserve_agenda_block` existe no banco, executável por
`authenticated`, e tem **0 ocorrências** no manifesto e **0** na EF do MCP. A tool `agenda_blocks`
expõe `list`, `confirm` e `no_show` — **duas delas escrevem**. Então não é "rota indisponível" (a
escrita existe) nem só "restrição por desenho" (há lacuna real): a superfície cobre o *veredito* e
não a *intenção*. Falta decidir a autoridade de reservar para si × para terceiro.

**#2159 — a auditoria de PII já existe e não se cruza.** `mcp_usage_log` tem 2.862 linhas e 223
tools, com `member_id` em 95,7% — e **`auth_user_id` em 0 de 2.862**, coluna morta que descreve
exatamente a pergunta que se quer responder. `pii_access_log` tem 34.585 linhas com accessor e alvo,
mas o `context` é o nome da RPC, não o canal. Dá para responder "quem leu PII" e "quem chamou o
MCP", e **não** "qual credencial, por qual canal, leu PII de quem".

## Lanes

| lane | árvore | estado |
|---|---|---|
| `lane-video-shorts-21` | `.wt-campanha` | sem PR nem migration; retratou-se na #2142 e liberou a fila |
| `ai-pm-research-hub-0b` | nenhuma | confirmou o resíduo do funil; comprimiu o MEMORY.md para 199 linhas |
| `lane-cpmai-ea` | `.wt-cpmai` | TAP: aprovação **11/09**. A aba Draft já serve a M04 |

## O PADRÃO DO DIA, e ele é mais estreito que o da manhã

A leva da manhã foi *medir o proxy em vez da fonte*. A da tarde é uma volta a mais:

> **Presença não é efeito — e em quase todos os casos EXISTIA uma verificação, e ela passava.**

- o guard #883 afirmava a **linha** `REVOKE ... FROM anon` no arquivo; `anon` executava assim mesmo;
- o guard p262 afirmava **5 portões** para `policy`; produção tem 3;
- meu `replace` no `package.json` casou **0 vezes** e o JSON continuou **válido** — só a asserção
  que **contava** as inserções pegou;
- minha primeira injeção de defeito "reprovou" em **22ms**, no `import`, não na asserção;
- meu controle negativo numa migration bateu no `NOT NULL` **antes** de alcançar o CHECK: teria
  capturado a exceção errada e se declarado satisfeito;
- minha chamada a `latestFunctionCapture` não casou o `RESOLVED_RE` (vírgula e parênteses inline),
  então o guard leria a definição corrente e **ainda assim** seria contado como dívida.

Nas seis, um verde estava disponível e teria sido aceito. Registrado na #588 em duas levas.

O ratchet do **#1932 pegou o meu próprio trabalho duas vezes seguidas**, e nas duas o defeito era
real. É o portão da casa funcionando contra quem o mantém, que é o único teste que vale.
