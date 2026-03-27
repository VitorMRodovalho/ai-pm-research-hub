# UX_GOVERNANCE_REFACTOR

**Alvo:** Navegação de Admin, Minha Tribo e LGPD

**Contexto:** Superadmins e Patrocinadores estão com a jornada "quebrada" por não estarem alocados em tribos.

**Missão:**

1. **Visão Global (Superadmin):** No `navigation.config.ts`, se o tier >= 4, o link "Minha Tribo" deve se transformar em "Explorar Tribos" ou abrir um seletor de tribo para visualização.
2. **Privacidade LGPD:** No espaço da tribo, implemente a máscara visual para dados sensíveis. Admins (Tier 4+) veem tudo; Líderes (Tier 3) veem apenas sua tribo; se o usuário não tiver permissão, mostre `***-***` com um tooltip explicativo ("Acesso restrito por LGPD").
3. **Analytics Nativo:** Remova os iframes legados de `/admin/analytics`. Use os dados das RPCs `exec_funnel_summary` e `exec_skills_radar` para gerar gráficos nativos usando Tailwind/CSS (barras de progresso e radares simples), eliminando a dependência de PostHog para visão executiva.
