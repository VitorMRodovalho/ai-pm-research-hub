# Gmail Data Extraction — Reconciliation Report

**Data:** 2026-03-13
**Executado por:** Claude (CXO AI)
**Fonte:** Lista de CC do Fireflies (kick-off Ciclo 3)

---

## 1. Reconciliação de Membros

**53 emails da lista do kick-off cruzados contra tabela `members`.**

### Resultado: 50 encontrados / 3 ausentes

#### Emails NÃO encontrados no DB:

| Email | Observação |
|-------|------------|
| `deborahvpontes@gmail.com` | Deborah Pontes — pessoa DIFERENTE de Débora Moura. Líder designada no Ciclo 3. **Precisa ser cadastrada pelo GP.** |
| `polliane.portes@pmi.org` | Polliane Portes — email institucional PMI. Não encontrado nem em `secondary_emails`. |
| `welma@pmigo.org.br` | Welma — email institucional PMI-GO. Não encontrado nem em `secondary_emails`. |

#### Membros encontrados mas INATIVOS:

| Email | Nome | is_active | current_cycle_active |
|-------|------|-----------|---------------------|
| `diego.msousa@hotmail.com` | Diego Menezes | false | false |
| `rogercortess@gmail.com` | Rogério Côrtes | false | false |

> **Ação recomendada:** Se Diego e Rogério participaram do kick-off, considerar reativá-los (`is_active=true, current_cycle_active=true`). Os 3 emails ausentes precisam de cadastro manual pelo GP.

---

## 2. Partner Entities — Datas Atualizadas

| Parceiro | partnership_date | Status |
|----------|-----------------|--------|
| PMI-CE | 2025-12-10 | active |
| PMI-RS | 2025-12-10 | active |
| PMI-DF | 2025-12-10 | active |
| PMI-MG | 2025-12-09 | active |
| Instituto Federal de Goiás (IFG) | 2025-12-10 | prospect |

IFG inserido como `prospect` (reunião de apresentação, pendente follow-up).

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

## 5. Contatos Estratégicos

| Contato | Cargo / Org | Registro |
|---------|-------------|----------|
| Cristina Duarte | Diretora de Administração e Finanças, PMI-DF | Nota adicionada ao `description` de PMI-DF em `partner_entities` |
| Polliane Portes | Staff PMI LATAM (`polliane.portes@pmi.org`) | Nova entrada `PMI LATAM Staff` em `partner_entities` (type: `pmi_global`) |
| Daniel Falcão | PMI Global | Registrado como contato adicional na entidade `PMI LATAM Staff` |
| Jessica Alcantara | Presidente PMI-CE (substituiu Cristiano) | Já no DB como `sponsor` com `designations=['sponsor']`, chapter PMI-CE |
| Cristiano Oliveira | Ex-presidente PMI-CE, agora embaixador | Já no DB com `designations=['ambassador']`, `is_active=false` |

---

## 6. Oportunidades Registradas no Backlog

| Sprint | Oportunidade | Status |
|--------|-------------|--------|
| W119 | Submeter proposta do Núcleo ao LATAM LIM 2026 (convite via Fabricio, 09/mar/2026) | Planned |
| W120 | Follow-up aplicação à iniciativa Ricardo Vargas / PM AI Revolution | Planned |

---

## Pendências para o GP

1. **Cadastrar 3 membros ausentes** (ou confirmar que não devem ser cadastrados):
   - `deborahvpontes@gmail.com` (Deborah Pontes)
   - `polliane.portes@pmi.org` (Polliane Portes)
   - `welma@pmigo.org.br` (Welma)

2. **Decidir sobre reativação** de Diego Menezes e Rogério Côrtes

3. **Preencher autores individuais** nos 7 artigos semeados (atualmente `Núcleo IA & GP`)

4. **Adicionar `external_url`** para os 4 artigos já publicados no ProjectManagement.com
