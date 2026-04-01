# Spec: Selection Journey V2 — Mid-Cycle Recruitment + Full Pipeline

**Data:** 31 March 2026
**Autor:** Claude Opus 4.6 + Vitor Maia Rodovalho (PM)
**Status:** Spec aprovada, implementacao em andamento
**Deadline:** Thursday 03/Apr (Joao Uzejka QA baseline test)
**Base spec:** W124_SELECTION_PIPELINE_SPEC.md (schema 100% deployed)

---

## 1. DECISOES DE NEGOCIO (validadas nesta sessao)

### D1: Ciclo de pesquisa ≠ Ciclo de selecao
O ciclo 3 de pesquisa (Jan-Jun 2026) continua ativo. Selecao e assincrona — novos membros entram via "batches" de recrutamento mid-cycle sem disrupcao do time atual. Cada batch e um selection_cycle separado com datas e comite proprios.

**Implicacao tecnica:** Criar novo `selection_cycle` (ex: "cycle3-2026-batch2") com status 'open'. O campo `cycle_code` indica o research cycle (3), o title indica o batch.

### D2: Opportunity tracking (vep_opportunity_id)
Cada candidato vem de uma vaga PMI VEP especifica:
- 64966: "Lider de tribo e Pesquisador chefe" → role_applied = 'leader'
- 64967: "Pesquisador e multiplicador" → role_applied = 'researcher'

O opportunity_id determina o role_applied default. Um pesquisador forte pode ser promovido a lider pelo comite (converted_from/to).

### D3: Membership snapshot dimensional
- `membership_status` e `chapter` sao capturados como fato temporal, nao dimensao estatica
- Cada import do CSV gera um snapshot com `imported_at` como timestamp
- Objetivo duplo:
  a) Validacao: aceite requer filiacao a capitulo parceiro
  b) Auditoria: detectar inadimplencia para informar diretoria de filiacao
- Capitulos parceiros sao dinamicos (hoje 5, pode mudar) — sem hardcode

### D4: Researcher → Leader promotion
- Comite/GP pode mover pesquisador para track de lider internamente
- Perguntas complementares de lider (leader_extra_criteria) sao adicionadas
- Candidato precisa aceitar formalmente via VEP a posicao de lider (etapa final)
- Pontuacao e etapas anteriores sao preservadas (sem re-avaliacao)

### D5: Dedup no import CSV
- CSV do VEP sempre traz TODOS os candidatos da vaga (ativos + anteriores)
- Dedup por `vep_application_id` (Application ID do CSV)
- Se ja existe: update snapshot de membership/chapter, nao reimportar
- Status VEP "OfferNotExtended" → skip (rejeitados no VEP)
- Status VEP "Active"/"Submitted" → import como 'submitted' na plataforma

---

## 2. SCHEMA CHANGES NECESSARIAS

### 2.1 Nova coluna em selection_applications
```sql
ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS vep_opportunity_id text;
```

### 2.2 Tabela de capitulos parceiros (dinamica)
```sql
CREATE TABLE IF NOT EXISTS partner_chapters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_code text NOT NULL UNIQUE,  -- 'PMI-GO', 'PMI-CE', etc.
  chapter_name text NOT NULL,
  is_active boolean DEFAULT true,
  partnership_start date,
  partnership_end date,
  created_at timestamptz DEFAULT now()
);

-- Seed dos 5 atuais
INSERT INTO partner_chapters (chapter_code, chapter_name, partnership_start) VALUES
  ('PMI-GO', 'Goias, Brazil Chapter', '2025-07-01'),
  ('PMI-CE', 'Ceara, Brazil Chapter', '2025-07-01'),
  ('PMI-MG', 'Minas Gerais, Brazil Chapter', '2025-07-01'),
  ('PMI-DF', 'Distrito Federal, Brazil Chapter', '2025-07-01'),
  ('PMI-RS', 'Rio Grande do Sul, Brazil Chapter', '2025-07-01')
ON CONFLICT (chapter_code) DO NOTHING;
```

### 2.3 Tabela de snapshots de membership (fatos temporais)
```sql
CREATE TABLE IF NOT EXISTS selection_membership_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id) ON DELETE CASCADE,
  snapshot_date timestamptz NOT NULL DEFAULT now(),
  membership_status text,        -- 'Individual Membership', 'Student Membership', etc.
  chapter_affiliations text[],   -- Array dos capitulos filiados
  certifications text,           -- 'PMP,CPMAI,...'
  is_partner_chapter boolean,    -- Calculado: algum chapter em partner_chapters?
  source text DEFAULT 'csv_import', -- 'csv_import', 'manual', 'vep_sync'
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_membership_snap_app ON selection_membership_snapshots(application_id);
```

---

## 3. RPCs A IMPLEMENTAR

### 3.1 import_vep_applications (CRITICO)
```
Input: p_cycle_id uuid, p_opportunity_id text, p_rows jsonb[]
Logic:
  FOR each row:
    - Parse CSV columns
    - Extract chapter affiliations from membership_status field
    - Check dedup by vep_application_id
    - If exists: update membership snapshot only
    - If VEP status = 'OfferNotExtended': skip
    - If new: INSERT into selection_applications + membership snapshot
    - Detect returning member (email match in members table)
    - Detect partner chapter membership
  RETURN: {imported, skipped_dedup, skipped_declined, updated_snapshots, returning_members}
```

