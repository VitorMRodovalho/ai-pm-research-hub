# Presenças apagadas ao cancelar as duplicatas da tribo 6 — 27/08/2026

> **RESOLVIDO em 27/08/2026 — ninguém perdeu presença. Ver "Desfecho" no fim.**
>
> Registro de incidente e de recuperação. O trigger `trg_cleanup_attendance_on_event_cancel` apagou
> 14 linhas de presença sem auditoria; não há tabela de histórico e `gamification_points` não
> referencia estes eventos (#2028). As linhas foram **recuperadas do dump diário do repositório**
> — o caminho está descrito abaixo e deve ser o PRIMEIRO a ser tentado num próximo incidente.

## O que aconteceu

Em 27/08/2026, entre 03:38 e 03:56 UTC, 12 eventos da tribo 6 (ROI & Portfólio) foram cancelados via
`cancel_event_occurrence`: 8 duplicatas de recorrência e 4 órfãs do dia antigo. O trigger apagou
**14 registros de presença** nos eventos que os tinham.

Contexto e causa em #2026; o defeito de auditoria em #2028.

## Os eventos cancelados, com a presença que havia

| data | dia | event_id | presenças apagadas |
|---|---|---|---:|
| 2026-08-05 | Qua | `8feb473d-c47c-4e7f-afb1-def1fa8482cb` | **5** |
| 2026-08-12 | Qua | `692cb523-f76a-4861-ac6a-cdc9f698a4d7` | **6** |
| 2026-08-19 | Qua | `5af8b473-b599-4e77-9f2c-66266087e27f` | **3** (1 presente, 2 marcados ausentes) |
| 2026-08-26 | Qua | `d6d19295-7971-4750-9365-c8cb031f2a59` | 0 |
| 2026-09-02 | Qua | `59e0ef6f-a8ee-4277-90ea-7d8d28acc4bb` | 0 |
| 2026-09-09 | Qua | `598c8ecb-1617-41e7-9c21-ff9ddad4ad29` | 0 |
| 2026-09-16 | Qua | `ce829616-d676-472b-8be9-24d02102a4c3` | 0 |
| 2026-09-23 | Qua | `477fb57d-6ecc-455d-83fa-48acc796172b` | 0 |
| 2026-09-30 | Qua | `5cfb27b5-9777-4bc8-a581-9fd4bfcea088` | 0 |
| 2026-10-07 | Qua | `61e75547-f2ae-466a-831a-49a5f2f42995` | 0 |
| 2026-10-14 | Qua | `ae6f1c19-3d78-4e2c-9a94-de1675037830` | 0 |
| 2026-10-21 | Qua | `ee98384c-f00c-4962-b172-e1a9ca275d9a` | 0 |

**Total apagado: 14 registros**, todos nos três primeiros eventos.

## As terças correspondentes (que permanecem ativas)

| semana ISO | terça | presenças na terça | quarta apagada | presenças na quarta |
|---|---|---:|---|---:|
| 2026-W32 | 04/08 (`4e1a3f2a-f11c-4682-8296-979a88f033cd`) | 7 | 05/08 | 5 |
| 2026-W33 | 11/08 (`85f8ef26-507f-4ba7-a2fd-c5048fac33fd`) | 7 | 12/08 | 6 |
| 2026-W34 | 18/08 (`cfc269f8-c964-4986-940d-3358cfa043f1`) | 6 | 19/08 | 3 |

## A pergunta a responder num backup

**Quem estava marcado na QUARTA e não está na TERÇA da mesma semana?** Essas pessoas perderam
crédito de presença sem equivalente no evento que ficou, e precisam de ajuste manual.

Consulta a rodar contra o estado restaurado (cópia local, **não** em produção):

```sql
SELECT w.date AS quarta, m.name, m.email, a.present
FROM attendance a
JOIN events w ON w.id = a.event_id
JOIN members m ON m.id = a.member_id
WHERE w.id IN (
  '8feb473d-c47c-4e7f-afb1-def1fa8482cb',
  '692cb523-f76a-4861-ac6a-cdc9f698a4d7',
  '5af8b473-b599-4e77-9f2c-66266087e27f'
)
AND NOT EXISTS (
  SELECT 1 FROM attendance a2
  JOIN events t ON t.id = a2.event_id
  WHERE a2.member_id = a.member_id
    AND t.initiative_id = w.initiative_id
    AND to_char(t.date,'IYYY-IW') = to_char(w.date,'IYYY-IW')
    AND extract(isodow from t.date) = 2
)
ORDER BY w.date, m.name;
```

## Desfecho: ninguém perdeu presença

Executado em 27/08/2026, ~04:10 UTC. **A quarta era subconjunto perfeito da terça nas três semanas**
— toda pessoa marcada na reunião duplicada já estava marcada na que ficou.

| semana | terça | quarta | interseção | **só na quarta** | só na terça |
|---|---:|---:|---:|---:|---:|
| W32 (04 e 05/08) | 7 | 5 | 5 | **0** | 2 |
| W33 (11 e 12/08) | 7 | 6 | 6 | **0** | 1 |
| W34 (18 e 19/08) | 6 | 3 | 3 | **0** | 3 |

**Nenhum ajuste manual é necessário.** As 14 linhas apagadas eram exatamente a dupla contagem que a
#2026 descreve, e nada além dela.

⚠️ **Controle positivo, sem o qual o zero não valeria nada.** Um "0 em todas as semanas" é
indistinguível de uma junção quebrada. A coluna "só na terça" (2, 1 e 3) e as interseções
não-vazias provam que a comparação enxerga diferença quando ela existe. Nunca publique o zero sem
o controle ao lado — é a classe do guard vazio que fica verde por vacuidade.

## O caminho que funcionou — tente ESTE primeiro

> 📘 **O procedimento genérico foi extraído para `docs/operations/BACKUP_RECOVERY_RUNBOOK.md`.**
> Este bloco fica aqui como o registro do que foi feito neste incidente; o runbook é o que se lê
> antes do próximo.

O dado foi recuperado **do próprio repositório**, sem restaurar nada e sem subir infra.

`.github/workflows/backup-database.yml` roda `pg_dump` **diário às 23:00 UTC**, publica o
`.sql.gz` como artefato do GitHub Actions (retenção 60 dias) e copia para o R2. O comentário do
workflow registra por que ele existe: o PITR de 7 dias custa ~US$ 100/mês contra ~US$ 10/mês do
projeto inteiro, então o dump diário compra o RPO por minutos de CI.

O backup usado rodou em **2026-08-27 00:12:57 UTC**, três horas e meia antes do primeiro
cancelamento (03:38 UTC).

```bash
# 1. achar o run e o artefato
gh run list --workflow=backup-database.yml --limit 5   --json databaseId,createdAt,conclusion
gh api "repos/<owner>/<repo>/actions/runs/<RUN_ID>/artifacts"   --jq '.artifacts[] | "\(.name) | \(.size_in_bytes) | expira \(.expires_at)"'

# 2. baixar
gh run download <RUN_ID> --dir ./bkp

# 3. extrair a tabela SEM subir banco: o dump e SQL puro com blocos COPY
zcat backup_*.sql.gz | awk '
  /^COPY public\.attendance \(/ {inblk=1; next}
  inblk && /^\\\.$/ {inblk=0}
  inblk {print}
' > attendance.tsv
```

Ordem das colunas no `COPY` (confira no cabeçalho do bloco, ela muda se a tabela mudar):
`id, event_id, member_id, present, registered_by, corrected_by, notes, created_at, updated_at,
checked_in_at, marked_by, excused, excuse_reason, edited_by, edited_at, organization_id`

### Por que os outros caminhos NÃO servem

| caminho | veredito (medido 27/08) |
|---|---|
| **dump diário no artefato do Actions** | **funciona** — lógico, baixa, e não toca em nada |
| PITR do Supabase | indisponível: `pitr_enabled = false` |
| backup físico do Supabase | existe (7 diários), mas **não tem download** e restaura no lugar |
| restaurar em produção | desfaria os 12 cancelamentos e a correção da regra |
| arquivos versionados no git | não há dado operacional versionado, e **não deve haver** — o repo é público e presença é dado pessoal |

## Lição de processo

Os caminhos de recuperação deviam ter sido levantados **antes** do cancelamento, não depois. O
backup existia, era acessível e estava a um comando de distância — a perda nunca foi real, mas foi
tratada como se fosse por horas. Junto com a lição da #2028 (ler a função não é ler o efeito;
`pg_trigger` sobre a tabela alvo faz parte da leitura), a regra é: **antes de qualquer `UPDATE` de
estado que possa apagar dado, saber onde está a cópia e como se lê ela.**
