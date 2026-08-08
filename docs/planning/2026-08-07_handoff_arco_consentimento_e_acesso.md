# Handoff — o arco de consentimento fechado, o acesso por componente aberto (07/08/2026)

> `main` em `6221e990` (o #1642 + #1649 já mergeados). PR aberto desta sessão: **#1677**.
> PR **#1674 fechado como superado** (não abandonado — o commit dele está inteiro no #1677).

## Regra zero

Nada aqui pode ser recitado. Toda contagem foi medida em 07/08 e a base é viva.

---

## Mergeado: #1642 + #1649 (PR #1667, `6221e990`)

- **#1642** — a comunicação negava a consequência. Três superfícies nos 3 idiomas, mais a correção
  de subprocessador: a tela nomeava só a Anthropic e as **47 de 47** análises do ciclo eram
  `gemini-2.5-flash`. Cada texto nomeava um provedor e omitia o outro.
- **#1649** — a varredura lia 147.794 linhas para devolver zero. Pré-filtro por faixa de `runid`
  (5212 ms → 78 ms; O(tabela) → O(constante)) com guarda O(1) que cai para a varredura completa se
  a faixa deixar de cobrir 48h. O `set_config` do #1663 era **inerte** e saiu.

---

## No PR #1677 (verde local: 6535 testes, 6534 passam, 0 falhas, 1 skip)

### #1666 — o consentimento de IA virou registro auditável
`consent_records` **já existia e estava vazia** (0 linhas, todos os tipos), com `policy_type`
prevendo `'ai_analysis'`, FK da candidatura e ponte de volta. Faltava coluna de prova e a escrita.
Backfill dos 56 como `v1-pre-1642` com `evidence` NULL — **sem inventar hash**.
⚠️ A exigência de evidência (`RAISE`, como no ramo de voz) é o **passo seguinte**, depois de
confirmado o front no ar. Hoje ela é registrada, não exigida.

### #1591 — o comitê alcança `/admin/selection`
Quarto eixo `is_selection_committee_member(membro, ciclo)`, **escopado por ciclo** (sem isso, o
comitê de hoje leria o PII de todos os ciclos passados). As **duas** implementações do menu
mudaram, e o `route-acl.test.mjs` foi ensinado sobre o eixo.
⏭️ **Falta o Fernando confirmar na prática**: abrir `/admin/selection` e `/minhas-avaliacoes`
logado. Não dá para medir por SQL (a RPC resolve por `auth.uid()`; o conector passa como o Vitor).

### #1665 — transferência internacional
Google, Anthropic e OpenAI entram em `privacy.s5int`. Bases separadas: infra no art. 33, IX; IA no
art. 33, **VIII**. ⚠️ O VIII exige informação prévia sobre o caráter internacional, então o texto
de consentimento ganhou "sediados nos Estados Unidos" e a versão foi para `v3`.
⚠️ **A escolha do inciso é jurídica** e vai ao comitê.

### #1423 — a transferência de tribo partia a ponte
A issue culpava o `remove`; medido, aquele caminho já estava coberto (`UPDATE status='expired'`,
não DELETE). A causa é **assimetria**: `tribe_id` escrito incondicionalmente, `initiative_id` só
`WHERE IS NULL`. Verificado por sonda em transação abortada; zero órfãos na base.

---

## ⚠️ O erro desta sessão, para não repetir

Apliquei DDL em produção com o #1674 aberto e **serializei os PRs**. Os três gates de drift caíram
por causa que não era do diff dele.

A memória `reference-prod-ahead-ddl-serializes-every-open-pr` foi **corrigida hoje** e o recorte
certo é: **não é "isso é DDL?", é "vou registrar uma versão?"**. Qualquer `migration repair` deixa
todo branch sem aquele `.sql` vermelho, mesmo que o conteúdo tenha sido um `UPDATE` de dado.

---

## Pendências de decisão (não são de código)

1. **#1641 — recomendação REVISTA para NÃO reemitir.** Dois fatos medidos:
   - **nenhuma** das 34 está em `submitted`, e `dispatch_consent_nudge` filtra por esse status: a
     ferramenta da issue alcança **zero**;
   - os "3 em processo sem token" são **2 `final_eval` + 1 `interview_done`**, todos já avaliados e
     já com entrevista. A análise de IA não tem finalidade restante para eles.
   Os 6 em `interview_pending` já têm token vivo e podem consentir sozinhos.

2. **Coerência round-robin × fila compartilhada.** O e-mail `peer_review_request` diz "você foi
   escolhido (round-robin) para avaliar a candidatura de X"; `get_my_pending_evaluations` mostra
   **todos** os avaliáveis do ciclo para **todos** do comitê (20 hoje). Decidir qual é o modelo
   antes de mexer em qualquer um dos dois. Inclui a afirmação incondicional "Pré-análise IA
   concluída" para candidatura sem análise.

3. **Comitê**: redação do #1642 (já publicada), inciso do art. 33 (#1665), e a cláusula nova no
   texto de consentimento.

4. **`curator` é vocabulário órfão**: zero portadores em toda a base, e gateia 10 entradas de nav
   (webinars, publicações, analytics, portfólio, agenda viva, cross-tribes, sustentabilidade,
   governança). A superfície de curadoria está fechada para todos, em silêncio. É atribuição de
   designation, não código. **98 membros não têm designation nenhuma.**

## Regras da casa

- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato ou membro nomeado, só contagens.
- Não rodar `npm test` local com CI em voo (os dois escrevem no mesmo banco de produção).
