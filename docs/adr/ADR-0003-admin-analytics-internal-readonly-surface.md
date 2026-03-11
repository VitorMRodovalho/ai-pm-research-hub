# ADR-0003: Admin Analytics as Internal Read-Only Surface

- Status: Accepted
- Data: 2026-03-12

## Contexto

Havia necessidade de abrir leitura executiva de analytics para audiência partner-facing interna (`sponsor`, `chapter_liaison`, `curator`) sem ampliar poderes administrativos de escrita ou acesso LGPD sensível.

## Decisão

1. `/admin/analytics` permite leitura para audiência interna autorizada.
2. Essa abertura não altera `admin_manage_actions` nem ACL de rotas sensíveis (`/admin/selection`).
3. O painel deve operar por contratos SQL explícitos (RPCs V2), evitando agregação pesada no frontend.

## Consequências

- Executivos internos ganham visibilidade sem elevar privilégio global.
- Segurança e governança ficam mais auditáveis por rota/contrato.
- Evolução de métricas ocorre por contratos de backend, com menor risco de drift no cliente.
