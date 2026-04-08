# Spec: Pre-Onboarding Gamification Journey (#18)

**Data:** 31 March 2026
**Autor:** Claude Opus 4.6 + Vitor Maia Rodovalho (PM)
**Status:** Spec para validacao e desenvolvimento
**Prioridade:** Alta — CBGP em ~28 dias trara novos candidatos

---

## 1. PROBLEMA

Candidatos aprovados no processo seletivo (8 pendentes hoje, mais esperados pos-CBGP) ficam em um "limbo" entre a aprovacao e o onboarding ativo. Nao ha engajamento pre-registro, o que aumenta o risco de dropout. O dropout rate nao e mensurado sistematicamente.

**Jobs to be done (candidato):**
- "Fui selecionado, e agora? O que faco enquanto espero?"
- "Quero entender o que o Nucleo faz antes de me comprometer"
- "Quero ja comecar a contribuir e me preparar"

**Jobs to be done (PM/gestor):**
- "Quero saber quais candidatos estao engajados antes mesmo do onboarding"
- "Quero reduzir dropout entre selecao e primeiro ciclo ativo"
- "Quero que candidatos cheguem no dia 1 ja preparados"

---

## 2. INFRAESTRUTURA EXISTENTE

| Componente | Status | Detalhes |
|-----------|--------|---------|
| `selection_applications` | Existe | Dados dos candidatos (nome, email, background, status) |
| `selection_cycles` | Existe | Ciclos de selecao com datas |
| `selection_committee` | Existe | Comite avaliador |
| `onboarding_progress` | Existe | `step_key`, `status`, `evidence_url`, `sla_deadline`, FK → `selection_applications` |
| `/admin/selection` | Existe | Pipeline de selecao admin |
| `/onboarding` | Existe (359 linhas) | Pagina de onboarding pos-registro |
| `get_selection_pipeline_metrics` | Existe | Metricas do pipeline |
| `volunteer_funnel_summary` | Existe | Funil de voluntariado |
| Gamification engine | Existe (1722 linhas) | XP, badges, leaderboard, Credly sync |

**Zero tabelas novas necessarias** — `onboarding_progress.step_key` ja suporta steps customizados.

---

## 3. JORNADA DO CANDIDATO (Advisory Panel Design)

### Painel Consultivo Simulado

| Persona | Perspectiva |
|---------|------------|
| **PMBOK 8th Ed. Advisor** | Voluntariado e um projeto — o candidato e um stakeholder em fase de engajamento. Pre-onboarding e "planning" do ciclo de vida do voluntario. Medir readiness antes da execucao. |
| **PMI Global Volunteer Consultant** | Framework PMI de voluntariado enfatiza: expectativas claras, desenvolvimento de competencias (mini-certs), reconhecimento (Credly), e construcao de comunidade. A trilha de mini-certificacoes e KPI anual. |
| **Gamification Designer** | Nao burocratizar. Usar: checklist visual com progress bar, XP por step, social proof ("veja quem mais esta se preparando"). Maximo 6-8 steps. Tempo total: ~2h espalhadas em 1-2 semanas. |
| **Tribe Leader (Jefferson)** | "Quero que o candidato ja chegue sabendo o que a tribo faz e com Credly preenchido" |
| **Candidato (Joao Uzejka — balizador QA/QC)** | Ja ativo, pode validar se a jornada e realista e motivadora |

### Trilha Proposta: 6 Steps

| # | Step Key | Titulo | Descricao | XP | Evidencia | SLA |
|---|----------|--------|-----------|-----|-----------|-----|
| 1 | `create_account` | Crie sua conta | Login na plataforma com Google/LinkedIn/Microsoft | 50 | Auto-detect (auth exists) | 7 dias |
| 2 | `complete_profile` | Complete seu perfil | Preencher nome, foto, bio, e LinkedIn no perfil | 75 | Auto-detect (fields filled) | 14 dias |
| 3 | `setup_credly` | Configure o Credly | Adicionar URL do Credly ao perfil para tracking de certificacoes | 75 | Auto-detect (credly_url != null) | 14 dias |
| 4 | `explore_platform` | Explore a plataforma | Visitar 3+ paginas (blog, tribos, gamificacao) | 50 | Auto-detect (page_views >= 3 via record_member_activity) | 14 dias |
| 5 | `read_blog` | Leia o blog do Nucleo | Ler ao menos 1 post do blog sobre o Nucleo IA | 50 | Auto-detect (blog page visited) | 14 dias |
| 6 | `start_pmi_certs` | Inicie a trilha PMI | Completar ao menos 1 mini-certificacao PMI (gratuita) e registrar no Credly | 150 | Manual ou Credly sync | 30 dias |

