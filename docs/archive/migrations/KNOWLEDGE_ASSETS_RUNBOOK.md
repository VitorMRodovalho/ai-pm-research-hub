# S-KNW1: knowledge_assets — Runbook

## Objetivo

Tabela `knowledge_assets` para o Repositório Central de Recursos (Wave 5 Knowledge Hub).

## Aplicar

```bash
supabase db push
```

Ou executar manualmente o conteúdo de `supabase/migrations/20260308150000_knowledge_assets.sql` no SQL Editor.

## Pré-requisito

A função `public.can_manage_knowledge()` deve existir no schema. Se não existir, as policies de insert/update falharão.

## Auditoria

```bash
# Ou no SQL Editor:
```

```sql
-- docs/migrations/knowledge-assets-audit.sql
```

## Rollback

Ver `docs/migrations/knowledge-assets-rollback.sql`. **Atenção**: perde dados.

## Próximos passos (S-KNW2+)

- Criar rota `/workspace` ou integração em admin
- CRUD UI para knowledge_assets
- Relacionar artifacts com knowledge_assets (S-KNW3)
