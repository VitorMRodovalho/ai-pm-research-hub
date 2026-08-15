# Prompt de arranque — a #1797 esperando 24/08, a véspera do #1710 e o resto do #1780

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> Arranque anterior: `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_1783_E_1780.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **15/08/2026** e vários se
movem sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num commit,
numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** `gh pr checks` cresceu de **10 para 11 linhas**
  durante a espera, nas DUAS PRs da sessão de 15/08 (o `quality_gate` chega por último). Espere os
  pendentes.
- **Ausência de par só é conclusiva se o carimbo cobre a janela inteira.**
- **Varra `pg_proc`, não o repositório** — e conte quantas funções têm o nome antes de confiar nele.
- **Conte pelo predicado INTEIRO da policy, não pela capacidade que a issue nomeia.**
- **Um guard verde fala de UM eixo.** Pergunte de que direção o verde está falando.
- **Uma barreira que funciona por efeito colateral não é barreira.** O INSERT escapa das policies de
  SELECT porque não lê linha nenhuma; exija o controle inverso na mesma transação.
- 🆕 **Auditoria de dependência mente se olhar a ÁRVORE.** Alerta fala de **pacote**; código que o
  framework copiou para dentro de si não é pacote e é invisível. Grepe a assinatura do código
  vulnerável no `dist/`, não o nome do pacote em `node_modules` — e separe "está bundleado" de "é
  chamado", seguindo o handler de runtime até o ponto de uso.
- 🆕 **Severidade nominal não é risco.** Antes de recomendar prazo com base em "2 medium + 1 low", leia
  o *summary* do advisory e **grepe o padrão que ele exige**. Os 3 alertas do astro são XSS que pedem
  `{...spread}`, `transition:persist/scope` e `transition:animate/ViewTransitions` — **zero
  ocorrências** no repo (medido 15/08). Isso é barato e muda a conversa.

---

## Estado (15/08, noite)

`main` em **`43247280`**. **1 PR aberta: a #1797** (verde, `MERGEABLE`, esperando decisão de data).
A sessão fechou **2 merges com zero bypass** (#1796 11/11 · #1797 11/11 mas **não mergeada**).

Alertas Dependabot: **8 → 3** na sessão, e os **5 high zerados**. Os 3 que restam são todos do
`astro` e são exatamente o conteúdo da #1797.

⚠️ **Re-medir a janela de bypass** (`gh` / audit semanal) antes de qualquer `--admin`. Não recitar.

---

## ⏰ ITEM 1 — #1710, e o prazo é 24/08

Config **conferida no banco em 15/08**, não recitada de handoff:

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

**Re-medir em 23/08 (a véspera), pelos dois caminhos independentes** — a consulta externa que
reproduz coorte + carência, e o ensaio da própria função — e só então levar o número ao PM.
⚠️ **É teto, e encolhe a cada presença registrada por um líder.**

**Como ensaiar sem esperar:** bloco `DO` que faz `UPDATE` em `platform_settings` deslocando
`grace_days` para dar o mesmo corte que 14 darão em 24/08, recuando também o `floor_date` (senão
volta `skipped: before_floor`), e terminando em `RAISE EXCEPTION` com o resultado. A exceção aborta o
bloco inteiro e o `UPDATE` volta sozinho. **Confira a config depois do ensaio.**

⚖️ **DECIDIDO pelo PM (15/08), NÃO re-litigar:** as células que nenhum líder de tribo alcança ficam
com o **GP, pela grade geral**. Nada muda no código.
📌 **Ação da véspera:** levar ao GP a lista **nominal** dessas células — **na conversa, não em issue
nem em PR** (repo público).

✅ **Já fechado, não re-investigar:** zero faltas ficariam sem superfície · `unseal_event_attendance`
**existe** · o selo grava **só `present=false`**, com `ON CONFLICT DO NOTHING`.

---

## 🟡 ITEM 2 — a #1797 está pronta e parada de propósito

**Não é trabalho de código. É uma decisão de data.**

A PR sobe `astro` 6.4.8 → 7.2.2 e o conjunto que ele obriga (`@astrojs/cloudflare` 13.5.1 → 14.2.1,
`@astrojs/react` 5 → 6, `astro-eslint-parser`/`eslint-plugin-astro` → 3.1.0, e `vite` 7 → 8 por
transitividade, com **rolldown no lugar do rollup**).

Medido em 15/08: **11/11 no CI** · suíte local **6846 · 6845 pass · 0 falhas · 1 skip · 634,6s**,
contra a baseline da `main` de 629,5s com a mesma contagem · `wrangler deploy --dry-run` passa com
470 módulos e os bindings `SESSION`/`BROWSER`/`IMAGES`/`ASSETS` resolvidos.

⚖️ **Recomendação registrada na PR: segurar até depois de 24/08.** Os 3 alertas são XSS sem padrão
correspondente no código (ver Regra zero), então a urgência é ~nula; do outro lado há o único item
com data. O risco não é o CI (não quebrou) — é algo aparecer só em produção dentro da janela em que o
selo precisa poder receber deploy urgente.

⚠️ **Antes de mergear, sincronize com `origin/main`:** `package-lock.json` é campo de conflito
garantido se a branch ficar parada.

⚠️ **NÃO vender a #1797 como correção do `image-size`.** A cópia que o próprio astro vendoriza tem o
mesmo laço ICNS sem guarda em **6.4.8, 7.1.0 e 7.2.2** (medido nas três). São classes independentes.

---

## ITEM 3 — o resto do EPIC #1780

A Fase 1 mediu e quatro cortes saíram (#1778, #1784, #1791, #1779). Segue aberto:

- **Agregada de comentário e de anexo não existe nem em SQL** — não é falta de porta MCP, é falta da
  função. Decidir com o PM se entra.
- **4 definições de autoridade para a mesma ação** — o #1778 unificou a do checklist num predicado
  só; as outras seguem espalhadas.
- **8 verbos de curadoria sem porta MCP nenhuma** — um ciclo inteiro de trabalho só alcançável pela
  tela. **Escopo é do PM.**
- **Linha de base do #1791:** 7 filhas seguem decidindo escrita só por capacidade, todas com **zero**
  linhas confidenciais hoje. O contrato falha se aparecer uma nova.
- **Linha de base do #1784:** 10 filhas de outros domínios seguem sem gate de leitura, idem.

---

## ITEM 4 — o que fecha com uso real, não com código

- **#1586** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`, conferindo
  na linha nova do audit `actor_id` **não nulo** e `dispatch_source='manual'`.
  ⚠️ **Não despachar para testar.** Re-medir a idade dos despachos sem reserva antes de sugerir.