### 3.2 admin_update_application
```
Input: p_application_id uuid, p_data jsonb
Logic:
  - Update status, tags, feedback, role_applied, conversion fields
  - If status changed to 'approved': trigger onboarding seed
  - If conversion: populate converted_from/to/reason
  - Log audit trail
```

### 3.3 finalize_decisions (bulk)
```
Input: p_cycle_id uuid, p_decisions jsonb[]
Logic:
  FOR each decision:
    - Set application status (approved/rejected/waitlist)
    - Set feedback
    - If approved: check partner chapter requirement
    - If approved + has member record: link member_id
    - If approved + no member record: create member stub
    - Seed onboarding steps
    - Take diversity snapshot
  RETURN: {approved, rejected, waitlisted, members_created}
```

### 3.4 manage_selection_committee
```
Input: p_cycle_id uuid, p_action text, p_member_id uuid, p_role text
Logic:
  - Add/remove committee members
  - Roles: evaluator, lead, observer
  - Default: curatorship committee members
  - Allow adding external members (p_role = 'invited')
```

---

## 4. FRONTEND FEATURES

### 4.1 CSV Import (admin/selection)
- File upload area (drag & drop ou browse)
- Preview parsed rows before import
- Show: name, email, membership, chapter, VEP status
- Flag: returning members, non-partner chapters, dedup matches
- Confirm button → call import_vep_applications
- Result summary: imported/skipped/updated

### 4.2 Evaluation Modal (blind review)
- Click candidate row → open modal
- Left: candidate data (essays, CV link, certifications)
- Right: scoring form (criteria from cycle config, 0-10 sliders)
- Notes field (private)
- Save draft / Submit (locks evaluation)
- After all evaluators submit: show consolidated scores + divergence alerts

### 4.3 Committee Management
- Tab or section in /admin/selection
- List current committee members with roles
- "Add member" search picker
- Default suggestion: curatorship committee members
- Remove/change role

### 4.4 Interview Scheduling
- Button on candidate row → schedule interview
- Select interviewers from committee
- Date/time picker
- Auto-send notification
- Status: pending → scheduled → completed → scored

### 4.5 Decision Actions
- Bulk select candidates
- Actions: Approve / Reject / Waitlist / Convert to Leader
- Feedback field (per candidate)
- Confirmation dialog with partner chapter validation
- Auto-trigger onboarding on approval

### 4.6 Cycle Management
- Create new cycle/batch
- Copy criteria from previous cycle
- Set committee
- Set dates and booking URL

---

## 5. PARTNER CHAPTER VALIDATION FLOW

```
Import CSV → Parse 'Membership status' field
  "Individual Membership,Goias, Brazil Chapter" → ['PMI-GO']
  "Student Membership,Minas Gerais, Brazil Chapter,Espirito Santo, Brazil Chapter" → ['PMI-MG', 'PMI-ES']

Check against partner_chapters (is_active = true):
  ✅ PMI-GO, PMI-CE, PMI-MG, PMI-DF, PMI-RS → partner
  ⚠️ PMI-ES, PMI-PE, etc. → non-partner (flag, don't block)
  ❌ No membership → flag for follow-up

At approval time:
  If candidate has NO partner chapter affiliation → block approval, show warning
  "Candidato precisa se filiar a um capitulo parceiro antes do aceite"
```

---

## 6. IMPLEMENTATION PLAN

### Sprint A: Schema + Import (esta sessao)
- [ ] Schema changes (vep_opportunity_id, partner_chapters, membership_snapshots)
- [ ] RPC import_vep_applications
- [ ] Create cycle "cycle3-2026-batch2"
- [ ] Test import with the CSV

### Sprint B: Frontend Import + Evaluation (proxima sessao)
- [ ] CSV upload UI in /admin/selection
- [ ] Evaluation modal (blind review form)
- [ ] Committee management tab

### Sprint C: Decision + Onboarding Trigger (proxima sessao)
- [ ] admin_update_application RPC
- [ ] finalize_decisions RPC
- [ ] Decision bulk actions UI
- [ ] Partner chapter validation at approval
- [ ] Auto-trigger pre-onboarding steps on approval

### Sprint D: Interview + Polish (proxima sessao)
- [ ] Interview scheduling UI
- [ ] Interview scoring UI
- [ ] Pipeline dashboard enhancements
- [ ] Joao Uzejka full journey QA test

---

## 7. PERSONAS VALIDACAO

| Persona | Validacao |
|---------|----------|
| **PMBOK 8ed Advisor** | Mid-cycle resource replacement e pratica padrao. Selection batch model alinha com stakeholder engagement continuo (dominio Stakeholders). |
| **PMI Global Consultant** | VEP CSV import e o padrao. Opportunity tracking e essencial. Partner chapter validation e requisito formal. Volunteer lifecycle tracking (filiacao) e boa pratica. |
| **LGPD Advisor** | Membership snapshots: base legal = execucao contrato voluntariado. CVs/essays: retencao ciclo + 1 ano. Scores: anonimizados apos decisao final. |
| **Tech Lead** | Schema dimensional correto (fatos temporais, nao hardcode). Latest stable dependencies. SECURITY DEFINER RPCs. RLS on all new tables. |
| **Tribe Leader (Jefferson)** | "Quero ver quem esta sendo avaliado para minha tribo e poder dar input na entrevista" |
| **Candidato (Joao Uzejka)** | Baseline QA: testar jornada completa import → evaluate → approve → onboard |

---

*Spec V2 construida sobre W124 (schema deployado), expandida com: mid-cycle recruitment, opportunity tracking, dimensional membership snapshots, partner chapter validation, researcher→leader promotion.*
