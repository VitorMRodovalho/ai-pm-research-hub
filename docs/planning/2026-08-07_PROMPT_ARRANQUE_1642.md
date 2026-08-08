# Prompt de arranque — #1642 e a cauda do arco de consentimento (07/08/2026)

> Colar depois do `/clear`.
> **Effort: `xhigh`.** O que está em jogo é texto que a LGPD trata como informação prestada ao
> titular (art. 18, VIII), em 3 idiomas, sobre uma consequência que ACABOU de deixar de existir.
> Errar a ordem inverte a mentira em vez de removê-la.
>
> Handoff completo: `docs/planning/2026-08-07_handoff_1640_fechado_convites_atribuidos.md`.
> `main` em **`54fe0eb9`**.

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número aqui foi medido em 07/08 de madrugada e a
base é viva. Re-medir com tool call na mesma volta antes de qualquer decisão.

E o padrão que já custou três leituras erradas neste arco continua valendo: **número certo,
significado errado.** O instrumento é barato — rodar o grupo de controle, ou perguntar *de quem é
este valor* em vez de *quantos são*.

Um exemplo desta própria sessão: `schedule_interview` tinha **zero** recusas `GATE_NO_AI` em 31
tentativas. Lido como "esse gate nunca incomodou ninguém", teria ficado. Medindo o caminho vizinho:
**14 bypasses** sobre candidaturas sem consentimento, **13 deles desnecessários** se não fosse o gate.
Zero recusas era **contorno**, não imunidade.

---

## Leia antes de planejar — já medido, não re-litigar

1. **#1640 está FECHADO e em produção.** O gate de IA saiu de `_issue_interview_booking_token_core`
   (modo `full`) e de `schedule_interview` (fora do bypass). P0002 (peer-review), P0003 (nota) e
   P0004 (status) ficaram. Isso **destrava o #1642** — e o #1642 só podia vir depois, senão o texto
   novo afirmaria "não há consequência" enquanto ela ainda existia.

2. **Os 4 convites presos já foram despachados**, pela tela, com `dispatch_source: manual` e ator
   nominal. As outras 2 da coorte não estavam presas: têm convite vivo dentro da carência de 10 dias.

3. **"Recusa" continua sendo inferência, não evento.** Só existem `consent_ai_analysis_at` e
   `consent_ai_analysis_revoked_at`. "Abriu o portal e nada foi gravado" é compatível com recusar
   **e** com abandonar o onboarding.

