# SPRINT_KNOWLEDGE_INGESTION

**Alvo:** Workspace, Presentations e Webinars

**Contexto:** O banco de dados já possui as tabelas `hub_resources` e `meeting_artifacts`, mas elas estão vazias.

**Missão:**

1. **Ingestão de Legado:** Execute a Edge Function `import-trello-legacy` e `import-calendar-legacy` com os dados reais dos Ciclos 1 e 2 para popular o Workspace e o Histórico de Apresentações.
2. **Upload de PDFs:** Implemente no `/admin/index.astro` (aba Knowledge) um campo de upload para arquivos PDF (referências técnicas e atas antigas), salvando-os no Supabase Storage e vinculando-os a `hub_resources`.
3. **Pipeline de Webinars:** Conecte os artefatos com a tag webinar à página de webinars. Se um artefato for marcado como webinar, ele deve aparecer automaticamente no log de webinars realizados, trazendo métricas do YouTube (via `sync-knowledge-youtube`).
