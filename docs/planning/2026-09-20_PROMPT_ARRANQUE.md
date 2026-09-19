# Prompt de arranque - sessão seguinte à de 19/09

> # 🛑 LEIA ISTO ANTES DE USAR AS PRIORIDADES ABAIXO
>
> **As 8 verticais e a tabela de prioridades deste documento estão SUPERADAS.** Elas foram
> derivadas das ~40 issues tocadas recentemente, não do corpus. O dono recusou, e com razão: é
> amostra por recência apresentada como mapa temático. Este documento adverte contra esse erro
> na seção 5 e o comete na seção 3.
>
> **Ele fica no repositório de propósito**, com este aviso, porque o erro e a correção valem mais
> juntos do que o registro limpo.
>
> ## Por onde arrancar de verdade
>
> 1. **Plano aprovado:** `~/.claude/plans/floating-kindling-teacup.md`
> 2. **Dados já coletados e verificados:** `~/.claude/backlog-recon-2026-09-20/ESTADO.md`
>    (fora de repo git de propósito: contém corpo de issue de trackers privados)
>
> ## O que a medição corrigiu
>
> | este documento diz | a medição diz |
> |---|---|
> | 390 issues abertas | **435**, no escopo do Núcleo, em **6 repositórios** |
> | 8 verticais que eu inventei | o repo **já tem** taxonomia de lanes: rótulos `onda:*` |
> | 185 de 390 com PR mergeada | a janela tinha **400 de 1123 PRs**: eu via 36% do universo |
> | wiki dentro de "camada de conhecimento" | wiki é **repositório próprio**; a lane não é rastreada por issue |
> | não menciona | lane de **domínio e site do PMI-GO** |
> | não menciona | **33 issues** no repo v2, que são o que trava o passo 5 da #2370 |
>
> ## Estado já medido, não refazer
>
> - **Coleta conferida contra a contagem autoritativa do servidor, repo a repo. Todos bateram.**
> - **Avanço:** 209 sem PR · 98 tocada (1 PR) · 128 trabalhada (2+) · soma **435** ✔
>   Nenhuma faixa vazia nem total, logo a faixa discrimina.
> - **Checkbox não mede avanço:** 597 caixas, **0 marcadas**, com controle positivo provando que o
>   instrumento acha caixa marcada. Não reintroduzir esse sinal.
> - **O resíduo foi medido e é 222.** O classificador por título decide 213 sozinho (casa
>   exatamente um tema) e deixa 222 para julgamento (87 sem tema + 135 ambíguas). Classificar pelo
>   corpo resolve cobertura e **destrói** discriminação: 5,4 temas por issue.
>   ⇒ **222 itens de julgamento com taxonomia fechada justificam o fan-out.** Retomar em B2.
>
> ## Uma decisão espera por você
>
> 4 dos 6 repositórios do escopo são privados e o maior é público. Proposta: o documento de
> reconciliação completo vai para o tracker **privado**, e no repositório público fica só a parte
> que é dele, mais um ponteiro sem conteúdo.
>
> ## Primeiro comando da sessão limpa
>
> ```bash
> cat ~/.claude/backlog-recon-2026-09-20/ESTADO.md
> ```
>
> ---


> **Nada aqui é medição viva.** Carimbado em 19/09/2026 ~15h50 UTC.
> **Re-meça antes de decidir.** Repositório público: não nomeia o repositório privado
> envolvido na #2370 nem identificadores de conta. Esses vivem na memória privada
> `project-relogios-vivos-agosto-2026`.

## 0. Leia isto primeiro, em 30 segundos

```
main            3009e16f          (produção alinhada, /api/version confirma)
PRs abertas     0
jobs em voo     0
issues abertas  390
```

**Comece por:** re-medir as quatro linhas acima. A fila é relógio, não fato.

```bash
git fetch origin && git rev-parse --short origin/main
curl -sS https://nucleoia.vitormr.dev/api/version
gh pr list --state open --json number --jq 'length'
gh run list --limit 30 --json name,status --jq '[.[]|select(.status!="completed")]|length'
```

⚠️ **Não conte issues com `--limit N`.** Se a resposta for exatamente N, ela foi truncada.
Use `gh api "search/issues?q=repo:OWNER/REPO+is:issue+is:open&per_page=1" --jq .total_count`.

---

## 1. O que FECHOU em 19/09

