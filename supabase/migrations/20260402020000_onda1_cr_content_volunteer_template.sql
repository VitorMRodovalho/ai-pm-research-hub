-- Sprint 12 — Onda 1+2: CR content population + volunteer term upgrade
-- Applied live via execute_sql. This migration records the changes for git history.

-- ═══ ONDA 1: CR proposed_changes population ═══

-- CR-024: Inativação de Tribos
UPDATE change_requests SET proposed_changes = 'Adicionar à §4.6 — Transições e Desligamento:

**Inativação de Tribos**

Uma tribo pode ser inativada quando perde viabilidade operacional (ex: saída do líder sem substituto, quorum insuficiente). O processo é:

1. O GP marca a tribo como inativa na plataforma (campo is_active = false)
2. A tribo desaparece da homepage e das listagens públicas
3. Os dados históricos (boards, artefatos, atas) são preservados em modo read-only
4. Os membros são redistribuídos individualmente para outras tribos ou movidos para o pool de pesquisadores disponíveis
5. A reativação é possível em ciclos futuros mediante nova designação de líder e quorum mínimo

**Precedente:** T3 (TMO & PMO do Futuro) foi inativada no Ciclo 2 quando o líder Marcel deixou o Núcleo.'
WHERE cr_number = 'CR-024' AND (proposed_changes IS NULL OR proposed_changes = '');

-- CR-028: Permissões por Board
UPDATE change_requests SET proposed_changes = 'Nova tabela board_members com roles por board:

**Modelo de Dados:**
- board_members(board_id, member_id, role: admin|editor|viewer, granted_by, granted_at)
- Board admin equivale a tribe_leader naquele board
- Board editor pode criar e editar cards próprios
- Board viewer tem acesso read-only

**RPCs Atualizadas:**
- create_board_item, update_board_item, move_board_item verificam board_members além de operational_role
- admin_manage_board_member para gestão pelo GP

**Nota:** Tabela e RPCs já implementados na plataforma. Este CR formaliza o modelo no manual §4.7.'
WHERE cr_number = 'CR-028' AND (proposed_changes IS NULL OR proposed_changes = '');

-- CR-039: Vaga Unificada
UPDATE change_requests SET proposed_changes = 'Reescrever §3.4 do Manual para processo seletivo unificado:

**Vaga Unificada com Faixa de Líder**

O processo seletivo opera com vaga unificada de pesquisador voluntário. Candidatos aplicam uma vez com formulário padrão, respondendo opcionalmente perguntas adicionais para a faixa de líder de tribo.

**Conversão Pesquisador → Líder:**
A conversão é possível via 3 gates:
1. Pré-recomendação: score quantitativo >= P90 OU tag explícita do avaliador
2. Aprovação do GP: validação de perfil de liderança
3. Aceite formal: candidato confirma interesse na faixa de líder

**Precedente Ciclo 3:** 5 candidatos convertidos para líderes via processo informal. Esta CR formaliza a prática.'
WHERE cr_number = 'CR-039';

-- ═══ R3 Manual Section: Apêndice B ═══

INSERT INTO manual_sections (section_number, title_pt, title_en, content_pt, content_en, manual_version, sort_order, is_current)
SELECT 'B', 'Acordos de Cooperação e Documentos Oficiais', 'Cooperation Agreements and Official Documents',
'## B.1 — Acordos de Cooperação

O Núcleo opera sob Acordos de Cooperação bilaterais entre capítulos PMI, formalizados via DocuSign.

### Acordos Vigentes

| # | Capítulo | Data | Status |
|---|----------|------|--------|
| 1 | PMI Goiás | Set/2025 | Ativo |
| 2 | PMI São Paulo | Abr/2026 | Em negociação |
| 3 | PMI Rio Grande do Sul | Mar/2026 | Ativo |
| 4 | PMI Minas Gerais | Mar/2026 | Em negociação |

## B.2 — Documentos Oficiais

| Tipo | Armazenamento |
|------|---------------|
| Manual de Governança | Plataforma (versionado) |
| Acordos de Cooperação | DocuSign + Plataforma |
| Termos de Voluntariado | Plataforma (assinatura digital) |
| Atas de Reunião | Plataforma (meeting_notes) |
| Certificados | Plataforma (verificáveis) |',
'## B.1 — Cooperation Agreements

The Nucleus operates under bilateral Cooperation Agreements between PMI chapters, formalized via DocuSign.

## B.2 — Official Documents

The Nucleus maintains digital records of official documents including: Governance Manual (versioned), Cooperation Agreements (DocuSign), Volunteer Terms (digital signature), Meeting Notes, and Certificates (verifiable).',
'R3', 99, true
WHERE NOT EXISTS (SELECT 1 FROM manual_sections WHERE section_number = 'B' AND manual_version = 'R3');

-- ═══ R3 §7.2: Fix MCP tool count 15→52 ═══

UPDATE manual_sections
SET content_pt = REPLACE(content_pt, '15 ferramentas', '52 ferramentas')
WHERE manual_version = 'R3' AND section_number = '7.2' AND content_pt LIKE '%15 ferramentas%';

-- ═══ ONDA 2: Volunteer term RPC upgrade (12 clauses) ═══
-- sign_volunteer_agreement updated via CREATE OR REPLACE to store full 12-clause content_snapshot
-- See function definition applied live

NOTIFY pgrst, 'reload schema';
