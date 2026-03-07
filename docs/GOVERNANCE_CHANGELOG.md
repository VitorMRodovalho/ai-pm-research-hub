# Governance Changelog — Núcleo IA & GP
## Registro de Decisões Arquiteturais e de Governança

Este documento registra formalmente as mudanças de estrutura organizacional, papéis, e regras de negócio da plataforma. Cada entrada tem data, autor, justificativa e impacto técnico.

---

### GC-001 — Modelo de Papéis 3-Eixos (v3)
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP)

**Decisão:** Substituir o campo único `role` por um modelo de 3 eixos: `operational_role` (o que a pessoa FAZ no ciclo), `designations[]` (reconhecimentos que transcendem ciclos), e `is_superadmin` (acesso à plataforma).

**Justificativa:** O campo `role` não comportava pessoas com múltiplas funções (ex: Fabricio é Líder de Tribo + Embaixador + Fundador + Curador). O modelo anterior forçava a escolha de um único papel.

**Impacto técnico:** Colunas `role` e `roles` dropadas da tabela `members`. RPCs reescritas com `compute_legacy_role()` para backward-compat. 3 views e 3 RLS policies recriadas.

---

### GC-002 — Deputy PM (Nível 2.5)
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP)

**Decisão:** Criar o `operational_role = 'deputy_manager'` para formalizar o Co-Gerente de Projeto. Fabricio Costa promovido a Deputy PM no Ciclo 3, mantendo `tribe_leader` como designação.

**Justificativa:** Com a expansão para 5 capítulos e 45+ colaboradores, a gestão necessita de um braço operacional. O Deputy PM tem acesso admin completo mas é visualmente diferenciado do GP.

**Hierarquia atualizada:**
- Nível 1.0: Patrocinador (sponsor) — Presidente do capítulo
- Nível 1.5: Ponto Focal (chapter_liaison) — Representante indicado pelo presidente
- Nível 2.0: Gerente de Projeto (manager)
- Nível 2.5: Deputy PM (deputy_manager)
- Nível 3: Líder de Tribo (tribe_leader)
- Nível 4: Pesquisador / Facilitador / Multiplicador
- Nível 5: Embaixador (ambassador)
- Órgão de Apoio: Curador (curator)

---

### GC-003 — Ponto Focal dos Capítulos (chapter_liaison)
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP)

**Decisão:** Criar a designação `chapter_liaison` para representantes indicados pelos presidentes dos capítulos. Diferencia do Patrocinador (que é o próprio presidente).

**Justificativa:** Os capítulos PMI-CE, PMI-DF e PMI-MG indicaram representantes operacionais que não são presidentes. Esses pontos focais têm visibilidade no site (seção Patrocinadores) e acesso observer no admin, mas não são o nível máximo de autoridade institucional.

**Pontos Focais iniciais:**
- Roberto Macêdo — PMI-CE (indicado por Jéssica Alcântara)
- Ana Cristina Fernandes Lima — PMI-DF
- Certificação PMI-MG — PMI-MG

---

### GC-004 — Time de Comunicação
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP)

**Decisão:** Criar a designação `comms_team` para membros do time de comunicação. No Ciclo 3: Mayanna Duarte (Líder), Leticia Clemente, Andressa Martins.

**Justificativa:** O time de comunicação existe desde o Ciclo 2 mas não estava registrado na plataforma. São responsáveis por postagens em redes sociais e disseminação de conteúdo. Todo membro do time é necessariamente ativo (Nível 2-4).

---

### GC-005 — Hard Drop de Colunas Legadas
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP)

**Decisão:** Eliminar definitivamente as colunas `role` (TEXT) e `roles` (TEXT[]) da tabela `members`. Criadas funções `compute_legacy_role()` e `compute_legacy_roles()` para backward-compat nas RPCs.

**Justificativa:** A tabela `members` deve ser tratada apenas como snapshot do momento atual. O tagueamento real é gerido via `member_cycle_history`. Manter colunas duplicadas era fonte de inconsistência.

---

### GC-006 — Política de Custo Zero e Alto Valor
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP)

**Decisão:** Formalizar no README.md a arquitetura "Zero-Cost, High-Value". O projeto opera exclusivamente com Free Tiers (Cloudflare Pages, Supabase, PostHog) e prioriza construção interna sobre ferramentas pagas.

**Justificativa:** Como iniciativa voluntária ligada ao PMI, não há orçamento recorrente. A arquitetura deve ser replicável por outros capítulos sem custos.

---

*Para adicionar uma nova entrada, use o formato acima. Cada decisão deve ter Data, Autor, Decisão, Justificativa, e Impacto técnico quando aplicável.*
