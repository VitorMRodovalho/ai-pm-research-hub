# Legal-Counsel Parecer — ADR-0078 `external_reviewer_agreement_v1` NDA-lite

**Council role:** legal-counsel (Brazilian, IP + LGPD specialist, 15+ years)
**Sessão:** p148 (2026-05-10), Round 2.5 input
**ADR alvo:** [`docs/adr/ADR-0078-external-reviewer-onboarding-pattern.md`](../../adr/ADR-0078-external-reviewer-onboarding-pattern.md)
**Decisão D5 alvo:** Cláusulas 1-6 do template `external_reviewer_agreement_v1`
**Trigger:** PM aprovou Round 2 (5/5 decisions); Round 3 sign-off requer legal-counsel + Ivan DPO. Este parecer é o input legal-counsel.

---

## Veredito

**APROVADO COM AJUSTES** — 2 issues críticos, 4 secundários, 3 gaps LGPD obrigatórios pré-DPO. Nenhum bloqueia shipping definitivo, mas IC-1 e IC-2 exigem redação antes de Ângelina receber o template para curadoria.

---

## Issues Críticos

### IC-1 — Cláusula 5: base legal `consent` sem nomear Art. 8º §5 (revogação a qualquer tempo)

**Problema:** Schema implementa self-revoke (D6 PM-confirmed Round 2), mas template não declara essa faculdade contratualmente. Art. 8º §5 LGPD garante revogação a qualquer tempo; ratificação informada exige nomear isso.

**Impacto:** ANPD audit pode entender que revisor "concordou irrevogavelmente" pelos 90d. Contradição com Art. 8º §5. Risco tangencial trabalhista se reviewer sustentar prazo mínimo.

**Redação sugerida (inserir ao final da Cláusula 5):**

> "O Revisor pode revogar este consentimento a qualquer momento, sem ônus, mediante uso da função 'Encerrar minha revisão' disponível na plataforma ou por comunicação escrita ao endereço institucional do Controlador. A revogação encerra imediatamente o acesso à plataforma (Art. 8º §5º LGPD). Dados já registrados permanecem sujeitos ao prazo de retenção de 2 (dois) anos para fins de auditoria, após os quais são anonimizados automaticamente."

---

### IC-2 — Cláusula 3: licença de comentários sem escopo de uso e sem ressalva acadêmica

**Problema:** "Licença não-exclusiva à Núcleo para uso interno dos comentários no ciclo de revisão" não especifica:
- (a) se sobrevive ao término do engajamento;
- (b) se a Núcleo pode citar comentários nominalmente em documentos publicados;
- (c) implicações para revisores jurídicos (OAB pode entender comentários como consultoria pública não-remunerada se usados em publicações);
- (d) Cenário C (acadêmico): ausência de ressalva sobre co-autoria conflita com normas COPE / ABNT NBR 6022.

**Impacto:** Lei 9.610/98 Art. 49 exige interpretação restritiva — ambiguidade prejudica. Para Ângelina especificamente, risco deontológico OAB é real (não eminente, mas tangível).

**Redação sugerida (substituir segundo parágrafo da Cláusula 3):**

> "Os comentários submetidos pelo Revisor integram o histórico do documento na plataforma (provenance de auditoria), sem cessão de direitos autorais do Revisor sobre o conteúdo de seus comentários. O Revisor concede à Núcleo IA & GP licença não-exclusiva, gratuita, de uso interno e irrevogável exclusivamente para fins de revisão do documento objeto deste Termo, pelo prazo do Engajamento acrescido do período de retenção (2 anos). A Núcleo não citará comentários nominalmente em publicações externas sem autorização escrita prévia do Revisor. Para revisores em vínculo acadêmico (Cenário C), reserva-se o direito de negociar cláusula adicional de co-autoria ou acknowledgment antes da ratificação deste Termo."

---

## Issues Secundários (não-bloqueantes; Ângelina curation pode absorver ou diferir v1.2)

### IS-1 — Cláusula 2: definir "terceiros"

Texto proíbe divulgação "a terceiros sem autorização escrita", sem dizer se orientadores, sócios de escritório, ou co-autores acadêmicos contam. **Sugestão:** adicionar "exceto colaboradores diretos sob mesmo dever profissional de sigilo".

### IS-2 — Cláusula 4: revogação administrativa sem prazo de transição

Revogação imediata por D6 admin path é OK operacionalmente, mas template não menciona prazo para revisor finalizar comentários em andamento. **Sugestão:** "salvo por justa causa, a revogação administrativa notificará o Revisor com antecedência mínima de 48 horas".

