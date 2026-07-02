# Aftershow Núcleo IA & GP (16/07) — executable event plan (#1006)

**Issue:** #1006 (EPIC #1002). **Depends on gate:** #1008 (disclosure) · #1009 (ROPA/comunicado).
**Type:** event-production plan — program + Airmeet + registration/privacy + certificate flow + 2-track comms.
**Lane:** planning/governance, **docs-only, NOT dev** — the event runs **outside the platform** (Airmeet),
**zero migration**, reusing existing certificate RPCs (`issue_certificate` / `counter_sign_certificate`, ADR-0098).

> **This plan is subordinate to the #1008 gate.** Nothing on the "locked" (Track 1) comms/certificate track ships
> until BOTH gates in `EVENT_1008_AI_COMMUNITY_DAY_DISCLOSURE_GATE.md` §5 are green. This doc produces the
> executable plan + drafts; it does not clear the gate. See §6/§7.

---

## 0. Grounding (live, 2026-07-01)

Re-queried this session (per CLAUDE.md grounding rule), not carried from issue bodies:

| Fact | Value | Source |
|---|---|---|
| Active members | **82** | `members WHERE is_active` |
| Active chapters | **11** | `members` distinct chapter |
| Webinars scheduled in July | **0** (clean slate) | `webinars` 2026-07 |
| Current cycle in DB | **Ciclo 3** still `is_current` (C4 turn = ops #1004, 09/07) | `cycles` |
| Certificate primitive | `issue_certificate(p_data jsonb)` + `counter_sign_certificate(p_certificate_id,…)` | `pg_proc` |
| Cron `offboard-antonio-c3-2026-07-03` (jobid 75) | **active**, `0 12 3 7 *` (09:00 BRT 03/07) | `cron.job` |

**Audience pool (target):** ~82 active members + leadership track + incoming Cycle-4 cohort (onboarding anchor,
#1005) + external guests from the 11 chapters. Attendance-cert emission is bounded by who actually attends, not
the pool.

---

## 1. Event concept (locked to the #1008 framing)

- **Name:** **"Aftershow Núcleo IA & GP"** (own name; "AI Community Day" referenced **descriptively** only —
  never as the event title). Reason: gate §0 headline decision.
- **When:** **16/07/2026, 19h–21h BRT** (2h). The night slot is the defensible, non-competing axis: the PMI
  GLOBAL AI Community Day runs ~10h–17h BRT; the aftershow does not overlap and captures the after-hours
  professional.
- **Where:** **Airmeet** (outside the platform). No new feature/migration.
- **What it is:** the chapter community's night meetup to *continue the conversation* about the new PMI AI
  Standard — an autonomous, independent Núcleo event. **Not** a PMI extension/parallel/official event.
- **What it is NOT (hard nos, gate §5 Path-A non-negotiables):** no "oficial/co-presented by PMI/extensão do
  PMI Global"; no PDU as a granted fact; no "AI Community Day" as the local title without written ratification;
  no reuse of the global visual identity/logo; no speaking *on behalf of* PMI Global/Latam; no certificate
  "emitido pelo PMI".

---

## 2. Program / run-of-show (19h–21h BRT)

Three formats in progression: **keynote → fishbowl → mesa redonda** (decision PM 2026-07-01, #1006).

| # | Bloco | Início | Dur | Formato | Responsável | Notas |
|---|---|---|---|---|---|---|
| 1 | Abertura + contexto (AI Day/PMI Standard, framing referencial) | 19:00 | 10 min | — | Host/PM | Ler disclaimer de não-endosso no slide de abertura (gate §3). Sem claim de PDU. |
| 2 | Keynote (convidado especial) | 19:10 | 30 min | palestra | Convidado + moderador | Curadoria §5. Tema ancorado no AI Standard (credibilidade), voz externa/PMI-Latam se possível. |
| 3 | Fishbowl "IA responsável na prática" | 19:40 | 40 min | participativo | Facilitador fishbowl | 4–5 cadeiras + 1 rotativa; roteiro de moderação próprio. |
| 4 | Mesa redonda temática (capítulos) | 20:20 | 30 min | roundtable | Host de mesa + presidentes | Presidentes em rodízio = prova social; 1 host indicado por capítulo. |
| 5 | Encerramento + próximos passos + certificado | 20:50 | 10 min | — | Host/PM | Explicar fluxo de certificado (participação, §4); anunciar os 11 follow-ups (§8). |

**Moderation kit (produce before D-2):** roteiro por formato (abertura/keynote Q&A/fishbowl/mesa); rotation
rules for the fishbowl chair; a pinned "house rules + non-endorsement" message for the Airmeet chat.

---

## 3. Airmeet setup + registration + privacy notice

### 3.1 Room build
- [ ] Airmeet event created: main stage (keynote + fishbowl) + breakout/temáticas para a mesa se necessário.
- [ ] Recording ON → VOD (on-demand) + clip capture (§8). **Image/recording consent** must be collected at
      registration (see 3.3) — do not record without it (cross-ref #729).
- [ ] Branding uses **Núcleo** identity only — **no PMI global visual identity/logo** (gate §5 Path-A).
- [ ] **D-2 technical rehearsal 14/07** (audio, screenshare, breakout, recording) — locked in #1006.

### 3.2 Registration page
- [ ] Title/subtitle + positioning + framing paragraph + non-endorsement disclaimer = **verbatim from gate §3**
      (`EVENT_1008…GATE.md`). Do not re-author; the language is legally locked.
- [ ] **Track discipline:** the *save-the-date* (Track 0) can point to registration now with Núcleo-only copy.
      Any PDU-adjacent language / global-name reference stays OUT until gate §5 Track-1 is green.
- [ ] Collect **name + e-mail only** (data minimization, Art. 6º III). No PMI ID / cargo / empresa unless a
      justified need is added — and if added, it needs its own basis in the notice.

### 3.3 Privacy notice (LGPD) — registration page checklist
Legal-counsel requirements (gate §3 + §7). The Airmeet notice **must** cover:
- [ ] **Legal basis = consent** (Art. 7º, I).
- [ ] **International transfer** for Airmeet (Lei 13.709/18 arts. 33–36): verify Airmeet **DPA/SCCs**; if absent,
      rely on **specific consent** (Art. 33, VIII) and say so.
- [ ] **Data minimization** (name + e-mail only; enumerate exactly what is collected).
- [ ] **Manual Art. 18 channel** — a **DPO/contact e-mail**. The platform's export/delete/anonymize cron does
      **NOT** reach Airmeet data; rights requests over registration data are handled manually.
- [ ] **Image/recording consent** if the session is recorded (cross-ref #729).
- [ ] **Sharing with PMI-GO/PMI?** If the participant list will be shared, that is a **second processing** — it
      needs its own stated basis + notice, not inferred after the fact. Default: **do not share** unless decided.
- [ ] **Cross-ref #1009 (ROPA):** ensure this event's processing is registered there, and the dated communiqué
      to the 11 chapter presidents is issued.

> **Owner note:** this privacy notice is a **human/legal deliverable** (DPO e-mail + Airmeet DPA verification are
> outside this lane). The plan supplies the checklist + the locked framing copy; legal fills the DPO channel and
> confirms the transfer basis.

---

## 4. Certificate flow (participation — reuse, no new code)

**Reuses the platform primitive** — zero migration. **Option A only** (safe, **no PDU**), per gate §2. Option B
(PDU self-declaration language) stays **disabled** until PMI confirms the CCR category in writing.

**Flow (post-event, after 16/07):**
1. **Attendance capture** — register who attended (Airmeet attendance export → `register_attendance` MCP tool /
   attendance registration). Attendance is the gate for who gets a cert.
2. **Issue** — `issue_certificate(p_data jsonb)` with `type = participation`, the **locked Option-A copy**
   (gate §2), 2h carga horária, no PDU field. Certificate is **Núcleo-issued**, under its own responsibility.
3. **Counter-signature** — `counter_sign_certificate(...)` by the authorized Núcleo/PMI-GO representative
   (ADR-0098/0104), same pattern as the #1003 cycle-closure cert.
4. **Verification** — public `verify_certificate` (already hardened in #991: shows authority + counter-signature
   flag, **no issuer PII**). The locked copy carries the non-endorsement clause in the certificate body itself.

**Locked certificate copy:** use **verbatim** from gate §2 (Option A). **Forbidden strings** (any = fail gate):
"concede N PDUs", "vale X PDUs", "válido como PDU oficial", "chancelado pelo PMI", "evento oficial do PMI",
"emitido pelo PMI".

> **Distinction from #1003:** #1003 issues the *first-ever cycle-completion* certificate for C3 closure. This
> event issues a *participation* certificate for the 16/07 aftershow. Same primitive + counter-sign pattern,
> different `type` and copy. Do not conflate the two emissions.

---

## 5. Guests & chapter coordination (11 chapters)

- [ ] **Convite às diretorias dos 11 capítulos** (dated communiqué — cross-ref **#1009**); each indicates a
      **mesa host or palestrante**.
- [ ] **Curated external guests** (priority order, from #1006 startup-advisor council):
      1. Someone tied to the **AI Standard** (credibility);
      2. **Chapter presidents in rotation** (social proof);
      3. A **corporate case** (Path B signal);
      4. An **international PMI-Latam voice**.
- [ ] **Name a quote/clip owner BEFORE 16/07** (so the VOD can be fragmented fast — §8).
- [ ] Cross-promo unificada (comms + social + wiki) — subject to track discipline (§6).

---

## 6. Comms — two tracks (from gate §0)

| | **Track 0 — ship NOW (zero-risk)** | **Track 1 — locked (needs gate §5 green)** |
|---|---|---|
| What | Save-the-date, Núcleo-only language | Final invite/page copy referencing global name, PDU language, certificate copy |
| Name | "Aftershow Núcleo IA & GP" only | May add descriptive AI-Community-Day reference **iff** PMI-GO answers in writing |
| PDU | **No mention** | Only Option-B language **iff** PMI confirms CCR category |
| Depends on | Nothing (no third-party authorization) | Gate A (PMI-GO written answer) **and** Gate B (legal sign-off) |
| Channels | Registration link, chapter DMs, wiki save-the-date | Full campaign (IG/LinkedIn carrossel, e-mail), certificate issuance |

**Post-event content (startup-advisor, #1006):** do **not** publish 2h corridas. Fragment the VOD into **3 clips**:
(1) practical case → Path B; (2) expert guest → whitepaper/Path A; (3) chapter roundtable → community. Segment
registrants into **3 funnels within 72h** (membership candidate / chapter leadership / corporate lead).

---

## 7. Gate status — what must be green before Track 1 (live check needed each session)

From `EVENT_1008…GATE.md` §5. **All are human/legal actions outside this lane.** As of 2026-07-01 (last grounded):

- [ ] **Gate A** — PMI-GO answers the §4 memo **in writing** (descriptive reference OK + PDU/Standard guidance).
- [ ] **Gate B** — `legal-counsel` signs off on final certificate + invite (Option A vs B).
- [ ] **Contract check** — reread ADR-0104 PMI brand-use clause; if prior approval is required for any PMI
      mention, obtain it in writing first (**sharpest Path-A trap**).
- [ ] **INPI check** — search "AI Community Day" before publishing any piece with the name (even descriptive).
- [ ] **Airmeet privacy notice live** (§3.3) — base legal + transfer + manual Art. 18 + sharing decision.
- [ ] **#1009** ROPA registered + dated communiqué to the 11 presidents issued.

**Fallback if the fuse tightens with no PMI-GO answer:** publish under the Núcleo-only name only; never publish
unratified name/PDU language.

> Re-query these each working session — issue-body state is stale by rule. Check #1008/#1009 comments and ADR-0104.

---

## 8. Timeline (D-minus countdown)

| Date | Milestone | Owner | Track |
|---|---|---|---|
| **02–03/07** | C3 closure (#1003) — sealing/certs/exits; Antonio offboard cron (jobid 75, 03/07 09:00 BRT) | ops | — |
| **now** | Ship Track-0 save-the-date + open Airmeet registration (Núcleo-only) | comms | 0 |
| **now (async)** | Send §4 PMI-GO memo; start ADR-0104 reread + INPI check + Airmeet DPA check | Vitor/legal | gate |
| **09/07** | C4 access turn (#1004) — cohort provisioning (separate ops lane) | ops | — |
| **by ~11/07** | Confirm keynote + fishbowl facilitator + 11 chapter mesa hosts; name clip owner | PM/chapters | — |
| **when gate green** | Publish Track-1 full campaign (invite/page/PDU-language decision) | comms | 1 |
| **14/07 (D-2)** | Airmeet technical rehearsal | production | — |
| **16/07 19–21h** | **Event** (keynote → fishbowl → mesa) | all | — |
| **16–17/07** | Attendance capture → issue participation certs (Option A) → counter-sign | PM/GP | — |
| **17–18/07** | 11 chapter 15-min follow-up calls; VOD → 3 clips; 3-funnel segmentation (72h) | PM/startup | — |

---

## 9. Acceptance criteria (#1006)

- [ ] Executable program (run-of-show §2) with formats + owners + moderation kit.
- [ ] Airmeet room + registration + LGPD privacy notice checklist (§3) ready for the human/legal fill-in.
- [ ] Participation-certificate flow defined, reusing `issue_certificate` (Option A, **no PDU**, counter-sign) (§4).
- [ ] Two-track comms plan (§6) aligned to the #1008 gate; Track 0 shippable now, Track 1 gated.
- [ ] Post-event momentum plan (11 calls + 3 clips + 3 funnels) (§8/§6).
- [ ] Gate-status checklist (§7) surfaced so no Track-1 piece ships before it is green.
- [ ] **No PDU claim; no implied endorsement; no reuse of the global name/identity** anywhere in the plan.

---

## 10. Out of scope (do not pull in)

- **#1004** C4 access turn (09/07) and **#1003** C3 closure (02–03/07) — already detailed/scheduled (sibling
  docs; cron jobid 75 handles Antonio's offboard 03/07).
- **#1000/#1001** VEP selection filters — dev lane.
- **#1026/#1020/#1021/#1022** structural improvements — filed, do not block 16/07.
- Any migration/feature — this event is **outside the platform** by decision (#1006 council).

**Human/legal deliverables (not this lane):** PMI-GO memo + written answer; ADR-0104 reread; INPI check; Airmeet
DPA verification + DPO channel; legal sign-off; the actual guest invitations. **Merge = main session** (this
branch is prepared, never merged — see `feedback-merge-to-main-is-main-session-only`).
