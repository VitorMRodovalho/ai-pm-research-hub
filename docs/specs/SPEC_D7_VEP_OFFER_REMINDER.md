# SPEC D7 — Lembrete automático de aceite de oferta VEP

**Status:** draft → council (data-architect + legal-counsel) → PR DB-first
**Épico:** D (funil de seleção preso) — camada *candidate-facing* (complementa o GP-facing #781)
**Data:** 2026-06-18
**Autor:** PM main-loop (acordado c/ PM 2026-06-18 pós-clear)
**Cross-ref:** [[handoff-2026-06-18-d-stuck-funnel]] · `SPEC_D_STUCK_FUNNEL_DETECTION.md` (#781) ·
[[selection-interview-invite-resend-runbook]] · p92 `process_pending_reschedule_nudges` (padrão de reuso) ·
p157 `process_vep_acceptance_transition` (padrão do trigger de transição)

---

## 1. Problema

Candidatos **aprovados pelo Núcleo** (`selection_applications.status='approved'`) recebem uma oferta de
voluntariado no VEP (volunteer.pmi.org). O VEP marca a candidatura como **`OfferExtended`**. Para virarem
members de fato, eles precisam clicar **"Accept Position"** no portal do PMI. Quem nunca aceita fica preso no
**topo do funil** — invisível a todos os crons de seleção (#781 cobre não-agendou/no-show; nenhum cobre
oferta-não-aceita) — e eventualmente a oferta **expira** (`OfferExpired` → `rejected`), perdendo o candidato
silenciosamente.

O e-mail do VEP de "oferta estendida" vem de `donotreply@pmi.org`, cai em spam com frequência, e em inglês —
candidatos BR muitas vezes não percebem que há uma ação pendente.

## 2. Coorte viva (aterrada 2026-06-18, `execute_sql` read-only)

`vep_status_raw='OfferExtended'` + `status='approved'` no ciclo **cycle4-2026 (open)** = **3 candidatos**:

| Candidato | app VEP | criada | `vep_last_seen_at` | `vep_reconciled_at` | `cutoff_email_sent_at` | tem email |
|---|---|---|---|---|---|---|
| Maria Araújo | 291346 | 2026-04-30 (~49d) | 2026-06-18 (hoje) | null | null | sim |
| Bruna Soares | 288697 | 2026-04-15 (~64d) | 2026-06-18 (hoje) | null | null | sim |
| Rafael Bellotti | 289167 | 2026-04-15 (~64d) | 2026-06-18 (hoje) | null | 2026-05-27 | sim |

Histórico: **1** candidatura `OfferExpired` (já virou `rejected`) — exatamente o desfecho que o D7 previne.

> **Grounding-chave (decisão de design abaixo):** **não existe timestamp de "quando a oferta foi estendida".**
> `vep_last_seen_at` é a hora do último *poll* do worker `pmi-vep-sync` (hoje, p/ todos os 3), `vep_reconciled_at`
> é null (reconciliação manual), `updated_at` é tocado pelo worker a cada poll. A janela de grace, portanto,
> **não tem âncora limpa** sem introduzir uma.

## 3. Onde `vep_status_raw` é escrito (aterrado)

- O **worker Cloudflare `pmi-vep-sync`** escreve `vep_status_raw` + `vep_last_seen_at` direto na linha a cada
  poll (reescrita no-change inclusive — confirmado pelo comentário do trigger p157).
- `import_vep_applications(uuid,jsonb,text,text)` **NÃO** escreve `vep_status_raw` (só insere apps novas com
  `status='submitted'` e pula terminais) — não é o ponto de stamp.
- Precedente de trigger sobre transição de status: **p157** `trg_vep_acceptance_on_active`
  (`AFTER UPDATE OF vep_status_raw ... WHEN (NEW.vep_status_raw='Active')`) → marca a etapa `vep_acceptance`
  do onboarding. **D7 espelha esse padrão** para `OfferExtended`.

## 4. Decisão de design — âncora da janela de grace (ratificada pelo council)

Adicionar coluna `vep_offer_extended_at timestamptz` carimbada por um **trigger de transição BEFORE**:

```sql
CREATE FUNCTION public._stamp_vep_offer_extended() RETURNS trigger ... BEGIN
  IF TG_OP = 'INSERT' OR OLD.vep_status_raw IS DISTINCT FROM 'OfferExtended' THEN
    NEW.vep_offer_extended_at := now();
    NEW.vep_offer_reminder_sent_at := NULL;   -- re-offer reseta o single-fire (§5)
  END IF;
  RETURN NEW;
END; ...

CREATE TRIGGER trg_stamp_vep_offer_extended
BEFORE INSERT OR UPDATE OF vep_status_raw ON public.selection_applications
FOR EACH ROW WHEN (NEW.vep_status_raw = 'OfferExtended')
EXECUTE FUNCTION public._stamp_vep_offer_extended();
```

**Por que BEFORE e não AFTER (como o p157):** o trigger só toca a própria linha → `BEFORE` modifica `NEW`
diretamente (sem 2º write, sem risco de recursão). O p157 usa `AFTER` porque toca *outra* tabela
(`onboarding_progress`). **Por que `INSERT OR UPDATE` (data-architect):** o worker `pmi-vep-sync` **pode INSERIR**
uma linha já em `OfferExtended` (`script-mapper.ts:162` seta `vep_status_raw` no insert; `index.ts result.was_new`)
— um trigger só-`AFTER UPDATE` perderia esses casos (ficariam com `vep_offer_extended_at` NULL → nunca
qualificam). **Por que o `WHEN` só referencia `NEW`:** o Postgres proíbe `OLD` no `WHEN` de um trigger que inclui
`INSERT`; a distinção genuína (vs. reescrita no-change a cada poll) é feita no corpo via `TG_OP`/`OLD`.

**Backfill dos 3 existentes:** `vep_offer_extended_at = COALESCE(cutoff_approved_email_sent_at, created_at)`.
Ambos são timestamps reais no passado (49-64d) → os 3 qualificam na 1ª run do cron, que é o comportamento
correto (estão genuinamente presos há semanas). A imprecisão (subestima a idade real da oferta) afeta **apenas**
os 3 históricos; daí em diante o trigger carimba com precisão. `vep_reconciled_at` NÃO entra no COALESCE
(é timestamp administrativo manual, não a hora da oferta — data-architect).

**Alternativas rejeitadas:** âncora direta em `created_at` (sem precisão futura, menos conservador);
`vep_last_seen_at` (refresca a cada poll); sem grace (PM pediu janela conservadora).

## 5. Idempotência — single-fire

Coluna `vep_offer_reminder_sent_at timestamptz` (espelha `interview_reschedule_last_nudged_at`/
`cutoff_approved_email_sent_at`). MVP = **single-fire**: gate `vep_offer_reminder_sent_at IS NULL`. A coluna é
nomeada/modelada para que um *repeat* futuro (ex.: 2º lembrete após N dias) seja mudança de uma linha.

**Re-offer (Option A, data-architect):** a flag NÃO é limpa pelo cron, mas **é resetada pelo trigger de §4** na
transição genuína para `OfferExtended`. Assim, um candidato cuja oferta expirou (`OfferExpired`→`rejected`) e que
recebe uma **nova** oferta meses depois ganha um lembrete fresco (a mesma linha do trigger reescreve
`vep_offer_extended_at=now()` e `vep_offer_reminder_sent_at=NULL`). Sem isso, a flag não-nula da oferta anterior
suprimiria o lembrete da nova — lacuna de correção, não só semântica.

**Race conhecido (aceito, data-architect):** o stamp `vep_offer_reminder_sent_at=now()` ocorre **após**
`campaign_send_one_off`, dentro do `BEGIN/EXCEPTION` per-row. Se o *send* falha → rollback do stamp da linha
(fica NULL → re-tentado na próxima run, correto). Se o *send* sucede mas o `UPDATE` falha → duplicata na próxima
run. Mesmo race que `process_pending_reschedule_nudges` aceita; tolerável p/ single-fire + coorte pequena.

## 6. Janela SLA — `offer_accept_grace`

Nova linha em `sla_policies` (reusa a tabela + UI admin do J4): `offer_accept_grace`, **proposta 7 days**
(oferta estendida há ≥7d e ainda não aceita). Tunável sem deploy; fallback ao literal `'7 days'` no corpo da RPC.

> Comparação: `interview_booking_grace`=10d (agendar entrevista é mais pesado). Aceitar oferta é 1 clique →
> janela mais curta é defensável. **A confirmar pelo data-architect.**

## 7. RPC — `process_pending_vep_offer_reminders()`

Clone do esqueleto `process_pending_reschedule_nudges` (p92):

- `RETURNS jsonb`, `LANGUAGE plpgsql`, `SECURITY DEFINER`, **`SET search_path TO ''`** (padrão endurecido
  #781/J4; todas as refs qualificadas `public.<tabela>` — data-architect CHANGE-3).
- **Cron-context auth bypass** idêntico ao p92 (se um usuário real chamar, exige `can_by_member(..,'manage_member')`;
  cron/service_role passa). → `rpc-v4-auth` não cobra `can()` porque o gate de usuário-real existe.
- `REVOKE ALL FROM public, anon, authenticated; GRANT EXECUTE TO authenticated, service_role`.
- Coorte (loop):
  ```
  WHERE a.status = 'approved'
    AND a.vep_status_raw = 'OfferExtended'
    AND a.vep_offer_reminder_sent_at IS NULL
    AND a.vep_offer_extended_at IS NOT NULL
    AND a.vep_offer_extended_at < now() - <offer_accept_grace>
    AND c.status = 'open'                       -- ciclo aberto (JOIN selection_cycles)
    AND a.email IS NOT NULL
  ```
- Por candidato: `campaign_send_one_off('vep_offer_accept_reminder', a.email, {first_name, lang?}, {source, application_id, ...})`
  dentro de `BEGIN/EXCEPTION` per-row (uma falha não derruba os outros), depois
  `UPDATE ... SET vep_offer_reminder_sent_at = now()`.
- `language`: default `'pt'` (precedente do reschedule nudge; coorte majoritariamente BR). Override por metadata
  se houver coluna de idioma (não há hoje em `selection_applications` — manter `pt`).
- Retorna `{success, reminders_sent, processed[], errors[], run_at}`.

## 8. Template — `vep_offer_accept_reminder`

Linha em `campaign_templates` (slug, i18n jsonb pt/en/es em subject/body_html/body_text), `category='operational'`,
`target_audience={audience:'selection_candidate'}`. Vars: `{{first_name}}`.

Conteúdo (3 idiomas):
- Assunto: "Falta 1 passo para você entrar no Núcleo IA, {{first_name}}".
- **Finalidade (legal-counsel B, Art. 6º VI / 9º I):** 1ª linha após a saudação — "Você está recebendo este
  e-mail porque sua candidatura ao Núcleo IA foi aprovada e há uma ação pendente no portal do PMI para concluir
  sua entrada como voluntário(a)."
- Corpo: passo a passo — **(1)** acesse **volunteer.pmi.org** → **(2)** menu **My Info & Activity** → **(3)** clique
  em **Accept Position** na oferta do Núcleo IA.
- Aviso de spam: "o PMI envia esse aviso de `donotreply@pmi.org` — confira sua caixa de spam".
- **Opt-out com efeito explícito (legal-counsel C, Art. 18 III):** "Se preferir não prosseguir, responda este
  e-mail com 'desisto' — sem problema nenhum. Sua candidatura será encerrada e não enviaremos mais comunicações
  sobre o processo seletivo."
- **Rodapé — identificação do controlador (legal-counsel A, OBRIGATÓRIO, Art. 9º I / 41):** "Este e-mail foi
  enviado pelo **Núcleo IA — capítulo voluntário do PMI** porque sua candidatura está aprovada e há uma ação
  pendente no portal do PMI. Dúvidas: responda este e-mail."
- Minimização: só `{{first_name}}` + os passos. **Sem** e-mail, sem score, sem PII extra no corpo.

`language`: passado em `p_metadata->>'language'` (default `'pt'`); o EF `send-campaign` seleciona a variante i18n
do `campaign_templates` por essa chave — padrão já em produção no `interview_reschedule_nudge`.

## 9. Cron

`SELECT cron.schedule('nudge-vep-offer-accept-daily', '0 17 * * *', $$ SELECT public.process_pending_vep_offer_reminders() $$)`
— **17:00 UTC** (evita o cluster 14h reschedule/cutoff-pending, 15h stuck-rescue, 16h detect-stuck-funnel #781).
Unschedule idempotente antes (padrão dos crons da casa).

## 10. Invariante

**Nenhum.** Como `detect_inactive_members`/`detect_stuck_selection_funnel` (#781): detecção/notificação efêmera,
sem invariante estrutural. (O trigger de stamp é determinístico e espelha p157, que tampouco tem invariante.)

## 11. LGPD / risco (legal-counsel)

- **Toque externo automático ao candidato** (classe D3). Base: o candidato consentiu no processo seletivo ao
  aplicar via VEP; o lembrete é sobre **uma ação pendente dele próprio**, não marketing. Mitigações: single-fire
  (1 e-mail só), janela conservadora (≥7d), opt-out por reply, minimização de PII no corpo.
**Veredito legal-counsel: GO-com-mudanças, 0 blockers.** Base legal principal = **Art. 7º II (execução de
procedimento preliminar que o próprio titular iniciou)** + Art. 7º IX (legítimo interesse) subsidiário — **não é
marketing**, é comunicação operacional. Opt-out por reply **é suficiente** sob Art. 18 III para single-fire.
Mudanças aplicadas no template (§8): A (controlador, OBRIGATÓRIA), B (finalidade), C (opt-out com efeito).

**Pontos monitorados (não-blockers):**
- (D, Art. 18 IV) Confirmar que o cron de anonimização 5y varre `selection_applications` por **tipo de coluna**
  (dinâmico) e não por lista estática — se lista, somar as 2 colunas novas. Verificar antes da 1ª rodada pós-deploy.
- (E) Gap de polling do worker: a oferta pode já ter expirado no PMI entre dois polls → o e-mail instruiria
  "Accept Position" inexistente. Risco baixo (sem dano), single-fire limita; auto-withdraw é domínio da
  reconciliação (§13).
- (F) **Não há coluna `opted_out`** (verificado ao vivo) — o gate `status='approved'` já exclui `status='withdrawn'`.
  Mas um reply "desisto" só vira `withdrawn` por ação manual do GP; até lá o candidato segue `approved`. Risco
  operacional aceito p/ MVP (single-fire limita a 1 e-mail); monitorar.

## 12. GC-097 / entrega

1 migration `20260805000209_d7_vep_offer_accept_reminder.sql`: coluna `vep_offer_extended_at` + coluna
`vep_offer_reminder_sent_at` + trigger de transição + backfill dos 3 + 1 `sla_policies` + 1 `campaign_templates`
+ RPC + cron. Ritual: `apply_migration` (verbatim, sem enxugar comentários — Phase-C) → escrever arquivo local →
`migration repair --status applied` + DELETE shadow por NAME → `NOTIFY pgrst`. Teste de contrato novo
(`d7-vep-offer-reminder.test.mjs`) registrado nas 2 whitelists do `package.json`. Validação: dry-run lógico da
coorte (3 esperados), `npx astro build`, `npm test` com `.env`, `check_schema_invariants` inalterado, Phase-C limpo.

## 13. Fora de escopo

- FE (painel) — D1 já existe (`GpActionTodayWidget`), coorte visível lá. D7 é só a camada PUSH candidate-facing.
- 2º/3º lembrete (repeat) — coluna preparada, mudança de 1 linha quando houver demanda.
- Auto-withdraw de ofertas expiradas — domínio da reconciliação (`reconcile_vep_terminal_status`), não D7.
