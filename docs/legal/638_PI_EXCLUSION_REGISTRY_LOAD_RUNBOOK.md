# #638 — PI Exclusion Registry First Load Runbook

> **Status:** HOLD operacional. Este runbook prepara a primeira carga real do registry
> de exclusao de PI, mas **nao autoriza executar mutacoes em producao**.
>
> **Gate obrigatorio antes de qualquer carga:** doc7/termo publicado ou fallback formal,
> retorno G12/legal, e decisao PM sobre escopo de ativos.
>
> **Estado live medido em 2026-06-13:** 0 declarations / 0 assets /
> 0 confirmed_assets / 0 open_assets.

## 1. Objetivo

Executar, quando os gates forem liberados, a primeira carga real da Declaracao de
Exclusao de PI e Autoria Independente (doc7) no registry de PI exclusion criado em
#569 / ADR-0101.

A carga usa somente os RPCs/MCP tools ja existentes:

- `create_exclusion_declaration`
- `register_exclusion_asset`
- `get_exclusion_declaration`
- `export_anexo_i`
- `get_ots_pipeline_health`

## 2. Hard stop antes dos gates

**NAO EXECUTAR** `create_exclusion_declaration` ou `register_exclusion_asset`
antes de todos os itens abaixo estarem resolvidos:

1. doc7/termo publicado como instrumento aplicavel, ou fallback formal registrado.
2. Retorno G12/legal confirmando que a linguagem e o procedimento podem ser usados.
3. Decisao PM sobre quais ativos entram na primeira carga, incluindo se codigo da
   plataforma entra como obra pre-existente.
4. Declarant(s) definidos: uma declaracao por pessoa, por categoria, ou outro
   agrupamento aprovado.
5. Lista de ativos congelada com arquivo byte-exato preservado fora da plataforma.

Enquanto qualquer item estiver pendente, a operacao correta e manter o registry vazio
e registrar o bloqueio na issue.

## 3. Premissas ADR-0101

- Registry e digest-only: a obra nunca sai do Nucleo; somente SHA-256, metadados e
  prova `.ots` sao armazenados.
- O SHA-256 deve representar o arquivo final byte-exato que se deseja proteger.
- OTS `pending` nao e eficacia plena; eficacia probatoria plena exige `confirmed`.
- `export_anexo_i.all_confirmed=true` e o sinal operacional para anexar/exportar com
  eficacia plena.
- Sucesso de `pg_cron` nao prova HTTP 200 da Edge Function; investigar `net._http_response`
  quando houver backlog, falha ou `stamp_attempts >= 5`.
- Declaracoes `revoked` sao terminais; assets e provas permanecem ate a janela de
  retencao aplicavel.

## 4. Inputs por ativo

Cada item do Anexo I precisa ter:

| Campo | Obrigatorio | Regra |
|---|---:|---|
| `title` | Sim | Nome identificavel da obra. |
| `sha256` | Sim | Lowercase 64 hex chars: `^[0-9a-f]{64}$`. |
| `nature` | Recomendado | Ex.: artigo, metodologia, codigo, framework, dataset, template. |
| `author_label` | Recomendado | Autor(es), capitulo ou grupo responsavel. |
| `work_created_on` | Recomendado | Data de criacao/congelamento conhecida. |
| `source_ref` | Recomendado | Caminho/URL/identificador interno; nao anexar o arquivo. |
| `reinforcement` | Opcional | Ata notarial, ICP-Brasil, INPI ou outro reforco manual aprovado. |

## 5. Preparacao dos arquivos

1. Separar uma copia congelada de cada obra que entrara no Anexo I.
2. Bloquear edicoes no arquivo congelado; qualquer alteracao exige novo digest.
3. Calcular o SHA-256 localmente:

```bash
sha256sum caminho/para/obra.ext
```

4. Registrar digest em lowercase. Se a ferramenta retornar uppercase, converter para
   lowercase antes da carga.
5. Guardar o arquivo congelado em repositorio/Drive interno controlado; a plataforma
   nao recebe o arquivo.

## 6. Sequencia quando os gates liberarem

### 6.1 Criar a declaracao

**DRY-RUN TEMPLATE — NAO EXECUTAR ANTES DOS GATES**

```json
{
  "tool": "create_exclusion_declaration",
  "params": {
    "title": "Declaracao de Exclusao de PI - <declarant> - <escopo>"
  }
}
```

Salvar o UUID retornado como `declaration_id`.

