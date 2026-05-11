# Termo de Revisão Externa — Núcleo IA & Project Management
## `external_reviewer_agreement_v1.1`

**Versão:** v1.1 (pós Round 2.5 — legal-counsel parecer incorporado)
**Status:** Draft pronto para curadoria do(a) primeiro(a) revisor(a) jurídico(a)
**Trilha de governança:** ADR-0078 D5 · `docs/council/decisions/2026-05-10-p148-legal-counsel-adr0078-external-reviewer-nda.md`
**Próximas etapas:** (1) curadoria revisor jurídico → v1.2; (2) Ivan DPO sign-off LGPD; (3) ratificação para uso em produção.

---

## Notas de contexto para o(a) revisor(a) curador(a)

Este termo será apresentado a revisores externos voluntários antes do primeiro acesso à plataforma para comentário em documentos de governança pre-publication. Você é o(a) primeiro(a) curador(a) — em alguns aspectos, o termo regula seu próprio acesso futuro. Essa transparência é proposital ("primeiro usuário valida o instrumento que o regula"), padrão comum em legal drafting comunitário, e a intenção é proteção mútua.

**Cenários cobertos pelo termo (definidos em ADR-0078 D5):**
- **Cenário A** — Curador externo voluntário PMI (revisor jurídico institucional voluntário)
- **Cenário B** — Peer-reviewer técnico inter-chapter
- **Cenário C** — Academic peer-reviewer

**Cenários NÃO cobertos** (exigem instrumento jurídico próprio: MSA, MOU, convênio, etc.):
- Consultor remunerado · Sponsor/partner · Reviewer de instituição pública · Presidente capítulo PMI federado (este último usa pattern existente `external_signer`).

---

## Termo (texto candidato a v1.1)

### Preâmbulo

A **Núcleo IA & Project Management** (núcleo de pesquisa institucional vinculado ao **PMI Goiás Chapter — PMI-GO**), doravante denominada **Controlador**, e o(a) signatário(a) deste Termo, doravante denominado(a) **Revisor(a)**, celebram o presente Termo de Revisão Externa, regido pelas cláusulas a seguir, sob as bases legais aplicáveis (Lei 13.709/2018 — LGPD; Lei 9.610/1998 — Direitos Autorais; legislação brasileira aplicável).

---

### Cláusula 1 — Objeto

O presente Termo concede ao Revisor o direito **não-exclusivo** de visualização e comentário em documentos específicos de governança institucional do Controlador, atribuídos pela coordenação do Núcleo IA & Project Management, exclusivamente pelo prazo do Engajamento previsto na Cláusula 4.

---

### Cláusula 2 — Confidencialidade

O Revisor compromete-se a não divulgar a terceiros o conteúdo dos documentos pre-publication acessados sob este Termo sem autorização escrita prévia do Controlador, durante e após a vigência do Engajamento.

> **🟡 Nota inline para curadoria (IS-1 do parecer legal-counsel):** avaliar se incluir ressalva: *"...exceto colaboradores diretos sob mesmo dever profissional de sigilo (orientadores, sócios de escritório de advocacia, ou co-autores legítimos sob acordo de sigilo equivalente)."* — sua perspectiva é bem-vinda.

---

### Cláusula 3 — Propriedade Intelectual e Licença de Comentários

Os comentários submetidos pelo Revisor integram o histórico do documento na plataforma (provenance de auditoria), **sem cessão de direitos autorais** do Revisor sobre o conteúdo de seus comentários.

O Revisor concede à Núcleo IA & Project Management licença **não-exclusiva, gratuita, de uso interno e irrevogável exclusivamente para fins de revisão do documento objeto deste Termo**, pelo prazo do Engajamento acrescido do período de retenção de 2 (dois) anos.

A Núcleo **não citará comentários nominalmente em publicações externas sem autorização escrita prévia** do Revisor.

Para revisores em vínculo acadêmico (Cenário C), reserva-se o direito de negociar cláusula adicional de co-autoria ou acknowledgment antes da ratificação deste Termo.

---

### Cláusula 4 — Vigência

