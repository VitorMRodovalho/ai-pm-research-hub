# Governança de Coleta de Dados Pessoais — Consultoria Multi-Perspectiva

**Autor:** Consultoria conjunta (PMI Global, PMBOK 7, LGPD auditor, arquitetura de dados, tech full-stack)
**Data:** 2026-04-10
**Status:** 📋 Recomendações para o PM
**Contexto:** Necessidade de coletar dados pessoais (endereço, cidade, nascimento, telefone) para geração do Termo de Compromisso de Voluntário (TCV)

---

## 1. Situação atual (baseline)

### 1.1 O que era antes (gap identificado)
- Platform só tinha: `name`, `email`, `phone`, `state`, `country`, `pmi_id`
- Termo de Voluntariado exigia também: `address`, `city`, `birth_date`
- Resultado: PDFs gerados tinham campos "—" (vazios), documentos legalmente frágeis

### 1.2 O que mudou hoje (2026-04-10)
1. ✅ Schema: `ALTER TABLE members ADD address text, city text, birth_date date` (nullable, LGPD-safe)
2. ✅ Backfill: 28/52 membros atualizados via extração dos 92 PDFs do ZIP de termos assinados de 2025
3. ✅ `sign_volunteer_agreement` RPC agora popula todos os campos no `content_snapshot`
4. ✅ `/profile` página adicionou formulários para membros atualizarem próprios dados
5. ✅ Pre-onboarding `check_pre_onboarding_auto_steps` agora valida todos os campos essenciais antes de marcar `complete_profile` como concluído

---

## 2. Perspectivas consultadas

### 2.1 👥 PMI Global Consultant
> *"Processos de voluntariado multi-capítulo devem documentar cada voluntário com dados suficientes para formalização legal + comunicação institucional. A ausência desses dados gera risco reputacional quando o chapter precisa emitir certificados, comprovantes ou cartas formais."*

**Recomendações:**
- ✅ Campos obrigatórios para TCV: nome, endereço, cidade/estado/país, telefone, email, PMI ID, aniversário (dd/mm)
- ⚠️ **Não exigir ano de nascimento** — idade não é relevante pra voluntariado e agrega risco LGPD sem benefício
- ✅ **Separação por stage**: pesquisador operacional pode ter dados mínimos; voluntário que assina TCV precisa ter completos
- ✅ **Revalidação anual**: ao renovar ciclo, pedir confirmação dos dados ("Estes dados ainda estão corretos?")

### 2.2 📘 PMBOK Guardian (PMBOK 7 — Stakeholder & Performance Domains)
> *"Engajamento de stakeholders requer comunicação confiável. Dados de contato desatualizados impactam o Communications Management Plan. Por outro lado, over-collection (coletar mais do que precisa) viola o princípio de stewardship do PMI Code of Ethics."*

**Recomendações:**
- ✅ **Data minimization**: só coletar campos que tenham uso claro (TCV, comunicação, emergência, convites presenciais)
- ✅ **Purpose statement por campo**: na UI do `/profile`, mostrar *"usado apenas no Termo de Voluntariado · LGPD"* ao lado de cada campo sensível (já implementado)
- ⚠️ **NÃO coletar**: CPF, RG, estado civil, renda, religião, filiação sindical — nunca necessários e alto risco LGPD
- ✅ **Change log**: toda alteração de dados pessoais deve gerar entry em `admin_audit_log` com actor + timestamp (membro edita próprio perfil também gera log)

### 2.3 🔒 Auditor LGPD (Lei 13.709/2018)
> *"LGPD exige base legal clara para cada dado coletado. Endereço, telefone e data de nascimento são 'dados pessoais' (não sensíveis) mas exigem: (a) finalidade específica, (b) consentimento ou legítimo interesse, (c) armazenamento limitado, (d) direito de exclusão."*

**Recomendações técnicas:**

