# Brief para Ângelina (advogada voluntária PMI-GO) — Revisão jurídica Round 6

**Audience:** Ângelina (advogada voluntária PMI-GO há ~2 anos, indicada pelo Ivan Lourenço)
**Tema:** Revisão jurídica das governance docs do Núcleo IA & GP — Round 6 (HYBRID expanded)
**Sender:** Vitor Maia Rodovalho (GP)
**Status atual:** Editorial hotfix v4 já aplicado 2026-05-04. Material fixes aguardam sua revisão.

---

## Sugestão de mensagem inicial (para Vitor enviar via canal aberto pelo Ivan)

> Olá Ângelina, tudo bem?
>
> Falou com você o Ivan sobre o Núcleo IA & GP, certo? Sou Vitor Maia, GP do programa. O Ivan comentou que você é advogada voluntária do PMI-GO há uns dois anos e topa nos ajudar com uma revisão jurídica dos nossos documentos de governança.
>
> Primeiro: muito obrigado por topar! Sua ajuda nesse momento faz muita diferença. Eu sei que o timing pode ser apertado pra você, então vamos no seu ritmo — o que importa é qualidade da revisão, não velocidade.
>
> O Núcleo IA & GP é uma iniciativa voluntária inter-capítulos do PMI Brasil, sediada no PMI-GO. Hoje somos 5 capítulos parceiros (GO/CE/DF/MG/RS), 48 voluntários ativos, 7 tribos de pesquisa, plataforma própria. A documentação de governança que precisamos revisar inclui 5 documentos principais:
>
> 1. **Política de Governança de Propriedade Intelectual** (era "Política de Publicação e PI")
> 2. **Termo de Adesão ao Serviço Voluntário** (era "Termo de Compromisso")
> 3. **Adendo Retificativo ao Termo de Adesão ao Serviço Voluntário**
> 4. **Adendo de Propriedade Intelectual aos Acordos de Cooperação**
> 5. **Acordo de Cooperação Bilateral — Template Unificado** (entre PMI-GO e PMI-CE/DF/MG/RS)
>
> Recebi recentemente uma análise crítica do Ricardo Santos (pesquisador do Núcleo, com patentes próprias). Ele apontou 8 pontos. Já apliquei os 5 que são correção factual / nomenclatura (typo de ano de lei, terminologia americana em doc brasileiro, simplificação tributária etc) — esses não envolvem direitos ou obrigações novas, só editorial.
>
> Mas há **4 mudanças materiais** que envolvem direitos/obrigações dos voluntários e capítulos. Essas eu prefiro que você revise antes de aplicar, porque envolvem questões legais sensíveis:
>
> 1. **Aceite tácito vs aceite expresso** (CC art. 111 e 423) — refinar a cláusula do Termo + Adendo Retificativo para distinguir alterações editoriais (aceite tácito ok) de materiais (aceite expresso requerido).
>
> 2. **Transferência internacional de dados (LGPD/GDPR §13.5 da Política)** — atualizar para 3 regimes: Brasil (LGPD), UE/EEE (adequacy recíproca janeiro/2026 — decisão Comissão Europeia), Reino Unido (sem adequacy ainda, mecanismo cabível UK GDPR).
>
> 3. **Cláusula sobre a plataforma operacional do Núcleo** — atualmente está dentro do Adendo de PI aos Acordos de Cooperação (Art. 8). A plataforma é projeto pessoal meu, opensource desde dia zero no GitHub, e a Política precisa esclarecer que o uso da plataforma não altera titularidade de obras dos voluntários nem do Núcleo. Sugestão é mover detalhamento técnico para um Anexo Técnico separado (ou Termos de Uso da Plataforma) e deixar só a regra-mãe nos docs principais.
>
> 4. **Risco de uso de marca PMI®** — usamos "PMI Goiás Chapter (PMI-GO)" como sponsor + 5 capítulos parceiros, mas queria sua leitura sobre eventual risco de trademark dispute com PMI Global, e como minimizar. (Independente do Round 6 mas estrutural.)
>
> Posso te enviar:
> - Os 5 documentos atuais (v4 editorial hotfix aplicada hoje, conteúdo material inalterado da v3 que os curadores revisaram nas últimas semanas)
> - A análise crítica do Ricardo Santos (3 páginas)
> - Os drafts simplificados que ele propôs (versões mais enxutas mas que sacrificam parte da estrutura legal estendida que construímos)
> - Spec interno detalhando as 4 mudanças materiais com diff source→target
>
> Que canal você prefere para revisar? PDF anotável, Google Docs com comentários, ou outra opção?
>
> Avisa qualquer coisa e fico no aguardo.
>
> Abraço!

---

## Anexos sugeridos para enviar à Ângelina

1. **Os 5 documentos governance v4** (editorial hotfix aplicada) — pode exportar via plataforma `nucleoia.vitormr.dev/governance/[doc-slug]` ou Drive
2. **Análise crítica Ricardo Santos** — `/home/vitormrodovalho/Downloads/A/Análise crítica dos documentos enviados.docx` (3 páginas)
3. **Drafts Ricardo Santos**:
   - `Política Institucional de Publicação e PI.docx`
   - `Termo de Adesão ao Serviço Voluntário.docx`
4. **Spec interno** — `docs/specs/p90-round-6-editorial-material-fixes-matrix.md` (detalha cada fix editorial vs material com diff)
5. **Resumo das 8 críticas Ricardo** com classificação editorial vs material

## Material fixes detail para revisão

### Fix #1 — Aceite tácito (Termo §15.4 + Adendo Retificativo §3º)

**Texto atual (v4):**
> "Aceite tácito por ato concludente. A continuidade da participação ativa no Programa após o decurso dos prazos estabelecidos em [§ anterior] sem manifestação contrária constitui aceite tácito da revisão, nos termos do CC art. 111."

