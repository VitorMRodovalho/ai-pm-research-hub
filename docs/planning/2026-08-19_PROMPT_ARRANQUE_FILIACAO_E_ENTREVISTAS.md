# Prompt de arranque: as entrevistas, o vencimento de 31/08 e o vermelho que é verdade

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-18_PROMPT_ARRANQUE_ENTREVISTA_HOJE_E_VESPERA_1710.md`.
> Handoffs de 18/08: `2026-08-18_handoff_1844_1850_e_a_raiz_com_pavio.md` (tarde) e
> `2026-08-18_handoff_noite_filiacao_e_seis_issues.md` (noite).

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **18/08/2026 até 22:30 UTC**.
Re-meça com tool call na mesma volta em que o número entrar numa decisão, commit, issue ou pergunta.

Regras de varredura que já custaram caro. As **cinco últimas foram ganhas em 18/08**, todas errando:

- **Uma listagem não sustenta afirmação de ausência.**
- **Varra `pg_proc`, não o repositório**, e leia o corpo antes de confiar na varredura.
- **A lista da issue não é a classe.** Derive do catálogo.
- **`replace_all` casa a string, não a intenção.** Conte e diffe.
- **O carimbo do TRANSPORTE não é o do FATO.**
- 🆕 🔴 **Reconhecer a distinção no TEXTO não impede de apagá-la no `INSERT`.** Escrevi numa issue
  que histórico de voluntariado ≠ filiação, e na hora de gravar escolhi `source = 'pmi_vep'` — rótulo
  reservado ao worker de sync. **O campo de procedência é onde a distinção precisa sobreviver.**
- 🆕 🔴 **Procurar a palavra errada esconde o processo inteiro.** Procurei tabela de *filiação*, achei
  `member_chapter_affiliations` e parei. Existia `member_affiliation_verifications` (129 linhas, a
  Diretoria de Filiação). **Pergunte "quem valida isso hoje?" antes de escrever dado à mão.**
- 🆕 🔴 **Descartar hipótese com a ferramenta da CAMADA errada, e publicar o descarte.**
  `pg_stat_activity` vê backends do Postgres; a pergunta era sobre a **fila do pooler**. Snapshot
  limpo da camada de baixo **não é evidência** sobre a de cima.
- 🆕 🔴 **Tratar contribuinte como CAUSA sem rodar o contrafactual.** Identifiquei a colisão de lane
  e propus conserto; rodar o job sozinho — teste barato — mostrou que falhava igual.
- 🆕 ⚠️ **Afirmar risco futuro sem filtrar as condições que o produzem.** Anunciei um "pavio aceso"
  três vezes; ao medir com `is_active` **e** capítulo, ele não existia.
- 🆕 ⚠️ **Extração que "funciona" e não vê tudo.** Texto de PDF não enxerga anotação de link: quando
  o LinkedIn está num **hiperlink** sobre a palavra, o parse conclui "não tem" com a mesma confiança
  de quem realmente não tem. **Ausência por limitação da ferramenta ≠ ausência real.**

---

## Estado (18/08, 22:30 UTC)

`main` em **`418b9d8d`** · PR **#1859** (handoff da noite) aberta · **216 issues abertas** ·
bypass **1 de 2** na janela.

🔴 **43 invariantes, 1 violação — ABERTA DE PROPÓSITO** (#1850). Ver ITEM 3.

---

## 🔴 ITEM 1: as três entrevistas

| quando (UTC) | quando (BRT) | status |
|---|---|---|
| **18/08 23:00** | 20:00 | `scheduled` — **Dayane Guimarães · entrevistador Fernando Maquiaveli** |
| **19/08 21:30** | 18:30 | `scheduled` |
| 24/08 23:30 | 20:30 | `scheduled` |

📌 **Marcar desfecho** com `interview_manage action='mark'`. Nenhuma passada está sem desfecho hoje.
✅ A de 18/08 tem **briefing gravado** (2.726 chars), amarrado à régua real da entrevista.

⚠️ **`mark` carimba `conducted_at` com a hora do REGISTRO**, não da entrevista — 16 de 99 já
divergem, máximo 64 dias. E **o envelope relata `application_status` que não gravou**. Sem issue.

⚠️ **A de 24/08 cai no mesmo dia do prazo do #1710.** Não deixe os dois para a mesma sessão.

## ⏰ ITEM 2: #1855 — 6 pessoas vencem em 31/08

O radar F3 **existe, está agendado e roda todo dia**: `v4-affiliation-expiry-notify`, `0 9 * * *`,
`active = true`, sempre **`p_dry_run := true`**. O texto da notificação **já está escrito** e já cita
o Termo, `pmi.org` e o opt-out.

📌 **Não é caso de criar campanha — é tirar o freio.** Mas ligar como está alcança **5 de 16**:

- 🔴 **avisa D-30 e D-7 e nunca DEPOIS** — `days_until_expiry` negativo não casa em faixa nenhuma.
  **2 já vencidas** (31/07) não recebem nada.
- 🔴 **ignora quem nunca foi verificado** — o laço lê da tabela de verificações; **9** não têm linha.

⚖️ **Decisão que trava tudo: o que "vencida" implica?** Aviso, restrição, ou só lembrete? Sem isso o
e-mail não sabe o que pedir.
⚖️ E os 9 nunca verificados **não são alvo de e-mail**: a lacuna é NOSSA. O caminho deles é a fila
da Diretoria (`get_affiliation_verification_queue`).

## 🔴 ITEM 3: #1850 — o CI está vermelho, e está CERTO

`U_active_person_has_primary_chapter_affiliation` = **1 violação**, por **decisão do PM**.

Uma pessoa ativa (`researcher`) exibe capítulo do registro **sem nenhuma filiação**. O PM decidiu que
a tabela contém **só filiação verificada** — e a linha `self_declared` que eu havia gravado foi
apagada.

📌 **Quem topar com esse vermelho NÃO deve reparar o dado para calar o check.** A saída é
**submeter à verificação** pela Diretoria. O vermelho está dizendo a verdade.
📌 **Não é flake e não é o #1844.**

⚠️ Contexto que economiza uma hora: `chapter_registry` e `member_chapter_affiliations` usam
**`GO`, `DF`** (sem prefixo); `members.chapter` usa **`PMI-DF`, `Outro`**. Comparar formatos
diferentes faz o predicado devolver zero e a violação parecer fantasma.

## ITEM 4: o conserto mais barato do lote — #1856

Dois defeitos na tela de seleção, sem decisão pendente:

- `row.phone.replace(/\\D/g, '')` — casa "barra invertida seguida de D". **Um caractere, dois
  lugares** (linhas 2333 e 3780).
- Os inputs de telefone/LinkedIn **só renderizam quando o campo está vazio**: dá para preencher,
  **não para corrigir**. A RPC sempre soube sobrescrever (`COALESCE(NULLIF(...))`).

⚖️ Pendente: hoje **observador não escreve** (decisão de 18/08). Se a correção de contato deve valer
para **todo** o comitê, é uma linha — mas é reversão consciente.

## ITEM 5: #1857 — 34 telefones já estão na plataforma

Dos 47 CVs com texto extraído: **34 contêm telefone** e o campo `phone` tem **1 preenchido em 83**.
**12** têm LinkedIn no texto com o campo vazio.

A extração roda e guarda; **ninguém colhe**. Não é o cabeçalho (o `unpdf` pega do início) — é que
não há parse nenhum.

🔴 **E o caso do hiperlink:** quando a URL está numa âncora sobre a palavra "LinkedIn", ela mora numa
anotação `/Link` do PDF e **texto puro não a vê** — **4 de 47**. Os 12 são **piso**, não total.

## ⏰ ITEM 6: #1710, prazo 24/08

Config conferida em 17/08 e intacta (`floor_date` 2026-08-24, `grace_days` 14; cron
`attendance-seal-window-daily`, `40 11 * * *`).

📌 **Re-medir em 23/08, a véspera, pelos DOIS caminhos independentes.** É TETO e encolhe a cada
presença registrada. A medição de 15/08 **não serve mais**.

## ITEM 7: funil, prazo 28/08

Medido em 18/08: **105 linhas, 1 reserva medida**. **Nenhum número de conversão é publicável sem o
denominador explícito** — a instrumentação começou no meio do ciclo. **Não provocar despacho.**

## ITEM 8: o resto, com dono

- **#1852** — filiação do VEP **parada há 4 meses** (434 linhas, todas de 01/04 a 21/04). Quem entrou
  depois nunca teve. ⚠️ São **dois exports diferentes** do PMI, e só o **enriquecido de membership**
  traz capítulo — o "volunteer full" não tem o campo.
- **#1854** — vencimento sem alarme (o sintoma; #1855 é o mecanismo).
- **#1858** — `card_write` pede aprovação em **toda** ação: anotação é por **ferramenta**,
  destrutividade é por **ação**. ⚠️ **Reproduzir antes de consertar** — a mensagem é do cliente.
  Vale para `engagement_write`, `event_write`, `member_lifecycle` também.
- **#1848** — detectar vínculo ausente no ato da gravação (item 2 do #1834).
- **#1844** — causa da saturação de pool **ainda não identificada**; a suíte roda contra **produção**.
- **#1842** · **#1829** · **#1822** (as 56) · **#1592** · **#1205** · **#905** (30/09).
- **#588 `[LL]` parado há 70 dias** — o laço do PMO. A madrugada e a noite de 17-18/08 geraram muita
  lição e **nada foi para lá**.
- **#92** (118 dias) — raiz estrutural da **#1614**.

---

## Ordem sugerida

1. **Marcar o desfecho das entrevistas** (18/08 e 19/08).
2. **#1855: decidir o que "vencida" implica**, e tirar o `dry_run` **junto** com a faixa de vencidos.
   **13 dias até 31/08.**
3. **#1856** — meia hora, alto valor.
4. **23/08: re-medir o #1710.**
5. **#1850: submeter à verificação** quem está sem.
6. **Alimentar a #588.**

---

## Armadilhas da vizinhança

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO.** md5 normalizado antes, bloco extraído **do
   arquivo**, substituição **contada**, diffe. 📌 **Aplique em LOTES** e confira md5 de cada um: foi
   assim que 33 mil chars saíram com drift zero.
2. ⚠️ **Captura antiga usa `CREATE FUNCTION` sem `OR REPLACE`** — troque, que `OR REPLACE` preserva
   as ACLs.
3. **`apply_migration` cria o timestamp**: renomeie o arquivo local para ele. **A CLI não está
   linkada.**
4. **DDL antes do merge deixa toda branch aberta vermelha.** Aplique com zero PRs.
5. **Schema novo exige `npm run db:types` na MESMA PR** — e **confira por `grep`**, porque o script
   faz **no-op com exit 0** quando o PostgREST serve schema em cache.
6. **Teste novo entra nas DUAS whitelists do `package.json`.**
7. **Suíte offline (~60 s):** `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`. ⚠️ **Skip ≡ pass.** Com DB: `set -a; . ./.env; set +a`.
8. ⚠️ **`Fecha #N` NÃO fecha.** Use `Closes #N`, e nunca escreva o padrão sem intenção.
9. ⚠️ **Branch nova nasce do HEAD.** `git checkout -b <nome> origin/main`. **Nunca `git add -A`.**
10. ⚠️ **Repo PÚBLICO.** Nome, e-mail e identificador não entram em issue, PR nem doc. **Conte a
    população.**