| Campo | Base legal | Justificativa | Retenção | Exposição |
|-------|-----------|---------------|----------|-----------|
| `address` | Consentimento | TCV exige endereço completo | Enquanto voluntário ativo + 5 anos após saída | **PII**: apenas admin + próprio membro |
| `city` | Consentimento | TCV + estatística de distribuição geográfica | Enquanto ativo + 5 anos | **PII limitada**: admin + membro |
| `birth_date` | Consentimento | Felicitações institucionais (data, sem ano) | Enquanto ativo | **PII**: apenas admin + próprio membro |
| `phone` | Consentimento (já existia) | TCV + comunicação urgente | Enquanto ativo + 2 anos | **PII**: admin + próprio membro |
| `pmi_id` | Legítimo interesse | Verificação de membership PMI | Permanente (registro histórico) | **Semi-público**: admin + líder da tribo |

**Mecanismos obrigatórios:**
- ✅ RLS (Row Level Security) nos campos sensíveis: membro só vê próprios dados; admin vê todos; líder vê apenas sua tribo
- ✅ **`share_whatsapp` flag** (já existe): governa visibilidade do phone para peers
- ⚠️ **Faltando**: flag equivalente para `address` (nunca expor a peers) e `birth_date` (visibilidade controlada)
- ✅ **Direito ao esquecimento**: RPC `delete_my_personal_data(p_member_id uuid)` que limpa address/city/birth_date/phone mas mantém histórico (nome, email, contribuições). **ainda não implementado — recomendação P1**
- ⚠️ **Log de acesso a PII** (quem consultou dados de quem): recomendação P2, precisa tabela `pii_access_log`

**Consentimento no pre-onboarding:**
- Candidato DEVE ver tela explicando por que cada campo é coletado
- Checkbox obrigatório: "Concordo com o tratamento dos meus dados conforme a Política de Privacidade e LGPD"
- Link para documento de política (deve existir em `/legal/privacy`)

### 2.4 🏗 Auditor de Arquitetura de Dados
> *"Evitar duplicação e fontes de verdade múltiplas. Dados pessoais em `members` são canônicos; snapshots em `certificates.content_snapshot` são para audit trail histórico (não devem ser re-escritos)."*

**Recomendações:**
- ✅ **Single source of truth**: `members` é a tabela canônica para dados pessoais correntes
- ✅ **Snapshot imutável**: ao assinar TCV, copiar dados de `members` para `certificates.content_snapshot` **naquele momento**. Mudanças posteriores em `members` NÃO alteram snapshots históricos (integridade jurídica do documento)
- ✅ **Re-hydration policy**: se membro atualizar dados DEPOIS de assinar TCV, o snapshot antigo permanece com dados antigos (evidência do que foi assinado), e próximo TCV terá dados novos
- ⚠️ **Migration path**: se precisar adicionar campos no futuro (ex: CEP), usar `ALTER TABLE ... ADD COLUMN` (additive) sem quebrar snapshots antigos
- ✅ **Índices LGPD**: não criar índices em campos PII a menos que necessário (reduz superfície de ataque)

### 2.5 🖥 Tech Architect (Full-stack)
> *"UX de coleta de dados é crítico. Formulários longos geram abandono. Progressive disclosure + contexto + validação em tempo real aumentam conclusão."*

**Recomendações UX:**
- ✅ **Progressive disclosure**: no `/profile`, agrupar campos por sensibilidade (público → restrito → sensível)
- ✅ **Validação client-side**: formato de telefone (BR/US), máscara de data (dd/mm), CEP auto-complete (futuro)
- ✅ **Auto-save opcional**: rascunho salvo a cada mudança, commit ao clicar "Salvar"
- ✅ **Badge de completude**: "Perfil 6/8 campos" → motiva conclusão
- ⚠️ **Não bloquear login** se perfil incompleto — apenas mostrar banner "Complete seu perfil para assinar o TCV"
- ✅ **Pre-onboarding wizard** (P1 futuro): tela dedicada com 1 pergunta por passo, gamificação (XP por campo)