### 6.2 Registrar assets do Anexo I

**DRY-RUN TEMPLATE — NAO EXECUTAR ANTES DOS GATES**

```json
{
  "tool": "register_exclusion_asset",
  "params": {
    "declaration_id": "<uuid>",
    "title": "<titulo da obra>",
    "sha256": "<64 lowercase hex chars>",
    "nature": "<natureza>",
    "author_label": "<autor(es)>",
    "work_created_on": "YYYY-MM-DD",
    "source_ref": "<referencia interna, nao arquivo>",
    "reinforcement": "<opcional>"
  }
}
```

Repetir uma vez por ativo. Se houver erro de digest duplicado ou formato invalido,
interromper a carga e reconciliar a planilha antes de continuar.

### 6.3 Aguardar pipeline OTS

1. Assets entram como `unstamped`.
2. Cron `ots-stamp-daily` roda 02:10 UTC e deve mover para `pending`.
3. Cron `ots-upgrade-daily` roda 02:40 UTC e deve mover para `confirmed` quando
   houver ancora Bitcoin disponivel.
4. Checar `get_ots_pipeline_health` ate todos os assets da declaracao ficarem
   `confirmed`.

### 6.4 Exportar Anexo I

Exportar somente depois de `all_confirmed=true`:

```json
{
  "tool": "export_anexo_i",
  "params": {
    "declaration_id": "<uuid>"
  }
}
```

Se `all_confirmed=false`, registrar pendencia operacional; nao comunicar como eficacia
plena.

## 7. Controles de qualidade

- Um operador calcula o hash; outro revisa arquivo, digest e metadados.
- Nenhum arquivo da obra deve ser enviado ao registry ou a calendarios OTS.
- A planilha de carga deve conter exatamente os mesmos `title`/`sha256`/`source_ref`
  que serao enviados.
- Cada digest deve ser reproducivel a partir do arquivo congelado.
- `pending != confirmed`; comunicacao externa deve refletir o estado real.
- Assets com `stamp_attempts >= 5` ficam fora do claim normal e exigem intervencao.
- Export administrativo com `view_pii` deve ser tratado como fiscalizacao e auditado.

## 8. Revogacao e rollback operacional

Nao existe "delete operacional" para esconder erro depois da carga. Se uma declaracao
for invalidada, usar `revoke_exclusion_declaration`; revogacao e terminal e preserva
assets/provas pela retencao configurada.

Para erro antes de publicar qualquer Anexo I:

1. Parar novas insercoes.
2. Identificar se a declaracao ja tem assets.
3. Revogar se a declaracao nao deve mais produzir efeito.
4. Criar nova declaracao corrigida somente apos aprovacao PM/legal.

## 9. Decisoes PM abertas

- Codigo da plataforma entra como obra pre-existente no primeiro lote?
- A carga inicial sera por declarant individual, por categoria de obra, ou por pacote
  institucional?
- Quais ativos precisam de reforco manual alem de OpenTimestamps?
- Quem e o declarant autorizado para ativos coletivos ou produzidos por tribos?
- Qual `governance_document_id`/doc7 sera vinculado quando a rotina estiver pronta?
- A primeira carga deve esperar todos os assets estarem confirmados antes de qualquer
  comunicacao interna?

## 10. Evidencia de estado inicial

Consulta live executada em 2026-06-13:

```sql
select
  (select count(*) from public.pi_exclusion_declarations) as declarations,
  (select count(*) from public.pi_exclusion_assets) as assets,
  (select count(*) filter (where ots_status = 'confirmed') from public.pi_exclusion_assets) as confirmed_assets,
  (select count(*) filter (where ots_status in ('unstamped','pending','error')) from public.pi_exclusion_assets) as open_assets;
```

Resultado observado:

| declarations | assets | confirmed_assets | open_assets |
|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 |

## 11. Referencias internas

- #638 — primeira carga real do registry de exclusao de PI.
- #569 — pipeline OpenTimestamps e registry PI exclusion.
- #625 — gates de doc7/termo e rotina de onboarding.
- `docs/adr/ADR-0101-pi-exclusion-asset-registry-opentimestamps.md`
- `supabase/migrations/20260805000135_p569_pi_exclusion_asset_registry.sql`
- `supabase/functions/_shared/ots.ts`
- `supabase/functions/ots-stamp/index.ts`
- `supabase/functions/ots-upgrade/index.ts`
