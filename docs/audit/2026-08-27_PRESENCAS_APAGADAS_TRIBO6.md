# Presenças apagadas ao cancelar as duplicatas da tribo 6 — 27/08/2026

> Registro de recuperação. **As contagens abaixo foram medidas ANTES do cancelamento e são a única
> referência sobrevivente**: o trigger `trg_cleanup_attendance_on_event_cancel` apagou as linhas sem
> auditoria, não há tabela de histórico e `gamification_points` não referencia estes eventos (#2028).

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

## Ponto de restauração

O estado íntegro é **anterior a 2026-08-27 03:38:00 UTC** (primeiro cancelamento). Qualquer backup
diário anterior a hoje serve.

⚠️ **Decisão do PM (27/08): restaurar para cópia LOCAL e comparar ali** — não subir restauração em
produção, que traria de volta também os eventos duplicados e desfaria a correção da regra.