4. **`gate_attempts` contém tráfego de teste** (#1636): `caller_id IS NULL` em 100% das linhas do
   `_issue_interview_booking_token_core`. Qualquer leitura precisa separar teste, cron e humano.

5. **A tela é hoje o único caminho de convite com atribuição humana** (mapa das 3 superfícies no
   comentário do #1586). Isso não bloqueia o #1642, mas é o contexto do #1586.

---

## A ordem

### 1. #1642 — o texto (P1, destravado)

Três superfícies, âncoras já levantadas na issue:

- **Tela primária de consentimento** — `src/i18n/pt-BR.ts` ~linha 6715. Hoje vende o consentimento
  como acelerador opcional, sem dizer nada sobre efeito.
- **E-mail de nudge** — `20260517100000_consent_nudge_template_and_dispatch_rpc.sql` (linhas 36-38).
  Diz "opcional" e instrui *"se prefere não dar consentimento de IA, ignore esta mensagem"*.
- **Política pública** — `src/i18n/pt-BR.ts` ~linha 3837. Cita **duas bases legais para a mesma
  operação**: consentimento expresso E art. 7º, V. Separar: art. 7º, V para o processo seletivo;
  art. 7º, I exclusivamente para a análise por IA, sem menção cruzada.

⚠️ **Paridade nos 3 dicionários** (pt-BR, en-US, es-LATAM) — é gate de CI, não zelo.
⚠️ O texto do e-mail vive em **migration**, não em dicionário: mexer nele é DDL, com o ritual completo
(`apply_migration` → deletar phantom → arquivo local → `migration repair` → `NOTIFY pgrst`).
⚠️ A redação sugerida na issue é **a validar com o comitê**, não a aplicar direto. Tom institucional.

### 2. #1641 — a oportunidade de consentir (P2)

33 de 34 não conseguem consentir: só 1 tem token vivo. Reemitir via `dispatch_consent_nudge`,
**desacoplado do convite** em tempo e mensagem — senão recria "consinta para avançar", que é o
defeito que o #1640 acabou de remover, por outra porta.

### 3. #1643 — varrer outras superfícies (P2)

Procurar outros consentimentos "opcionais" com gate escondido em caminho crítico. É o 2º caso no
mesmo funil, então trate como padrão, não incidente. Inclui limpar a dica morta do
`interview_manage` no `nucleo-mcp`, que ainda sugere `bypass_gate=true` ao ver `GATE_NO_AI` — ramo
que não pode mais casar.

### 4. #1649 — o vermelho de CI (ABERTA; a 1ª correção não pegou)

⚠️ **Leia isto antes de tentar de novo.** O PR #1663 elevou o `statement_timeout` para 60s *de dentro*
de `_alert_sweep_cron` e o `validate` dele passou. **Passou por cache quente, não por eficácia.** O
teste seguinte, num PR de dois markdowns, falhou com `duration_ms: 8974` — parou nos 8s de sempre.

Sonda que fecha a questão:

```sql
SET statement_timeout = '2s';
SELECT set_config('statement_timeout', '60s', true), pg_sleep(4);
-- ERROR: 57014 canceling statement due to statement timeout
```

**O `statement_timeout` é armado quando o statement COMEÇA.** Elevá-lo de dentro da função vale só
para os statements seguintes da transação, nunca para a chamada em curso. Para este fim, aquele
`set_config` é inerte — defesa decorativa clássica: o mecanismo existe, o teste passou, o efeito não
acontece.

O que sobrou de bom do #1663: `duration_ms` gravado em `platform.alert_sweep_run` (instrumentação
real) e as medições. O comentário da migration e o corpo daquele PR afirmam eficácia que a sonda
desmente — corrigir na próxima migration que tocar a função.

**Saídas ainda vivas:** `ALTER ROLE service_role SET statement_timeout` (funciona, porque o statement
nasce com o teto maior — mas é decisão de plataforma, vale para toda chamada `service_role`); ou
tabela-sombra alimentada por cron próprio (roda como `postgres`, sem teto), tirando a varredura de
150 MB do caminho do PostgREST.

E a forma que vale como sedimento:

- **8s não era o teto da função, era o teto de outra coisa.** `service_role` não define
  `statement_timeout` e herda o do `authenticator`, que é orçamento de chamada **interativa** do
  PostgREST. O chamador natural de `_alert_sweep_cron` é o `pg_cron`, que roda como `postgres` sem
  teto. Uma varredura em lote estava sendo medida com a régua de uma consulta de tela.
- **Elevar teto sozinho é máscara.** Veio casado com `duration_ms` gravado na linha de auditoria que
  a função já escrevia — a degradação vira número observável, não vermelho intermitente.
- **Duas saídas caíram por medição:** índice parcial em `cron.job_run_details` (`42501, must be
  owner` — a tabela é do pg_cron) e corte por `runid` (**3.294 ms contra 152 ms**, porque troca
  leitura sequencial por 20 mil buscas no heap). A segunda foi proposta por mim antes de medir.

Se `1621 behavioural` voltar a estourar, o sintoma agora é outro: leia `duration_ms` na última linha
de `platform.alert_sweep_run` antes de mexer em qualquer coisa.

---

## Armadilhas de execução (medidas 06-07/08)

- **DDL em prod antes do merge serializa TODOS os PRs abertos** e, pior, faz a suíte ANTIGA rodar
  contra o banco NOVO. Antes de aplicar: mergear o que está verde e esperar o CI da `main` terminar.
- **Ao remover/afrouxar um gate, `grep` o código de recusa na suíte INTEIRA antes do DDL.** Um
  predicado ancorado em "esta recusa" deixa de observar e passa a EXECUTAR o ato (emitir token,
  mandar e-mail) sobre linha real de produção.
- **`apply_migration` cria phantom row** com timestamp real; deletar (1 por chamada) e
  `supabase migration repair --status applied <sintético>`.
- **Guard de AUSÊNCIA sobre fonte crua casa o próprio comentário** que explica o defeito. Remover
  comentários antes de assertar (vale para o arquivo E para `prosrc`).
- **`confirm()` da página trava a extensão do Chrome** — neutralizar antes de automatizar clique.
- **Teste novo não roda em CI** se não estiver nas **duas** whitelists do `package.json`.
- **`npm test` com `.env` exportado**: 6460 testes, **1 skip**. ~548 skips = `.env` não subiu.
- **Não rodar `npm test` local com CI em voo** (`gh run list`): as suítes DB-aware escrevem em prod.

## Pendências que não são desta frente

- **#1556**, irmã da Wave 0, segue aberta.
- **#1637** Dependabot `astro` 6→7: não mergear (política #611); major não é higiene de rotina.
- **#1205** só fecha com o William no `/profile` LOGADO.

## Regras da casa

- Merge à `main` é da sessão main; lane leva o PR até verde e para.
- Commit: `Assisted-By: Claude (Anthropic) <noreply@anthropic.com>`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato nomeado, só contagens.
