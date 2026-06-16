# Discovery — Jornada de Pré-Onboarding (descoberta para planejamento)

> **Status:** DISCOVERY / planejamento. Nada aqui foi implementado. Insumo para requisitos → spec → wave.
> **Data:** 2026-06-16 · **Origem:** áudios/WhatsApp de voluntários novos + bug do cadeado de perfil (PR #739) + sessão de simulação de personas (ux-leader + candidato + GP/diretorias).
> **Grounding:** todos os números/estados abaixo vêm de queries ao vivo nesta sessão (DB `ldrfrvwhxsmgaabwmaik`) ou leitura de código. Marcado `[live]` / `[code]`.

## 1. A jornada-alvo (modelo do PM, refinado nesta sessão)

```
candidato aprovado na seleção (no VEP/plataforma)
  → PMI envia e-mail de oferta (donotreply at pmi.org) com link de ACEITE formal
  → [GAP D7] se NÃO aceita após X dias → lembrete automático da plataforma p/ aceitar a oferta
  → candidato ACEITA a oferta pelo VEP (volunteer.pmi.org → My Info & Activity → Accept Position)
  → vira member em PRÉ-ONBOARDING (operational_role='guest')
  → loga e entra no /perfil
       → aceita consentimento de privacidade (LGPD)
       → adiciona Credly (link público) · adiciona e-mails · corrige nome/dados
       → ESCOLHE o capítulo pelo qual entra no projeto (governança/indicador) — APENAS capítulos PMI Brasil
  → SE membresia PMI ativa (futuro: gate; hoje: farol)
       → assina o Termo de Voluntariado (SEMPRE pelo PMI-GO, capítulo sede)
  → é promovido ao papel real (researcher/tribe_leader)
```

Princípio norteador declarado pelo PM: **onboarding "jeito Disney"** — sem fricção, centralizado, acolhedor, com o grupo de WhatsApp de pré-onboarding como canal coletivo de dúvidas.

Grupo de WhatsApp de pré-onboarding (canal oficial): `https://chat.whatsapp.com/Gl6eUqK45DJGQxZ8VFE2bs`

**Escopo deste discovery = a PRIMEIRA PERNADA:** aprovado → aceite da oferta → pré-onboarding → perfil/consentimento/Credly/escolha-de-capítulo → termo assinado → promoção. **FORA de escopo (jornadas próprias, depois):** (a) **seleção de tribo** (mão dupla: candidato escolhe + líder aceita; tribos novas; doubt-clearing — ver Épico H); (b) personas de diretoria que não sejam voluntariado/filiação.

## 2. Estado real aterrado (o que a plataforma faz HOJE)

- **Papel de pré-onboarding = `operational_role='guest'`** `[live]`. Não há enum; "pré-onboarding" é DERIVADO via `member_is_pre_onboarding(person_id, member_status)`. A única constraint é impedir `(active + 'none')`. → O nome do papel (`guest`) não casa com o conceito (`pré-onboarding`) — raiz do bug que trancou 19 membros fora do /perfil (corrigido em PR #739).
- **Gate do termo** (`sign_volunteer_agreement` + `volunteer-agreement.astro`) `[code]`: exige dados pessoais completos (pmi_id, phone, address, city, state, country, birth_date). **NÃO bloqueia por membresia PMI ativa** — `members.pmi_id_verified` é só FAROL (gravado como `affiliation_unverified` no audit; "v1=farol, não bloqueio", #625). Bloqueio por membresia = **v2 futuro**.
- **Signatário do termo** `[live]`: a RPC tenta `chapter_registry.chapter_code = members.chapter`, mas `chapter_code` = `GO/CE/DF/MG/RS` e `members.chapter` = `PMI-GO/PMI-CE/...` → **nunca casa** → cai no fallback `is_contracting_chapter=true` → **PMI-GO**. Hoje o termo sai sempre PMI-GO **por acidente de formato**, não por design.
- **Modelo de capítulo** `[live]`: `members.chapter` é texto ÚNICO (`PMI-GO`, `PMI-CE`, ... + `Outro`/`Externo`). Sem multi-capítulo, sem restrição Brasil, sem escolha "vim por qual". `chapter_registry` tem só 5 entradas (GO+CE+DF+MG+RS) de 15 capítulos brasileiros do projeto.
- **Funil de seleção** `[live]`: tabelas `selection_applications`, `selection_interviews`, `selection_dispatch_url_log`, `onboarding_progress/steps/tokens`. Existe RPC `selection_rescue_stuck_interview` e crons de overdue, mas há lacunas (ver Épico D).
- **Superfícies admin existentes** `[code]`: `/admin/filiacao` + `AffiliationQueueIsland`, `VolunteerAgreementPanel` (by_chapter), `/admin/selection` (chip "Stuck Scheduled"), `get_selection_dashboard` (expõe `interview_stuck`, `interview_pending`, `cutoff_approved_email_sent_at`).

### 2.1 Correções de premissa (PDFs da plataforma — /workspace + /perfil)
Capturas reais da plataforma (2026-06-16) corrigiram suposições da simulação:
- **O checklist de onboarding EXISTE e é real** `[pdf+code]`: vive no **/workspace** (`OnboardingChecklist.tsx`), conectado ao banco, com 7 passos canônicos e estado ✅ derivado: (1) **Código de Conduta** — aceite o Código de Ética PMI + reconheça os termos do Acordo de Voluntariado; (2) **Complete seu perfil** — foto, estado, país, LinkedIn, PMI ID (mín. 4 campos); (3) **Termo de Voluntário**; (4) **Aceitar posição no VEP** (volunteer.pmi.org); (5) **Conheça sua tribo** (líder, agenda, WhatsApp); (6) **Inicie a Trilha PMI AI** (7 cursos, badges Credly, ≥1); (7) **Participe da primeira reunião**. → A premissa "checklist invisível" estava ERRADA; o gap real é **fragmentação** (4 componentes: `OnboardingChecklist`, `PreOnboardingChecklist`, `PMIOnboardingPortal`, `onboarding.astro` estático) + **reachability do guest ao /workspace** (depende do gate G3).
- **Discrepância do termo (cópia desatualizada)** `[pdf+code]`: o passo "Termo de Voluntário" descreve "Baixe o Termo pré-preenchido, **assine via gov.br** e faça upload do assinado", MAS o botão real aponta para `/volunteer-agreement` = **assinatura digital in-platform** (`sign_volunteer_agreement`, hash SHA-256, sem gov.br). A cópia engana o candidato. (`gov.br` aparece em i18n + geração de PDF do certificado — provável legado.)
- **/workspace é o cockpit de onboarding real** → o gate de tier do guest (G3) deixa de ser "P2 isolado" e vira **dependência da Wave 1** (sem alcançar /workspace, o pré-onboarding não vê o checklist).
- **Perfil é rico mas capítulo/papel/tribo são geridos pelo GP** `[pdf]`: "🔒 Email, capítulo, papel e tribos são geridos pelo GP" — hoje o membro NÃO escolhe o próprio capítulo. → o requisito C2 (escolha de capítulo na jornada) é capacidade **nova** member-facing, não ajuste.
- **VEP-accept aparece em 2 lugares**: como gate pré-plataforma (D7) e como item do checklist (passo 4) — possível redundância a reconciliar.

## 3. Capítulos PMI Brasil do projeto (escopo da restrição)

Fonte: arte oficial "Projects with Purpose — Latam Brazil Chapter in Action" + `https://www.pmi.org/membership/chapters/latin-america`.

**PMI-GO = sede (signatário do termo, sempre).** 14 parceiros: Amazônia, Bahia, Ceará, Distrito Federal, Espírito Santo, Minas Gerais, Paraíba, Paraná, Pernambuco, Rio de Janeiro, Rio Grande do Sul, Santa Catarina, São Paulo, Sergipe.

**Regra de escolha de capítulo (novo requisito):** o membro pode ser filiado a até 4 capítulos (fato do PMI, não declaração). Na jornada ele ESCOLHE por qual entra no projeto — mas só pode escolher entre os **capítulos PMI Brasil** participantes. Capítulos não-brasileiros (ex.: Portugal, Angola — Henrique Diniz) podem ser EXIBIDOS, mas não SELECIONÁVEIS.

## 4. Inventário de gaps (organizado por épico)

Severidade: 🔴 alta / 🟡 média / 🟢 baixa. Fonte: `ux`=ux-leader, `cand`=persona candidato, `gp`=persona GP/diretorias, `pm`=correção do PM, `gr`=grounding.

### ÉPICO A — Cockpit/navegação do pré-onboarding
| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| A1 | Pré-onboarding logado NÃO é levado ao /onboarding; cai na home com conteúdo que não é dele. Sem redirect nem banner sticky. | 🔴 | ux1, cand2 |
| A2 | **Onboarding fragmentado em 4 componentes** (`OnboardingChecklist`@workspace [real, DB], `PreOnboardingChecklist`, `PMIOnboardingPortal`, `onboarding.astro` [estático/localStorage]) sem fonte única canônica; `/onboarding` sem `drawerSection`. Definir UM cockpit. (Correção: o checklist NÃO é invisível — está no /workspace.) | 🔴 | ux1, pdf |
| A3 | Sequência não comunicada: 3 instrumentos desconexos (PrivacyGateModal flutuante, /perfil tudo-de-uma-vez, /onboarding 8 steps auto-declarativos via localStorage NÃO derivados do banco). Nenhum stepper linear "1/4". | 🔴 | ux2, cand3 |
| A4 | Tela de sucesso do termo = dead-end: mostra hash/código, sem próximos passos (tribo, trilha, WhatsApp). | 🟡 | ux5, cand11 |
| A5 | Sem confirmação de promoção pós-assinatura: operational_role muda em background, sem toast/e-mail "você agora é Pesquisador". | 🟡 | cand11 |
| A6 | `/onboarding` aberto a qualquer membro e estático (membro promovido vê os mesmos 8 steps "pendentes"); countdown do ciclo confunde com deadline de onboarding. | 🟢 | ux8 |
| A7 | Mobile: /perfil tem seções demais sem âncoras/tabs; ruído (XP/histórico) para quem só quer completar onboarding. | 🟢 | cand12 |

### ÉPICO B — Termo: clareza, farol e gating
| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| B1 | Botão do termo no /perfil tem **race condition**: aparece "Assinar" antes do `check_my_tcv_readiness` carregar; em 3G o candidato clica e cai numa tela de campos faltantes. CTA deve ser determinístico (verificar readiness ANTES de decidir texto/destino). | 🔴 | ux3, cand3 |
| B2 | Farol de membresia PMI (`pmi_id_verified`) é invisível ao próprio voluntário (só admin o vê). Candidato não sabe se precisa acionar a Filiação. | 🟡 | ux4, cand4 |
| B3 | Gate do termo não explica POR QUÊ os campos (ex.: data de nascimento) nem a consequência de não assinar (fica guest indefinidamente? prazo?). | 🟡 | ux3, cand3 |
| B4 | **Adendo do termo**: o fluxo serve só o template `active` (#648 snapshot imutável). A versão nova (PI/governança) está em aprovação → liberar a versão vigente do capítulo agora e comunicar que virá um adendo de retificação/assinatura nas próximas semanas — SEM impactar o início do trabalho. Hoje a jornada não comunica nada disso. | 🟡 | pm, ux5 |
| B5 | **Membership-active como gate (v2)**: requisito do PM de exigir membresia PMI ativa para assinar. Hoje é só farol. Especificar política de bloqueio + mensagem + caminho de remediação. | 🟡 | pm |
| B6 | Label "Campos obrigatórios pendentes:" hardcoded em PT-BR no banner (profile.astro:203) — não traduz em /en /es. | 🟢 | ux7 |
| B7 | **Cópia desatualizada do passo do termo**: descreve "assine via gov.br e faça upload", mas o fluxo real é assinatura digital in-platform (`/volunteer-agreement`). Engana o candidato. Corrigir a cópia (o gov.br era o fluxo ANTIGO, pré-plataforma — ex.: termo do próprio GP). | 🟡 | pdf, pm |
| B8 | **Auditar a jornada de assinatura in-platform nos DOIS lados + loop de rejeição/retorno**: hoje `sign_volunteer_agreement` é mão única (emite certificado). Falta: (a) contra-assinatura/validação do emissor (PMI-GO/chapter_board); (b) se o documento tem erro na fase de assinatura, o signatário pode REJEITAR e o emissor CORRIGIR/RE-EMITIR — ambos os lados conseguem voltar. Verificar integridade do ciclo completo (emissão → assinatura → contra-assinatura → arquivamento/anexo ao engagement). | 🔴 | pm |

### ÉPICO C — Modelo multi-capítulo + filiação PMI (NOVO, requisito central do PM)
| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| C1 | **Sem modelo multi-capítulo**: `members.chapter` é texto único. Precisa representar os N capítulos de filiação do membro + o capítulo-de-entrada ESCOLHIDO (governança/indicador). | 🔴 | pm, gr |
| C2 | **Escolha na jornada restrita a Brasil**: a tela de escolha exibe todos os capítulos do membro, mas só permite selecionar capítulos PMI Brasil participantes (15). Não-brasileiros (Portugal/Angola) exibidos mas bloqueados. | 🔴 | pm |
| C3 | **Termo sempre PMI-GO (explícito)**: tornar o signatário PMI-GO explícito no `sign_volunteer_agreement` (hoje é correto só por acidente de mismatch de formato `GO`≠`PMI-GO`). Capítulo do membro = indicador, NUNCA signatário. | 🔴 | pm, gr |
| C4 | **`chapter_registry` incompleto**: só 5 de 15 capítulos brasileiros. Seed dos 15 + normalização de formato (`PMI-XX` vs `XX`). | 🟡 | gr |
| C5 | **Dependência de privacidade do perfil PMI community**: se o membro não tem perfil em community.pmi.org ou está com "Hide my chapter(s)" ativo, a sincronização não traz o capítulo → retorna errado/vazio mesmo sendo filiado. **Remediação:** orientar o membro a desmarcar "Hide my chapter(s)" + acionar o time de gestão do Núcleo para re-sincronizar → destrava a jornada. Canal: grupo de WhatsApp. Hoje a jornada não detecta nem orienta isso. | 🟡 | pm |
| C6 | **Reports sem duplicidade**: garantir que relatórios a capítulos usem o capítulo-de-entrada escolhido (não dado duplicado/sem jornada de escolha feita). | 🟡 | pm, gp |

### ÉPICO D — Candidatos "enterrados" no funil (operacional, gente parada AGORA)
Coorte vivo `[live]` (16 apps em estados de entrevista):
- 🔴 **Hector Rigon** (84d, convite há 20d, nunca agendou, sem cobrança); **Djeimiys Wille** (55d, idem); **Edinan Soares** (84d, **no-show 05/06 não recuperado**, sem novo convite); **Bruna Zomer** (entrevista **cancelada** mas status app = `interview_scheduled` → **drift**).
- 🟡 Cristiano Filho (82d, cancelada→re-convidado há 2d, recuperando); Francisco (26d, `interview_pending` sem convite, envelhecendo).

| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| D1 | Sem painel unificado "candidatos que precisam de ação minha HOJE". Dados existem (`get_selection_dashboard`) mas sem agregação por tipo de problema na home do GP. | 🔴 | gp |
| D2 | Sem auto-dispatch de convite com SLA: `interview_pending` sem `cutoff_approved_email_sent_at` envelhece em silêncio. Wave 2b do #411 (cron que varre pending-sem-convite) NÃO encontrada nas migrations; só existe cron de overdue. | 🔴 | gp |
| D3 | No-show não recuperado: `selection_rescue_stuck_interview` existe mas não é acionada automaticamente/em lote. | 🟡 | gp |
| D4 | Drift de status app↔entrevista (Bruna: app `interview_scheduled` vs interview `cancelled`). Integridade. | 🟡 | gp, gr |
| D5 | "Convite enviado mas nunca agendado" pode não ter `selection_interviews` row → não cai no chip `interview_stuck` → invisível no filtro. Auditar. | 🟡 | gp |
| D6 | Sem dono/SLA/cobrança por candidato (assignee). `interviewer_ids` existe como proxy. | 🟢 | gp |
| D7 | **Oferta VEP não aceita (topo do funil)**: aprovado na seleção mas sem dar o ACEITE da oferta no VEP → não vira member, fica invisível. Falta lembrete automático da plataforma após X dias, com passo a passo (volunteer.pmi.org → My Info & Activity → Accept Position) e aviso de que o e-mail oficial vem de `donotreply at pmi.org` (checar spam). | 🔴 | pm |

### ÉPICO E — Visibilidade/controles da liderança (GP/co-GP + diretorias)
| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| E1 | Diretoria de Voluntariado não distingue "pending que JÁ pode assinar" (passou entrevista, apto) de "pending ainda no funil". Visão é de conformidade, não de ação priorizada. | 🟡 | gp |
| E2 | Sem notificação quando candidato passa entrevista e fica APTO a assinar (só existe notif de quem JÁ assinou). | 🟡 | gp |
| E3 | Diretoria de Filiação não vê filiação de candidato de OUTRO capítulo na mesma tela (coordenação offline sem registro). Badge "externo" + focal_points do capítulo de origem (dados já em `get_volunteer_agreement_status.focal_points`). | 🟡 | gp |
| E4 | Sem alerta proativo de filiação expirando (farol "soon" só aparece ao abrir o painel; sem push). | 🟢 | gp |

### ÉPICO F — Comunidade, comunicação e propósito
| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| F1 | Plataforma não convida ao grupo de WhatsApp de pré-onboarding; voluntário se sente isolado, não sabe onde tirar dúvida. | 🟡 | cand9, ux9, gp |
| F2 | Sem guia "como pegar meu link público do Credly" (3 passos/GIF) — candidato sai da plataforma e perde 8min. | 🟡 | cand5 |
| F3 | Metas 2026 do Núcleo / propósito não visíveis ao recém-chegado ("por que estou aqui?"); risco de desengajamento silencioso em 2-3 semanas. | 🟡 | cand10 |
| F4 | Gamificação/trilha de mini-certificação: sem "primeira missão" nem "como ganhar XP" para quem tem 0 pontos; trilha externa sem ponteiro claro. | 🟡 | cand7 |
| F5 | Sem ponto de ajuda contextual ("Fale com o GP"/WhatsApp) nas telas de pré-onboarding travadas; `renderNotRegistered` só mostra e-mail para quem não tem member. | 🟢 | ux9 |
| F6 | E-mail de aprovação/aceite VEP não prepara o candidato (sem link direto p/ /onboarding, sem dizer com qual e-mail logar). | 🟡 | cand0 |

### ÉPICO G — Identidade, acesso e dívida correlata
| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| G1 | **#704 merge de identidade**: mesma pessoa sob >1 conta PMI (pmi_id/email distintos). `approve_selection_application` casa member/person só por e-mail → cria 2º person silencioso. Radar `get_duplicate_identity_candidates` (mig 175) existe; falta o guard não-bloqueante na fronteira do onboarding. | 🟡 | gr, #704 |
| G2 | `claim/start` sem contexto: não mostra o e-mail OAuth usado, não dá exemplos do identificador, erro `invalid_identifier` ambíguo, link de volta vai p/ home (perde contexto de login). | 🟡 | ux6 |
| G3 | **(P2 pré-existente)** `workspace.astro` usa `if(m)` como gate de pertencimento + `resolveTier` LOCAL que mapeia `guest→'member'` (diverge de `constants.ts getAccessTier` = `visitor`). Migrar p/ `isRegisteredMember` + `resolveTierFromMember`. | 🟡 | code-reviewer #739 |
| G4 | **(P3 hardening)** handlers `nav:member` em gamification/attendance sem else-branch p/ caso hipotético detail-não-nulo-sem-id. | 🟢 | code-reviewer #739 |
| G5 | Acessibilidade: botões amber-500 contraste <4.5:1; banner sem `aria-live`/`role=alert`; step-toggles sem `aria-expanded`. | 🟢 | ux a11y |

### ÉPICO H — Pós-promoção imediato (primeiros 7 dias como pesquisador/líder)
> O onboarding atual termina na assinatura do termo. Falta a jornada dos primeiros dias do papel real. (Nota: o GP não tem tribo por ser GP — exceção; candidatos TERÃO tribo.)
| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| H1 | Sem jornada pós-promoção: assinou o termo → "e agora?". Falta sequência guiada (primeira reunião → primeira entrega → primeiro XP). | 🟡 | cand11, pm |
| H4 | Primeira presença/anti-dropout imediato: recém-chegados entram como "missing-both"; sem nudge "registre sua primeira presença". 40 em risco de dropout / 36 sem presença `[pdf]`. | 🟡 | pdf, gp |
| H5 | Sem buddy/padrinho nos primeiros dias (mentor de tribo) — onboarding social. | 🟢 | cand |
| H6 | Primeira missão de gamificação/trilha para gerar o 1º XP e engajar (liga a F4). | 🟡 | cand7 |

> ⏭️ **JORNADA SEPARADA — DIFERIDA (NÃO escopo desta primeira pernada; discovery próprio depois):** **Seleção de tribo é jornada de MÃO DUPLA e calorosa**, não alocação fria. Requisitos capturados para não perder:
> - O **candidato escolhe** a tribo, MAS o **líder de tribo também ACEITA** — ninguém "cai" na tribo sem o aceite do líder (matching bilateral, análogo ao loop de assinatura B8).
> - Há **tribos novas a abrir** (oferta não é estática).
> - Momento de **tirar dúvida com os líderes** antes/durante a escolha — a jornada precisa ser pensada e acolhedora.
> - "Conheça sua tribo" (passo 5 do checklist): acesso a líder/agenda/WhatsApp; link de grupo é gated (WS-A) — confirmar acesso do recém-promovido.
> - Hoje: `select_tribe` term-gated (#734); PDF mostra dezenas de pré-onboarding com tribo "—" / "🔴 missing-both"; SEM fluxo de aceite do líder.

### ÉPICO I — Casos de borda da jornada
| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| I1 | Oferta VEP recusada/expirada (Declined/OfferExpired/OfferNotExtended): o que acontece? Comunicação ao candidato? (liga a #693 terminal status). | 🟡 | pm |
| I2 | Reprovado que reaplica (returning): `get_application_returning_context` existe — a jornada reconhece e acolhe o retorno? | 🟢 | gr |
| I3 | Dual-track (mesma pessoa em 2 trilhas: líder + pesquisador): risco de dupla avaliação/contagem (caso Ana). | 🟡 | gr |
| I4 | Membro sem membresia ativa que destrava DEPOIS (filiação resolvida via re-sync C5): como retoma a jornada do ponto onde parou? | 🟡 | pm |
| I5 | **Identidade duplicada (#704)**: mesma pessoa sob 2 contas PMI → 2º person silencioso no onboarding (= G1). | 🟡 | gr |
| I6 | Filiação privada (capítulo oculto em community.pmi.org) → sync retorna errado/vazio (= C5). | 🟡 | pm |
| I7 | Membro de capítulo NÃO-brasileiro (Portugal/Angola): exibir mas bloquear escolha (= C2); mensagem clara do porquê. | 🟡 | pm |
| I8 | Pré-onboarding que abandona/nunca completa: `detect_onboarding_overdue` existe — qual o desfecho (lembrete? offboard? expira)? | 🟡 | gr |
| I9 | Login com e-mail ≠ VEP (claim WS-B #735): caso de borda já tratado, mas referenciar na jornada. | 🟢 | gr |

### ÉPICO J — Comunicações e cadência (e-mail + WhatsApp + in-app)
| # | Gap | Sev | Fonte |
|---|-----|-----|-------|
| J1 | **Mapa de comunicações por etapa ausente/fragmentado**: definir quais e-mails/lembretes automáticos em cada estágio (aprovação → oferta-pendente → convite-entrevista → no-show → aprovado/pré-onboarding → termo-pendente → promoção → 1ª reunião). Sintomas: D2, D7, A5, E2. | 🔴 | pm |
| J2 | **Decisão de canal**: o que vai pro grupo WhatsApp (coletivo/dúvidas), in-app (notificações), e-mail (formal/lembrete). Sem matriz definida. | 🟡 | pm |
| J3 | Convite ao grupo WhatsApp no momento certo da jornada (= F1). | 🟡 | pm |
| J4 | Cadência de lembretes com SLA configurável: oferta não aceita, termo não assinado, onboarding parado, convite sem agendamento. | 🟡 | pm |
| J5 | Tom "jeito Disney": celebrar marcos (perfil 100% → +50pts já existe `[pdf]`; estender a termo assinado, promoção, 1ª presença, 1ª entrega). | 🟢 | pm |
| J6 | Cópia operacional canônica (aceite de oferta, sync de filiação privada) — ver §9; embutir nos e-mails/telas. | 🟡 | pm |

## 5. Notas transversais de modelagem
- **Renomear conceito de pré-onboarding**: `operational_role='guest'` deveria ser explicitamente "pré-onboarding" (ou ao menos documentado canonicamente) — a ambiguidade guest↔não-membro já causou 1 incidente (PR #739). Avaliar valor de papel dedicado vs manter derivação `member_is_pre_onboarding`.
- **Capítulo = duas coisas distintas**: (a) filiação(ões) PMI do membro [fato, multi, sincronizado do PMI] vs (b) capítulo-de-entrada no projeto [escolha, único, governança]. Hoje há um só campo. Separar é pré-requisito de C1-C6 e dos reports.

## 6. Perguntas abertas para a fase de requisitos/spec
1. **Renomear papel** `guest`→`pre_onboarding` (migração + todos os call-sites) ou só documentar/derivar? (impacto vs risco)
2. **Multi-capítulo — modelo de dados**: nova tabela `member_chapter_affiliations` (N filiações) + `members.entry_chapter` (escolha)? Como sincronizar filiações do PMI community (worker `pmi-vep-sync`)?
3. **Gate de membresia ativa (v2)**: bloquear assinatura, ou permitir assinar + flag? Qual a política para filiação expirada vs ausente vs privada?
4. **Sincronização de filiação privada (C5)**: detectar automaticamente "chapter oculto/ausente" e orientar, ou fluxo manual via gestão + WhatsApp?
5. **Auto-dispatch de convite (D2)**: SLA (ex.: 48h pós-objetiva)? Reenvio? Limite de tentativas antes de escalar ao GP?
6. **Adendo do termo (B4)**: assinatura separada do adendo quando aprovado, ou re-assinatura completa? Como comunicar na jornada sem assustar?

## 7. Agrupamento sugerido para waves (ordenação a validar com o PM)
- **Wave 1 — "Destravar e orientar" (rápida, alto impacto humano):** A1+A2 (cockpit único: consolidar os 4 componentes + redirect)+A3, B1 (race condition do botão), B7 (corrigir cópia gov.br→in-platform, barato), **G3 (gate de tier do guest — dependência: sem isso o pré-onboarding não alcança o /workspace/checklist)**, D7 (lembrete de aceite de oferta), F1+F6 (WhatsApp + e-mail de aprovação), J3, G2 (claim context). Desbloqueia/clarifica os 19 + recém-chegados.
- **Wave 2 — "Funil sem enterrados":** D1–D5 (painel de ação + auto-dispatch + rescue + drift + visibilidade no chip), E1+E2 (apto-a-assinar + notif), J1+J4 (mapa de comunicações + cadência de lembretes do funil). Resolve Hector/Djeimiys/Edinan/Bruna e previne recorrência.
- **Wave 3 — "Capítulo & governança + assinatura":** C1–C6 (modelo multi-capítulo, escolha restrita a Brasil, termo PMI-GO explícito, registry seed, sync de filiação privada), **B8 (auditoria da assinatura in-platform nos 2 lados + loop de rejeição/retorno)**, E3+E4 (visibilidade cross-capítulo).
- **Jornada SEPARADA (fora deste discovery, detalhar depois):** Seleção de tribo (mão dupla — candidato escolhe + líder aceita; tribos novas; doubt-clearing) — ver callout no Épico H.
- **Wave 4 — "Termo v2 + comunidade + pós-promoção":** B2–B5 (farol visível, clareza, adendo, gate de membresia), F2+F3+F4 (Credly guide, metas 2026, gamificação first-mission), H1+H3–H6 (jornada dos primeiros dias), J2+J5 (matriz de canais + tom Disney).
- **Casos de borda (Épico I):** distribuir conforme a wave do tema correspondente (I5→G1, I6/I7→C, I1→D, etc.).
- **Higiene contínua:** G1 (#704 merge), G4 (else-branch), B6+A4+A5+A6+A7+F5+G5 (polish).

## 8. Cross-ref
- PR #739 (fix cadeado pré-onboarding) · #704 (merge identidade) · #625 (farol filiação v1) · #648 (snapshot imutável termo) · #411 (auto-dispatch entrevista, Wave 2b pendente) · `sign_volunteer_agreement` · `get_selection_dashboard` · `selection_rescue_stuck_interview` · worker `pmi-vep-sync`.
- Relatórios das personas desta sessão: ux-leader (9 gaps), candidato (12 atritos), GP/diretorias (8 gaps de controle) — sintetizados acima.

## 9. Apêndice — cópia operacional a preservar (insumo de comms)

**Lembrete de aceite da oferta (gap D7)** — passo a passo a embutir no e-mail/lembrete:
> A aprovação realizada na plataforma envia automaticamente um e-mail a vocês (remetente `donotreply at pmi.org` — se não recebeu, verifique o spam) com um link para dar o ACEITE formal na vaga. Caso não tenham recebido, acessem `https://volunteer.pmi.org/` → **[My Info & Activity / Minhas Informações e Atividades]** → **[Accept Position / Aceitar Posição]**.

**Sincronização de filiação privada (gap C5)** — orientação ao membro:
> Se seu capítulo não aparece, verifique em `https://community.pmi.org/profile/` → Edit Overview → **Chapter Membership**: desmarque "Hide my chapter(s) from my profile". Depois avise o time de gestão do Núcleo (grupo de WhatsApp) para re-sincronizar — então sua jornada destrava.

**Grupo de WhatsApp de pré-onboarding:** `https://chat.whatsapp.com/Gl6eUqK45DJGQxZ8VFE2bs` — canal coletivo de dúvidas (candidatos + Núcleo + diretorias de filiação/voluntariado). Usar como ponto de ajuda referenciado nas telas (gaps F1, F5, C5).