**Crítica Ricardo:** "Em contrato de adesão, a combinação de remissão dinâmica, mudança posterior de obrigações e aceite tácito é sensível. O CC diz que o silêncio só importa anuência quando as circunstâncias autorizarem, e cláusulas ambíguas em contrato de adesão devem ser interpretadas em favor do aderente."

**Recomendação Ricardo:** "manter atualização automática apenas para mudanças editoriais; para mudanças materiais de PI, dados, sanções e uso de obras, exigir aceite expresso."

**Pergunta para Ângelina:** Isso já está endereçado pelo nosso framework Material vs Editorial change (Cláusulas 12.2 e 12.3 da Política IP). O texto atual de aceite tácito menciona "revisão" genericamente. Você redrafta a cláusula para tornar explícito que aceite tácito aplica APENAS a editorial change, e material change requer aceite expresso?

---

### Fix #2 — LGPD/GDPR §13.5 da Política IP (atualização adequacy 2026)

**Texto atual (v4):**
> "consentimento explícito art. 49.º(1)(a), com ciência prévia dos riscos, renovável se condições materiais mudarem — para transferências ocasionais; (iii) necessidade contratual art. 49.º(1)(b), subsidiária para dados..."

**Crítica Ricardo:** "Isso ficou desatualizado em 2026. A Comissão Europeia e o Brasil adotaram decisões de adequação recíproca em janeiro de 2026. Já para o Reino Unido, a situação é diferente: a orientação atual do ICO ainda trata o Brasil como sem adequacy no regime UK GDPR."

**Recomendação Ricardo:** "separar três regimes: Brasil, UE/EEE e Reino Unido. Para UE/EEE, usar a base da adequação quando aplicável; para UK e outros países sem adequação, usar o mecanismo cabível do direito aplicável. Não usar consentimento do art. 49 como solução padrão para fluxo rotineiro."

**Pergunta para Ângelina:** Você verifica o status atual da decisão de adequacy Brasil-UE (jan/2026) e redrafta §13.5 com 3 regimes separados (BR + UE + UK + outros sem adequacy)?

---

### Fix #3 — Cláusula plataforma operacional (Adendo PI Cooperação Art 8 + cross-refs)

**Texto atual (v4):**
> "plataforma de software como projeto independente do GP. Conflito de interesse declarado — A condição do GP autor da plataforma como simultaneamente Gerente de Projeto..."

**Crítica Ricardo:** "Isso pode gerar desconfiança e confusão entre PI das obras do Núcleo e PI da plataforma. Sugere-se mover esse tema para um anexo técnico separado ou para os termos de uso da plataforma."

**Contexto adicional Vitor (não Ricardo):** A plataforma (`nucleoia.vitormr.dev`) é projeto pessoal meu, opensource desde dia zero (auto-licenciada por mim no meu GitHub). Hoje sou único contributor; futuramente, quando outros voluntários contribuírem para o desenvolvimento, podemos ter co-autoria de software. Possível futuro: closure comercial conjunta Núcleo + Vitor.

**Pergunta para Ângelina:** Você redrafta:
1. **Adendo PI Cooperação Art 8** simplificando a cláusula da plataforma para apenas cross-ref ao "Anexo Técnico — Plataforma Operacional do Núcleo IA"?
2. **Cria o "Anexo Técnico"** com (a) declaração da plataforma como ferramenta de gestão; (b) titularidade da plataforma (Vitor único contributor atual, opensource); (c) regra de co-autoria futura caso outros voluntários contribuam; (d) CoI declarado GP como Vitor; (e) regra de futura exploração comercial conjunta Núcleo + Vitor?

---

### Fix #4 — Risco de uso de marca PMI® (estrutural, independente Round 6)

**Contexto:** Núcleo usa "PMI Goiás Chapter (PMI-GO)" como sponsor + "PMI Brasil" + "PMI Latam" + "PMI Global" em diversos materiais. Mas Núcleo IA & GP não tem licença formal da marca PMI®.

**Pergunta para Ângelina:** Você revisa nosso uso atual de "PMI®" no contexto do Núcleo (5 docs governance + plataforma + materiais públicos) e nos orienta sobre:
1. Risco real de trademark dispute com PMI Global
2. Limites permissíveis de citação institucional
3. Eventual remediation plan (se necessário)
4. Texto canônico recomendado para uso

---

## Timing expectations

- **Você não tem prazo apertado** — Ivan disse seu timing não é super ágil, e está tudo bem
- **Nossa pressão de timing:** queremos circular para os 15 capítulos PMI Brasil até **fim de junho 2026** (depois que os curadores assinarem v4)
- **Workflow Round 6:** após sua revisão, aplicaremos as 4 mudanças materiais como v5 + curadores revisitam + circulação aos pontos focais dos 15 capítulos
- **Caso seu prazo seja > 2 meses:** nos diga com franqueza para podermos avaliar se contratamos backup advogado especialista PI external

## Próximos passos

1. ☐ Vitor envia esta mensagem inicial à Ângelina (canal indicado pelo Ivan)
2. ☐ Vitor passa contato Ângelina ↔ Ivan cross-introduction
3. ☐ Ângelina confirma escopo + timeline
4. ☐ Vitor envia anexos (5 docs v4 + análise Ricardo + drafts Ricardo + spec)
5. ☐ Ângelina revisa + propõe redraft das 4 mudanças materiais
6. ☐ Vitor aplica via apply_migration v5 (Phase 2: Material fixes)
7. ☐ Curadores revisitam v5 (sign-off final)
8. ☐ Circulação para 15 capítulos via pontos focais
