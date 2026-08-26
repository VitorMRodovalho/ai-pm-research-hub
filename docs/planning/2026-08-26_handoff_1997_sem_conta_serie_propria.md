# Handoff 26/08 (tarde) — #1997: quem não tem conta para de ser cobrado

**Estado final:** branch `fix/1997-onboarding-sem-conta`, **PR #2008** aberta, fila **vazia** quando a
DDL foi aplicada, zero bypass. Migration `20260826144210`. **A #1997 fica ABERTA de propósito** — 2,5
dos 5 itens de aceite; os outros 2,5 pedem decisão do PM, não código.

⚠️ **Os 3 checks vermelhos da PR são a queda do GitHub Actions, não o código.** `analyze`, `deno` e
`gen-types-drift` foram **cancelados no mesmo segundo** (15:17:43 UTC), cada um após exatamente 15
minutos, **com `steps=0`** na API: nunca receberam runner. `githubstatus.com` confirma **Actions em
`major_outage`** desde 15:11:58 UTC. Padrão da #1869: required cancelado lê como vermelho e não é.
**Re-rodar quando o Actions voltar.** Verificação local feita antes do push: `test:contracts`
**6786 testes, 0 falhas**; `npx astro build` passa; o teste novo 11/11 **com** o de DB rodando (0
skipped); `check_schema_invariants()` sem violação.

---

## 1. O caso, e o relógio que ele tem

Farhad Abdollahyan, aprovado como **líder** em 14/08 (`cycle4-2026`), 16 passos de onboarding,
**0 feitos**, `members.auth_id` NULL. Três passos já `overdue` — e um deles é literalmente
**`platform_access`**, SLA vencido em 21/08. O detector marcou atraso no passo "conseguir acesso" e
cobrou a pessoa por isso numa notificação cujo link exige a sessão que falta.

Não é caso isolado. Medido 26/08, **4 pessoas** sem `auth_id` carregam jornada ativa:

| pessoa | passos | feitos | overdue | próximo SLA | token vivo? |
|---|---:|---:|---:|---|---|
| Farhad Abdollahyan (líder) | 16 | 0 | 3 | 28/08 21:15 UTC | não |
| Rafael dos Santos | 12 | 0 | 0 | 29/08 01:35 UTC | não |
| Thiago Sousa | 12 | 0 | 0 | 29/08 01:35 UTC | não |
| Hector Rigon (inativo) | 7 | 1 | 0 | — | não |

O cron `detect-onboarding-overdue-daily` (`jobid 39`, `0 13 * * *`) fazia a primeira leva reproduzir
o defeito em **29/08 às 10:00 BRT**. Os tokens de `profile_completion` (o outro caminho sem sessão,
via `/pmi-onboarding/<token>`) venceram todos entre 19/05 e 07/08.

## 2. A premissa da issue, corrigida por medição

A issue dizia "sem conta, in-app é inalcançável". **É mais preciso que isso**, e a diferença muda o
conserto. `selection_onboarding_overdue` sai como `digest_weekly`, e o digest semanal **não filtra
por `auth_id`**: gente sem conta recebe o e-mail dele (15 envios a 8 pessoas sem `auth_id`). O que a
falta de conta impede não é a **entrega**, é o **destino** — todo link aponta para tela com sessão.