| # | o que | como fechou |
|---|---|---|
| PR #2375 | Credly sync afirma ENTREGA no dado, não 200 na conexão | mergeada, exercida |
| PR #2376 | o passo que tratava o timeout morria no timeout (`set +e`) | mergeada, exercida |
| PR #2377 / #2379 | handoff de 19/09 + adendo | mergeadas |
| #2378 | acesso do Instagram expirava em 2026-09-26 | **prazo eliminado**, não adiado: token de System User, `data_access_expires_at` NULL |
| #2380 | CI Validate vermelho na `main` | re-run verde; era o flake da #2343, não o conteúdo |
| #2381 | produção atrasada em relação à `main` | deploy disparou após o verde; `/api/version` = `3009e16f` |
| #2370 passos 1-4 | secret alinhado, 200 medido, 4 workflows do outro repo desativados, Credly consertado | **exercidos**, não só escritos |

## 2. O que ABRIU em 19/09, derivado da investigação

| # | vertical | por que existe |
|---|---|---|
| **#2382** | Comunicação | LinkedIn vence **2026-10-27**; ter refresh token não prova que o refresh roda (em agosto expirou e ficou 4 dias parado) |
| **#2383** | Comunicação | canal `newsletter` tem **1 linha na vida**, de 2026-03-08: nunca começou, e a tela não distingue isso de quebrado |
| **#2384** | Comunicação / CI | `Comms Metrics Sync` com 29 verdes em 30 dias sem chamar a EF, e o feed que ele espera não existe |

---

## 3. Verticais de trabalho

> A fila tem **390** issues abertas. As verticais abaixo organizam o **conjunto de trabalho
> recente** que passou por esta sessão e pelas anteriores, não a fila inteira. Tratar esta lista
> como exaustiva é o erro que ela mesma adverte.

### V1. Sincronizações, CI e deploy
*A vertical que mais mordeu hoje.*

| estado | # | item |
|---|---|---|
| 🟡 pipeline | **#2370** | passos 1-4 fechados. Restam: **passo 5** (arquivar o repo abandonado) e a decisão sobre o Credly com **dois caminhos vivos** |
| 🔴 aberto | **#2343** | `browser_guards` intermitente (`workerd-nao-resolve-BaseLayout`). **Mordeu na `main` hoje** e levou o Deploy junto |
| 🔴 aberto | **#2255** | o portão de deploy fica `skipped` em silêncio quando o CI Validate falha. **Segundo caso documentado hoje**, janela de ~2h30 |
| 🔴 aberto | #2340 | serialização do banco não cobre o eixo suíte-local × CI |
| 🔴 aberto | #2322 | smoke de rotas falha 1 em 5 |
| 🔴 aberto | #2271 | 45 Edge Functions sem portão nem carimbo de publicação |

⇒ **#2343 e #2255 são a mesma dor vista de dois ângulos**: um flake que não bloqueia PR mas para a publicação, e um portão que não avisa quando isso acontece. Resolver os dois junto vale mais que separado.

### V2. Comunicação e redes sociais

| estado | # | item |
|---|---|---|
| ✅ fechado | #2378 | Instagram: prazo eliminado via System User token |
| 🔴 **prazo** | **#2382** | **LinkedIn vence 2026-10-27** |
| 🔴 aberto | #2384 | `Comms Metrics Sync` verde sem trabalho |
| 🔴 aberto | #2383 | canal newsletter fantasma |

⚠️ Dois alertas obsoletos em `comms_token_alerts` (18/09 e 19/09, `acknowledged = false`) avisam de um prazo que não existe mais. Reconhecer na tela.

### V3. Camada de conhecimento
| estado | # | item |
|---|---|---|
| 🔴 aberto | #2260 | guarda-chuva: a camada existe nas 4 superfícies e está sem acervo |
| 🔴 aberto | #2261 | 58 corridas verdes receberam 16 linhas em 6 meses |
| 🔴 aberto | #2262 | ninguém escreve há 41 dias |
| 🔴 aberto | #2263 | 4 moradas coexistem para arquivos (Drive, banco, git, Storage) |
| 🔴 aberto | #2264 | trilíngue declarado e ausente: ZERO linhas es-LATAM |
| 🔴 aberto | #2313 | `hub_resources` com forma de URL que não abre em navegador |

⇒ A #2370 tocou o cano (`knowledge_ingestion_runs`) e **não** o acervo. O cano está consertado e continua trazendo zero: `chunks_scanned: 0`. O trabalho de verdade é esta vertical.

