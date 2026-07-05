# ADR-0120: Governed lessons intake for the portfolio brain (design deferred to private kernel)

- Status: **Proposed (placeholder).**
- Data: 2026-07-01
- Autor: Vitor Maia Rodovalho (com assistência de agente de IA)

## Contexto

A plataforma passará a oferecer uma capacidade **governada de intake de lições** para o brain do portfólio: um caminho para que o conhecimento operacional produzido no contexto do PMO possa ser capturado, revisado e reaproveitado, sempre sob os controles de autoridade, consentimento e isolamento por organização que a plataforma já possui.

## Decisão

O **detalhamento de design** desta capacidade (esquema de dados, superfície de acesso e os portões de governança associados) é mantido no **kernel privado do PMO** e será publicado em conjunto com a pesquisa associada, conforme a fronteira de divulgação definida no framework. Este ADR permanece como marcador de numeração até essa publicação.

## Consequências

- Nenhuma mudança de código ou de schema é introduzida por este ADR.
- Quando realizada, a capacidade reutiliza primitivos existentes — autoridade (`can()` / `can_by_member()`, ADR-0007 / 0011), tenancy por `organization_id` (ADR-0004) e consentimento/auditoria LGPD — sem inventar sistemas paralelos.
- O design detalhado será aberto publicamente junto da publicação da pesquisa associada.

## Referências

- Fronteira de divulgação e kernel de design: framework privado do PMO.
