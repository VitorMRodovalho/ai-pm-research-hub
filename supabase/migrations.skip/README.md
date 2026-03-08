# Migrations não aplicadas

`20260308150000_knowledge_assets.sql` e `20260308160000_knowledge_assets_manager_select.sql` ficam aqui porque a tabela `knowledge_assets` já existe em produção com schema diferente (sync/embeddings: external_id, source, source_url, tags, etc.). A tabela `hub_resources` (20260308170000) é a usada para CRUD admin de recursos curados.
