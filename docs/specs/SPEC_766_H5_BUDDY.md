# SPEC: Buddy / padrinho pós-promoção — #766 item 4/4 (H5)

**Status:** Draft — council aplicado (product-leader + ux-leader + data-architect, 2026-06-17, todos GO-with-changes); aguardando OK do PM antes do PR1
**Priority:** 🟢 Green / non-blocking (resíduo social do discovery, ÉPICO H, H5)
**Created:** 2026-06-17
**Author:** Claude (PM/Architect) + Vitor (GP)
**Decisões de produto já tomadas pelo PM (2026-06-17, AskUserQuestion):**
1. **Modelo de pareamento = BILATERAL** (oferta + aceite) — análogo ao loop de convite de iniciativa (ADR-0061 w2) e ao aceite-do-líder do `select_tribe` (B8). Ambos consentem; ninguém "cai" como afilhado.
2. **Direção do convite = PADRINHO SE VOLUNTARIA** — um sênior da tribo se oferece para padrinhar; o afilhado aceita. Dá agência ao sênior; tom mão-dupla.
3. **Escopo MVP = PONTEIRO SOCIAL LEVE** — superfície pós-promoção mostra "seu padrinho é X — fale no WhatsApp"; **SEM** check-ins, duração, ou relacionamento de mentoria rastreado.

---

## 1. Contexto & problema

`PRE_ONBOARDING_JOURNEY_DISCOVERY_2026-06-16.md` (ÉPICO H, linha 140):

> **H5** — "Sem buddy/padrinho nos primeiros dias (mentor de tribo) — onboarding social." Severidade **🟢**, fonte: candidato.

O onboarding atual termina na assinatura do termo. O recém-promovido entra na tribo sem um ponto humano de contato ("com quem eu falo?"). H5 cobre o **onboarding social**: um par sênior da própria tribo que se apresenta nos primeiros dias.

**É o último item aberto do #766** (marcos server-side ✅ + J4 SLA configurável ✅ fechados). Por ser 🟢, o SPEC deliberadamente resiste a inflar o escopo: pareamento mínimo + ponteiro, nada de plataforma de mentoria.

---

## 2. Aterramento server-side (grounded — `execute_sql` 2026-06-17, projeto `ldrfrvwhxsmgaabwmaik`)

| Fato | Verificado | Implicação no design |
|------|------------|----------------------|
| **Não existe** tabela/RPC buddy/padrinho/mentor/pairing | ✅ grep migrations vazio | Modelo de dados novo, mas DEVE espelhar primitivo existente |
| `initiative_invitations` = loop bilateral rico (`inviter_member_id`/`invitee_member_id`/`status`/`expires_at`/`responded_at`/`responded_note`/`revoked_*`), RPCs SECDEF `create_initiative_invitations` + `respond_to_initiative_invitation` (ADR-0061 w2, mig `20260514330000`) | ✅ lido | **Padrão a espelhar**, MAS acoplado a iniciativa (FK `initiative_id` NOT NULL + `kind_scope` validado contra `engagement_kinds` + cria `engagement` no accept). Nada disso cabe em buddy → **tabela própria mínima** (`buddy_pairings`), não reuso direto. |
| `members.tribe_id` (integer) — ligação direta membro→tribo | ✅ | Pool de padrinhos = membros da mesma `tribe_id` |
| `members.operational_role`: guest 27 / researcher 26 / tribe_leader 6 / sponsor 5 / chapter_liaison 5 / observer 4 / manager 2 | ✅ | Elegível a padrinhar = ativo da tribo, **não-`guest`** (guest = pré-onboarding). Afilhado = recém-promovido (entrou como researcher na tribo). |
| **`members.share_whatsapp` (boolean)** + `phone` (text) + `phone_encrypted` (bytea) | ✅ | **Resolve o LGPD do ponteiro**: WhatsApp só é exposto se `share_whatsapp=true`. |
| `select_tribe` term-gated (mig `20260309010000`) | ✅ (handoff) | Referência de tom "mão-dupla e caloroso" (discovery linhas 143-148) |

> ⚠️ **Reuso vs tabela nova (a confirmar com data-architect):** `initiative_invitations` poderia teoricamente ser generalizado, mas o acoplamento a `initiative_id`/`kind_scope`/criação de `engagement` torna o reuso um *stretch* semântico que sujaria aquele primitivo. A recomendação é uma `buddy_pairings` mínima que **espelha o shape** (mesmos nomes de coluna onde fizer sentido) sem herdar o acoplamento.

---

## 3. Fluxo (volunteer-driven, bilateral)