### IS-3 — Foro / lei aplicável

Foro de eleição pode ser omitido em template volunteer-grade (razoável). Mas se houver revisor de outro Estado, ausência gera incerteza. **Alternativa mínima:** "controvérsias seguem a legislação brasileira" sem eleger foro específico.

### IS-4 — Reconhecimento público

Cláusula 6 exclui credly badge + voluntariado VEP. Mas não diz se Núcleo pode citar nome em agradecimentos (acknowledgments). Para Ângelina, isso pode ser desejável (portfolio). **Sugestão:** "A Núcleo poderá mencionar o Revisor em agradecimentos públicos de documentos revisados, salvo manifestação em contrário do Revisor no ato da ratificação."

---

## LGPD Audit-Readiness — 3 gaps obrigatórios pré-Ivan DPO sign-off

A Cláusula 5 cobre base legal (Art. 7º I), retenção (730d) e anonimização. Faltam:

1. **DPO contact / canal institucional concreto** (Art. 41 LGPD) — hoje "canal institucional do controlador" genérico; precisa email institucional ou URL portal LGPD nomeada.
2. **Identidade do Controlador nomeada** — "Núcleo" usado informalmente; precisa "Núcleo IA & GP / PMI-GO" + CNPJ ou identificador institucional.
3. **Direitos do titular Art. 18 completos** — template menciona só "export ou deleção"; faltam confirmação da existência de tratamento, acesso, correção, portabilidade, informação sobre uso compartilhado, oposição. **Linha sugerida:** "O Revisor tem os direitos previstos no Art. 18 da LGPD, exercíveis pelo canal institucional acima indicado."

(Não-obrigatório mas defensável: prazo de resposta a solicitações — Resolução CD/ANPD 2/2022 orienta 15 dias. Ivan DPO decide se adiciona.)

---

## Cross-cut ADR-0076 (PMI 3-d Volunteer Model + Phase B Base Legal)

**Alinhamento OK.** A distinção `consent` (external_reviewer) vs `legitimate_interest` (external_signer) está alinhada com Princípio 2 ADR-0076 — conteúdo pre-publication exige consentimento explícito (única base defensável perante ANPD).

**Ponto de atenção tangencial — Princípio 7 (Trentim firewall):** comentários jurídicos da Ângelina sobre Política IP poderiam, em tese, ser citados como "assessoria jurídica Núcleo" em disputas com parceiros. **Cláusula 3 revisada (IC-2) mitiga** — uso interno restrito + autorização para citação pública. Não-bloqueante; vale Ângelina estar ciente na curadoria.

**Retenção 730d** alinhada com Princípio 6 (12m piso para candidatos rejeitados; 2y para reviewer faz sentido pelo papel distinto + interesse de auditoria).

---

## Recomendação sequencial

1. **Incorporar IC-1 + IC-2 + 3 LGPD gaps no template ANTES** de enviar a Ângelina (estes 5 itens afetam diretamente os direitos dela como primeira signatária; enviar abertos seria gap óbvio que ela apontaria de volta).
2. Enviar template **v1.1** a Ângelina com contexto explícito sobre conflict of interest natural (transparência = proteção mútua). Pedir confirmação especial Cláusula 3 à luz de obrigações OAB.
3. Consolidar **v1.2** com retorno dela. Encaminhar a Ivan DPO focado exclusivamente nos 3 gaps LGPD (DPO contact, Controlador nomeado, Art. 18 completo). Ivan não precisa revisar cláusulas não-LGPD.
4. **Wave 1 (D5) só após etapas 2 + 3.**
5. Issues secundários IS-1 a IS-4 absorvidos por Ângelina ou diferidos a v1.2 sem bloquear.

---

## Limitações deste parecer

Parecer para revisão inicial; confirmação com advogado licenciado (Ângelina Ourem ou substituto indicado pelo PM) recomendada antes de ratificação e shipping. Ivan DPO assina separadamente o fluxo LGPD como etapa independente.

---

## Decisão PM (Round 2.5 inputs)

PM aprovou caminho A (2026-05-10 p148): incorporar IC-1 + IC-2 + 3 LGPD gaps no ADR-0078 (Round 2.5 commit), salvar parecer aqui para traceability, IS-1 a IS-4 ficam como notas inline pendentes de Ângelina curation. Round 3 = sign-off final pós-Ângelina + Ivan DPO.
