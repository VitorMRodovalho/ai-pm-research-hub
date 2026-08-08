# Recuperação de desastre: onde estão os backups e o que eles realmente restauram

> Tudo abaixo foi **medido em 08/08/2026** restaurando o backup real de 03/08. Nada aqui é
> suposição de projeto. Ao reler, re-meça: `scripts/pull-backup-local.sh --restore` refaz o ensaio
> inteiro em poucos minutos.

## As três cópias

| onde | o que é | cadência | retenção |
|---|---|---|---|
| Supabase (plataforma) | backup **físico** WAL-G do projeto | diário, ~04:20 UTC | janela da plataforma |
| GitHub Actions artifact | dump **lógico** `pg_dump` gzipado | semanal, domingo 23:00 UTC | 60 dias, 8 cópias |
| Cloudflare R2 (`nucleoia-db-backups`) | o **mesmo** dump lógico, offsite | semanal, junto com o de cima | bucket |
| máquina local (opcional) | o mesmo dump, via `scripts/pull-backup-local.sh` | semanal, timer `systemd --user` | 8 cópias, `chmod 600` |

A separação existe por desenho (#618): código e backup não podem morar na mesma cesta de
fornecedor. A cópia local é a terceira perna e é a única que sobrevive à perda de acesso às duas
contas de nuvem.

⚠️ **`pitr_enabled` era `false` em 08/08.** Sem point-in-time, o RPO é a granularidade do diário,
e uma falha do diário empurra isso para 48 h ou mais.

Preço do add-on, medido em 08/08 pela API de billing (`/v1/projects/<ref>/billing/addons`), para
comparar com o compute atual do projeto, que é **Micro a ~US$ 10/mês**:

| PITR | preço |
|---|---|
| 7 dias | **US$ 100/mês** |
| 14 dias | US$ 200/mês |
| 28 dias | US$ 400/mês |

O que o PITR compra que o diário não compra: RPO abaixo de um dia, restauração **para um instante**
(por exemplo, o segundo anterior a uma migration ruim) e um alvo de restauração **não-destrutivo** —
sem ele, o único restore do fornecedor é in-place sobre a própria produção.

A alternativa barata para o **RPO**, e só para ele: tornar o dump lógico **diário** em vez de
semanal. Custa minutos de CI e leva o RPO da cópia lógica de 7 dias para 1. Não dá
point-in-time nem alvo não-destrutivo.

## O que o dump lógico NÃO contém

O `pg_dump` do `backup-database.yml` exclui doze schemas. Dois grupos, por motivos diferentes:

**Excluídos porque são da plataforma, não do domínio:** `storage`, `supabase_functions`,
`extensions`, `graphql`, `graphql_public`, `realtime`, `pgsodium`, `vault`, `supabase_migrations`,
e (desde 08/08) `cron` e `net`.

**Excluído com consequência de recuperação: `auth`.**

Medido no ensaio de 08/08, restaurando o backup de 03/08:

| | |
|---|---|
| `auth.users` no restaurado | **0** |
| membros com `auth_id` órfão | **100** de 131 |
| chaves estrangeiras | 523 na origem, **518** no restaurado |

As 4 FKs ausentes são `members_auth_id_fkey`, `user_profiles_id_fkey`, `events_created_by_fkey` e
`webinars_created_by_fkey`, todas contra `auth.users`.

**Em português:** restaurar só este dump devolve todo o dado e **nenhuma identidade**. Ninguém
consegue entrar. A recuperação completa exige, além do dump, reprovisionar as identidades (backup
físico do Supabase, ou recriação via OAuth com re-vínculo de `members.auth_id`).

### Decisão do PM, ratificada em 08/08/2026: o schema `auth` NÃO entra no dump

Incluir resolveria a recuperação de identidade e levaria **hashes de senha e refresh tokens** para o
artefato do GitHub, que é o repositório de código. O risco de exfiltração de credencial supera o
ganho de conveniência na recuperação.

**Consequência aceita, e ela precisa estar escrita:** uma recuperação a partir deste dump devolve o
dado e **não** devolve o acesso. Reprovisionar identidade passa a ser um passo explícito do
procedimento, por uma destas vias:

1. backup **físico** do Supabase (o único que carrega `auth`), o que na prática exige PITR ligado
   para ter um alvo de restauração não-destrutivo;
2. recriação das contas via OAuth com re-vínculo de `members.auth_id`, manual e proporcional ao
   número de pessoas ativas.

⚠️ As duas vias dependem de decisões que **não** estavam fechadas quando este parágrafo foi escrito.
Antes de confiar nele num incidente, confira qual delas existe de fato.

## Fidelidade medida do dump lógico

Ensaio de 08/08 sobre o backup de 03/08, restaurado num `supabase/postgres:17.6.1.084`:

- **213 de 216** tabelas do schema `public`. As 3 ausentes (`alert_deliveries`,
  `cron_vitality_watch`, `selection_booking_attempts`) foram **criadas em 05/08**, depois do dump.
  A ausência estava correta.
- **153 de 213** com contagem idêntica à produção no dia do teste.
- O restante é crescimento de 5 dias, confirmado contra um oráculo recortado na data do dump
  (`count(*) filter (where created_at < '<data>')`). Exemplos que fecharam exatos: `events` 625,
  `selection_evaluations` 420, `gate_attempts` 30.

## Como ler o resultado de um ensaio sem se enganar

Três armadilhas, todas custaram uma volta em 08/08:

1. **Compare contra a data do BACKUP, não contra produção agora.** Dezenas de tabelas parecem
   divergentes e são só crescimento. O controle mais barato: uma tabela que só ganhou linhas depois
   do dump deve voltar **vazia**. Se ela vier cheia, você está lendo produção por engano.
2. **Tabela ausente pode ter nascido depois.** Datar pela migration resolve:
   `git log -1 --format=%ad -- supabase/migrations/<arquivo>.sql`.
3. **Qualquer `syntax error` no log do restore é perda silenciosa de dado**, não ruído. Ele
   significa que o `psql` saiu de um bloco `COPY` e passou a interpretar linhas de dado como
   comando. O tell é o token do erro ser um valor (`localhost`, `3`) e não um identificador SQL.

Foi exatamente assim que `admin_audit_log` se perdeu inteiro (67.494 linhas na origem, zero no
restaurado) antes da correção do #1684: o dump carregava `COPY cron.job`, tabela de extensão, o
restore respondia `permission denied for table job`, e a cascata levou junto tabelas sem relação
nenhuma com `cron`.

## Procedimento de restauração local

```bash
# baixa o mais novo, verifica o gzip, mantém 8 cópias e ENSAIA a restauração
scripts/pull-backup-local.sh --restore

# instala o timer semanal (segunda 09:00, depois do dump de domingo 23:00 UTC)
scripts/pull-backup-local.sh --install-timer
```

O script recusa um destino dentro de um repositório git: o dump contém PII de membros e
candidatos, e o destino nasce `0700` com os arquivos `0600`.

## O ambiente restaurado também é o laboratório de perfis

Gates que resolvem por `auth.uid()` não são mensuráveis em produção: `execute_sql` entra como
`service_role` e o conector MCP entra como o dono da conta. Numa cópia restaurada:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '<auth_id do perfil alvo>', true);
select public.a_rpc_que_voce_quer_testar();
rollback;
```

⚠️ A imagem `supabase/postgres` define `auth.uid()` lendo `request.jwt.claim.sub` (singular).
Produção aceita também `request.jwt.claims`. Confira com `pg_get_functiondef` antes de concluir que
um gate está quebrado.

⚠️ **A cópia é da data do backup.** Para testar código de hoje, aplique por cima as migrations
posteriores ao dump. Rodar cru mede o comportamento **antigo**, o que é útil como controle
histórico e enganoso como validação.

Usos reais em 08/08:

- **#1591:** avaliador não-GP resolveu `selection_committee_role = 'evaluator'` e atravessou
  `submit_evaluation`; observador resolveu `'observer'` e levou
  `Unauthorized: observer role does not evaluate`. As **duas classes de recusa diferentes** são o
  que prova o gate: se ambos falhassem igual, o teste não provaria nada.
- **#1682:** o defeito do ledger foi reproduzido, corrigido e validado com controle negativo, e o
  alcance (**34** pessoas) bateu com a medição feita em produção por consulta independente.