Mapeando "padrinho se voluntaria" no padrão invite→respond:

| Papel | Quem | Equivalente em `initiative_invitations` |
|-------|------|------------------------------------------|
| **Padrinho** (inicia, se oferece) | sênior ativo da tribo (researcher/tribe_leader) | `inviter_member_id` |
| **Afilhado** (aceita/recusa) | recém-promovido da tribo | `invitee_member_id` |

```
1. Afilhado é promovido → entra na tribo (tribe_id setado, operational_role researcher).
   → aparece no "pool de quem ainda não tem padrinho" visível aos seniores da MESMA tribo.

2. Sênior da tribo vê o pool → "Quero ser padrinho de <afilhado>"
   → offer_buddy(afilhado) → buddy_pairings (status='offered', padrino=sênior, afilhado=X).

3. Afilhado vê "<sênior> se ofereceu para ser seu padrinho" (notification + card)
   → respond_to_buddy_offer(pairing, 'accept'|'decline').
   → accept: status='accepted' → ATIVA o ponteiro social.

4. Ponteiro (superfície leve, pós-aceite):
   - Afilhado vê: "Seu padrinho é <sênior> — fale no WhatsApp [link]" (link só se share_whatsapp).
   - Padrinho vê: "Você é padrinho de <afilhado>".
```

**Quem é elegível a se voluntariar como padrinho? (RESOLVIDO — product-leader):** membro ativo da **mesma `tribe_id`** do afilhado, com `operational_role NOT IN ('guest')` (i.e., já estabelecido — researcher/tribe_leader/etc.), e que **não seja o próprio afilhado**. **Cadeia PERMITIDA**: um researcher recém-promovido (que é afilhado de alguém) pode padrinhar outro — bloquear cadeia exigiria uma checagem extra na RPC sem ganho para o MVP. Sem requisito de tempo mínimo de casa (exigiria um campo de data-de-entrada-na-tribo, overhead alto para 🟢). Regra final na RPC: *não-guest da mesma tribo, não-self*.

**Cobertura (risco reconhecido pelo PM; product-leader confirmou suficiente para 🟢):** o modelo volunteer-driven pode deixar afilhados **sem padrinho** se nenhum sênior se oferecer. MVP **não** faz auto-atribuição. Insight do product-leader: o *floor* é o estado de hoje (nenhum buddy existe) — o MVP só melhora; um afilhado sem par não está pior do que antes. Mitigação leve via UX (não nova lógica): o `tribe_leader` enxerga os afilhados não-pareados na aba Membros da tribo (§6c). Documentado como limitação aceita do MVP 🟢. **Métrica de alerta:** se 0% dos researchers com <60 dias de tribo tiver par ativo em 4 semanas pós-launch, o risco "ninguém se voluntaria" materializou-se → revisar (ver §10).

---

## 4. Modelo de dados proposto

```sql
CREATE TABLE public.buddy_pairings (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  padrino_member_id   uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,  -- inviter (se oferece)
  afilhado_member_id  uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,  -- invitee (aceita)
  status              text NOT NULL DEFAULT 'offered',
  message             text,                       -- saudação opcional do padrinho
  offered_at          timestamptz NOT NULL DEFAULT now(),
  responded_at        timestamptz,
  revoked_at          timestamptz,
  revoked_by          uuid REFERENCES public.members(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT buddy_pairings_status_chk
    CHECK (status IN ('offered','accepted','declined','revoked')),
  CONSTRAINT buddy_pairings_distinct_chk
    CHECK (padrino_member_id <> afilhado_member_id)
);

-- No máximo UM par ativo (offered/accepted) por afilhado — afilhado tem 1 padrinho de cada vez;
-- libera re-pareamento após declined/revoked (não estão no predicado).
CREATE UNIQUE INDEX buddy_pairings_one_active_afilhado
  ON public.buddy_pairings (afilhado_member_id)
  WHERE status IN ('offered','accepted');

-- lookup por padrino (get_my_buddy as_padrino + revoke); o afilhado já é coberto pelo índice parcial acima.
CREATE INDEX buddy_pairings_padrino_idx ON public.buddy_pairings (padrino_member_id);

-- updated_at NÃO congela: função de trigger DEDICADA por-tabela (o projeto NÃO tem helper genérico
-- set_updated_at — usa uma fn por tabela, ex. _trg_initiative_invitations_updated_at). Criar a própria:
CREATE FUNCTION public.buddy_pairings_set_updated_at() RETURNS trigger
  LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
CREATE TRIGGER _trg_buddy_pairings_updated_at
  BEFORE UPDATE ON public.buddy_pairings
  FOR EACH ROW EXECUTE FUNCTION public.buddy_pairings_set_updated_at();
```

