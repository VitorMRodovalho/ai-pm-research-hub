# SPEC — Épico D / Auto-rescue de candidato convidado-preso ("fechar o loop")

**Status:** ready to build (council GO-with-changes aplicado)
**Migration:** `20260805000219` (head atual = 218)
**Decisões PM (2026-06-18):** unbooked + no-show **unificados** (re-convite ancorado no ÚLTIMO convite, não na idade do problema); **cap = 1** auto-rescue (1º convite do job51 + 1 re-convite automático; depois escala ao GP).
**Council:** data-architect GO-w-changes + legal-counsel GO-w-changes (base legal Art. 7º II = D7).

---

## 1. Problema (aterrado ao vivo, cycle ativo)

Só o **1º** convite de agendamento de entrevista é automático: `_selection_cutoff_pending_cron` (job51)
dispara `notify_selection_cutoff_approved` apenas quando `cutoff_approved_email_sent_at IS NULL`. Depois disso
**nada re-dispara** por envelhecimento. Um candidato aprovado que recebeu o convite e **nunca agendou**
fica preso: `status='interview_pending'`, `cutoff_approved_email_sent_at` setado, sem slot futuro — invisível
a todos os crons de ação. O detector `detect_stuck_selection_funnel` (#781, job60) apenas **notifica o GP**.

**Coorte viva (medida):** Hector Rigon (convite 27/05, 23d, nunca agendou) = o caso indisputável. Os 2 no-shows
(Edinan, Bruna) já são re-convidados pelo caminho `interview_scheduled → selection_rescue_stuck_interview`;
o auto-rescue unificado os cobre quando o convite de re-engajamento deles envelhecer.

**Não é o mesmo que o stuck-SCHEDULED já coberto** por `_selection_stuck_scheduled_rescue_cron` (job52):
aquele trata `interview_scheduled` com linha `scheduled` passada/não-conduzida. Este trata `interview_pending`
com convite envelhecido (mutuamente exclusivos por status).

---

## 2. Design

### 2.1 Coluna nova
```
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS interview_auto_rescue_count int NOT NULL DEFAULT 0;
COMMENT ON COLUMN ...: 're-convites automáticos já disparados por _selection_unbooked_rescue_cron
  (cap=1). NÃO conta o 1º convite do job51 — conta apenas re-envios deste path.'
```
Backfill 0 (DEFAULT). Cap = 1 (literal no corpo; constante documentada).

### 2.2 RPC `selection_rescue_unbooked_invite(p_application_id uuid)`
SECURITY DEFINER, `search_path=''`, **service-role/cron-aware** (espelha `selection_rescue_stuck_interview`
+ ADR-0028: v_caller NULL + sem JWT/service_role → v_is_cron; senão exige `manage_member` OR committee lead).
Passos:
1. carrega app; `IF NOT FOUND RAISE`.
2. **guard ciclo (data-architect blocker 1):** carrega cycle; `IF v_cycle.status <> 'open' THEN RAISE`.
3. **guard status:** `IF v_app.status <> 'interview_pending' THEN RAISE` (ERRCODE P0024).
4. **guard cap:** `IF v_app.interview_auto_rescue_count >= 1 THEN RAISE` (ERRCODE P0025 — escalada é do detector).
5. `UPDATE ... SET interview_auto_rescue_count = interview_auto_rescue_count + 1,
   cutoff_approved_email_sent_at = NULL, updated_at = now()`.
6. `v_notify := notify_selection_cutoff_approved(p_application_id)` (re-dispara; idempotência interna re-arma
   pelo NULL acima). **Não** envolvido em EXCEPTION → se notify RAISE, rola tudo back (atômico).
7. audit `selection.unbooked_invite_rescued` com metadata **legal-counsel R4**:
   `legal_basis='LGPD Art. 7º II — procedimento preliminar de seleção voluntária'`,
   `trigger_type` (`auto_rescue_never_booked` se sem linha de entrevista, senão `auto_rescue_noshow`),
   `attempt_number=1`, `dispatch_source` (cron|manual), `cycle_id`, `prior_redispatch=v_notify->>'resolution_path'`.

### 2.3 Cron `_selection_unbooked_rescue_cron()` + schedule
SECURITY DEFINER, service-role-only. Varre (predicado):
```
status='interview_pending'
AND c.status='open'
AND cutoff_approved_email_sent_at IS NOT NULL          -- data-architect blocker 2 (explícito)
AND cutoff_approved_email_sent_at < now() - interview_booking_grace   -- ancora no ÚLTIMO convite
AND interview_auto_rescue_count < 1                    -- cap
AND interview_reschedule_requested_at IS NULL          -- reschedule em curso = job33 cuida
AND NOT EXISTS (slot futuro: scheduled/rescheduled com scheduled_at > now())
ORDER BY cutoff_approved_email_sent_at ASC
LIMIT 20                                                -- small-cohort cap (igual job52)
```
Por linha: subtransação `BEGIN ... PERFORM selection_rescue_unbooked_invite(id) ... EXCEPTION WHEN OTHERS`.
Audit run `selection.unbooked_rescue_cron_run` (rescued_count/error_count/run_at/grace/limit).
`grace` lido de `sla_policies.interview_booking_grace` (10d), fallback literal.
**Schedule:** `cron.schedule('selection-unbooked-rescue-daily', '30 15 * * *', ...)` — **15h30 UTC, ANTES do
detector #781 (16h)** para que o detector não notifique antes de o auto-rescue tentar (data-architect Q2:
o re-convite re-seta cutoff=now() → detector bucket A `cutoff < now()-10d` não casa → sem dupla notificação).
Unschedule idempotente antes.

