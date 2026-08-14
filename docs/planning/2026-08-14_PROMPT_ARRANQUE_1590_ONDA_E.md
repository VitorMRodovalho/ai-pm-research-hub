# Prompt de arranque - #1590, o que sobrou da onda D (e a onda E depois)

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-14_handoff_1590_onda_d_a_tentativa_ganhou_linha.md`
> (onda D entregue: o despacho virou a linha viva).

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número abaixo foi medido em **14/08/2026** e
vários se movem sozinhos: na onda C, `selection_booking_attempts` saiu de 40 para 41 linhas **no
meio da sessão**, sem ninguém tocar em código.

Re-medir com tool call na mesma volta em que o número entrar numa decisão, num commit, numa issue
ou numa pergunta ao PM.

E um aviso específico desta sessão: **uma listagem não sustenta afirmação de ausência.** Na onda D
eu afirmei "não existe e-mail" olhando 5 de 27 mensagens que a busca resumira. Vale para
`gh run list --limit`, `LIMIT` em SQL, `pg_policies` filtrado, qualquer paginação. Para dizer que
algo NÃO existe, abra o contêiner ou conte explicitamente.

---

## Estado (14/08, início do dia)

`main` em **`f22fe2aa`**. Onda D fechada em duas PRs, **#1766** (código) e **#1767** (handoff),
ambas verdes, **zero bypass**.

⚠️ **PRs de outra lane (Biblioteca), possivelmente já mergeadas quando você ler:** **#1750** (tile
da tribo) e **#1752** (handoff da lane). Estavam 11/11 verdes mas `BEHIND` da `main` pós-onda-D.
**Conferir `gh pr list --state open` antes de qualquer coisa.**

⏰ **Compromisso com data, de outra lane:** antes de **24/08** alguém precisa re-medir o que a
primeira execução do cron de selo do #1710 (`attendance-seal-window-daily`) vai gravar. Não é
trabalho desta onda, mas se a sessão atravessar aquela data, é dela.

---

## ⚠️ O primeiro trabalho da sessão: o mecanismo da onda D está ARMADO e INERTE

Medido em 14/08: **94 linhas** em `selection_dispatch_url_log`, **0 instrumentadas**, 0 carimbos de
abertura, 0 de reserva.

Isso é o esperado (nenhum despacho novo saiu desde a migration), mas significa que a instrumentação
**nunca foi exercida por tráfego real**. É a mesma situação das **0 linhas** em
`selection_interviewer_blackouts` que a onda C deixou: a superfície existe, o contrato passa, e o
invariante segue em **vácuo**.

A prova da onda D cobre a cadeia inteira, mas rodou dentro de transação abortada. **Antes de
publicar qualquer número do funil, conferir na primeira linha nova:** `instrumented = true`,
`booking_token_md5` preenchido, e o carimbo de abertura caindo na linha certa quando o candidato
abre `/interview-booking/[token]`.

Se nenhum despacho tiver saído até a sessão, **provocar um** é decisão do PM (manda e-mail de
verdade para um candidato real).

---

## O item da vez: o que a onda D deixou de fora

O PM decidiu em 13/08 que o escopo da onda D era instrumentação + #1664. Estas duas ficaram
**medidas e prontas para executar**, e a issue já carrega o diagnóstico:

### #1587 - `selection_interviews` com múltiplas linhas (P1)

**14 candidaturas** com mais de uma linha (re-medido 14/08). Dessas, **5 dão resposta ERRADA hoje**
quando lidas como `DISTINCT ON (application_id) ... ORDER BY scheduled_at DESC`:

| o que a última por data diz | na verdade já foi realizada | candidaturas |
|---|---|---|
| `cancelled` | **sim** | 4 |
| `scheduled` | **sim** | 1 |

Quem lê "a mais recente por data" nos corpos **VIVOS** (varrido em `pg_proc`, não no repositório):
`selection_rescue_stuck_interview` e `mirror_sibling_interview`.

A issue já propõe a view canônica `v_application_interview_state` com
`ja_realizada = bool_or(status='completed' OR conducted_at IS NOT NULL)`. **O alerta da própria
issue continua valendo:** a heurística precisa distinguir **supersede**, **dual_track** (duas
linhas legítimas, uma por trilha, com o mesmo `conducted_at` e a mesma nota) e **duplicata de
verdade**.

⚠️ Achado lateral registrado na issue, **não é desta onda**: `mirror_sibling_interview` é
`SECURITY DEFINER` com `EXECUTE` para `anon`. **Não é explorável** (o corpo exige `auth.uid()` →
membro → `can_by_member(manage_platform)`), é a classe já triada do #1592.

### #1586 - `selection_rescue_unbooked_invite` sem superfície (P1)

**Confirmado NÃO entregue.** O arranque da onda D trocou as duas funções: `interview_manage
action='rescue'` mapeia para `selection_rescue_stuck_interview` (convite JÁ agendado que lapsou).
Esta issue é sobre a **complementar**, o convite emitido e nunca agendado. Varredura: a RPC existe
em `pg_proc`, aparece **só em `src/lib/database.gen.ts`**, e tem **zero ocorrências** na EF e nas
telas.

População no ciclo aberto (re-medida 14/08): **9** candidaturas em `interview_pending`.

⚠️ **O cap muda o desenho:** na medição de 13/08, **5 das 9** já tinham
`interview_auto_rescue_count >= 1`, ou seja, já gastaram o resgate único. Expor a RPC sem endereçar
o cap entrega uma tela que recusa a maioria dos casos que ela mostra. **Re-medir antes de desenhar.**

---

## Depois dessas duas

**#1664 fase 2** - a fila de VÍNCULO que o PM decidiu em 13/08. As 31 `no_application` (re-medidas
14/08: ainda 31) já estão classificadas na issue: 11 linhas são a sonda do operador, **7 linhas / 6
pessoas são candidatos REAIS que reservaram com outro e-mail**, e um deles segue sem entrevista no
ciclo aberto. Encosta na **#1614** (adiada pelo PM em 05/08), que é a mesma causa raiz: o endereço
com que a pessoa AGENDA nunca é capturado.

**#1762** - o rodízio concentra despachos quando o lote sai na mesma transação (`now()` é da
transação, o LRD empata e o desempate por `member_id` decide). **Corrigir muda quem recebe
candidato → precisa do PM.**

**Onda E** (avaliação e decisão), já triada no backlog: #1572 (P0, aprovação sem avaliação não
deixa trilha), #1575, #1574, #1573, #1576, #1634, #1581, #1579.

---

## Decisões que já foram tomadas - NÃO re-litigar

- **O despacho é a linha viva** do funil (não `access_count`, não tabela nova).
- **As 31 `no_application`:** tirar a sonda do operador da fila + fila de VÍNCULO para os 6
  candidatos reais; o resto vira relatório, não trabalho pendente.
- **URL de agenda** = autosserviço + GP. **Painel** visível às 11 pessoas da tela, URL crua só na
  própria linha e para GP.
- **O painel NÃO publica "próximo da fila"** enquanto a #1762 não for corrigida.
- **Selo de presença** (#1710): automático com janela e aviso, 14 dias, correção pelo líder da
  tribo, dry-run obrigatório, reversão por evento (não existe `unseal`).

---

## Armadilhas da vizinhança, com o preço que já custaram

1. **O payload do `apply_migration` tem de ser O ARQUIVO, byte a byte.** Aplicar uma versão
   "limpa" (sem os comentários internos) faz o corpo vivo divergir da captura: comentário dentro
   de `$function$` é `prosrc`, e o Phase C hasheia isso. Na onda D as **4** funções divergiram, e o
   conserto (reaplicar verbatim) criou uma **segunda linha de tracking** — que aí deixou o gate
   **ADR-0097** (`no NEW missing-file drift`) vermelho no CI até o arquivo local dela entrar.
   `apply_migration` por MCP aplica no banco e **não** escreve arquivo nem registra na CLI.

2. **`CREATE FUNCTION` concede EXECUTE a `PUBLIC` por padrão.** Toda RPC nova nasce alcançável por
   `anon`; o `REVOKE ... FROM PUBLIC, anon` vai na MESMA migration (#1710, #1592). E **não**
   revogar o que o candidato deslogado precisa (`validate_interview_booking_token` é a porta dele).

3. **Gate por RECURSO, não por papel.** Uma RPC que recebe um alvo concreto e não olha para ele
   alcança o recurso de qualquer um: #1728, e 622 pares indevidos medidos no #1710.

4. **Mudança de assinatura de RPC exige `npm run db:types` na MESMA PR** (gate `gen-types-drift`).
   ⚠️ **O script falha em SILÊNCIO mesmo com `TMPDIR` no prefixo do `npm run`**: o `&&` da cadeia
   esconde o erro e o arquivo simplesmente não muda. Rodar `mktemp` + `supabase gen types`
   **separados**, conferir tamanho e sentinela, e **grepar a função nova dentro do arquivo** — o
   `git status` vazio não distingue "não mudou nada" de "falhou".

5. **Endpoints de auditoria de CATÁLOGO estouram o timeout.**
   `_audit_secdef_public_grant_drift` e `_audit_list_public_function_bodies` varrem os 1.082 SECDEF
   e devolvem **504** sob contenção (medido em 14/08, com a mesma árvore que respondera 200 em
   4,5 s). Para "anon alcança esta RPC?", **sonda direta na porta** (chamar com a chave anon e
   exigir `status != 200`) é mais forte que inspecionar o grant e caiu de **61 s para 0,4 s**.

6. **A suíte de contratos offline (~75 s) é o gate barato antes da PR:**
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   ⚠️ **Mas skip ≡ pass:** a camada viva PULA sem credencial. Rodar o arquivo novo **com**
   `.env` exportado antes de acreditar no guard, e conferir `gh run list` antes (o `validate` com
   DB não tolera execução concorrente — #1505).

7. **Teste novo tem de entrar nas DUAS whitelists do `package.json`** (`test` e `test:contracts`,
   SEDIMENT-186.C). Duas PRs com contrato novo colidem SEMPRE ali, e resolver escolhendo um lado
   DESLIGA o teste do outro em silêncio.

8. **Um guard antigo ficar vermelho pode ser o vermelho CORRETO.** Desça a afirmação um nível em
   vez de apagá-la.

9. ⚠️ **Nunca escrever `close #N` / `fixes #N` / `resolves #N` num corpo de PR sem intenção de
   fechar, nem para CITAR o padrão.** E o espelho: **`Fecha #N` em português não fecha nada.**

10. ⚠️ **O conector cacheia `tools/list`.** `scope='funnel'` (onda D) e `scope='routing'` (onda C)
    só aparecem depois de recarregar o catálogo. Não conclua que a tool não subiu.

---

## Primeiros passos sugeridos (não decididos)

1. **Conferir se #1750 e #1752 já mergearam**; se não, elas estão verdes e só precisam de
   `gh pr update-branch`.
2. **Re-medir tudo** da seção do item da vez: as 14 candidaturas com múltiplas linhas, quantas
   dessas dão resposta errada hoje, as 9 em `interview_pending` e quantas já gastaram o resgate.
3. **Conferir se a instrumentação da onda D saiu do vácuo** (`instrumented = true` em alguma linha).
4. **#1587 primeiro** (é P1 e não depende de decisão do PM), **#1586 depois** (o cap de resgate
   único pode exigir decisão).
5. Só então a #1664 fase 2, que precisa do PM para o desenho da fila de vínculo.