**Mudanças aplicadas do council (data-architect):**
- **`tribe_id` REMOVIDO da tabela** (CHANGE 1/2). Era cache column derivável de `members.tribe_id` — guardá-la exigiria sync trigger ADR-0012 (drift se o membro trocar de tribo via `select_tribe`) e a FK `ON DELETE CASCADE` em `tribes` apagaria pares historicamente em fusão de tribos. A tribo é sempre derivável dos membros; tabela é pequena, JOIN no RLS é trivial. Se tribe-by-leader virar hot path no futuro, readicionar com trigger.
- **`responded_note` REMOVIDO** (product-leader): herdado por analogia ao convite de iniciativa, sem caso de uso no buddy (afilhado que declina não precisa justificar). Restaurar em v2 se houver demanda.
- **Status `'expired'` REMOVIDO do CHECK** (product-leader): sem cron no MVP, seria estado inalcançável que confunde quem lê o schema. Readicionar junto do cron, se um dia houver expiração.

Demais decisões:
- **`expires_at`?** Oferta **não expira** no MVP (🟢 — sem SLA, sem cron; data-architect confirmou). UX deferiu um possível estado visual "sem resposta há X dias" para v2.
- **RLS:** SELECT para as duas partes (`padrino`/`afilhado` via `members.auth_id = auth.uid()`) + o `tribe_leader` da tribo do par. Como `tribe_id` saiu da tabela, o gate de tribe_leader usa JOIN 2-níveis (`tl.tribe_id = padrino.tribe_id` via `members`); aceitável para tabela pequena. Edge: manager/GP têm `tribe_id IS NULL` → `NULL = NULL` é `false`, GP **não** vê tudo por acidente. INSERT/UPDATE **só via RPCs SECDEF**. FK `ON DELETE CASCADE` nos member FKs cobre LGPD Art. 18.
- **PII:** a tabela só guarda IDs; WhatsApp/telefone vive em `members` e só é exposto pelo `get_my_buddy()` com **duplo gate** `share_whatsapp=true` **E** par `accepted`. O aceite **é** o consentimento bilateral; `share_whatsapp` é o consentimento individual de exposição.
- **Taxonomia (ADR-0013):** Categoria B (Domain Lifecycle Event) — shape próprio, escolha deliberadamente *narrow* (não consolida em `initiative_invitations`) para evitar lock-in semântico; a notificação de oferta É um `notifications`, mas o par é entidade própria.
- **`organization_id` fora do v1** (single-org/PMI-GO — YAGNI, igual ao SPEC de marcos §3).

---

## 5. RPCs (SECDEF, espelhando o padrão ADR-0061 w2)

| RPC | Assinatura | Caller | Papel |
|-----|-----------|--------|-------|
| `offer_buddy` | `(p_afilhado_member_id uuid, p_message text DEFAULT NULL) → jsonb` | padrinho (sênior da tribo) | Valida: caller ativo & não-guest & mesma `tribe_id` do afilhado; afilhado ativo & sem par ativo; sem auto-pareamento. Insere `buddy_pairings` status='offered' + cria `notifications` ao afilhado. |
| `respond_to_buddy_offer` | `(p_pairing_id uuid, p_response text) → jsonb` | afilhado | Valida caller = `afilhado_member_id` & status='offered'. accept→'accepted' + notification ao padrinho; decline→'declined'. *(`p_note` removido — ver §4 `responded_note`.)* |
| `revoke_buddy_offer` | `(p_pairing_id uuid) → jsonb` | padrinho (ou tribe_leader) | Padrinho retira oferta pendente, OU qualquer parte encerra par aceito (status='revoked'). Mantém o índice parcial livre para novo par. |
| `get_my_buddy` | `() → jsonb` | qualquer membro | **Canônico para a superfície FE.** Retorna `{ as_afilhado: {padrino, whatsapp?}, as_padrino: [afilhados], can_volunteer_for: [afilhados sem par na minha tribo] }`. WhatsApp só se `share_whatsapp` + accepted. **Guarda:** se o caller tem `tribe_id IS NULL` (manager/GP), `can_volunteer_for` retorna `[]` (não crashar). |

