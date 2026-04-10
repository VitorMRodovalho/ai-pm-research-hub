# SPEC: Sistema de Dois Rankings no Processo Seletivo (Pesquisador + Líder)

**Autor:** Consultoria conjunta (governança PMI, auditoria de dados, arquitetura, tech full-stack)
**Data:** 2026-04-10
**Status:** 🟡 Proposta — CR-047 `submitted`, aguarda review/aprovação
**Origem:** Issue #66 + pergunta do PM sobre `leader_extra`
**Change Request:** [CR-047](https://nucleoia.vitormr.dev/admin/governance) — predecessor CR-042 (implemented)

---

## 1. Contexto e motivação

### 1.1 Problema
O processo seletivo do Núcleo tem **duas trilhas de candidatura**:

1. **Pesquisador**: avaliado em `objective` + `interview`
2. **Líder**: avaliado em `objective` + `interview` + **`leader_extra`** (5 critérios adicionais: Exp. Pesquisa+GP, Liderança, Conhecimento Técnico, Envolvimento PMI, Idiomas — peso total 18, max 90 pontos PERT)

Além disso, existe **um fluxo de triagem**: um candidato que se aplica como pesquisador pode ser identificado pelo comitê como potencial líder e receber **avaliação adicional** na trilha de líder.

### 1.2 Estado atual (problemas detectados)

Após auditoria no banco de produção, identificamos 4 problemas críticos:

**P1 — Fórmula de `final_score` inconsistente entre RPCs**
- `submit_evaluation` (antiga, migration `20260319100025`): ao receber `leader_extra`, faz `objective_score_avg += leader_extra_pert` e recalcula `final_score`
- `submit_interview_scores` (nova, migration `20260401070000`): sobrescreve `final_score = objective_score_avg + interview_score`, **ignorando leader_extra**
- **Efeito**: se a entrevista completa DEPOIS do leader_extra, a contribuição do leader_extra é perdida. Fabrício Costa (leader) está nesse estado: `final_score=364=242+122`, sem os 76 pontos do leader_extra.

**P2 — Candidatos duplicados em fluxo de dupla-trilha**
Dados de produção:
- **Ana Carla Cavalcante** aparece com **2 linhas** em `selection_applications`:
  - `role_applied='leader'`, objective=240, final=361 (approved)
  - `role_applied='researcher'`, objective=115, final=236 (converted)
- **Hayala Curto**: mesma situação (212/333 leader vs 137.5/258.5 researcher)

Isso quebra unicidade de `(cycle_id, email)` e cria ambiguidade: qual é a "verdadeira" application para audit? Por que os objective scores são diferentes entre as duas linhas da mesma pessoa?

**P3 — Ranking único e ambíguo**
- Coluna `rank_chapter` existe, mas é **um único ranking** misturando pesquisadores e líderes
- Não há como auditar "o ranking de líderes" separadamente
- `rank_global` não existe

**P4 — Falta de documentação formal da fórmula**
- Não há um documento do ciclo (DAC) que especifique: "final_score = X + Y + Z para líderes" vs "final_score = X + Y para pesquisadores"
- A fórmula está embutida em migrations, o que viola o princípio de "rules as data" do PMBOK para governança

---

## 2. Perspectivas consultadas

### 2.1 Consultor PMI Global
> Processos seletivos devem ter **transparência de critério** (DAC publicado antes da seleção) e **reprodutibilidade** (qualquer auditor externo deve conseguir recalcular a nota com os dados brutos). Rankings devem ser **estáveis** (não mudam por side-effect de eventos em outros candidatos).

**Requisito:** a fórmula de cálculo precisa estar declarada no `selection_cycles` como dado, não em código. O `recalculate_rankings()` deve ser idempotente e auditável.

### 2.2 PMBOK Guardian (PMBOK 7 — Performance Domain: Measurement)
> Métricas de decisão devem ser **multidimensionais** e **explícitas sobre tradeoffs**. Comparar um candidato com critérios diferentes (leader vs researcher) em um único ranking viola o princípio de "comparable baselines".

**Requisito:** rankings separados por track. Candidatos na dupla-trilha devem aparecer em ambos, mas com scores corretos para cada um.

### 2.3 Auditor de arquitetura de dados
> Dois problemas de integridade: (a) duplicação de applicant como múltiplas rows quebra a relação 1:1 com `members.email`; (b) `final_score` não é uma fonte de verdade — é um valor derivado sobrescrito por múltiplas RPCs.

**Requisitos:**
- **Um `application_id` por candidato por ciclo** (garantido por unique constraint)
- Scores componentes (`objective_pert`, `interview_pert`, `leader_extra_pert`) são **fonte de verdade**
- Scores agregados (`research_score`, `leader_score`) e rankings são **sempre derivados** via função pura
- **Audit log** em `admin_audit_log` a cada recalc de ranking

### 2.4 Tech Architect (full-stack)
> Duas RPCs escrevendo em `final_score` é código smell. Deve haver um **único ponto de consolidação** (`compute_application_scores`) chamado ao fim de qualquer submit. Frontend precisa mostrar a estrutura correta ao usuário (líderes veem dois rankings, pesquisadores veem um).

**Requisitos:**
- Centralizar cálculo em função única
- Tipar os estados de track como enum
- Frontend `/admin/selection`: abas ou filtro por tipo de ranking
- MCP tool `get_selection_rankings(track: 'researcher'|'leader')`

---

## 3. Proposta arquitetural

### 3.1 Novo modelo de dados

#### 3.1.1 Colunas adicionais em `selection_applications`

```sql
ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS
  track text NOT NULL DEFAULT 'researcher'
  CHECK (track IN ('researcher', 'leader', 'dual'));
-- 'researcher': só avaliado em objective+interview
-- 'leader':     aplicou como líder OU foi promovido para leader-only
-- 'dual':       avaliado em AMBOS (pesquisador e líder) — caso de triagem completa

ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS
  research_score numeric;  -- objective_pert + interview_pert (null até completar ambos)

ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS
  leader_score numeric;    -- research_score + leader_extra_pert (null se track='researcher')

ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS
  rank_researcher int;     -- posição no ranking de pesquisador (null se track='leader')

ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS
  rank_leader int;         -- posição no ranking de líder (null se track='researcher')

ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS
  track_decided_at timestamptz;  -- quando o track atual foi definido

ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS
  track_decided_by uuid REFERENCES members(id);
```

#### 3.1.2 `final_score` vira **campo computado de display** (para backward compat)

Opção A: trigger mantém `final_score = COALESCE(leader_score, research_score)` automaticamente.
Opção B: remove `final_score` e frontend consulta diretamente os dois.

**Recomendação**: A, para não quebrar queries existentes.

#### 3.1.3 Nova tabela de audit: `selection_ranking_snapshots`

```sql
CREATE TABLE selection_ranking_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES selection_cycles(id),
  snapshot_at timestamptz NOT NULL DEFAULT now(),
  triggered_by uuid REFERENCES members(id),
  reason text,
  rankings jsonb NOT NULL,  -- [{application_id, track, rank_researcher, rank_leader, research_score, leader_score}]
  formula_version text  -- hash/id da fórmula usada
);
```

Toda chamada de `recalculate_rankings(cycle_id)` grava um snapshot. Isso dá **trilha de auditoria imutável** — um auditor externo pode reconstituir "o ranking vigente na data X".

### 3.2 Lógica de ranking

```sql
CREATE OR REPLACE FUNCTION recalculate_cycle_rankings(p_cycle_id uuid)
RETURNS jsonb AS $$
BEGIN
  -- Ranking de pesquisador: todas as applications com track IN ('researcher','dual')
  --                         onde research_score IS NOT NULL, ordenadas desc
  UPDATE selection_applications SET rank_researcher = NULL WHERE cycle_id = p_cycle_id;
  WITH ranked AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY research_score DESC NULLS LAST, applicant_name) as rnk
    FROM selection_applications
    WHERE cycle_id = p_cycle_id
      AND track IN ('researcher', 'dual')
      AND research_score IS NOT NULL
      AND status NOT IN ('withdrawn', 'rejected', 'cancelled')
  )
  UPDATE selection_applications a SET rank_researcher = r.rnk
  FROM ranked r WHERE a.id = r.id;

  -- Ranking de líder: applications com track IN ('leader','dual')
  --                   onde leader_score IS NOT NULL
  UPDATE selection_applications SET rank_leader = NULL WHERE cycle_id = p_cycle_id;
  WITH ranked AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY leader_score DESC NULLS LAST, applicant_name) as rnk
    FROM selection_applications
    WHERE cycle_id = p_cycle_id
      AND track IN ('leader', 'dual')
      AND leader_score IS NOT NULL
      AND status NOT IN ('withdrawn', 'rejected', 'cancelled')
  )
  UPDATE selection_applications a SET rank_leader = r.rnk
  FROM ranked r WHERE a.id = r.id;

  -- Snapshot para audit trail
  INSERT INTO selection_ranking_snapshots (cycle_id, triggered_by, reason, rankings, formula_version)
  VALUES (p_cycle_id, auth.uid()::uuid, 'auto-recalc', (
    SELECT jsonb_agg(jsonb_build_object(
      'application_id', id, 'track', track,
      'rank_researcher', rank_researcher, 'rank_leader', rank_leader,
      'research_score', research_score, 'leader_score', leader_score
    ))
    FROM selection_applications WHERE cycle_id = p_cycle_id
  ), 'v1.0');

  RETURN jsonb_build_object('success', true);
END;
$$;
```

### 3.3 Consolidação única de scores

```sql
-- Função única chamada ao final de QUALQUER submit (evaluation, interview_scores)
CREATE OR REPLACE FUNCTION compute_application_scores(p_application_id uuid)
RETURNS void AS $$
DECLARE
  v_obj_pert numeric; v_int_pert numeric; v_lead_pert numeric;
BEGIN
  -- PERT já consolidado em momentos anteriores; aqui só lemos
  SELECT AVG(weighted_subtotal) INTO v_obj_pert
  FROM selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = 'objective' AND submitted_at IS NOT NULL;

  SELECT AVG(weighted_subtotal) INTO v_int_pert
  FROM selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = 'interview' AND submitted_at IS NOT NULL;

  SELECT AVG(weighted_subtotal) INTO v_lead_pert
  FROM selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = 'leader_extra' AND submitted_at IS NOT NULL;

  -- Atualiza application
  UPDATE selection_applications
  SET
    research_score = CASE WHEN v_obj_pert IS NOT NULL AND v_int_pert IS NOT NULL
                          THEN v_obj_pert + v_int_pert ELSE NULL END,
    leader_score = CASE WHEN v_obj_pert IS NOT NULL AND v_int_pert IS NOT NULL AND v_lead_pert IS NOT NULL
                        THEN v_obj_pert + v_int_pert + v_lead_pert ELSE NULL END,
    final_score = CASE
      WHEN track IN ('leader','dual') AND v_lead_pert IS NOT NULL THEN v_obj_pert + v_int_pert + COALESCE(v_lead_pert, 0)
      ELSE COALESCE(v_obj_pert, 0) + COALESCE(v_int_pert, 0)
    END,
    updated_at = now()
  WHERE id = p_application_id;
END;
$$;
```

**Ambas RPCs (`submit_evaluation` e `submit_interview_scores`) chamam essa função no fim**. Remove-se toda lógica de cálculo das RPCs individuais.

### 3.4 Fluxo de triagem (researcher → leader)

Quando o comitê decide que um pesquisador deve ser avaliado também como líder:

```sql
CREATE OR REPLACE FUNCTION promote_to_leader_track(
  p_application_id uuid,
  p_to_track text  -- 'leader' (só líder) ou 'dual' (ambos)
) RETURNS jsonb AS $$
-- Auth: só manager, deputy, superadmin
-- Action: atualiza track, track_decided_at, track_decided_by
-- Audit: admin_audit_log
$$;
```

---

## 4. Migração dos dados históricos

### 4.1 Problema P2: duplicação Ana Carla + Hayala

**Decisão**: merge manual. Para cada par de applications duplicadas:
1. Decidir qual row é a "canônica" (provavelmente a mais recente)
2. Mover evaluations da segunda row para a primeira
3. Setar `track='dual'` na canônica
4. Soft-delete (status='merged') ou hard-delete a duplicada
5. Registrar em `admin_audit_log`

### 4.2 Backfill de scores

```sql
-- Para cada application existente:
SELECT compute_application_scores(id) FROM selection_applications;

-- Depois:
SELECT recalculate_cycle_rankings(cycle_id) FROM (SELECT DISTINCT cycle_id FROM selection_applications) x;
```

### 4.3 Resultado esperado (ciclo 3, Fabrício como exemplo)

| Candidato | Track | research_score | leader_score | rank_researcher | rank_leader |
|-----------|-------|----------------|--------------|-----------------|-------------|
| Fabrício Costa | leader | — (null, não conta) | 440 (242+122+76) | — | 2 (exemplo) |
| Fernando Maquiaveli | leader | — | 462 (252+130+80) | — | 1 |
| Pesquisador X | researcher | 330 (200+130) | — | 1 | — |
| Ana Carla (merged) | dual | 361 (240+121) | 441 (+80 leader_extra) | N (pos. entre pesquisadores) | M (pos. entre líderes) |

Candidatos em `dual` aparecem nos DOIS rankings, com scores coerentes (research é subset do leader).

---

## 5. Frontend

### 5.1 `/admin/selection`

**Abas**:
- Overview (como hoje)
- **Ranking Pesquisadores** (nova) — tabela filtrada por `track IN ('researcher','dual')`, ordenada por `rank_researcher`
- **Ranking Líderes** (nova) — tabela filtrada por `track IN ('leader','dual')`, ordenada por `rank_leader`

Colunas novas:
- `research_score`, `leader_score` (quando aplicável)
- badges: 🎯 Pesquisa, 👑 Líder, ✨ Dupla-trilha

### 5.2 `/admin/selection/applicant/[id]`

Detalhe do candidato deve mostrar:
- Scores componentes (objective_pert, interview_pert, leader_extra_pert)
- research_score e leader_score
- rank_researcher e rank_leader
- Histórico de mudança de track (via `selection_ranking_snapshots`)

### 5.3 Candidato self-view

Um candidato deve poder ver **suas próprias notas** (LGPD-ok) mas **não as dos outros**:
- Seu score bruto por critério
- Seu research_score (se aplicável)
- Seu leader_score (se aplicável)
- Sua **posição relativa** (ex: "top 10%") sem revelar nomes de outros

---

## 6. MCP tools

Novas tools:
- `get_selection_rankings(cycle_id?, track: 'researcher'|'leader'|'both')` — retorna ranking atual
- `get_application_score_breakdown(application_id)` — componentes + ranks
- `promote_to_leader_track(application_id, to_track)` — action tool (escrita)

Atualizar tools existentes:
- `get_selection_dashboard` — incluir track, research_score, leader_score nas rows

---

## 7. DAC do ciclo — declarar fórmula como dado

Adicionar coluna em `selection_cycles`:

```sql
ALTER TABLE selection_cycles ADD COLUMN IF NOT EXISTS
  scoring_formula jsonb DEFAULT '{
    "research_score": "objective_pert + interview_pert",
    "leader_score": "research_score + leader_extra_pert",
    "pert_formula": "(2*min + 4*avg + 2*max) / 8",
    "min_evaluators": { "objective": 2, "leader_extra": 2, "interview": 1 },
    "tiebreaker": "alphabetical_by_name"
  }'::jsonb;
```

Isso torna o ciclo **self-describing**. Um auditor externo pode ler direto do banco como o ranking foi calculado.

---

## 8. Plano de rollout (faseado)

### Fase 1 — Schema + consolidação (sem impacto visível)
- [ ] Migration: adicionar colunas `track`, `research_score`, `leader_score`, `rank_researcher`, `rank_leader`
- [ ] Criar `compute_application_scores()` e `recalculate_cycle_rankings()`
- [ ] Criar tabela `selection_ranking_snapshots`
- [ ] Patchear `submit_evaluation` e `submit_interview_scores` para chamar `compute_application_scores()` no fim

### Fase 2 — Backfill de dados históricos
- [ ] Migrar Ana Carla e Hayala para track='dual' (resolver P2)
- [ ] Rodar `compute_application_scores()` em todas as applications
- [ ] Rodar `recalculate_cycle_rankings()` por ciclo
- [ ] Validar: Fabrício deve ter leader_score = 440, rank_leader = X

### Fase 3 — Frontend admin
- [ ] `/admin/selection` abas de ranking
- [ ] Detalhe de applicant com breakdown
- [ ] Badges de track

### Fase 4 — Candidato self-view + MCP tools
- [ ] Página do candidato com posição relativa
- [ ] MCP tools novas e atualizadas

### Fase 5 — Governança
- [ ] Adicionar `scoring_formula` no ciclo atual
- [ ] Publicar DAC atualizado em `docs/GOVERNANCE_CHANGELOG.md`
- [ ] Comunicar ao comitê como auditar

---

## 9. Riscos e mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| Merge errado de Ana Carla/Hayala (perda de histórico) | Baixa | Alto | Dry-run + backup de `selection_evaluations` + revisão manual antes |
| Recálculo muda ranking já comunicado a candidatos | Alta | Médio | Comunicar mudança com transparência; `ranking_snapshots` preserva histórico |
| `compute_application_scores` falha silenciosa | Média | Alto | Testes unitários cobrindo todos os cenários (só obj, obj+int, obj+int+leader, dual, etc.) |
| Frontend quebra ao ler colunas novas | Baixa | Baixo | Deploy fase 1 + 2 antes de fase 3 |
| LGPD: candidato vê score de outros | Média | Alto | RPC `get_my_score_breakdown` com check `auth.uid()` = application.email |

---

## 10. Perguntas em aberto para o PM decidir

1. **Backfill**: recalcular rankings do Ciclo 3 agora (mudando posições já comunicadas) ou só aplicar a novos ciclos? *Recomendação: aplicar só ao Ciclo 3 se os resultados ainda não foram formalmente publicados.*
2. **Ana Carla e Hayala**: qual é a application canônica delas? Mergear para dual?
3. **Publicação**: candidatos devem ver seus próprios ranks ou só status? *Recomendação: rank relativo (top X%) sem nomes.*
4. **Tiebreakers**: quando dois candidatos empatam em score, o que decide? *Proposta: ordem alfabética do nome (determinístico e auditável).*
5. **Fórmula `leader_score`**: soma simples ou ponderada? *Atual proposto: soma simples. Alternativa: `research_score * 0.7 + leader_extra_pert * 0.3` se quiser valorizar mais os critérios de liderança.*

---

## 11. Decisão requerida

**Antes de qualquer implementação**, preciso das suas respostas para:
- (1) a (5) das perguntas abertas
- Aprovação do schema proposto (3.1)
- Aprovação do plano de rollout fases 1-5 (ou repriorização)
- Confirmação de que o `leader_score` será quantitativo e entrará em ranking separado (conforme sua resposta original)

Após aprovação, implementamos em **5 commits sequenciais** (um por fase), cada um testado em produção antes do próximo.

---

## 12. Respostas do PM (2026-04-10) e revisões do spec

### R1. Recalcular Ciclo 3 ✅
> "sim recalcular pois ele é um balizador de estabilidade da feature para eu poder avancar com a analise dos 8 novos candidatos"

**Decisão:** backfill inclui Ciclo 3. Snapshot pré-recálculo gravado para rollback se necessário.

### R2. Dupla candidatura (Ana Carla, Hayala) — modelo revisado ⚠️
> "varios candidatos podem ocorrer de terem candidatado primeiro como pesquisador e terem sido triados para virarem lideres, neste caso apos a rotina de entrevista completa ja contemplando a de lider eles aplicam para a vaga de lider, entao provavelmente neste caso voce tem o application id de ambas vagas para eles, isto é normal e parte da jornada"

**Descoberta:** Não é duplicação errada. É **jornada de triagem legítima**: candidato aplica como pesquisador, entrevista contempla critérios de líder, se triado ele **aplica novamente** para vaga de líder. Resultado: 2 application_ids distintos, 1 por pessoa.

**Revisão do schema (§3.1.1):**

```sql
-- Substituir track='dual' por link explícito entre applications
ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS
  linked_application_id uuid REFERENCES selection_applications(id);
  -- self-FK: researcher app ↔ leader app da mesma pessoa

ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS
  promotion_path text CHECK (promotion_path IN (
    'direct_researcher',    -- aplicou e ficou como pesquisador
    'direct_leader',         -- aplicou direto como líder
    'triaged_to_leader'      -- aplicou como pesquisador, foi triado, RE-aplicou como líder
  )) DEFAULT 'direct_researcher';

-- Integridade: unique por cycle × pessoa × role
ALTER TABLE selection_applications
  ADD CONSTRAINT uq_app_per_role_per_cycle UNIQUE (cycle_id, email, role_applied);
```

**Exclusão de rank_researcher para promovidos:**
- Researcher app com `linked_application_id IS NOT NULL` E o linked leader app com status `approved|converted` → sai do `rank_researcher` (virou líder, não compete mais entre pesquisadores).
- Researcher app mantém a row para audit histórico.

**Backfill Ana Carla + Hayala:**
- Identificar o par de applications (mesmo email, cycle_id)
- Setar `linked_application_id` bidirectional
- Setar `promotion_path='triaged_to_leader'` nas duas
- Registrar em `admin_audit_log`
- **Não há merge** — as 2 rows permanecem.

### R3. Self-view do candidato — objeção acatada ✅
> "o ranking não ficaria variando até ter o resultado final? isto não seria mais um risco que oportunidade?"

**PM tem razão.** Mostrar rank oscilante durante processo gera ansiedade e percepção de injustiça. Consultores (PMI + auditor + PMBOK) convergem:

**Decisão revisada (§5.3):**

Candidato NÃO vê ranking durante processo. Vê apenas:
- Status da etapa atual (`submitted` → `triagem` → `objetiva` → `entrevista` → `resultado_final`)
- **Suas próprias notas** por critério, **após consolidação PERT de cada etapa** (imutável a partir do momento em que a etapa fecha)
- Timestamp de "última atualização" para transparência operacional

**Após status final** (`approved`/`rejected`/`objective_cutoff`):
- **Rank absoluto** da sua posição (no seu track) — snapshot imutável gravado em `selection_ranking_snapshots`
- Apenas o próprio candidato vê seu rank (LGPD: não comparação com outros por nome)

### R4. Tiebreaker — Standard Competition Ranking ✅
> "se o score teve empate acho que ficam na mesma posicao do ranking e o proximo no ranking ficaria na posicao seguinte (exemplo 3 empataram na posicao 12, entao siginfica que o slot 13 e 14 nao pode ser usado, e o proximo no rank esta na posicao 15"

**Confirmado como boa prática.** Isso é **Standard Competition Ranking** (ISO 80000-2), também conhecido como "1-2-2-4 ranking". Usado em competições olímpicas e processos seletivos formais.

**Implementação SQL (§3.2):**

```sql
-- Usar RANK() em vez de ROW_NUMBER() — respeita empates com gap
SELECT id, RANK() OVER (ORDER BY research_score DESC NULLS LAST, applicant_name ASC) as rank_researcher
FROM selection_applications
WHERE cycle_id = p_cycle_id AND ...;

-- Exemplo: scores 450, 430, 430, 430, 410 → ranks 1, 2, 2, 2, 5
```

**Secondary tiebreaker** (para display determinístico quando scores idênticos): `applicant_name ASC`. Auditável.

**Alternativas descartadas:**
- `ROW_NUMBER()`: 1, 2, 3, 4, 5 — não respeita empate
- `DENSE_RANK()`: 1, 2, 2, 2, 3 — sem gap, não é o que PM pediu

### R5. Fórmula ponderada — vira CR-047 ✅
> "interessante tua recomendacao de poderacao para nao ter tanta distorcao, eu concordo e acato - isto tem que ir como uma solicitacao de mudanca do manual de governanca"

**Decisão:** `leader_score = research_score * 0.7 + leader_extra_pert * 0.3`

**Justificativa da ponderação:**
- Soma direta (`research + leader_extra`) dá vantagem artificial: líder pode ter max = 300 + 90 = 390 vs pesquisador max = 300
- Ponderação normaliza a escala: líder max = 300*0.7 + 90*0.3 = 210 + 27 = 237 — comparável
- Alternativamente pode-se normalizar por % do max de cada dimensão antes de somar. A ponderação 0.7/0.3 é mais simples e auditável.

**Processo formal (cumprido):**
1. ✅ Entender critério de CR — tabela `change_requests` + workflow (proposed → submitted → pending_review → approved → implemented)
2. ✅ Verificar CRs relacionados existentes:
   - **CR-042 "SLA e Fórmula de Corte (§3.6)"** — `implemented`, HIGH. Estabeleceu PERT + threshold Mediana×0.75 **dentro de cada dimensão**. CR-047 **não obsoleta** CR-042 — complementa adicionando multi-track e ponderação leader_score.
   - **CR-040 "Métricas de Diversidade"** — `proposed`, low. Não conflita.
   - **CR-037 "Comitê de Seleção Configurável"** — `implemented`. Não conflita.
3. ✅ CR-047 criado como `submitted`, aguardando review.

**Predecessors declarados:**
- CR-042 (complementar, não obsoleto)
- GC-097 (pre-commit QA rules)
- Issue #66 (self-eval já resolvida via trigger DB)

---

## 13. Status atual

- [x] Spec escrito com consultoria multi-perspectiva
- [x] Respostas do PM incorporadas (R1-R5)
- [x] CR-047 criado formalmente em `change_requests` (status: submitted)
- [ ] **Aguardando review/approval do CR-047** antes de implementação
- [ ] Fase 1: schema + compute_application_scores
- [ ] Fase 2: backfill Ciclo 3 + link Ana Carla/Hayala
- [ ] Fase 3: frontend admin
- [ ] Fase 4: candidate self-view + MCP tools
- [ ] Fase 5: scoring_formula declarativa + Manual R3