Por isso a correção **não suprime** a notificação (isso criaria ausência indistinguível de "ninguém
estava atrasado"): ela troca **texto** e **destino**, e conta o caso em série própria.

## 3. O que entrou

1. **`detect_onboarding_overdue`** separa "atrasado" de "impedido". O passo continua `overdue`; quem
   não tem conta recebe título/link diferentes (`/guia-pre-onboarding`, página pública cujo passo 2 é
   "entre com o MESMO e-mail do PMI"), **um aviso por PESSOA, não por passo**, e sem o nome cru do
   passo. Retorno ganha `blocked_no_account_steps` / `blocked_no_account_people`.
2. **`get_application_onboarding_pct`** para de filtrar por `metadata->>'phase'='pre_onboarding'`.
   **0 das 899 linhas** de `onboarding_progress` carregam essa chave, então a RPC devolvia `-1` para
   as **71** candidaturas com jornada e a coluna "Onboarding" do `/admin/selection` era `—` para
   todo mundo, sempre. Agora: 71 com número, média **55%**, **6** em 0%.
3. **`get_onboarding_blocked_cohort()`** (nova, SECDEF, `manage_platform`): a lista acionável.
   Exercitada viva: `people 4 · steps_blocked 46 · steps_overdue 3`.
4. **Botão de login morto** em `/workspace` e na home: disparavam `open-auth-modal` no `window`;
   o único ouvinte é `open-auth` no `document`. São 10 pontos de despacho no `src/`, 8 já certos.
   `/workspace` é o destino do 302 de `/onboarding`, o endereço de todo e-mail de aprovação.
5. **Guard** `tests/contracts/1997-onboarding-sem-conta.test.mjs`, 11 testes, derivado da captura
   vigente e da identidade que o `AuthModal` escuta, com reinjeção dos dois lados e controles
   negativos.

## 4. O que NÃO entrou, e as duas perguntas ao PM

Aceite da #1997: `[x]` detector, `[x]` painel, `[~]` bloqueio marcado (mas não "garantir o convite no
fluxo de aprovação"), `[ ]` caminho de recuperação, `[ ]` acesso do Farhad.

**A plataforma não tem "reenviar convite de acesso".** Acesso é self-service: `try_auto_link_ghost`
vincula pelo e-mail primário no primeiro login, e `request_account_claim` exige que a pessoa **já
esteja logada** (é para quem entrou com e-mail diferente). Construir a recuperação significa mandar
e-mail a gente de verdade.

1. **Mandar o e-mail de recuperação às 4 pessoas — sim/não, e com que texto?** Se sim, o caminho mais
   barato é catalogar um tipo `transactional_immediate` novo em `_delivery_mode_for` + uma RPC de
   admin que o dispara. Não inventei isso sem resposta.
2. **Farhad tem duas candidaturas**: a `approved` é de **líder**, a `rejected` é de **pesquisador**.
   A jornada de 16 passos é a de líder. Confirma que é essa que vale?

## 5. Cinco achados colaterais, todos medidos, nenhum consertado aqui

- **`seed_pre_onboarding_steps` nunca rodou para ninguém.** Ela semeia um passo chamado
  **`create_account`** — exatamente o que teria pego este caso — mais `setup_credly`,
  `explore_platform`, `read_blog`, `start_pmi_certs`, com XP. **Não tem chamador em lugar nenhum**
  (nem SQL, nem frontend, nem EF): 0 linhas com `phase`, 0 com `step_key='create_account'`. Toda a
  gamificação de pré-onboarding foi construída e nunca ligada.
- **130 de 899 linhas usam step_key que não está no catálogo.** `accept_terms`, `kick_off`,
  `platform_access`, `profile_complete`, `join_whatsapp` (26 linhas cada) não têm linha em
  `onboarding_steps`: sem rótulo, sem `is_required`, sem `applies_to_role`. `get_onboarding_dashboard`
  junta com o catálogo, então **ignora essas 130 em silêncio** ao contar `total_steps` e
  `fully_onboarded`.
- **O digest semanal só entrega notificação de quem tem OUTRO conteúdo na semana.** O gate
  `v_has_content` de `generate_weekly_member_digest_cron` olha cards/engajamentos/eventos/publicações/
  broadcasts/governança/conquistas, e **não olha notificações pendentes**. Medido: 68 `digest_weekly`
  nunca entregues, 6 com mais de 7 dias — **4 delas `selection_onboarding_overdue` de 18/08, e 3
  dessas 4 são de gente COM conta**. Não é defeito de conta, é do gate.
- **`selection_onboarding_overdue` não está no catálogo de `_delivery_mode_for`**: cai no `ELSE`.
  O comentário do próprio arquivo avisa que "o ELSE é um default de conveniência e um dia muda".
- **Todo link de e-mail da plataforma usa o domínio pessoal.** 37 ocorrências de
  `nucleoia.vitormr.dev` em **10 edge functions** (6 delas remetentes de e-mail a membro:
  `send-notification-email`, `send-campaign`, `send-account-claim`, `send-email-verification`,
  `send-allocation-notify`, `send-global-onboarding`) e **0** de `nucleoia.pmigo.org.br`, contra a
  diretiva do dono de 03/07 ("sempre `nucleoia.pmigo.org.br` nas comunicações; o 301 funciona").

## 6. Ritual da migration

Aplicada com a fila vazia. **Duas** chamadas de `apply_migration` (a segunda trocou "um aviso por
passo" por "um por pessoa"): a primeira registrou `20260826144210`, que virou o nome do arquivo
local; a segunda registrou a fantasma `20260826145316`, **apagada por versão exata** e a ausência
conferida com consulta NOVA (o `RETURNING` da própria `DELETE` mostraria o snapshot pré-delete).
md5 normalizado vivo == arquivo local nas três funções, zero erro de transcrição.
`database.gen.ts` regenerado com a CLI **pinada pela CI** (2.109.0, não a local 2.115.0): diff de
uma linha.

## 7. Fila daqui

`#1995` (visão do admin, denominador varia por template) · `#1996` (`No Memberships` virando NULL) ·
`#1999` (2 RPCs de editar membro + `is_superadmin` gravado direto) · `#2001` (`legal_basis`, guard
primeiro, backfill é jurídico) · `#2004` (rótulo ou portão, pede decisão) · `#2007` (token LinkedIn).