- **Funil, prazo 28/08.** Falta `booked_at`. **Nenhum número de conversão pode ser publicado** até uma
  linha carimbar reserva. **Não provocar despacho** — o cron gera linhas sozinho. Exigir
  `instrumented = true` **e** `booking_token_md5` na linha nova.

---

## Depois desses

**#1777** (o fluxo que gravou o papel divergente; o dado já está normalizado), **#1776**, **#1664
fase 2**, **#1762** (corrigir muda quem recebe candidato → precisa do PM), **#1729**, **#1742**,
**#1744**, **#1728** (20 RPCs da mesma classe, sem detalhe na issue).
**Onda E:** #1572 (P0), #1575, #1574, #1573, #1576, #1634, #1581, #1579.
**#1783** fecha quando a #1797 mergear (Lotes 2 e 3 já entregues e registrados na issue).

---

## Armadilhas da vizinhança, com o preço que já custaram

1. **`apply_migration` recebe o SQL como STRING.** Feche o risco comparando
   `md5(regexp_replace(prosrc,'\s+',' ','g'))` do corpo vivo com o do arquivo, **incluindo as quebras
   de linha das bordas do `$function$`**.
2. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local
   para casar, ou o gate ADR-0097 fica vermelho.
3. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com **zero PRs abertas**
   e mergeie antes de aplicar a próxima. ⚠️ **Hoje há a #1797 aberta** — ordene em torno dela.
4. **Mudança de schema exige `npm run db:types` na MESMA PR.**
5. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
   migration, e prove com **sonda na porta** — e com uma RPC pública de **controle**.
6. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 tem de estar **dentro** da função.
7. **A versão da superfície semântica tem QUATRO pins em arquivos que não se conhecem.**
8. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`).
9. **Suíte offline (~55 s) é o gate barato:**
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` antes de acreditar no guard (`set -a;
   source ./.env; set +a`), e confira `gh run list` antes (o `validate` com DB não tolera execução
   concorrente — #1505).
10. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`. E o espelho: **nunca escrever
    `close #N` sem intenção de fechar, nem para CITAR o padrão.**
11. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`.
12. ⚠️ **`supabase` CLI aqui não está linkado:** `--project-ref ldrfrvwhxsmgaabwmaik`.
13. ⚠️ **O conector cacheia `tools/list`.** Ação nova dentro de tool existente evita o problema.
14. ⚠️ **Repo é PÚBLICO.** Achado de segurança se **corrige primeiro e descreve depois**. Nome de
    pessoa não entra em issue, PR nem doc — conte a população, não a pessoa. Análise de
    alcançabilidade específica da plataforma fica FORA da issue; só o veredito entra.
15. ⚠️ **RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para
    `service_role`.** Derive do catálogo (`_audit_function_source`) ou impersone em transação abortada.
16. ⚠️ **`pg_get_function_identity_arguments` devolve nome E tipo** (`p_board_id uuid, ...`).
17. 🆕 ⚠️ **NUNCA canalize a suíte por `| tail -N` rodando em background.** O pipe segura TODA a saída
    até o fim, e não dá para ver onde parou. Redirecione para arquivo (`> log 2>&1`). Custou uma
    rodada inteira de 50 min cega em 15/08.
18. 🆕 ⚠️ **Para distinguir suíte LENTA de suíte TRAVADA, amostre os processos FILHOS** (`pgrep -P
    <pid>`) algumas vezes: nomes diferentes = progredindo. O pai fica em `ep_poll` com **0% de CPU nos
    dois casos**, então CPU não distingue — errei o diagnóstico nas duas direções em 15/08.
19. 🆕 ⚠️ **Um contract test que faz shell-out de lint pode TRAVAR em vez de falhar.** O gate do #1205
    executa `lint:client-scripts` por dentro; quando o lint quebrou, aquele teste sozinho consumiu
    **39,9 min** de uma suíte que inteira leva 10min30s. Num major de framework, **rode os lints
    separadamente ANTES da suíte**.
20. 🆕 ⚠️ **O build para no primeiro erro e mente sobre o tamanho do estrago.** Rode o compilador sobre
    `git ls-files '*.astro'` de uma vez (deu **400 arquivos, 399 OK, 1 falha**) em vez de iterar
    build-corrige-build. Transforma risco difuso em decisão.
21. 🆕 ⚠️ **Antes de propor "subir o pai" para um transitivo sem patch, leia a FAIXA que o pai
    declara** (`npm view <pai>@<nova> dependencies`). Pin exato (sem `^`) não alcança a versão nova do
    filho nem quando ela já abandonou a dependência vulnerável.
