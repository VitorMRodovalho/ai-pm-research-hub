# Pré-onboarding == `operational_role='guest'` (modelo e helpers)

> **Status:** referência canônica (D3 do épico #740). **Decisão do PM (não re-litigar):
> NÃO migrar o enum `operational_role` agora** — `guest`↔pré-onboarding fica DOCUMENTADO +
> coberto por helpers. Rename é issue própria (alto blast radius, todos os call-sites).

## O fato

Um membro **em pré-onboarding** (aprovado na seleção, aceito, mas ainda sem o termo de
voluntariado contra-assinado / sem ter sido promovido ao papel real) tem
`members.operational_role = 'guest'`. Esse `'guest'` é um **estado legítimo do ciclo de
vida do membro**, não "visitante anônimo" e não "não-membro".

O membro pré-onboarding **já tem registro** (`members.id`, `auth_id` vinculado,
`get_member_by_auth()` retorna a linha dele) e **precisa** alcançar `/profile` e
`/workspace` para completar consentimento (LGPD), Credly, e-mails alternativos, nome e a
**assinatura do termo** — tudo isso ANTES de ser promovido para fora do `guest`.

## Os três SSOTs (não confundir)

| Conceito | Fonte da verdade | Forma | Para quê |
|---|---|---|---|
| **"é membro registrado?"** | `isRegisteredMember(member)` = `!!(member && member.id)` | helper FE (`src/lib/routing.js`) | gate de **pertencimento** no front-end |
| **"está em pré-onboarding?" (coorte)** | `public.member_is_pre_onboarding(person_id, member_status)` | predicado SQL (mig `20260805000143`) | coorte #625/#626; stats; gates server-side |
| **"qual o papel operacional?"** | `members.operational_role` (cache do trigger `sync_operational_role_cache`) | enum; `'guest'` durante pré-onb | **styling/atalhos por papel**, NÃO pertencimento |

### `isRegisteredMember` (FE) — `src/lib/routing.js`
`!!(member && member.id)`. Um membro retornado por `get_member_by_auth()` carrega `id` →
**é** registrado, independentemente de `operational_role`. O caso genuíno de
autenticado-sem-membro produz `member === null` (tratado pelo fluxo de account-claim WS-B,
`/claim/start`, #735) — esse sim não é membro.

### `member_is_pre_onboarding(uuid, text)` (SQL) — coorte canônica
Regra (#625 C0): `member_status='active'` **E** tem ≥1 engagement ativo **E** NÃO tem
nenhum engagement operacional (kind sem `requires_agreement`, ou com termo já satisfeito
via `agreement_certificate_id`). Existir 1 engagement operacional **tira** o membro da
coorte (= foi promovido). Não é API-exposto (sem EXECUTE para anon/authenticated).

> Note a sutileza: `operational_role='guest'` é o **cache de papel** visível ao FE durante
> o pré-onboarding; `member_is_pre_onboarding()` é o **predicado de coorte** server-side.
> Eles concordam na prática, mas têm donos diferentes — para gates server-side use o
> predicado SQL; para gate de pertencimento no FE use `isRegisteredMember`.

## 🔴 Anti-pattern (incidente PR #739)

**NUNCA use `operational_role` (ou `getMemberRole(m) === 'guest'`) como proxy de
"não é membro".** Isso trancou membros legítimos em pré-onboarding fora do `/profile`
(viam "Sua conta foi autenticada mas ainda não está cadastrada") — eles JÁ eram membros,
só estavam com papel `guest`. O fix (#739) trocou todos os gates de pertencimento por
`isRegisteredMember(m)` e **preservou** `getMemberRole(m)` apenas para styling/atalhos de
papel (ex.: Nav). Regra prática:

- **Pertenço / posso ver minha jornada?** → `isRegisteredMember(member)`.
- **Que papel/atalhos/estilo mostro?** → `getMemberRole(member)` / `operational_role`.
- **Coorte/stat/gate server-side de pré-onboarding?** → `member_is_pre_onboarding(...)`.

## Onde o `guest`/pré-onboarding aparece na jornada

- `PreOnboardingChecklist` + `OnboardingChecklist` montam incondicionalmente em
  `workspace.astro` (gate por existência do membro, não por papel).
- `OnboardingCockpitNudge` (#743) roteia o pré-onboarding (`operational_role==='guest'` +
  `isRegisteredMember`) ao cockpit `/workspace`.
- RPCs gated do termo/tribo (`get_tribe_group_link`, `select_tribe`) usam
  `member_is_pre_onboarding(person_id, status)` para barrar acesso **antes** da assinatura.

## Resíduo conhecido (não bloqueador)

`workspace.astro` ainda tem um `resolveTier` LOCAL que mapeia `guest→'member'` (diverge de
`resolveTierFromMember`/`getAccessTier` em `constants.ts`, que dá `visitor`). Convergência
rastreada como **G3** (#740) — toca atalhos de vários papéis, exige regressão. Não afeta o
acesso ao checklist (que monta por existência).

## Ver também

- `docs/reference/MEMBER_STATUS_LIFECYCLE.md` — `member_status` (active/alumni/inactive).
- `docs/reference/V4_AUTHORITY_MODEL.md` — `can()` / designations / op-role cache.
- `docs/project-governance/PRE_ONBOARDING_JOURNEY_DISCOVERY_2026-06-16.md` — discovery #740.
- PR #739 — fix do cadeado de pré-onboarding (origem do `isRegisteredMember`).
