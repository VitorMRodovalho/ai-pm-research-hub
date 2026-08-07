# Prompt de arranque — #1640 e a cauda do ciclo seletivo (07/08/2026)

> Colar depois do `/clear`.
> **Effort: `xhigh`.** Não é tamanho, é classe de risco: é correção de conformidade sobre um gate
> que decide quem avança num processo seletivo, e o modo de falha da família inteira é **silencioso**.
>
> Handoff completo: `docs/planning/2026-08-06_handoff_wave1_consentimento_medido_1586b_e_impasse_prs.md`
> (Parte 6 traz a decomposição e a ordem). `main` em `0897ccf1`.

---

## Regra zero

**Nada deste documento pode ser recitado.** Os números do ciclo seletivo mudaram 4 vezes em 06/08,
inclusive contra o handoff da própria manhã. Re-medir antes de qualquer decisão, com tool call na
mesma volta.

E o padrão que se repetiu **três vezes** em 06/08 foi **número certo, significado errado**:

- "34 sem `ai_analysis`" ≡ "34 sem consentimento" era verdade, mas **por construção** (a análise é
  gateada pelo consentimento), então citar uma medindo a outra não informa nada
- "206 recusas `GATE_NO_AI`" mediam **quantas vezes a suíte de testes rodou**, não produção
- "35 nunca receberam convite" eram **4** de fato presos; os outros 31 já tinham avançado

O instrumento que pegou os três é barato: **rodar o grupo de controle**, ou perguntar *de quem é
este valor* em vez de *quantos são*. Use antes de deixar qualquer número entrar num argumento.

---

## Leia antes de planejar — já medido, não re-litigar

1. **`#1640` não é decisão de mérito.** A análise por IA não é necessária à decisão: 50 aprovadas no
   ciclo, 18 sem `ai_analysis`, **17 dessas entrevistadas**. Avaliar, entrevistar e aprovar sem o
   dado é rotina. Só o **convite** trata a ausência como impedimento. A escolha é *quando*, não *se*.

2. **A comunicação NEGA a consequência.** A tela de consentimento e o e-mail de nudge dizem que é
   opcional, e o nudge instrui *"se prefere não dar consentimento de IA, ignore esta mensagem"*.
   Como a consequência existe, é informação **falsa por conteúdo declarado**, não incompleta.
   Art. 18, VIII. Isso é o **#1642**, e está BLOQUEADO pelo #1640 estar em prod.

3. **"Recusa" é inferência, não evento.** Só existem `consent_ai_analysis_at` e
   `consent_ai_analysis_revoked_at`. Não há carimbo de recusa: "abriu o portal e nada foi gravado"
   é compatível com recusar **e** com abandonar o onboarding.

4. **`gate_attempts` contém tráfego de teste** (#1636). Dois contract tests escolhem candidatura
   REAL de produção por predicado e gravam recusa que, por desenho, sobrevive ao rollback. Qualquer
   leitura dessa tabela precisa filtrar, e `caller_id IS NULL` em 100% é o tell.

5. **Cron verde não é cron que fez algo.** O detector do funil rodou `succeeded` por 24 dias
   varrendo o ciclo errado. Ler o **efeito**, nunca o `status`.

---

## A ordem, e por que ela não é livre

### 1. #1640 — tirar a IA da pré-condição do convite

Remover `consent_ai_analysis_at`/`ai_analysis` da condição de bloqueio em
`_issue_interview_booking_token_core` (modo `full`). **Manter** `GATE_NO_PEER_REVIEW` e
`GATE_NO_SCORE`: são requisitos de conclusão do processo objetivo, não dados opcionais de terceira
finalidade, e não têm problema de LGPD.

Teste que afirme a **regra**: candidatura sem `ai_analysis`, com 2 avaliações e nota calculada,
**recebe** token.

⚠️ Basear o `CREATE OR REPLACE` no **corpo vivo** (`pg_get_functiondef`), não no arquivo de
migration — eles divergem.

### 2. #1586(a) — a superfície MCP, ANTES de reprocessar

Expor `selection_rescue_unbooked_invite` no `interview_manage`. Sem isso, reprocessar por SQL faz a
conexão ser `service_role`, a RPC entra no ramo `v_is_cron` e o `admin_audit_log` grava
`actor_id = NULL` com `dispatch_source: 'cron'`: ato humano registrado como automático. Já aconteceu
com 3 candidaturas em 03/08. **Num reparo de conformidade é o pior lugar possível para esse defeito.**

### 3. Reprocessar as bloqueadas

Re-medir a coorte antes. Em 06/08 eram 6 em `interview_pending` sem consentimento, 4 delas nunca
convidadas.

### 4. #1642 — o texto, só com o #1640 em prod

Tela de consentimento + e-mail de nudge + política pública (que hoje cita **duas** bases legais para
a mesma operação). Paridade nos **3** dicionários. Publicar antes do gate corrigido inverte a
mentira em vez de removê-la.

### 5. #1641 e #1643 — independentes

#1641: 33 de 34 não conseguem consentir (só 1 com token vivo). Reemitir via `dispatch_consent_nudge`,
**desacoplado do convite** em tempo e mensagem, senão recria "consinta para avançar".
#1643: varrer outras superfícies de consentimento em busca de gate escondido (é o 2º caso no mesmo
funil, então é padrão, não incidente).

---

## Verificação pendente da sessão anterior

O #1586(b) subiu em 06/08 e o cron roda 16:00 UTC. **Conferir que ele realmente inseriu as
notificações** (esperado: 2 candidaturas × 2 managers). Ler as linhas criadas em `notifications`,
não o retorno do job.

---

## Armadilhas de execução medidas em 06/08

- **DDL em prod antes do merge serializa TODOS os PRs abertos.** Três gates comparam a árvore contra
  o banco vivo. Antes de aplicar, listar os PRs abertos: se houver, ou ele entra primeiro, ou você
  acabou de deixá-lo vermelho por causa que não é dele.
- **Vermelho de contenção ≠ vermelho de defeito.** `check-invariants` falha após esperar 900s pela
  faixa de banco (#1509). Reemitir vários PRs DB-aware de uma vez cria isso.
- **`apply_migration` que falha: corrigir o ARQUIVO antes de rechamar**, senão o versionado deixa de
  ser idêntico ao aplicado. E apagar a phantom, **1 por chamada**.
- **Guard de AUSÊNCIA sobre fonte crua casa o próprio comentário** que explica o bug. Remover
  comentários antes de assertar.
- **Detectar a coorte não é entregar o alerta:** conferir que a classe destinatária do fan-out não
  está vazia, senão computa N e entrega 0.
- **Teste novo não roda em CI** se não estiver nas **duas** whitelists do `package.json`.
- **`npm test` sem `.env` exportado pula ~548 testes calado.** Conferir o número de skips.
- **Não rodar `npm test` local com CI em voo** (`gh run list`): as suítes DB-aware escrevem em prod.

## Pendências que não são trabalho desta frente

- **#1637** Dependabot `astro` 6→7: não mergear (política #611), mas major não é higiene de rotina.
  Decisão do PM.
- **#1556**, irmã da Wave 0, segue aberta.
- **Bypass:** janela de 7 dias em **1 de 2**.

## Regras da casa

- Merge à `main` é da sessão main; lane leva o PR até verde e para.
- Commit: `Assisted-By: Claude (Anthropic) <noreply@anthropic.com>`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato nomeado, só contagens.
