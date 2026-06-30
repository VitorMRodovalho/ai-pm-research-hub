# ADR-0115 — Gate Matrix v3: cadeia de ratificação de Material change (#975, PR-3 de #571)

**Status:** Accepted (2026-06-30, #975 — PR-3 da Camada 5 / #571)
**Relacionado:** ADR-0016 (IP ratification, gates-as-data — **este ADR a amenda**) · ADR-0113 (PR-1: change_class + calendário BR — usado p/ a janela em dias úteis) · ADR-0114 (PR-2: version-pin) · ADR-0102 (GR-1 visibility≠actionability) · ADR-0105 (#785 confidencial) · `docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md` §5 PR-3 + §9.4 + §4.
**Migration:** `20260805000303_975_pr3_camada5_material_ratification_chain.sql`.

## Contexto

A frente **WA2** da Camada 5 (Política **12.2.2**) exige que a ratificação de uma **Material change** da Política seja dirigida por três etapas: **Comitê de Curadoria por maioria simples** → **ratificação obrigatória do PMI-GO** → **consulta consultiva aos capítulos parceiros por 15 dias úteis, SEM poder de veto**.

O estado vivo (auditado este turno) implementava o oposto no que toca aos parceiros: o único gate de parceiro, **`president_others`** (threshold `4`), é **bloqueante** — a chain de policy não aprovava sem os 4 presidentes de capítulo assinarem. Na prática, **os capítulos parceiros tinham veto de fato** ("veto invertido"). Além disso, o subsistema de gates (ADR-0016) só sabia expressar thresholds `'all'` | `int>=0`; "maioria simples" e "janela consultiva" eram inexprimíveis, e `approval_chains` não tinha conceito de prazo/janela.

## Decisão

**1. Schema de gate estendido (amenda ADR-0016): `{kind, order, threshold, blocking?, window_business_days?}`.**

Dois novos `threshold` string: `'majority'` e `'window_optional'`. Dois novos `kind`: `committee_majority` e `partner_consultation`. `_validate_gates_shape` foi estendido **nos DOIS branches na MESMA migration** (invariante §4.4): allowlist de `kind` **E** allowlist de `threshold` string — esquecer o segundo faria o INSERT da chain estourar o CHECK `approval_chains_gates_shape`. As chaves opcionais (`blocking` boolean, `window_business_days` int≥1) são validadas quando presentes ("aceita novos campos / rejeita malformados").

**2. `partner_consultation` — consultivo, janelado, NUNCA bloqueante (o "sem veto" do 12.2.2).**

- `_can_sign_gate('partner_consultation')` reusa **exatamente** o predicado de `president_others` (capítulos CE/DF/MG/RS + `chapter_board` + `legal_signer`; 4 elegíveis ao vivo). **NÃO repropositamos `president_others`** — `cooperation_agreement`/`_addendum`/`manual` legitimamente continuam a usá-lo bloqueante.
- O caráter não-bloqueante vive **inteiramente** em `_gate_threshold_met` (threshold `'window_optional'`), nunca em `_can_sign_gate` (que permanece o **denominador PURO** — invariante #654). `window_optional` é atingido quando: a **janela auto-fechou** (`auto_closed_at` escrito pelo cron) **OU** todos os elegíveis responderam (**qualquer** `signoff_type` — uma `rejection` de parceiro é **registrada mas nunca veta**).
- Como `partner_consultation` é o **último** gate da cadeia e é `window_optional`, a chain **sempre conclui** após a janela de 15 dias úteis, independentemente de silêncio ou discordância dos parceiros. É essa propriedade estrutural — não um flag — que garante o "sem veto".

**3. `committee_majority` — maioria simples determinística contra roster pinado.**

- `_gate_threshold_met('majority')`: `count(approvals do roster) > floor(cardinality(roster)/2)` (maioria estrita). O **roster é lido do snapshot** (`approval_chains.gate_state`), pinado na ativação do gate, **não** de `_can_sign_gate` ao vivo — senão encolheria mid-flight se um membro saísse de função (#654 / SPEC §9.4). Roster vazio ⇒ não atingido (quórum falha).
- `_can_sign_gate('committee_majority')` é **stub `false`** até **§7.1** (composição/quórum do Comitê de Curadoria — questão aberta legal/PM). Roster snapshotado fica vazio ⇒ a maioria nunca é atingida ⇒ o gate fica **dormente** sem travar outros gates. No go-live, trocar o stub por um predicado de designação (ex.: `'ip_committee' = ANY(designations)`); a matemática da maioria já lê o snapshot, então **nenhuma outra mudança** é necessária.

**4. `approval_chains.gate_state jsonb` + `_activate_eligible_gates` + 2 triggers.**

`gate_state` (`{<kind>:{eligible_from, eligible_snapshot, committee_roster_ids, window_business_days, window_closes_at, auto_closed_at}}`) persiste a âncora de elegibilidade, o roster/denominador snapshotado e a janela. `_activate_eligible_gates(chain)` (SECDEF, idempotente, único UPDATE batched) escreve a entrada de um gate `majority`/`window_optional` **quando ele fica elegível** (prior gates satisfeitos), snapshotando o cohort via `_can_sign_gate` PURO e computando `window_closes_at = add_business_days(now(), window_business_days)`. Disparado por dois triggers finos: **ao abrir a chain** (`AFTER INSERT OR UPDATE OF status WHEN status='review'` — snapshota o 1º gate) e **a cada signoff** (`AFTER INSERT` em `approval_signoffs` — abre a janela do gate seguinte quando o anterior é satisfeito). Sem recursão: o UPDATE só toca `gate_state` (não `status`), logo não re-dispara o trigger da chain nem `trg_sync_ratification_cache` (que é `UPDATE OF status`).

**5. Cron `ratification-window-close-daily` (07:00 UTC).**

`ratification_window_close_cron()` (SECDEF, REVOKE PUBLIC/anon/authenticated): fecha janelas consultivas expiradas (escreve `auto_closed_at`), **re-avalia a conclusão da chain espelhando exatamente `sign_ip_ratification`** (`COUNT(gates WHERE NOT _gate_threshold_met)=0` ⇒ `status='approved'`) e notifica o submitter. Idempotente (`auto_closed_at` escrito uma vez); `FOR UPDATE` serializa contra signoffs concorrentes. **On-read nunca vira status sozinho** — só este cron e `sign_ip_ratification` concluem a chain.

**6. `resolve_default_gates('policy')` → template de 3 gates.**

`[committee_majority(1,majority) → president_go(2,1) → partner_consultation(3,window_optional,blocking=false,window_business_days=15)]`. Demais doc_types inalterados.

## Por que dropar `curator` + `submitter_acceptance` do template de policy

A cadeia 12.2.2 é a **ratificação** de uma Material change, não o ciclo editorial. A revisão curatorial e o aceite do proponente acontecem **upstream**, no fluxo de Change Request (`submit → review → approve`, SPEC §6 passo 4); o **Comitê de Curadoria deliberando por maioria É** o órgão curatorial desta cadeia (substitui o gate `curator`/`all` unânime por uma deliberação colegiada). Manter `submitter_acceptance` seria redundante com o aceite no CR. (Decisão de modelagem do implementador, fiel ao texto do issue #975 que lista exatamente os 3 gates; sinalizada à revisão adversarial.)

## Dormência e go-live (build-ahead)

- **Behavior-neutral no apply:** a troca de `resolve_default_gates('policy')` só afeta chains **novas**; a chain de policy **in-flight** em `review` mantém seus gates já materializados (`president_others/4`). `gate_state` só é escrito p/ gates `majority`/`window_optional`; nenhuma chain existente os possui ⇒ zero efeito observável. `committee_majority` stub-false ⇒ uma chain de policy nova fica dormente.
- **Go-live aguarda §7.1** (composição/quórum do Comitê) **+** ratificação do v2.7. Não se abrem chains de policy novas até lá (padrão build-ahead do projeto).
- **Limitação conhecida (SPEC §9.5):** a janela de 15 úteis usa o calendário **GO/sede** (`add_business_days`); feriados estaduais de CE/DF/MG/RS não são observados. Aproximação aceita; documentada.

## Invariantes honradas

- **#654 pureza:** `_can_sign_gate` permanece puro (sem awareness de chain-state); roster/janela vivem em `_gate_threshold_met` + `gate_state`.
- **§4.4:** os dois branches de `_validate_gates_shape` estendidos atomicamente.
- **§4.1 append-only / imutabilidade:** nenhuma linha lacrada é mutada; signoffs continuam append-only.
- **GR-1 (ADR-0102):** as notificações dos 2 kinds vão **só a signatários elegíveis** (`_can_sign_gate`); `committee_majority` stub-false ⇒ ninguém é notificado (dormente). O cron notifica só o submitter na conclusão.
- **`check_schema_invariants()` = 0** (PR-3 não adiciona invariante; não toca `check_schema_invariants`).

## Correções da revisão adversarial (4 lentes, `wf_2925e793-a49`, antes do apply)

Revisão por legal-counsel + data-architect + security-engineer + senior-software-engineer (cada uma tentando quebrar a migration). Verdict consolidado = APPLY_AFTER_FIXES. Incorporadas:

- **BLOCKER (4/4 lentes): `window_optional` auto-satisfazia com `eligible_snapshot=0`** (`count(*)>=0` é vacuamente TRUE) — uma chain de Política poderia concluir com ZERO consulta. Fix: guard `eligible_snapshot::int > 0` no branch de contagem (com 0 parceiros, só `auto_closed_at`/cron fecha o gate ⇒ a janela de 15 úteis sempre roda). Espelha o guard `n>=1` do `committee_majority`.
- **HIGH (security): `gate_state` era gravável por qualquer `manage_member`** (não GP-only) via a policy `approval_chains_update_admin`, permitindo forjar `auto_closed_at`/roster e concluir sem consulta (mesmo bypass do BLOCKER por outra porta). Fix: trigger `trg_guard_gate_state_system_only` (SECURITY INVOKER, `BEFORE UPDATE OF gate_state`) **bloqueia** writes de `gate_state` salvo writers de sistema (`current_user IN postgres/supabase_admin/service_role`); `_activate`/cron são SECDEF owned-by-postgres ⇒ liberados.
- **HIGH: notificação `chain_approved` assimétrica** (cron notificava, assinatura-antecipada silenciava). Fix: trigger `trg_notify_chain_approved` (`review→approved`) centraliza a notificação em ambos os caminhos sem editar `sign_ip_ratification`; `project_charter` é pulado (tem notifier dedicado). Chamada explícita removida do cron (evita duplicar).
- **MEDIUM: `_activate_eligible_gates` sem `FOR UPDATE`** (clobber concorrente). Fix: `SELECT … FOR UPDATE` serializa.
- **MEDIUM: REVOKE ausente** nos 2 wrappers de trigger SECDEF. Fix: REVOKE PUBLIC/anon/authenticated.
- **MEDIUM (legal): janela de 15 úteis usa calendário GO** sem divulgar aos parceiros (transparência LGPD Art. 6º VI). Fix: texto da notificação `partner_consultation` agora declara "contados pelo calendário de feriados de Goiás".
- **`count(DISTINCT signer_id)`** no branch `window_optional` (auto-documenta "respondentes distintos"; o UNIQUE `approval_signoffs(chain,gate,signer)` já existente garante 1 linha/membro — verificado ao vivo, 0 dups, índice não precisou ser criado).
- **REJEITADO — finding #9** (data-architect, low): "escopar o trigger de signoff a `WHEN NEW.gate_kind IN (committee_majority, partner_consultation)`". **Inseguro:** o signoff que torna `partner_consultation` elegível é o de **`president_go`** (gate anterior), não um de `partner_consultation` — esse `WHEN` impediria a ativação cross-gate. O trigger fica sem `WHEN` (overhead desprezível: 1 SELECT + loop curto). Documentado.
- **#10 (blocking declarativo):** `blocking` mantido (mandato do schema da SPEC) com `COMMENT` explícito de que é metadado declarativo — o não-bloqueio vem do `window_optional`.

## Alternativas rejeitadas

- **Repropositar `president_others` como não-bloqueante:** quebraria `cooperation_agreement`/`_addendum`/`manual` que legitimamente precisam dele bloqueante. Rejeitada (SPEC §5 PR-3).
- **`blocking` como flag funcional que pula o gate:** desnecessário — `window_optional` (gate final, auto-satisfaz na expiração) já realiza o não-bloqueio estruturalmente. `blocking=false` fica como metadado declarativo/forward-compat.
- **Roster ao vivo (via `_can_sign_gate`) no cálculo da maioria:** encolheria mid-flight; quebraria #654. Rejeitada — roster pinado no snapshot.
- **`committee_majority` com predicado de designação já agora:** não há designação `ip_committee` e a composição/quórum é questão aberta §7.1. Stub-false até a deliberação legal/PM.
