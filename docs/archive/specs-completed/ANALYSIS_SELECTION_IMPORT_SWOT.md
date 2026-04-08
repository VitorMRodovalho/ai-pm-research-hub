# Analise SWOT + Gap + Recomendacoes: Selection VEP Import

**Data:** 01 April 2026
**Contexto:** Selection Pipeline V2 em producao. Problemas identificados durante teste pelo GP.
**Painel:** PMI Global Consultant, PMBOK 8ed Guardian, LGPD Advisor, Tech Lead, Product Owner

---

## 1. DESCOBERTAS (Findings)

### D1: Logica de skip de membros inativos e fragil
**Problema:** A RPC `import_vep_applications` faz skip de qualquer email que exista em `members` com `is_active = false`. Isso bloqueia ex-voluntarios que retornam legitimamente (ex: alguem do ciclo 1 que quer participar do ciclo 3).
**Caso real:** Leandro Mota (offboarded 18/Mar no ciclo 3) apareceu como "Submitted" no VEP. A logica corretamente skipou, mas a regra e muito ampla.
**Regra correta:** So bloquear quem foi inativado DENTRO DO CICLO ATUAL. Ex-voluntarios de ciclos anteriores que reaplicam sao candidatos legitimos.

### D2: Dados de teste contaminaram producao
**Problema:** Os 8 candidatos do primeiro import manual tinham dados parciais (sem essays, membership fake). O Joao Uzejka apareceu como PMI-GO quando na realidade e PMI-RS.
**Causa:** Import manual via SQL com dados simplificados antes do CSV real estar disponivel.
**Solucao:** Limpar dados de teste e reimportar do CSV real.

### D3: Perguntas customizaveis por vaga (VEP Additional Questions)
**Problema:** O CSV do VEP exporta as respostas como "Essay Question 1" a "Essay Question 5" sem incluir os titulos das perguntas. As perguntas sao configuradas por vaga no VEP. Cada vaga pode ter perguntas diferentes.
**Vaga 64967 (Pesquisador):**
  1. "Voce e filiado a um dos capitulos parceiros? Se sim, qual?"
  2. "Em qual perfil voce melhor se encaixa? Pesquisador/Multiplicador/Facilitador? Por que?"
  3. "Voce tem familiaridade com o Guia PMBOK ou certificacao?"
  4. "Voce possui disponibilidade de 4-6h semanais?"
**Vaga 64966 (Lider) provavelmente tem perguntas diferentes.**
**Implicacao:** O mapeamento Essay→campo do DB deve ser configuravel por opportunity_id, nao hardcoded.

### D4: Data de candidatura nao capturada
**Problema:** O CSV tem "Application Submitted" date mas nao estamos importando. O campo `created_at` do DB recebe `now()` (data de import) em vez da data real de candidatura.
**Implicacao:** Timeline de selecao fica incorreta. Candidatos que aplicaram em Marco aparecem como se tivessem aplicado em Abril.

### D5: Joao PMI-GO vs PMI-RS
**Causa raiz:** Import manual com dados fake. O membro tem `chapter = PMI-RS` na tabela members, mas a selection_application tem `chapter = PMI-GO` do import manual.
**Nota:** No CSV real do VEP (vep_app_id 281787), Joao aparece com status "Active" (ja aceito) e membership "Individual Membership,Goias, Brazil Chapter" — isso e o CHAPTER DA VAGA (PMI-GO posted a vaga), nao o chapter do voluntario.
**Descoberta critica:** O campo "Membership status" do CSV mistura o tipo de membership com os CHAPTERS QUE O VOLUNTARIO E FILIADO, nao o chapter que postou a vaga. Mas um voluntario pode ser filiado a multiplos chapters. Joao pode ser filiado a PMI-GO E PMI-RS.

---

## 2. SWOT

### Strengths (Forcas)
- Schema dimensional correto (partner_chapters, membership_snapshots)
- Dedup por vep_application_id funciona
- Parser RFC 4180 resolve campos multi-linha
- Blind review, PERT, calibration alerts implementados
- Conversion flow researcher→leader existe
- Pre-onboarding gamification integrado

### Weaknesses (Fraquezas)
- **Logica de skip baseada em is_active sem considerar o ciclo** — bloqueia retornantes
- **Mapeamento de essays hardcoded** — nao escala para vagas com perguntas diferentes
- **Data de candidatura nao importada** — timeline incorreta
- **Chapter do voluntario pode ser multiplo** — so capturamos o primeiro match do parser
- **Dados de teste em producao** — contaminacao

### Opportunities (Oportunidades)
- **Configuracao de opportunity (vep_opportunities table):** Armazenar titulo, perguntas customizadas, chapter que postou, role default. Permite mapear essays corretamente por vaga.
- **Expansao para outros capitulos e EUA:** Com o modelo dimensional de partner_chapters e configuracao por opportunity, a plataforma escala naturalmente.
- **Snapshot de membership ao longo do tempo:** Auditoria de filiacao para diretoria dos capitulos.

### Threats (Ameacas)
- **VEP nao tem API** — dependemos de CSV export manual, sujeito a erros humanos
- **VEP pode mudar formato do CSV** — parser precisa ser resiliente
- **Crescimento de candidatos pos-CBGP** — volume pode expor bugs nao descobertos com 8 candidatos

---

## 3. GAP ANALYSIS