**Total: 450 XP** — suficiente para o candidato ja aparecer no leaderboard antes do onboarding formal.

### Principios de Design
- **Nao-burocratico**: Steps 1-5 sao auto-detectados, zero formulario
- **Progressivo**: Candidato pode fazer no seu ritmo
- **Motivador**: XP + progress bar + posicao no ranking
- **Mensuravel**: Admin ve % de completude por candidato
- **Alinhado a KPIs**: Step 6 (mini-certs) alimenta o indicador anual `certification_trail`

---

## 4. IMPLEMENTACAO TECNICA

### 4.1 Backend (onboarding_progress)

Seed dos 6 steps quando candidato e aprovado:

```sql
-- Triggered when selection_application.status = 'approved'
INSERT INTO onboarding_progress (application_id, member_id, step_key, status, sla_deadline)
VALUES
  (p_app_id, p_member_id, 'create_account', 'pending', now() + interval '7 days'),
  (p_app_id, p_member_id, 'complete_profile', 'pending', now() + interval '14 days'),
  (p_app_id, p_member_id, 'setup_credly', 'pending', now() + interval '14 days'),
  (p_app_id, p_member_id, 'explore_platform', 'pending', now() + interval '14 days'),
  (p_app_id, p_member_id, 'read_blog', 'pending', now() + interval '14 days'),
  (p_app_id, p_member_id, 'start_pmi_certs', 'pending', now() + interval '30 days');
```

### 4.2 Auto-detection (pg_cron ou on-login check)

```sql
-- Runs periodically or on login to auto-complete steps
CREATE OR REPLACE FUNCTION check_onboarding_auto_steps(p_member_id uuid)
RETURNS void AS $$
BEGIN
  -- Step 1: create_account — completed if member exists with auth_id
  UPDATE onboarding_progress SET status = 'completed', completed_at = now()
  WHERE member_id = p_member_id AND step_key = 'create_account' AND status = 'pending'
  AND EXISTS (SELECT 1 FROM members WHERE id = p_member_id AND auth_id IS NOT NULL);

  -- Step 2: complete_profile — name + photo_url filled
  UPDATE onboarding_progress SET status = 'completed', completed_at = now()
  WHERE member_id = p_member_id AND step_key = 'complete_profile' AND status = 'pending'
  AND EXISTS (SELECT 1 FROM members WHERE id = p_member_id AND name IS NOT NULL AND photo_url IS NOT NULL);

  -- Step 3: setup_credly — credly_url filled
  UPDATE onboarding_progress SET status = 'completed', completed_at = now()
  WHERE member_id = p_member_id AND step_key = 'setup_credly' AND status = 'pending'
  AND EXISTS (SELECT 1 FROM members WHERE id = p_member_id AND credly_url IS NOT NULL);

  -- Step 4: explore_platform — 3+ distinct pages visited
  UPDATE onboarding_progress SET status = 'completed', completed_at = now()
  WHERE member_id = p_member_id AND step_key = 'explore_platform' AND status = 'pending'
  AND (SELECT count(DISTINCT page) FROM member_activity WHERE member_id = p_member_id) >= 3;

  -- Step 5: read_blog — blog page visited
  UPDATE onboarding_progress SET status = 'completed', completed_at = now()
  WHERE member_id = p_member_id AND step_key = 'read_blog' AND status = 'pending'
  AND EXISTS (SELECT 1 FROM member_activity WHERE member_id = p_member_id AND page LIKE '%/blog%');

  -- Step 6: start_pmi_certs — requires manual or Credly sync (badge count > 0)
  -- Auto-detect via Credly sync if available
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 4.3 Frontend — Candidate Dashboard

**Opcao A (recomendada):** Estender `/onboarding` existente com uma secao "Pre-Onboarding" que mostra o checklist gamificado quando o membro tem `onboarding_progress` rows pendentes.

**UI:**
```
┌─────────────────────────────────────────────────────────┐
│  Bem-vindo ao Nucleo IA, [Nome]!                        │
│  Complete sua preparacao para comecar com tudo.          │
│                                                         │
│  ████████████░░░░░  4/6 completos (300/450 XP)         │
│                                                         │
│  ✅ Crie sua conta                              +50 XP  │
│  ✅ Complete seu perfil                         +75 XP  │
│  ✅ Configure o Credly                          +75 XP  │
│  ✅ Explore a plataforma                        +50 XP  │
│  ○  Leia o blog do Nucleo                       +50 XP  │
│     → nucleoia.vitormr.dev/blog                         │
│  ○  Inicie a trilha PMI                        +150 XP  │
│     → pmi.org/learning (gratuito)                       │
│                                                         │
│  ┌──────────────────────────────┐                       │
│  │ 🏆 Ranking Pre-Onboarding   │                       │
│  │ 1. Joao Uzejka — 450 XP ✅  │                       │
│  │ 2. Voce — 300 XP            │                       │
│  │ 3. Blenda Amorim — 125 XP   │                       │
│  └──────────────────────────────┘                       │
└─────────────────────────────────────────────────────────┘
```

### 4.4 Admin View — Selection Pipeline Enhancement

Adicionar coluna "Onboarding %" na tabela de `/admin/selection`:

```
| Candidato          | Status    | Onboarding | SLA      |
|--------------------|-----------|------------|----------|
| Joao Uzejka        | Approved  | 6/6 (100%) | ✅ OK    |
| Blenda Amorim      | Approved  | 2/6 (33%)  | ⚠️ 5d    |
| Andre Abreu        | Pending   | —          | —        |
```

### 4.5 Metricas de Dropout

Nova RPC ou extensao de `volunteer_funnel_summary`:

```sql
-- Funnel stages with conversion rates
SELECT
  count(*) FILTER (WHERE status = 'submitted') as applied,
  count(*) FILTER (WHERE status = 'approved') as approved,
  count(*) FILTER (WHERE status = 'approved' AND onboarding_pct >= 50) as engaged,
  count(*) FILTER (WHERE status = 'approved' AND onboarding_pct = 100) as ready,
  count(*) FILTER (WHERE status = 'active') as active
