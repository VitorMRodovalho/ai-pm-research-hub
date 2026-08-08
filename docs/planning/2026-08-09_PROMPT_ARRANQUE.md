# Prompt de arranque — depois do backup restaurável (próxima sessão)

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff completo: `docs/planning/2026-08-08_handoff_backup_restauravel_e_laboratorio_de_perfis.md`.
> `main` em **`2913aede`**.

---

## Regra zero

**Nada deste documento pode ser recitado.** Re-medir com tool call na mesma volta. Os dois padrões
que custaram caro nas duas últimas sessões:

- **verde sem significado** (o gate passou, o efeito não aconteceu)
- **número certo, significado errado** (a query estava certa, a população não era a da pergunta)

Depois de consertar qualquer coisa, verifique o **efeito**, nunca só a cor. E antes de citar um
contador, pergunte **de quem é este valor** e **em que ponto do processo essa população está**.

---

## O que existe agora e a sessão anterior não tinha

**Uma base de teste restaurável, em um comando.** É a mudança de método mais importante:

```bash
scripts/pull-backup-local.sh --restore     # ~15s, baixa o mais novo e ensaia
```

Com ela, gates que resolvem por `auth.uid()` deixam de ser "precisa de confirmação humana":

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '<auth_id do alvo>', true);
select public.a_rpc_que_voce_quer_testar();
rollback;
```

⚠️ `auth.uid()` na imagem lê `request.jwt.claim.sub` (**singular**).
⚠️ A cópia é da **data do backup**. Para testar código de hoje, aplique as migrations posteriores;
rodar cru mede o comportamento **antigo** (útil como controle, enganoso como validação).
⚠️ O dump **não traz o schema `auth`**: `auth.users` volta vazio e 100 de 131 membros ficam com
`auth_id` órfão. Isso não atrapalha a impersonação (o `auth_id` vem de `members`), mas atrapalha
qualquer coisa que faça JOIN com `auth.users`.

Detalhes e armadilhas: `docs/reference/RECUPERACAO_DE_DESASTRE.md`.

---

## Não re-litigar (fechado e em produção)

- **#618** fechada pelo #1684. Backup restaura, limpeza enxerga, alarme voltou a ter significado,
  cópia local semanal instalada e testada sob systemd.
- **#1673** e **#1683** mergeados.
- **#1679** respondida com veredito. **#1591** confirmado por impersonação.
- **#1682** aberta com reprodução e correção **já validada** em ambiente de teste.

---

## Ordem sugerida

### 1. 🔴 Os 10 membros que sumiram (uma medição, não uma decisão)
Backup de 03/08 tem 131 membros; produção tem 121, com **zero** criados desde então e **zero** ações
de remoção no `admin_audit_log`. A cópia está em `~/.local/share/nucleo-backups/`. Restaurar,
extrair os IDs e comparar diz **quais** são e o que eram. Só depois disso decidir se é incidente.

### 2. #1682 — implementar a correção que já está validada
A ponte de e-mail no `export_my_data` e no `list_my_consents`, com **uma transação por função**
(uma âncora ruim reverte o patch bom). Alcance medido: **34** pessoas. Levar junto as três decisões
de escopo listadas na issue.

### 3. #1643 — terminar o sweep
Falta a **terceira classe** ("afirmação incondicional sobre tratamento condicional") nas funções de
despacho, mais o `sign_proposer_consent`. Método e parcial na issue.

### 4. 🔴 Personas sintéticas (pedido do PM em 08/08)
Hoje a suíte de contrato bate em **produção contra candidaturas reais**: `gate_attempts` tem **542**
tentativas desde 04/08, **537 sem ator**, tocando **15 candidaturas reais**, com **159** passando o
gate. Isso é #1636, e é a mesma raiz do meu uso de identidades reais na base restaurada.

Semear personas sintéticas na base restaurada (visitante, membro, líder, avaliador, observador,
curador, GP, ghost) e apontar a suíte DB-aware para ela. Ganha três coisas: para de tocar gente
real, o teste deixa de depender de **quem** ocupa o papel, e some a PII do laboratório.

⚠️ Antes disso, uma pergunta **não medida**: as 159 passagens de gate emitiram token de agendamento
para candidatos reais? Cruzar com as tabelas de token e entrevista responde.

### 5. Resíduos escolhidos
- observador por URL direta ainda recebe a fila em `get_my_pending_evaluations`
- `route-acl.test.mjs` **reimplementa** o `canAccess` em vez de importar `getItemAccessibility`;
  agora dá para ancorar em comportamento real
- exigir evidência no consentimento de IA (`RAISE`), depois de confirmado o front no ar

---

## Decisões que estavam com o PM

Se ainda não vieram, perguntar antes de agir:

1. **Schema `auth` no backup** — incluir resolve a recuperação de identidade e leva hashes de senha
   e refresh tokens para o artefato do GitHub.
2. **PITR no Supabase** — hoje `false`; RPO é o diário, e o diário tinha dois dias faltando.
3. **Ticket no Supabase** pelos diários ausentes de 02/08 e 07/08.
4. Os quatro defeitos recortáveis do **#1679** viram issues?

---

## Regras da casa

- Merge à `main` é da sessão main; lane leva o PR até verde e para.
- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato ou membro nomeado, só contagens.
- **Postura de backup não vai para issue pública.**
- Não rodar `npm test` com CI em voo. **Monitorar por RUN**, não por `gh pr checks`.
