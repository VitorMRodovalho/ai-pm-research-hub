# Handoff - 08/08 (fim de tarde): #1643 fechada, #1647 destravada, e a faixa de banco cobrou

> Sessão a partir de `docs/planning/2026-08-08_handoff_1682_fechada_e_dois_falsos_incidentes.md`.
> `main` em **`dea130d7`**. Mergeado: **PR #1647**. Aberto e verde: **PR #1689**.

---

## Estado ao fechar

| item | estado |
|---|---|
| **#1647** | mergeado em `dea130d7` (squash), 11/11 verde |
| **#1643** | **fechada**, sweep completo publicado na issue |
| **#1689** | **aberto, `CLEAN`, 11/11 verde, NÃO mergeado** - decisão do PM |
| `main` | `dea130d7`, alinhada com produção |

---

## #1647 - a hipótese do handoff anterior estava certa

Estava vermelho por estar **atrás do `main`**, não por defeito próprio. Confirmado por atualização
e re-run: 11/11.

Detalhe de método que vale reter: **force-push está bloqueado pelo harness**, então rebase não é
opção nesta lane. A atualização foi por `git merge origin/main` dentro do worktree do PR
(`~/projects/ai-pm-paulo`), o que é seguro porque o merge final é **squash** e a história do branch
não sobrevive de qualquer forma.

O único conflito foi a linha gigante do `test` no `package.json`. Resolvido por script, não à mão:
toma a lista do `main` e reinsere só o arquivo que o branch acrescentava, com verificação de que o
outro teste continua presente. Transcrever essa linha à mão é como se perde um teste calado.

---

## #1643 - fechada, com uma instância viva a menos do que a issue supunha

O sweep completo está na issue. Veredito:

| classe | resultado |
|---|---|
| 1. gate de tratamento | correta onde existe (biometria de voz, purga por revogação, `lgpd_consent`) |
| 2. gate de avanço | uma instância, o `GATE_NO_AI`, corrigida no #1640 |
| 3. afirmação incondicional sobre tratamento condicional | uma instância, o `peer_review_request`, já corrigida na migration `20260807001000` (#1591) nas 3 línguas |
| inversa (tratamento sem consentimento) | **ausência medida**: 170 candidaturas, 56 com consentimento, 56 com `ai_analysis`, 56 com `ai_triage_at`, **0** sem |
| `sign_proposer_consent` | fora da família: assinatura de proponente de documento de governança, sem titular nem finalidade de tratamento |

### O zero daquela função precisava de nome

`selection.peer_review_dispatched`: **6 eventos, todos em 05/05/2026, 12 convites**, e **nenhum**
carrega o campo `no_ai_context`. Esse campo nasceu com o soft-gate do p228 - logo, **a versão atual
da função nunca rodou em produção**.

Isso reclassifica o número do comentário de 07/08. As 294 avaliações sobre candidatura sem análise
**nunca foram teto de e-mails falsos**: no máximo 12 saíram por essa porta, e todos sob a versão de
gate duro, que só despachava **com** análise. As avaliações chegam pela fila compartilhada
(`get_my_pending_evaluations`), não pelo convite despachado. O zero era **contorno**, não imunidade.

### Uma assimetria estrutural que sobrevive à correção

`dispatch_peer_review_invitations` **calcula** a nota condicional (`v_no_ai_context`) e entrega ao
sino in-app. O e-mail recebe **5 variáveis, nenhuma sobre IA**. Hoje é inofensivo porque o template
não afirma nada. É também a razão pela qual a afirmação falsa foi possível: **o canal que não
recebe a condição não tem como respeitá-la.**

---

## #1689 - a guarda, e por que ela existe sem defeito vivo

A correção do #1591 vive numa **linha de dados**: o template é editável pela UI do admin, e a
migration verificou o efeito por contagem de linhas no momento em que rodou. O teste do #1642
tranca só o `pmi_consent_nudge` e só a afirmação dirigida ao **titular**. A frase podia voltar por
edição sem CI nenhum reclamar.

- **Camada A** prova os dentes do predicado, sem ler arquivo de migration (guard ancorado em
  arquivo fica verde com o mecanismo inerte). Inclui o controle negativo que importa: o **nome da
  organização**, que contém "IA" e "Inteligência Artificial".
- **Camada B** varre os 3 idiomas de assunto, corpo-texto e corpo-HTML de **todo** template vivo;
  **falha alto** com zero linha; confere que o `peer_review_request` não foi apenas **esvaziado**; e
  afirma que o despacho ainda ramifica por `v_no_ai_context`.
- **Isenção nominal** do `pmi_consent_nudge`, com um teste da camada A afirmando que o predicado
  **acusa** aquele texto - a isenção continua sendo escolha declarada, não efeito colateral.
- **Mutação: detectada** (sem a isenção, fica vermelho nomeando `pmi_consent_nudge.body_text.pt`).

Suíte no CI: **6585 pass, 0 fail, 1 skip**. Não é o modo de falha dos 548 skips silenciosos.

---

## 🔴 O vermelho da sessão: faixa de banco, não schema

`check-invariants` ficou **vermelho na `main` e no PR** ao mesmo tempo. Não era defeito: era
**fome de faixa**.

O repo serializa o acesso ao Postgres de produção no CI (`wait-for-db-lane`, do #1509). Um job por
vez; espera até **900s** e então **falha em vez de rodar concorrente**. É o desenho certo, e é a
defesa contra a contaminação entre runs.

Eu criei **três consumidores simultâneos**: o primeiro push do #1689, o merge do #1647 e o segundo
push do #1689. O `check-invariants` morreu na fila dos dois lados.

Medido direto, sem esperar CI: **`check_schema_invariants()` devolveu 43 invariantes, todas com
`violation_count` 0**. Re-disparados **um de cada vez** com a faixa livre, os dois voltaram
`success`.

⚠️ **A regra da casa cobria o andar de baixo.** "Não rodar `npm test` com CI em voo" tem um irmão:
**não mergear com a CI de outro PR em voo**. O custo é o mesmo, e o sintoma é pior - o vermelho
aparece em PR inocente e na `main`, e parece regressão de schema.

⚠️ **`gh run list --limit N` mente por omissão.** Ele me mostrou "faixa livre" enquanto o `validate`
do meu próprio PR rodava. A leitura confiável é filtrar por status explicitamente
(`select(.status=="in_progress" or .status=="queued" or .status=="pending")`).

---

## Próximo

1. **#1689** está verde e pronto. Falta só a decisão de merge.
2. **Personas sintéticas (#1636)** - segue sendo o maior e o único com **dano em curso**: cada
   rodada de CI que exercer aquele caminho cria token real sobre candidatura real. ⚠️ A suíte também
   escreve `members`. O mesmo trabalho cobre as duas superfícies.
3. **Resíduos escolhidos**, ainda intocados: observador por URL direta em
   `get_my_pending_evaluations`; `route-acl.test.mjs` reimplementando o `canAccess`; exigir
   evidência no consentimento de IA sob `RAISE`.

## Em aberto, sem decisão (herdado)

- Os quatro defeitos recortáveis do **#1679** viram issues?
- R2 sem lifecycle (~5 GB/ano). Se ganhar poda, a retenção de 30 do artefato precisa subir.
- Os 4 tokens do #1636 expiram sozinhos em **21/08**.
