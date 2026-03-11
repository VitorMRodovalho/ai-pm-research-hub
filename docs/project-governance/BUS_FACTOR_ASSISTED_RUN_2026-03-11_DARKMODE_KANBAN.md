# Bus-Factor Assisted Run — Dark Mode + Kanban UX

## Meta

Validar que um operador secundário consegue executar a rotina de verificação das mudanças recentes sem depender do autor da implementação.

## Escopo validado

- Toggle de tema no drawer de perfil.
- Persistência de tema (`ui_theme`) no navegador.
- Leitura de `/teams` e `/webinars` em modo escuro.
- Fluxo de cards em `/tribe/[id]`:
  - abrir modal
  - criar card por coluna
  - editar campos principais
  - arquivar card (soft delete)

## Procedimento

1. Abrir ambiente de homologação/produção com usuário de gestão.
2. Executar checklist de `docs/QA_RELEASE_VALIDATION.md` seção 4.
3. Registrar prints e observações.
4. Confirmar que nenhum passo depende de comando local do autor.

## Resultado esperado

- Fluxo reproduzível por operador secundário.
- Sem regressões visuais críticas no tema escuro.
- Operação do kanban funcional com governança preservada.

## Pendências para drill cego (próxima sprint)

- Rodar o mesmo checklist sem briefing prévio do autor.
- Medir tempo de recuperação de contexto e pontos de dúvida.
- Converter dúvidas em runbook objetivo.
