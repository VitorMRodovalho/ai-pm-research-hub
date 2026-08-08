# Handoff — 08/08 (tarde): #1682 fechada, e dois "incidentes" que não eram

> Sessão a partir de `docs/planning/2026-08-09_PROMPT_ARRANQUE.md`.
> `main` em **`d473050b`**. Mergeado: **PR #1688** (fecha **#1682**).

---

## O que mudou em produção

| migration | função | efeito |
|---|---|---|
| `20260808000100` | `export_my_data` | art. 18 II alcança o ledger pela candidatura |
| `20260808000200` | `list_my_consents` | idem |
| `20260808000300` | `give_consent_via_token` | carimba `member_id` no ato do aceite |

Ritual GC-097 completo nas três: arquivo local, `repair`, `NOTIFY pgrst`, **3 phantoms deletados**
(um por chamada de `apply_migration` — o Gotcha 0 apareceu de novo, e o terceiro só foi pego
quando o gate reclamou). Drift final: **0**.

---

## Os dois falsos incidentes

Os dois entraram na sessão como alarme e saíram como medição. Vale reter o formato: **os dois
tinham o número certo e o significado errado**, e nos dois o que resolveu foi classificar as
linhas em vez de contá-las.

### 1. Os "10 membros que sumiram" — eram fixtures

131 no backup de 03/08, 121 em produção, zero remoções no `admin_audit_log`. Todos os 10 tinham
e-mail `@example.com`, `auth_id` NULO e `person_id` NULO: são `Test Sync Member __205_synthetic__`,
debris do `tests/contracts/member_emails.test.mjs`.

**Membros REAIS nos três backups: 121, 121, 121.** Nada desapareceu. O que aconteceu foi a
sweep-por-marcador do #1437 apagando o lixo que ela mesma acumulara antes daquele conserto — o
fix funcionando, não uma perda.

Nota de método: dá para responder "quais" extraindo o bloco `COPY public.members` direto do dump
gzipado com `awk`. Não precisa restaurar o banco.

### 2. Os PRs abertos já estavam serializados

O arranque avisava que aplicar DDL antes do merge serializaria os PRs abertos. Medi antes de
decidir: **todos os PRs recentes já estavam `validate=FAILURE`**, o #1647 já reprovando no
`Phase C` desde 07/08 — por estarem atrás do `main`, não por defeito próprio. O drift do `main`
era **0**.

Custo marginal de aplicar o #1682 agora: **zero**. Eles já precisavam de rebase. E mergear foi o
que realinhou `main` com produção, que é o que os destrava.

---

## O recorte do #1682 encolheu por medição

A issue listava quatro superfícies fora da exportação. **Três já saíam.**
`privacy_consent_accepted_at` (88), `consent_voice_biometric_at` + evidência (32) e
`persons.consent_status` (9) são carregados por `row_to_json()`, que serializa a linha inteira
sem que o corpo da função nomeie coluna alguma. A issue grepou o **texto**; o export impersonado
mostrou o **comportamento**: `v1.0`, `{lang, version, label_text_hash}`, `accepted` — e
`consent_records` = **0**, o defeito real e único.

Alcance corrigido: **33 pessoas**, não 34. Os 34 eram **linhas** do ledger.

**Decisões de escopo tomadas** (as três que o arranque mandava levar junto):

1. `list_my_consents` ganhou a ponte em vez de ser declarada "só de membro" — com o export já
   corrigido, divergir criaria um segundo significado de "meus consentimentos".
2. O carimbo só ocorre quando a resolução por e-mail é **inequívoca**. O vínculo errado é pior
   que nenhum: a leitura alcança ambos de qualquer forma, a escrita persistiria o erro.
3. **Sem backfill** das 56 linhas. O ledger é imutável por desenho (#1666).

Validação em base restaurada (o método novo): escrita ponta a ponta com token real
(`member_linked: true`), leitura pelos dois caminhos, e dois controles — membro sem candidatura
vê **0**, e **0** linhas visíveis por mais de um titular.

---

## Um guard consertado no caminho

`p569-s4` comparava o md5 do corpo vivo de `export_my_data` contra um arquivo de migration
**escolhido à mão**. Nasceu em `...139`, o #625 acrescentou `...148`, e o #1682 seria o terceiro
ponteiro — o teste reprovou o PR por trabalho correto, enquanto o gate principal passava no mesmo
commit. Passou a derivar de `loadLatestCaptures` (o SSOT do Phase C), com falha alta se a chave
não resolver. Mutação: detectada.

---

## #1636 — a pergunta em aberto foi medida

**Sim: a suíte emitiu token de agendamento real.** Quatro tokens, do run `31144140275`
(07/08 03:23–03:31), **vivos até 21/08**, sobre candidaturas reais. `access_count` **0**, nenhum
consumido.

O caminho até esse número passou por uma armadilha que vale registrar: dos 17 tokens da janela,
**12 tinham emissor nulo, e 8 desses eram do cron de resgate**, não da suíte. Cron e suíte rodam
como `service_role` e produzem a mesma digital. O que separa é o carimbo no `admin_audit_log` no
mesmo segundo, e a janela real dos runs — havia **dois runs simultâneos** em 07/08, e o intervalo
do run "óbvio" não continha os quatro.

⚖️ **Decisão do PM (08/08): registrar, não revogar.** Está na issue #1636.

---

## Próximo

1. **#1643** — falta a terceira classe ("afirmação incondicional sobre tratamento condicional")
   nas funções de despacho, mais `sign_proposer_consent`. Método e parcial na issue.
2. **Personas sintéticas (#1636)** — segue sendo o recorte certo, agora com dano medido: sem
   elas, cada rodada de CI que exercer aquele caminho cria token real sobre candidatura real.
   ⚠️ A suíte também escreve `members` (foi assim que os 10 fixtures nasceram) — o mesmo trabalho
   cobre as duas superfícies.
3. **PR #1647** precisa de rebase, não de conserto.
4. Resíduos escolhidos do arranque, ainda intocados: observador por URL direta em
   `get_my_pending_evaluations`; `route-acl.test.mjs` reimplementando o `canAccess`; exigir
   evidência no consentimento de IA sob `RAISE`.

## Em aberto, sem decisão

- Os quatro defeitos recortáveis do **#1679** viram issues?
- R2 sem lifecycle (~5 GB/ano). Se ganhar poda, a retenção de 30 do artefato precisa subir.
- Os 4 tokens expiram sozinhos em **21/08** — se a decisão mudar, é antes disso.