O Engajamento tem prazo padrão de **90 (noventa) dias** corridos a partir da ratificação deste Termo, alinhado com o campo `engagement.end_date` registrado na plataforma. O prazo é renovável por iguais períodos, mediante novo convite e nova ratificação, sem limite de renovações dentro de 365 dias.

A revogação do Engajamento pode ser feita a qualquer momento, por qualquer das partes, mediante comunicação escrita.

> **🟡 Nota inline para curadoria (IS-2 do parecer legal-counsel):** avaliar se incluir: *"Salvo por justa causa, a revogação administrativa pelo Controlador notificará o Revisor com antecedência mínima de 48 (quarenta e oito) horas, para permitir finalização de comentários em andamento."* — protege o(a) revisor(a) em fim de revisão.

---

### Cláusula 5 — Tratamento de Dados Pessoais (LGPD)

#### 5.1 Base legal e finalidade

O tratamento de dados pessoais do Revisor (nome, e-mail, conteúdo de comentários, metadados de acesso à plataforma) tem como base legal o **consentimento expresso** (Art. 7º, I, Lei 13.709/2018 — LGPD), prestado pelo Revisor mediante a ratificação deste Termo. A finalidade é exclusivamente operar e auditar o ciclo de revisão de documentos atribuídos.

#### 5.2 Identidade do Controlador e DPO

**Controlador:** Núcleo IA & Project Management, núcleo institucional vinculado ao **PMI Goiás Chapter — PMI-GO** (identificador institucional formal a ser preenchido por Ivan DPO antes da ratificação).

**Encarregado de Proteção de Dados (DPO):** Ivan (sponsor PMI-GO), contato via canal institucional indicado na plataforma e portal LGPD do PMI-GO (URL canônica a ser preenchida por Ivan DPO antes da ratificação).

#### 5.3 Retenção e anonimização

Os dados são retidos por **2 (dois) anos após o término do Engajamento** (`retention_days_after_end=730`), prazo necessário para fins de auditoria de governança documental. Após esse período, os dados são **anonimizados automaticamente** pelo Controlador (`anonymization_policy='anonymize'`).

#### 5.4 Direitos do titular (Art. 18 LGPD)

O Revisor tem os seguintes direitos, exercíveis a qualquer tempo pelo canal institucional indicado em 5.2:

(i) confirmação da existência de tratamento;
(ii) acesso aos dados;
(iii) correção de dados incompletos, inexatos ou desatualizados;
(iv) anonimização, bloqueio ou eliminação de dados desnecessários, excessivos ou tratados em desconformidade;
(v) portabilidade dos dados a outro fornecedor de serviço ou produto;
(vi) eliminação dos dados pessoais tratados com base no consentimento;
(vii) informação sobre as entidades públicas e privadas com as quais o Controlador realizou uso compartilhado de dados;
(viii) informação sobre a possibilidade de não fornecer consentimento e sobre as consequências da negativa;
(ix) revogação do consentimento.

#### 5.5 Revogação a qualquer tempo (Art. 8º, §5º LGPD)

O Revisor pode **revogar este consentimento a qualquer momento, sem ônus**, mediante:
- (a) uso da função **"Encerrar minha revisão"** disponível na plataforma; ou
- (b) comunicação escrita ao endereço institucional do Controlador.

A revogação encerra **imediatamente** o acesso do Revisor à plataforma. Dados já registrados (comentários, metadados de acesso) permanecem sujeitos ao prazo de retenção de 2 (dois) anos para fins de auditoria, após os quais são anonimizados automaticamente.

> **🟡 Nota inline para Ivan DPO (gap LGPD pendente):** avaliar inclusão de prazo de resposta a solicitações de titular — Resolução CD/ANPD nº 2/2022 orienta 15 dias. Não-obrigatório por lei, mas defensável em audit. Sugestão: *"O Controlador responderá a solicitações deste Termo no prazo de 15 (quinze) dias, conforme orientação da Autoridade Nacional de Proteção de Dados."*

---

### Cláusula 6 — Não-vínculo e escopo restrito

