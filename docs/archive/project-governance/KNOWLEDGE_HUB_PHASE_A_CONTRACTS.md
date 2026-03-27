# KNOWLEDGE_HUB_PHASE_A_CONTRACTS.md

Pacote de contratos operacionais para a Fase A do Knowledge Hub.

## Objetivo da fase

Garantir base consistente de curadoria/publicação antes de expansão funcional (fases B/C).

## Contratos mínimos (fase A)

1. **Entrada de itens**
   - Fontes: `artifacts`, `hub_resources`, `events`, `knowledge_assets`.
   - Estado inicial esperado para revisão: `review`/`pending` conforme tabela.

2. **Curadoria**
   - RPC canônica: `curate_item`.
   - Ações permitidas: `approve`, `reject`.
   - Campos de targeting aceitos:
     - `p_tribe_id` (opcional)
     - `p_audience_level` (opcional; aplicável quando suportado).

3. **Exposição no hub**
   - Item aprovado deve aparecer em surface pública/admin correspondente.
   - Item rejeitado não deve permanecer em coluna de aprovados/publicados.

4. **Observabilidade**
   - Erros de contrato devem gerar mensagem amigável de UI e log de console com contexto.

## Checklist de aceite da fase A

- [ ] Curadoria aprova/rejeita sem erro 4xx por payload inválido.
- [ ] Busca/filtro operacional em curadoria reduz volume manual.
- [ ] Targeting de tribo/audiência preservado no payload RPC.
- [ ] Testes de regressão (`ui-stabilization` + `browser-guards`) verdes.
- [ ] `npm run build` e `npm run smoke:routes` verdes.

## Dependências para fase B

- métricas de throughput de curadoria por ciclo;
- auditoria de SLA de publicação;
- trilha de evidências de qualidade por item.