11. ⚠️ **RPC com `auth.uid()` devolve "Not authenticated" para `service_role`.** Impersone em
    transação abortada, `set_config` **antes** do `SET LOCAL ROLE`. 📌 Para capturar exceção por
    papel, use tabela TEMP com `GRANT INSERT ... TO authenticated` — `RAISE NOTICE` não volta.
12. 📌 **Prove o guard VERMELHO**, e faça-o devolver **todos** os examinados com um booleano.
13. ⚠️ **Guard que PROÍBE um padrão acusa a própria documentação.** Rode a proibição sobre o SQL
    **sem comentários**.
14. ⚠️ **Guard estático com janela FIXA empresta a checagem do handler vizinho.** Corte na **próxima
    chamada**, e aceite identificador renomeado.
15. ⚠️ **O build leva 2m30s a 4m40s: background + confira o `Complete!`.**
16. 🔴 **SQL direto por `service_role` registra ato humano como 'cron' com actor nulo.** Use a porta
    MCP. ⚠️ **`upsert_chapter_affiliation` NÃO audita** e é a única porta de escrita da tabela que
    ancora o capítulo.
17. 🔴 **Despacho em LOTE quebra o rodízio** (`now()` é da transação).
18. ⚠️ **`rescue` e `rescue_unbooked` são COMPLEMENTARES**, com pré-condições opostas.
19. ⚠️ **Drive:** barra fullwidth (`／`), gravação do Meet **sem extensão**, doc nativo **0 bytes**
    pelo mount. `~/.local/bin/rclone` (1.74), nunca o do apt.
20. ⚠️ **YouTube:** ferramental em `~/projects/_pmo/youtube/`; a API **mente por propagação nos dois
    sentidos**; `videos.update` com `part='snippet'` substitui o snippet INTEIRO.
