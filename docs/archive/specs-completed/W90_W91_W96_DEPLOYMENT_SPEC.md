# Deployment Spec — W90 + W91 + W96

**Data:** 2026-03-12
**Autor:** Vitor (GP) + Claude (CXO)
**Decisões:** Todas aprovadas pelo GP

---

## W90 — Curation Review Audit Trail

### Contexto
O Manual de Governança (R2) define 7 etapas para produção de artigos, com "dupla avaliação por dois avaliadores independentes" no Comitê de Curadoria. O sistema atual tem SLA badges mas sem rubrica formal nem tracking de múltiplos revisores.

### Schema

**NÃO criar tabela nova.** Expandir `board_lifecycle_events` com 3 campos:

```sql
ALTER TABLE board_lifecycle_events
ADD COLUMN IF NOT EXISTS review_score jsonb DEFAULT NULL,
ADD COLUMN IF NOT EXISTS review_round int DEFAULT NULL,
ADD COLUMN IF NOT EXISTS sla_deadline timestamptz DEFAULT NULL;

COMMENT ON COLUMN board_lifecycle_events.review_score IS 
  'Rubrica formal: {clarity: 1-5, originality: 1-5, adherence: 1-5, relevance: 1-5, ethics: 1-5, overall: text}';
COMMENT ON COLUMN board_lifecycle_events.review_round IS 
  'Rodada de revisão (1 = primeira, 2 = segunda após correções)';
COMMENT ON COLUMN board_lifecycle_events.sla_deadline IS 
  'Prazo para conclusão desta ação de curadoria';
```

**Nova tabela para SLA config por board:**

```sql
CREATE TABLE IF NOT EXISTS board_sla_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_id uuid REFERENCES project_boards(id) NOT NULL,
  sla_days int NOT NULL DEFAULT 7,
  max_review_rounds int NOT NULL DEFAULT 2,
  reviewers_required int NOT NULL DEFAULT 2,
  rubric_criteria jsonb NOT NULL DEFAULT '["clarity","originality","adherence","relevance","ethics"]',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(board_id)
);

COMMENT ON TABLE board_sla_config IS 'SLA configuration per board — curadoria deadlines and review requirements';
```

### RPCs

**1. `submit_for_curation(p_item_id uuid)`**
- Muda status do item para 'curation_pending'
- Cria lifecycle event com action='submitted_for_curation'
- Calcula sla_deadline baseado em board_sla_config.sla_days
- Permissão: tribe_leader do board OU manager/deputy_manager

**2. `assign_curation_reviewer(p_item_id uuid, p_reviewer_id uuid, p_round int DEFAULT 1)`**
- Cria lifecycle event com action='reviewer_assigned', review_round=p_round
- Permissão: designation='curator' OU manager/deputy_manager
- Validação: reviewer deve ter designation='curator'
- Validação: não pode designar a si mesmo como único revisor (conflito)

**3. `submit_curation_review(p_item_id uuid, p_score jsonb, p_verdict text, p_notes text DEFAULT NULL)`**
- p_verdict: 'approved' | 'revision_requested' | 'rejected'
- p_score: {"clarity": 4, "originality": 5, "adherence": 3, "relevance": 5, "ethics": 5}
- Valida que os 5 critérios estão presentes e são 1-5
- Cria lifecycle event com review_score, review_round, action='curation_review'
- Se ambos os revisores aprovaram (count reviews WHERE verdict='approved' AND round=current >= reviewers_required):
  - Muda status para 'approved'
  - Cria lifecycle event action='curation_approved'
- Se algum pediu revisão:
  - Muda status para 'revision_requested'
  - Recalcula sla_deadline para o autor corrigir
- Permissão: somente o reviewer designado para este item e round

**4. `get_curation_dashboard()`**
- Retorna todos os items em curation_pending ou revision_requested
- Agrupa por board/tribe
- Inclui: contagem de reviews recebidas vs required, SLA status (on_time/overdue)
- Substitui a RPC órfã `get_curation_cross_board`
- Permissão: designation='curator' OU manager/deputy_manager

**5. `get_item_curation_history(p_item_id uuid)`**
- Retorna timeline de curadoria: submissions, assignments, reviews com scores
- Usado pelo CardDetail na aba "Curadoria"
- Permissão: membros do board + curators

### UI

**CardDetail — Nova aba "Curadoria":**
- Timeline de revisões com scores de rubrica (radar chart ou barras simples)
- Status atual: "Aguardando Revisor 1" / "Revisor 1 Aprovado — Aguardando Revisor 2" / etc.
- SLA countdown com badge (verde/amarelo/vermelho)
- Botão "Submeter Parecer" (só para reviewers designados)
- Modal de parecer: 5 sliders (1-5) para cada critério + campo de observações + select de verdict

**CuratorshipBoardIsland — Dashboard view:**
- Consumir `get_curation_dashboard()` ao invés de `list_curation_pending_board_items`
- Mostrar progress: "1/2 revisores aprovaram"
- Filtrar por: overdue, awaiting_review, approved, revision_requested

### Rubrica (i18n)