Este Termo **não cria** relação trabalhista, voluntariado formal sob VEP (Volunteer Engagement Profile do PMI), nem direito a credly badge ou outro reconhecimento de gamificação institucional.

Este Termo destina-se **exclusivamente** a revisores externos voluntários ou peer-reviewers em vínculo recíproco (Cenários A, B, C definidos em ADR-0078 D5). Engajamentos comerciais (consultoria remunerada), parcerias institucionais (sponsors), ou instrumentos com órgãos públicos requerem instrumento jurídico próprio (MSA, MOU, convênio bilateral, etc.) — não esse template.

> **🟡 Nota inline para curadoria (IS-4 do parecer legal-counsel):** avaliar inclusão de: *"A Núcleo poderá mencionar o Revisor em agradecimentos públicos (acknowledgments) de documentos revisados, salvo manifestação em contrário do Revisor no ato da ratificação ou em momento posterior."* — positivo para revisores que valorizam acknowledgment de portfolio (Cenários A, C).

---

### Cláusula 7 — Foro e legislação aplicável (opcional)

> **🟡 Nota inline para curadoria (IS-3 do parecer legal-counsel):** avaliar se incluir cláusula simples como: *"As eventuais controvérsias decorrentes deste Termo seguem a legislação brasileira aplicável."* — foro de eleição pode ser omitido em template volunteer-grade. Se incluir, é boa prática institucional para clareza geográfica entre revisores de Estados distintos.

---

### Ratificação

O Revisor declara ter lido, compreendido e aceito integralmente os termos acima. A ratificação se dá mediante:

- (a) clique no botão **"Aceitar e iniciar revisão"** na plataforma, gerando registro em `external_reviewer_agreements` (campos `signed_at`, `ip_address`, `user_agent`); ou
- (b) assinatura física/digital deste documento em PDF, com escaneamento enviado ao Controlador.

---

## Sumário das notas inline (4 itens IS- + 1 LGPD pendente)

| Item | Onde | Curador | Decisão pedida |
|---|---|---|---|
| IS-1 | Cláusula 2 | Revisor jurídico | Incluir ressalva "colaboradores diretos sob mesmo dever de sigilo"? |
| IS-2 | Cláusula 4 | Revisor jurídico | Incluir 48h notice em revogação administrativa? |
| IS-3 | Cláusula 7 | Revisor jurídico | Incluir cláusula de lei brasileira aplicável (sem foro)? |
| IS-4 | Cláusula 6 | Revisor jurídico | Incluir opt-out de acknowledgment público? |
| LGPD-prazo | Cláusula 5.4-5.5 | Ivan DPO | Incluir prazo de resposta de 15 dias (Res. ANPD 2/2022)? |
| LGPD-id | Cláusula 5.2 | Ivan DPO | Preencher CNPJ ou identificador institucional preciso PMI-GO |
| LGPD-url | Cláusula 5.2 | Ivan DPO | Preencher URL canônica do canal institucional/portal LGPD |

---

## Próximas etapas operacionais

1. ✅ Round 2.5 fechado — template v1.1 incorpora IC-1 + IC-2 + 3 LGPD gaps do parecer legal-counsel (`docs/council/decisions/2026-05-10-p148-legal-counsel-adr0078-external-reviewer-nda.md`).
2. ⏳ **Vitor envia v1.1 ao(à) revisor(a) curador(a)** com contexto explícito sobre conflict of interest natural ("transparência = proteção mútua") + pedido especial de confirmação Cláusula 3 à luz de obrigações deontológicas OAB.
3. ⏳ Curador(a) responde com confirmações + ajustes nos 4 IS- → consolidar **v1.2**.
4. ⏳ **Vitor encaminha v1.2 a Ivan DPO** focado nos 3 LGPD itens (CNPJ, URL canônica, prazo de resposta).
5. ⏳ Ivan responde com sign-off LGPD → consolidar **v1.3 ratificável**.
6. ⏳ Round 3 do ADR-0078: status bumped PROPOSED → ACCEPTED.
7. ⏳ Wave 1 implementation libera (D1 RPC + D5 minimal template como `governance_documents` row).