### 2.4 Fix do detector #781 — bucket B ancora no cutoff (data-architect blocker 3, mesmo PR)
No `detect_stuck_selection_funnel`, bucket B (noshow): adicionar
`AND a.cutoff_approved_email_sent_at < now() - v_booking_grace` ao predicado (além do `ns.last_noshow_at`),
para não notificar o GP sobre no-show **já re-convidado** (Edinan/Bruna re-convidados 17/06 mas ainda contados).
Re-aplicar o corpo VERBATIM (Phase-C compara prosrc; copiar do arquivo da mig 208 + 1 linha).

### 2.5 Invariante `AI_unbooked_rescue_cap_respected` (data-architect rec; 35→36)
```
'selection_applications com interview_auto_rescue_count > 1 (acima do cap=1)'  severity medium
SELECT count(*) FROM selection_applications WHERE interview_auto_rescue_count > 1
```
Baseline 0. `check_schema_invariants` CREATE OR REPLACE = reproduzir corpo VERBATIM da última mig que a
define (mig 216) + append AI. Bumpar os 3 testes que pinam o total (35→36) / o `>=` em 766-pr5.

### 2.6 (rec, mesmo PR) expandir `get_cutoff_dispatch_health`
Incluir o 3º cron (`selection.unbooked_rescue_cron_run`) + `pending_unbooked` live count, para o GP ver a
saúde do funil sem cron invisível. (Se inflar o PR, vira follow-up imediato — decidir no build.)

---

## 3. Gating de go-live (legal-counsel — antes do 1º disparo AO VIVO, padrão D7)
- **R1 (necessário):** template `selection_cutoff_approved` ganha linha de **saída por inação** ("Se não tem
  mais interesse, nenhuma ação é necessária — a candidatura será encerrada ao fim do prazo."). Afeta também o
  1º convite (aceitável/desejável). **Revisão de copy pelo PM.**
- **R3 (rec):** variante de copy reconhecendo o contato anterior para no-show (parágrafo condicional por
  `trigger_type`). Não-bloqueante.
- **R5 (necessário):** verificar DPA/cadeia de operadores do provedor do link de booking (Calendly/Cal.com/etc.).
- O cron pode ser criado e validado por **dry-run** (a RPC envia e-mail real → NÃO invocar ao vivo na validação;
  validar via probe ROLLBACK + dry-run lógico da coorte, padrão D7).

---

## 4. Validação (GC-097)
- Coorte alvo do cron (dry SELECT do predicado) = Hector (1) hoje; Edinan/Bruna NÃO (convite fresco 2d).
- Probe ROLLBACK da RPC: `DO` block que chama a RPC, assere count incrementado + cutoff limpo, `RAISE` p/ rollback.
- Invariantes 36/0 (AI=0). `npx astro build` verde. Suíte completa DB-aware. Contrato novo `D3-auto-rescue.test.mjs`.
- Ritual apply_migration: apply MCP → Write arquivo local 219 → `migration repair --status applied 20260805000219`
  → DELETE shadow por NAME → `NOTIFY pgrst`.

---

## 5. Backlog
- Foto de perfil: client-side downscale/compress (teto 2MB baixo p/ celular) — separado do Épico D.
- Após 1 ciclo de confiança, avaliar se o cap=1 deve subir.