- `p_message` **opcional** (≠ initiative que exige ≥50 chars) — uma saudação curta basta; 🟢.
- Todas SECDEF com `SET search_path TO 'public', 'pg_temp'` e auth via `members.auth_id = auth.uid()`.
- `offer_buddy` guards finais: caller ativo & não-guest; mesma `tribe_id` do afilhado; afilhado ativo & sem par ativo (índice parcial reforça); não-self.
- **🔧 Nota de implementação (ADR-0011, PR1):** buddy é ação **consensual peer-to-peer**, não autoridade privilegiada — o contrato `rpc-v4-auth` proíbe gates de role (`operational_role`/nome-de-role em `IF/THEN`) em RPC nova sem `can()`. Logo: (a) a **exclusão de guest** do padrinho/afilhado NÃO é um RAISE de role em `offer_buddy`; vive como **filtro de dados** no pool `can_volunteer_for` (SELECT, permitido) + FE — um guest ofertando direto é inócuo (o afilhado ainda precisa aceitar); (b) `revoke_buddy_offer` é **ownership-only** (uma das duas partes) — o **force-revoke do tribe_leader foi deferido** (seria capability de role via `can()`); a visibilidade do tribe_leader p/ cobertura permanece na **policy RLS de SELECT** (não escaneada pelo contrato). O gate real do pareamento é co-membro de tribo + aceite bilateral.
- **GC-097 (checklist do PR1):** RPCs são novas → `CREATE OR REPLACE` sem DROP (confirmar antes: `SELECT count(*) FROM pg_proc WHERE proname IN ('offer_buddy','respond_to_buddy_offer','revoke_buddy_offer','get_my_buddy')` = 0). DDL via `apply_migration` → shadow UTC → `migration repair --status applied <ts-lógico>` + DELETE shadow (NÃO o baseline `name=null`) → arquivo local byte-igual ao live (Phase-C: **rationale no header acima do `CREATE FUNCTION`, NUNCA comentário inline dentro de `$fn$ BEGIN…END`** — sedimento recorrente dos PRs de marcos). `NOTIFY pgrst, 'reload schema'` é obrigatório **também para expor a tabela nova** `buddy_pairings` no schema cache do PostgREST, não só pelas RPCs.

---

## 6. Superfície FE (ponteiro leve — placement RESOLVIDO pelo ux-leader)

Três micro-superfícies, todas trilíngues (pt-BR/en-US/es-LATAM). **Decisão estrutural do ux-leader:** o lado do afilhado **NÃO** é roteado pela ilha global `MilestoneCelebration.tsx` — a ilha é para eventos one-time celebratórios; oferta de padrinho exige *decisão* (não é celebração) e o ponteiro *persiste* (não é efêmero). Misturar os dois causa card fatigue (a ilha já enfileira promotion/first_attendance/etc. com cooldown de 300ms; o recém-promovido veria dois cards seguidos). Em vez disso:

**(a) + (b) — Bloco "Padrinho" inline no `/workspace`** (abaixo do HBLOCK, nível do card "Minha tribo"), com **três estados**:
- *sem oferta* → silencioso (não renderiza nada);
- *oferta pendente* (b) → card de aceite [Aceitar] [Agora não];
- *par aceito* (a) → o ponteiro: nome do padrinho + botão WhatsApp (se `share_whatsapp`) ou fallback.

A notificação via `notifications` (já prevista) cobre o awareness cross-page; o badge de nav já existe. a11y: replicar o padrão da ilha de marcos — `role="status"` no ponteiro, foco programático no 1º botão da oferta (`dismissRef`/`useEffect`), Escape → [Agora não], botões `min-h-[44px]`, `flex-wrap` nos dois botões (375px).

**(c) — Pool do sênior = PULL na aba "Membros" da `/tribe/[id]`** (não card global push — push de responsabilidade não-solicitada contradiz a voluntariedade). Indicador discreto na linha do afilhado sem padrinho ("sem padrinho ainda" + CTA "Oferecer-me como padrinho"), ou uma linha-resumo no topo "N membros sem padrinho". Mesmo filtro serve o `tribe_leader` (mitigação de cobertura §3). Sem rota/aba nova.

**Fallback de contato (`share_whatsapp=false`):** ancorar no link de grupo da tribo **já existente** (`joinWhatsApp`/`chatWhatsApp` em `src/pages/tribe/[id].astro`), não inventar copy nova.

**Microcopy pt-BR (os outros 2 idiomas espelham o tom mão-dupla):**
- (a) ponteiro: título "Seu padrinho no Núcleo" · corpo "**[Nome]** é seu padrinho — alguém de dentro da sua tribo que já passou por onde você está." · CTA "💬 Falar no WhatsApp" (ou "💬 Falar no grupo da tribo").
- (b) oferta: título "**[Nome]** quer ser seu padrinho" · corpo "Ele(a) se voluntariou para te apoiar nos primeiros passos. Você decide." · [Aceitar] [Agora não].
- (c) sênior: linha "sem padrinho ainda" · CTA "Oferecer-me como padrinho" (tom neutro, sem apelo).

