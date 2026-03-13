# Gmail Data Extraction — Reconciliation Report

**Data:** 2026-03-13 (atualizado com dados da aplicação Ambassador)
**Executado por:** Claude (CXO AI)
**Fonte:** Lista de CC do Fireflies (kick-off Ciclo 3) + Aplicação Ambassador (fev/2026)

---

## 1. Reconciliação de Membros

**53 emails da lista do kick-off cruzados contra tabela `members`.**

### Resultado: 50 encontrados / 3 ausentes

#### Emails NÃO encontrados no DB:

| Email | Observação |
|-------|------------|
| `deborahvpontes@gmail.com` | Deborah Pontes — pessoa DIFERENTE de Débora Moura. **Precisa ser cadastrada pelo GP.** |
| `polliane.portes@pmi.org` | Polliane Portes — Staff PMI LATAM. Registrada como contato externo em `partner_entities`. |
| `welma@pmigo.org.br` | Welma — email institucional PMI-GO. Não encontrado nem em `secondary_emails`. |

#### Membros encontrados mas INATIVOS:

| Email | Nome | is_active | current_cycle_active |
|-------|------|-----------|---------------------|
| `diego.msousa@hotmail.com` | Diego Menezes | false | false |
| `rogercortess@gmail.com` | Rogério Côrtes | false | false |

> **Ação recomendada:** Se Diego e Rogério participaram do kick-off, considerar reativá-los (`is_active=true, current_cycle_active=true`). Os 3 emails ausentes precisam de cadastro manual pelo GP.

---

## 2. Partner Entities — Datas Atualizadas + Prospects

### Capítulos PMI (datas formalizadas)

| Parceiro | partnership_date | Status |
|----------|-----------------|--------|
| PMI-CE | 2025-12-10 | active |
| PMI-RS | 2025-12-10 | active |
| PMI-DF | 2025-12-10 | active |
| PMI-MG | 2025-12-09 | active |

### Prospects (aplicação Ambassador + reuniões)

| Entidade | Tipo | Status | Origem |
|----------|------|--------|--------|
| Instituto Federal de Goiás (IFG) | academia | prospect | Reunião 10/dez/2025 com Prof. Sirlon Diniz |
| FioCruz | governo | prospect | Negociações mencionadas na aplicação Ambassador (fev/2026) |
| AI.Brasil | empresa | prospect | Negociações mencionadas na aplicação Ambassador (fev/2026) |
| CEIA-UFG (Centro de Excelência em IA) | academia | prospect | Negociações mencionadas na aplicação Ambassador |
| PMO-GA | governo | prospect | Negociações mencionadas na aplicação Ambassador (fev/2026) |

### Contatos Estratégicos

| Contato | Cargo / Org | Registro |
|---------|-------------|----------|
| Cristina Duarte | Diretora de Administração e Finanças, PMI-DF | Nota no `description` de PMI-DF |
| Polliane Portes | Staff PMI LATAM (`polliane.portes@pmi.org`) | Entidade `PMI LATAM Staff` (type: `pmi_global`) |
| Daniel Falcão | PMI Global | Contato adicional na entidade `PMI LATAM Staff` |

---

## 3. Publicações Semeadas (Ciclo 2)

7 artigos submetidos ao ProjectManagement.com registrados em `public_publications`:

| Título | Status |
|--------|--------|
| Data-Driven Environmental Management: The Role of AI in Selecting High-Impact Projects | published |
| Smart Prioritization: A Practical Guide to Using AI in Project Selection and Prioritization | published |
| AI-Supported Feasibility in Real Estate: A Strategic Framework | published |
| Generative AI in Risk Management: The Copilot Every Project Deserves | published |
| Measuring the Success of AI in the Public Sector: A Practical Guide to KPIs | pendente |
| Using AI for Strategic KPI Selection in Wind Farm Project Management | pendente |
| Ethical Use of Generative AI in PM: Balancing Productivity and Confidentiality | pendente |

Todos com `cycle_code='cycle2-2025'`, `authors=['Núcleo IA & GP']` (autores individuais a serem preenchidos pelo GP), `external_platform='projectmanagement.com'`.

> **Nota KPI:** Estes artigos são do Ciclo 2. O KPI `articles_published` do Ciclo 3 (2026) só deve contar publicações com `cycle_code='cycle3-2026'` ou `publication_date >= '2026-03-01'`.

---

## 4. Verificação de Emails de Líderes

Todos os 7 líderes encontrados no DB com emails corretos:

| Nome | Email | operational_role |
|------|-------|-----------------|
| Débora Moura | debi.moura@gmail.com | tribe_leader |
| Marcel Fleming | fleming.marcel@yahoo.com.br | tribe_leader |
| Ana Carla Cavalcante | anagatcavalcante@gmail.com | tribe_leader |
| Jefferson Pinto | jefferson.pinheiro.pinto@gmail.com | tribe_leader |
| Fernando Maquiaveli | fernando@maquiaveli.com.br | tribe_leader |
| Hayala Curto | hayala.curto@gmail.com | tribe_leader |
| Marcos Antunes Klemz | maklemz@gmail.com | tribe_leader |

**Deborah Pontes** (`deborahvpontes@gmail.com`) NÃO está no DB — é uma das 3 ausentes listadas acima.

---

## 5. Governance

| Pessoa | Cargo Atual | DB Status |
|--------|-------------|-----------|
| Jessica Alcantara | Presidente PMI-CE (substituiu Cristiano) | `sponsor`, `designations=['sponsor']`, chapter PMI-CE |
| Cristiano Oliveira | Ex-presidente PMI-CE, embaixador | `designations=['ambassador']`, `is_active=false` |

---

## 6. Oportunidades Registradas no Backlog

| Sprint | Oportunidade | Status |
|--------|-------------|--------|
| W120 | PM AI Revolution Ambassador follow-up (aplicação 11/fev/2026, Vitor + Fabricio) | Planned |
| W121 | LATAM LIM 2026 — submissão de proposta (convite via Fabricio, 09/mar/2026) | Planned |
| W122 | Carlos Novello Award follow-up (Vitor indicado Voluntário do Ano PMI LATAM 2025) | Planned |
| W123 | Partner pipeline management (5 entidades em negociação: FioCruz, AI.Brasil, CEIA-UFG, IFG, PMO-GA) | Planned |

---

## Pendências para o GP

1. **Cadastrar 3 membros ausentes** (ou confirmar que não devem ser cadastrados):
   - `deborahvpontes@gmail.com` (Deborah Pontes)
   - `polliane.portes@pmi.org` (Polliane Portes — já registrada como contato externo)
   - `welma@pmigo.org.br` (Welma)

2. **Decidir sobre reativação** de Diego Menezes e Rogério Côrtes

3. **Preencher autores individuais** nos 7 artigos semeados (atualmente `Núcleo IA & GP`)

4. **Adicionar `external_url`** para os 4 artigos já publicados no ProjectManagement.com

5. **Atribuir responsáveis** para cada negociação de parceria (5 prospects)