FROM selection_applications_with_onboarding;
```

---

## 5. PLANO DE IMPLEMENTACAO

### Sprint 1 — Backend + Seed (1 sessao)
- [ ] RPC `check_onboarding_auto_steps`
- [ ] RPC `get_candidate_onboarding_progress` (retorna steps + % + XP)
- [ ] Seed dos 6 steps para os 8 candidatos pendentes
- [ ] Seed para Joao Uzejka (balizador QA/QC — deve aparecer 100%)

### Sprint 2 — Frontend Candidate Dashboard (1 sessao)
- [ ] Secao pre-onboarding no `/onboarding` ou landing page dedicada
- [ ] Progress bar + checklist com XP
- [ ] Mini leaderboard de candidatos
- [ ] Auto-detection trigger on page load

### Sprint 3 — Admin Enhancements (1 sessao)
- [ ] Coluna "Onboarding %" no `/admin/selection`
- [ ] Dropout funnel metrics no dashboard
- [ ] Email/notification quando candidato completa 100%

---

## 6. DECISOES PENDENTES

| # | Decisao | Opcoes | Recomendacao |
|---|---------|--------|-------------|
| D1 | Candidato acessa a plataforma ANTES de ser aprovado? | (a) Sim, qualquer um com conta ve o checklist (b) So apos aprovacao | **(b)** — Manter exclusividade, candidato so ve apos aprovacao |
| D2 | XP do pre-onboarding conta no leaderboard geral? | (a) Sim, aparece junto (b) Separado, so pre-onboarding | **(a)** — Motiva mais e ja integra o candidato na comunidade |
| D3 | Step 6 (PMI certs) e obrigatorio para completar? | (a) Obrigatorio (b) Bonus (nao bloqueia 100%) | **(b)** — Bonus com XP extra. Nao queremos bloquear quem ainda nao teve tempo |
| D4 | Quem triggera o seed dos steps? | (a) Auto ao aprovar no /admin/selection (b) Manual via botao | **(a)** — Auto, zero fricção |

---

## 7. VALIDACAO (QA/QC com Joao Uzejka)

Joao Uzejka ja e membro ativo. Usar como baseline:
1. Seed os 6 steps para ele
2. Verificar que auto-detection completa todos (ele ja tem conta, perfil, Credly)
3. Confirmar que ele aparece como 100% no ranking
4. Pedir feedback dele sobre a jornada proposta

---

*Spec construida com advisory panel: PMBOK 8ed (lifecycle), PMI Global (volunteer framework), Gamification Designer (engagement), Tribe Leader (practical needs), Candidato balizador (Joao Uzejka).*