```typescript
const RUBRIC_CRITERIA = {
  clarity: { pt: 'Clareza e estrutura', en: 'Clarity & structure', es: 'Claridad y estructura' },
  originality: { pt: 'Originalidade', en: 'Originality', es: 'Originalidad' },
  adherence: { pt: 'Aderência ao tema', en: 'Topic adherence', es: 'Adherencia al tema' },
  relevance: { pt: 'Relevância prática', en: 'Practical relevance', es: 'Relevancia práctica' },
  ethics: { pt: 'Conformidade ética', en: 'Ethical compliance', es: 'Conformidad ética' }
} as const;

// Scale: 1=Insuficiente, 2=Regular, 3=Bom, 4=Muito Bom, 5=Excelente
```

---

## W91 — Tribe Island Parity + Múltiplos Assignees

### Schema

**Nova junction table:**

```sql
CREATE TABLE IF NOT EXISTS board_item_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid REFERENCES board_items(id) ON DELETE CASCADE NOT NULL,
  member_id uuid REFERENCES members(id) NOT NULL,
  role text NOT NULL DEFAULT 'contributor',
  assigned_at timestamptz DEFAULT now(),
  assigned_by uuid REFERENCES members(id),
  UNIQUE(item_id, member_id, role)
);

COMMENT ON TABLE board_item_assignments IS 'Múltiplos assignees por card com papéis diferenciados';
COMMENT ON COLUMN board_item_assignments.role IS 'author | reviewer | contributor | curation_reviewer';

CREATE INDEX idx_bia_item ON board_item_assignments(item_id);
CREATE INDEX idx_bia_member ON board_item_assignments(member_id);

-- RLS
ALTER TABLE board_item_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read assignments" ON board_item_assignments
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Board members can manage assignments" ON board_item_assignments
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
  -- Fine-grained control via SECURITY DEFINER RPCs
```

**Migration: Backfill from legacy fields:**

```sql
-- Migrate existing assignee_id to junction table
INSERT INTO board_item_assignments (item_id, member_id, role, assigned_at)
SELECT id, assignee_id, 'author', updated_at
FROM board_items
WHERE assignee_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- Migrate existing reviewer_id to junction table
INSERT INTO board_item_assignments (item_id, member_id, role, assigned_at)
SELECT id, reviewer_id, 'reviewer', updated_at
FROM board_items
WHERE reviewer_id IS NOT NULL
ON CONFLICT DO NOTHING;
```

**Legacy fields: MANTER `assignee_id` e `reviewer_id`.** 
O frontend lê da junction table com fallback para os campos legacy.
Novos assignments vão APENAS para a junction table.

### RPCs

**1. `assign_member_to_item(p_item_id uuid, p_member_id uuid, p_role text DEFAULT 'contributor')`**
- Insere na junction table
- Cria lifecycle event action='member_assigned'
- Valida role: 'author' | 'reviewer' | 'contributor' | 'curation_reviewer'
- Permissão: tribe_leader do board OU manager/deputy_manager OU curator (para curation_reviewer)

**2. `unassign_member_from_item(p_item_id uuid, p_member_id uuid, p_role text)`**
- Remove da junction table
- Cria lifecycle event action='member_unassigned'
- Mesma permissão que assign

**3. `get_item_assignments(p_item_id uuid)`**
- Retorna membros assignados com role, nome, avatar, data de assignment
- Inclui fallback: se junction table vazia, retorna legacy assignee_id/reviewer_id

**4. Atualizar `get_board()` e `get_board_by_domain()`:**
- Incluir assignments no retorno de cada item (LEFT JOIN board_item_assignments)
- Retornar como array de {member_id, name, avatar_url, role}

### UI

**MemberPicker v2 — Multi-select com roles:**
- Usar cmdk (já instalado) com multi-select
- Cada membro selecionado aparece como chip/tag com badge de role
- Ao adicionar, selecionar o role (author/reviewer/contributor)
- Permitir "Adicionar grupo": dropdown com "Comitê de Curadoria" que expande para os 3 curators

**CardDetail — Seção Assignees reformulada:**
- Lista todos os assignees com avatar + nome + role badge
- Botão "+" para adicionar membro
- "×" para remover (com confirmação)
- Agrupados por role: Autores | Revisores | Contribuidores

**CardCreate — Multi-assignee desde a criação:**
- Campo de assignees com MemberPicker v2
- Default role: 'author' para o primeiro, 'contributor' para os demais

### Backward Compatibility
- `CardDetail` lê de `get_item_assignments()` que tem fallback para legacy
- Boards antigos com `assignee_id` preenchido funcionam normalmente
- Novos assignments vão para junction table
- Os campos legacy `assignee_id`/`reviewer_id` ficam congelados (não recebem novos writes)

---

## W96 — Route Policy Contract Tests + Backend LGPD Enforcement

### Contexto
O enforcement atual é 100% frontend. Um usuário com o Supabase URL pode fazer queries diretas. As rotas `/admin/selection` e `/admin/comms` expõem dados LGPD-sensíveis (emails, telefones, endereços).

### Backend Enforcement

**1. RLS policies para tabelas sensíveis:**