| Item | Estado Atual | Estado Desejado | Gap |
|------|-------------|-----------------|-----|
| Skip de membros | Skipa qualquer email em members com is_active=false | Skipar APENAS membros inativados no ciclo corrente (offboarded_at dentro do periodo do ciclo) | Logica de data no check |
| Perguntas por vaga | Hardcoded (Essay Q1→motivation, Q2→role, Q3→pmbok, Q4→availability) | Configuravel por opportunity_id com mapeamento {essay_index: db_field} | Nova tabela/config |
| Data de candidatura | Nao importada (usa now()) | Importar "Application Submitted" do CSV como application_date | Novo campo + parser |
| Chapter primario | Primeiro partner match do parser | Capturar TODOS os chapters do voluntario, usar o chapter do members table se existir | Logica de merge |
| Dados de teste | Misturados com producao | Limpos, apenas dados reais do CSV | Cleanup SQL |

---

## 4. PAINEL DE ESPECIALISTAS

### PMI Global Volunteer Consultant
> "A logica de skip deve ser: (1) VEP Active/Complete → skip (ja aceitos); (2) VEP OfferNotExtended → skip (rejeitados); (3) VEP Submitted → verificar se o email existe em `members`. Se existe E foi offboarded DENTRO DO CICLO CORRENTE (offboarded_at >= cycle.open_date) → flag para revisao manual do GP, NAO auto-skip. Se existe de ciclos anteriores → importar normalmente como returning member. Isso preserva o pool de talentos."

### PMBOK 8ed Guardian
> "As perguntas de selecao sao artefatos do processo de avaliacao (PMBOK 8, dominio Stakeholders). Cada vaga e um 'projeto' com criterios proprios. O mapeamento {pergunta→campo} deve ser parte da configuracao da vaga, nao do parser. Recomendo uma tabela `vep_opportunities` com `essay_mapping jsonb`."

### LGPD Advisor
> "O chapter do voluntario e dado pessoal do PMI, nao nosso. Ao importar, devemos registrar a fonte (csv_import) e a data. Nao devemos inferir ou alterar o chapter — usar o dado do CSV como fato, e o dado da tabela members como dimensao. Se divergem, flaggear para revisao."

### Tech Lead
> "Recomendo: (1) Criar tabela `vep_opportunities` com essay_mapping, chapter_posted, role_default. (2) Adicionar campo `application_date` em selection_applications. (3) Refatorar o skip logic para checar offboarded_at vs cycle dates. (4) Cleanup dos dados de teste do Batch 2. (5) Nao complicar demais — o VEP e um sistema externo sem API, entao a interface sera sempre CSV manual."

---

## 5. RECOMENDACOES FINAIS

### R1: Corrigir logica de skip (CRITICO)
```
IF membro existe AND is_active = false:
  IF offboarded_at >= ciclo_atual.open_date:
    → FLAG para revisao manual (inativado no ciclo corrente)
    → Log em data_anomaly_log
    → NAO importar automaticamente
  ELSE:
    → Importar como returning_member (ex-voluntario retornando)
    → is_returning_member = true
    → Atualizar membership snapshot
```

### R2: Criar tabela vep_opportunities (MEDIO)
```sql
CREATE TABLE vep_opportunities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id text NOT NULL UNIQUE, -- '64967'
  title text NOT NULL,
  chapter_posted text, -- 'PMI-GO' (who posted)
  role_default text DEFAULT 'researcher',
  essay_mapping jsonb NOT NULL DEFAULT '{}',
  -- Ex: {"1":"motivation_letter","2":"areas_of_interest","3":"academic_background","4":"availability_declared"}
  start_date date,
  end_date date,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
```

### R3: Adicionar application_date (MEDIO)
- Novo campo `application_date date` em selection_applications
- Parser extrai do CSV (se disponivel)
- Frontend mostra na tabela e no modal

### R4: Cleanup Batch 2 (IMEDIATO)
- Deletar os 8 registros de teste manual
- Reimportar do CSV real com parser corrigido
- Joao sera importado corretamente como returning member com dados reais

### R5: Chapter merge logic (BAIXO)
- Ao importar, se email existe em members table, usar o chapter da members table como primario
- Chapters do CSV ficam no snapshot para auditoria
- Se divergem, flaggear (nao sobrescrever)

---

## 6. CHANGE REQUEST — Manual de Governanca R2

### CR-001: Secao 3 (Processo Seletivo)
Adicionar paragrafo: "Candidatos que possuem registro historico como voluntarios em ciclos anteriores e que reaplicam via VEP sao tratados como 'returning members' e passam pelo pipeline completo de avaliacao. Apenas voluntarios inativados DENTRO DO CICLO CORRENTE (com data de offboarding posterior ao inicio do ciclo) sao sinalizados para revisao manual pelo GP antes de reingressar no pipeline."

### CR-002: Secao 3.2 (Configuracao de Vagas)
Adicionar: "Cada vaga publicada no PMI VEP deve ter seu mapeamento de perguntas customizadas registrado na plataforma antes do primeiro import de CSV. O mapeamento associa cada 'Essay Question' do CSV ao campo correspondente na base de dados."

---

*Analise conduzida com painel: PMI Global Consultant (jornada voluntariado), PMBOK 8ed Guardian (processo), LGPD Advisor (dados pessoais), Tech Lead (implementacao). Recomendacoes R1-R5 priorizadas por criticidade.*