**Componente canônico (product-leader Q5):** o card do ponteiro do afilhado é o **componente importado** pela futura jornada pós-promoção H1 — H1 **não** recria o card. Evita dois cards descoordenados.

---

## 7. RLS / LGPD / Segurança

- WhatsApp/telefone: exposto **só** quando `share_whatsapp=true` **e** par `accepted` — duplo gate (consentimento de compartilhar + consentimento do par). Sem isso, ponteiro mostra só o nome + "fale no grupo da tribo".
- Ghost/anon: nada (own-data RLS).
- `buddy_pairings` não é PII por si (são IDs de membro); o conteúdo sensível fica em `members`, atrás do RPC.
- Apagamento Art. 18: `ON DELETE CASCADE` em ambos os FKs de membro.
- *(security-engineer: invocar só se o council de dados levantar bandeira — escopo 🟢, consentimento bilateral + own-data RLS cobrem o caso; não convocar por padrão.)*

---

## 8. Plano de PRs (condiz com 🟢)

- **PR1 — loop de pareamento (DB):** `buddy_pairings` (+ índice parcial + índice padrino + trigger `updated_at`) + 3 RPCs de mutação + `get_my_buddy` + RLS + notifications. GC-097 ritual completo (checklist §5). Teste de contrato (offer→respond→pointer; gates de elegibilidade não-guest/mesma-tribo/não-self; cadeia permitida; LGPD duplo-gate WhatsApp; guarda manager `tribe_id IS NULL`). **Sem invariante** em `check_schema_invariants()` (par é estado mutável bidirecional, CHECK + índice parcial bastam — análogo à decisão "sem invariante" do PR4 de marcos). *Nota:* o data-architect identificou uma invariante direcional livre-de-falso-positivo possível (`AF_buddy_accepted_pair_padrino_active` — par accepted com padrinho inativo), mas recomendou **NÃO** adicioná-la no PR1 (ON DELETE CASCADE já cobre membro deletado; "nice to have" em escala, deferir para H1 se crescer).
- **PR2 — ponteiro social (FE):** bloco "Padrinho" inline no `/workspace` (3 estados a/b) + indicador na aba Membros da `/tribe/[id]` (c) + i18n trilíngue (3 dicts). **Sem rota nova** (placement inline em páginas existentes → não precisa de redirect /en//es/). Componente do ponteiro canônico (reusável por H1).
- **Pode caber em 1 PR** se enxuto. Ao fechar H5: **fechar #766 exige OK do PM** (governança — marcos✅ J4✅ H5✅).

---

## 9. Perguntas abertas — RESOLVIDAS pelo council (2026-06-17)

- **Q1 (product-leader) ✅:** elegível = não-guest da mesma tribo, não-self; **cadeia permitida**; sem requisito de tempo mínimo. (§3)
- **Q2 (data-architect) ✅:** `buddy_pairings` própria (reuso de `initiative_invitations` sujaria o primitivo). Oferta **não expira** (sem cron). `tribe_id` removido da tabela. Índice parcial cobre "1 padrinho ativo"; + índice padrino + trigger `updated_at`. (§4)
- **Q3 (ux-leader) ✅:** (a)+(b) inline no `/workspace` (NÃO ilha de marcos); (c) pull na aba Membros da tribo. Microcopy mão-dupla definida. (§6)
- **Q4 (cobertura) ✅:** só visibilidade do `tribe_leader` (pull) é suficiente para 🟢; floor = estado de hoje. Métrica de alerta em §10. (§3)
- **Q5 (H1/H4/H6) ✅:** o card do ponteiro é componente canônico que H1 **importa**, não recria. H5 = quem cobre o afilhado (contato humano); H1 = o que o afilhado faz (ativação). (§6/§8)

## 10. Métrica de sucesso (leve, condiz com 🟢)

Sem funil de conversão. Proxy único, extraível de uma query `buddy_pairings ⋈ members` (sem novo tracking):

> **% de researchers com <60 dias de tribo que têm um par `accepted`, 30 dias após o launch.**

- Meta mínima razoável: **≥ 30%**.
- **Alerta:** se for **0%** em 4 semanas, o risco Q4 ("ninguém se voluntaria") materializou-se → revisar o modelo (ex.: nudge ativo do tribe_leader em v2).
- **Calibração pré-launch:** verificar a taxa de `members.share_whatsapp = true` — se baixa, o ponteiro cai muito no fallback "grupo da tribo" e o valor percebido diminui (ajustar copy/expectativa).