```sql
-- members table: restringir acesso a dados sensíveis
CREATE POLICY "Members can read own data" ON members
  FOR SELECT TO authenticated
  USING (
    auth.uid() = auth_id  -- próprio registro
    OR EXISTS (  -- OU é admin/superadmin
      SELECT 1 FROM members m 
      WHERE m.auth_id = auth.uid() 
      AND (m.is_superadmin = true 
           OR m.operational_role IN ('manager', 'deputy_manager'))
    )
    OR EXISTS (  -- OU é tribe_leader da mesma tribo (dados limitados)
      SELECT 1 FROM members m 
      WHERE m.auth_id = auth.uid() 
      AND m.operational_role = 'tribe_leader'
      AND m.tribe_id = members.tribe_id
    )
  );
```

**NOTA:** A tabela members já tem RLS com SECURITY DEFINER RPCs para evitar recursão. As novas policies devem seguir o mesmo padrão — não queries diretas, sempre via RPCs.

**2. RPCs sensíveis — adicionar tier check:**

Todas as RPCs que retornam dados LGPD devem verificar o tier do caller:

```sql
-- Pattern para RPCs LGPD-sensíveis
CREATE OR REPLACE FUNCTION admin_get_member_details(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_role text;
  v_caller_is_admin boolean;
BEGIN
  SELECT operational_role, is_superadmin INTO v_caller_role, v_caller_is_admin
  FROM members WHERE auth_id = auth.uid();
  
  IF NOT (v_caller_is_admin OR v_caller_role IN ('manager', 'deputy_manager')) THEN
    RAISE EXCEPTION 'Access denied: requires admin tier';
  END IF;
  
  -- ... retorna dados completos
END; $$;
```

**3. Tabelas/views a proteger:**

| Recurso | Dados sensíveis | Quem acessa |
|---|---|---|
| `members` (email, phone) | Email, telefone | Próprio + admin + tribe_leader (limitado) |
| `admin/selection` data | Formulários de seleção | Somente admin |
| `admin/comms` data | Emails de broadcast | Somente admin + comms_leader |
| `attendance` (individual) | Horas por pessoa | Próprio + admin + tribe_leader |

### Contract Tests (Playwright)

**Estrutura de testes:**

```
tests/
  contracts/
    route-acl.spec.ts          — Testa que cada rota respeita minTier
    rpc-acl.spec.ts            — Testa que RPCs LGPD retornam 403 para tiers baixos
    navigation-visibility.spec.ts — Testa que nav items são visíveis/ocultos por tier
```

**route-acl.spec.ts:**
Para cada rota em `navigation.config.ts`:
1. Simular usuário com tier abaixo do `minTier`
2. Acessar a rota
3. Verificar que é redirecionado ou vê "acesso negado"
4. Simular usuário com tier correto → verificar que acessa

**rpc-acl.spec.ts:**
Para cada RPC LGPD-sensível:
1. Chamar com token de `researcher` → esperar erro/empty
2. Chamar com token de `manager` → esperar dados
3. Chamar com anon (sem auth) → esperar erro

**navigation-visibility.spec.ts:**
Para cada item no nav-config com `lgpdSensitive: true`:
1. Simular tiers: visitor, researcher, tribe_leader, admin, superadmin
2. Verificar que o item só aparece para o tier correto
3. Verificar que `allowedDesignations` é respeitado

### Biblioteca
- **Playwright** (já instalado v1.58.2) para route tests
- **Supabase CLI** (já instalado v2.75.0) para RPC tests via `supabase db execute`
- Criar helper `tests/helpers/auth-simulator.ts` que gera tokens JWT com diferentes tiers

---

## Ordem de Execução

```
Sprint A (W90): Schema + RPCs de curadoria → UI do parecer → Dashboard
Sprint B (W91): Junction table + migration + RPCs → MemberPicker v2 → CardDetail
Sprint C (W96): RLS policies → RPC tier checks → Contract tests
```

W96 vai por último porque as RLS policies precisam considerar as novas tabelas de W90 e W91.

Cada sprint: build + tests + smoke antes de push.

---

## Critérios de Aceite

### W90
- [ ] Revisor designado vê formulário de rubrica com 5 critérios (sliders 1-5)
- [ ] Após 2 aprovações, item muda para 'approved' automaticamente
- [ ] SLA badge mostra countdown configurável por board
- [ ] Dashboard de curadoria mostra progresso "1/2 revisores"
- [ ] Timeline do card mostra histórico de pareceres com scores

### W91
- [ ] Card pode ter múltiplos assignees com roles diferentes
- [ ] MemberPicker suporta multi-select com chips/tags
- [ ] "Adicionar grupo" expande designation para membros individuais
- [ ] Cards legados continuam funcionando (fallback para campos legacy)
- [ ] 354 cards existentes migrados para junction table sem perda

### W96
- [ ] RPCs LGPD retornam erro para tiers abaixo do permitido
- [ ] Rotas /admin/selection e /admin/comms inacessíveis para researchers
- [ ] Contract tests automatizados passam em CI
- [ ] Zero queries diretas a tabelas sensíveis sem RLS enforcement