### V4. Presença, gamificação e ranking
| estado | # | item |
|---|---|---|
| 🔴 aberto | #2295 | evento anterior à entrada é cobrado quando NÃO foi selado |
| 🔴 aberto | #2281 | denominador de presença ignora a data de entrada |
| 🔴 aberto | #2296 | 86 badges caem no fallback de 10 pontos |
| 🔴 aberto | #2297 | ranking opaco para auditoria |
| 🔴 aberto | #2246 | auto check-in e escrita sem autor são indistinguíveis |
| 🔴 aberto | #2247 | arquivar iniciativa não fecha a série de reuniões |

### V5. Liderança e ciclo
| estado | # | item |
|---|---|---|
| 🔴 aberto | #2333 | o modelo de líder em formação não tem representação |
| 🔴 aberto | #2334 | o onboarding de líder pressupõe tribo que ainda não existe |
| 🔴 aberto | #2265 | 94 de 172 tokens de onboarding expiram sem uso |

### V6. Autoridade, segurança e LGPD
| estado | # | item |
|---|---|---|
| 🔴 aberto | #2362 | função auxiliar de teste com EXECUTE para anon/authenticated |
| 🔴 aberto | #2361 | 170 tools seguem expostas apesar da absorção declarada |
| 🔴 aberto | #2342 | 1.993 notificações carimbadas como ENTREGUES sem entregar |
| 🔴 aberto | #2252 | ADR-0012 protege 3 tabelas e a coluna de cache entrou fora |

### V7. Governança de repositórios e credenciais
| estado | item | onde |
|---|---|---|
| 🟡 pipeline | arquivar o repositório abandonado; **antes**, apagar os 4 secrets dele | #2370 passo 5 |
| 🔴 aberto | **chaves legadas do Supabase, prazo fim de 2026** | tracker **PRIVADO** da lane `pmigo-plataforma`. ⚠️ **Não abrir issue pública** sem decisão do dono |

### V8. Qualidade de dado e medição
| estado | # | item |
|---|---|---|
| 🔴 aberto | #2365 | `get_public_impact_data` se contradiz no mesmo payload |
| 🔴 aberto | #2275 | 2 fixtures órfãs contam como membro real |
| 🔴 aberto | #2283 | `member_get` devolve 0 engajamentos para quem tem 2 |
| 🔴 aberto | #2253 | hook de pré-commit acusa 203 linhas contra 78 reais |

---

## 4. Prioridades

| prioridade | item | por quê |
|---|---|---|
| **P0 - prazo** | **#2382** LinkedIn | data dura: **2026-10-27**. Precedente medido de 4 dias sem métrica |
| **P1** | **#2343 + #2255** juntos | hoje pararam a publicação por 2h30 e ninguém foi avisado |
| **P1** | **#2384** | decisão barata (remover ou tirar `schedule:`) que limpa a superfície do audit semanal |
| **P2** | **#2370** passo 5 | higiene; a escrita já está fechada, então não há urgência |
| **P2** | V3 conhecimento | é onde está o valor não entregue, mas é trabalho de fôlego, não de sessão curta |
| **P3** | #2383 newsletter | decisão de produto antes de conserto técnico |

---

## 5. Armadilhas desta sessão que vão voltar

1. **`set -uo pipefail` não desliga o `-e` que vem de `bash -e {0}`.** Todo step do Actions que faça `VAR=$(cmd)` seguido de `$?` precisa de `set +e`. Já mordeu uma vez, com o passo que existia para tratar o próprio código de saída que o matou.
2. **`gh issue comment --edit-last` não edita o seu último comentário.** Editou um de dois meses atrás. Sempre `gh api -X PATCH .../issues/comments/<id>`. Recuperação: GraphQL `userContentEdits`, nó `[1]`.
3. **Lista com `--limit N` que responde exatamente N foi truncada.** Aconteceu duas vezes hoje: contagem de issues e opções de permissão num dropdown.
4. **Nome quase igual não desambigua.** Dois apps homônimos, e o errado vinha primeiro na lista. Sempre por ID.
5. **Verde de workflow agendado não prova trabalho; vermelho não prova ausência de trabalho.** Quem decide é o efeito, contado por janela no destino.
6. **Depois de mergear, confira a `main`.** O CI da PR ficou verde e o da `main` caiu. Eu não olhei, e descobri 2h30 depois, ao montar este documento.

---

## 6. Sugestão de primeiro movimento

Se a sessão for curta, **#2384**: a medição já está feita, a recomendação está escrita, e fecha um item inteiro.

Se houver fôlego, **#2343 + #2255**: é a dor que hoje custou a publicação, e as duas se resolvem melhor juntas do que separadas.

Se o dono quiser tocar o prazo, **#2382**, lembrando que a pergunta ali não é "tem refresh token?" e sim **"alguém exerce o refresh?"**.