---

## 3. Fluxo recomendado de coleta

```
┌─────────────────────────────────────────────────┐
│ CANDIDATO aprovado na seleção                   │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ 1. Pre-onboarding: create_account (auto)        │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ 2. Pre-onboarding: complete_profile             │
│    - Banner destacado no workspace              │
│    - 8 campos essenciais marcados               │
│    - Purpose statement visível                  │
│    - Consentimento LGPD obrigatório             │
│    - XP ao completar (50 pontos)                │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ 3. Sign Volunteer Agreement (TCV)               │
│    - Dados do membro snapshot em certificates   │
│    - PDF gerado com template legal completo     │
│    - Notificação para diretor contra-assinar    │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ 4. Director counter-signs (2-wave)              │
│    - Documento passa a "completo"               │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ 5. Renovação anual: revalidate                  │
│    - "Confirme seus dados" modal                │
│    - Novo TCV com snapshot atualizado           │
└─────────────────────────────────────────────────┘
```

---

## 4. Recomendações priorizadas

### 🔴 P0 — Já implementado hoje (2026-04-10)
- [x] Schema: address, city, birth_date em `members`
- [x] Backfill: 28/52 membros do ZIP de TCVs 2025
- [x] `sign_volunteer_agreement` incorpora todos campos
- [x] `/profile` permite edição self-service
- [x] `check_pre_onboarding_auto_steps` valida perfil completo
- [x] PDF template usa dados reais

### 🟡 P1 — Próxima sprint (recomendado)
- [ ] **RPC `delete_my_personal_data`** (direito ao esquecimento LGPD)
- [ ] **Flag `share_address`** em `members` (equivalente ao share_whatsapp)
- [ ] **Política de Privacidade** em `/legal/privacy` (documento formal obrigatório LGPD)
- [ ] **Checkbox de consentimento** no pre-onboarding antes de submeter perfil
- [ ] **Revalidação anual**: modal "Confirme seus dados" ao iniciar novo ciclo
- [ ] **Máscara/validação** de telefone, data, CEP no formulário

### 🟢 P2 — Backlog (futuro)
- [ ] **Tabela `pii_access_log`**: auditar quem consultou PII de quem
- [ ] **CEP auto-complete** (integração ViaCEP para preencher endereço)
- [ ] **Wizard de pre-onboarding**: fluxo guiado de 1 pergunta por passo, gamificado
- [ ] **Export LGPD**: membro pode baixar ZIP com TODOS os seus dados (direito de portabilidade)
- [ ] **Anonimização em massa**: para membros inativos há 5+ anos, limpar PII mantendo histórico de contribuições

---

## 5. Change Request sugerido

Este trabalho sugere um **CR novo** no manual de governança — a inclusão de uma seção sobre "Coleta e Tratamento de Dados Pessoais" que formalize:
1. Quais dados são coletados e por quê
2. Base legal de cada campo
3. Direitos do titular
4. Processo de revalidação
5. Política de retenção e exclusão

**Sugestão**: criar **CR-048** referenciando esta spec como base técnica.

---

## 6. Resumo executivo para o PM

| Pergunta | Resposta |
|----------|----------|
| "Os dados vão estar no Meu Perfil?" | ✅ Sim, já implementado |
| "Pre-onboarding vai coletar?" | ✅ Sim, `complete_profile` agora valida os campos |
| "Consultoria recomenda?" | ✅ Sim, com ressalvas LGPD |
| "Precisa de CR?" | 🟡 Recomendado (CR-048 para formalizar na governança) |
| "O que falta para estar 100% LGPD?" | Política de Privacidade + consentimento explícito + direito ao esquecimento |
| "Riscos atuais?" | Baixo — implementação já segue princípios; falta formalização documental |
