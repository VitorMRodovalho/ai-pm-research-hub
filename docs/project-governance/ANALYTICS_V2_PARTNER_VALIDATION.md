# Analytics V2 Partner Validation (W44.3)

## Objetivo

Validar leitura real do `/admin/analytics` para audiencia partner-facing interna (`sponsor`, `chapter_liaison`, `curator`) sem ampliar permissao de escrita.

## Escopo de validacao

### 1) Acesso e ACL

- Perfil parceiro autorizado acessa `/admin/analytics` com sucesso.
- Perfil parceiro autorizado **nao** ganha acesso de escrita em telas administrativas operacionais.
- Perfil sem autorizacao continua em `#analytics-denied`.

### 2) Contratos SQL (dados reais)

Validar retorno nao vazio (ou vazio justificado) dos RPCs:

- `exec_funnel_v2`
- `exec_impact_hours_v2`
- `exec_certification_delta`
- `exec_chapter_roi`
- `exec_role_transitions`
- `exec_analytics_v2_quality`

### 3) Qualidade e consistencia

- KPI de funil, horas de impacto, delta de certificacao, ROI por capitulo e transicoes exibidos sem erro de render.
- Banner de qualidade (`analytics_v2_quality`) sem `issues` criticos.
- Export/copy summary disponivel e coerente com os cards.

## Procedimento sugerido (operador)

1. Login com conta de `sponsor` (ou `chapter_liaison` / `curator`) ativa.
2. Acessar `/admin/analytics` e registrar evidencias:
   - screenshot do carregamento completo
   - screenshot dos filtros globais
   - screenshot do card de quality banner
3. Alterar filtros (`cycle_code`, `tribe_id`, `chapter_code`) e verificar recarga dos blocos.
4. Executar copy summary e anexar texto no release evidence.
5. Repetir com conta sem permissao e confirmar deny.

## Evidencia minima para fechamento

- data/hora da validacao
- operador e perfil usado (sem PII sensivel)
- resultado por RPC (`ok`, `vazio esperado`, `erro`)
- print de ACL deny para perfil nao autorizado
- referencia de commit e release log

## Resultado atual desta tranche

- Governanca/fluxo preparados.
- Fechamento funcional de W44.3 depende de execucao com conta partner real no ambiente operacional.
