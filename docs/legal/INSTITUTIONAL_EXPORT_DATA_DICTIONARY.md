# Institutional Export — Data Dictionary (LGPD semantic overlay)

**Scope:** #572 Block A institutional export. This document is the **human-authored LGPD overlay** that the
machine-readable dictionary (`export_institutional_data_dictionary()` → `data_dictionary.json`) cannot hold:
per **domain group**, the LGPD data classification, legal basis (Art. 7º / Art. 11), and retention anchor.
Structural detail (every table/column/type/PK-FK/RLS) lives in `data_dictionary.json`; this overlay is at
domain granularity by design (per-column LGPD tagging of ~200 tables is out of scope — ADR-0112).

**Version:** tracks migration head. Cite the `migration_head` from the manifest in the dump header.
**Companions:** `docs/operations/INSTITUTIONAL_EXPORT_RUNBOOK.md` · `docs/adr/ADR-0112-institutional-data-portability-block-a.md`.

## Classification legend

- **PII** — dado pessoal (LGPD Art. 5º I): identifica ou pode identificar o titular.
- **PII-sensível** — Art. 5º II (origem racial/étnica, saúde, biometria, etc.).
- **Pseudônimo** — hash/derivado one-way (Art. 12): não reidentifica isoladamente.
- **Não-pessoal** — agregado/operacional/configuração sem titular.

## Domain groups

| Domínio | Tabelas-núcleo | Classificação | Base legal (LGPD) | Âncora de retenção |
|---|---|---|---|---|
| **Identidade** | `members`, `persons`, `engagements`, `auth_engagements` | PII (nome, email, telefone, `pmi_id`, `auth_id`) | Art. 7º V (execução do Termo de Voluntário) + Art. 7º IX | Vínculo ativo + 5 anos → anonimização (Block C cron `lgpd-anonymize-inactive-monthly`) |
| **Seleção** | `selection_applications`, `selection_cycles`, `application_*`, `ai_processing_log` | PII + **PII-sensível** (vídeo/voz do candidato = Art. 11) | Art. 7º I (consentimento) + Art. 11 II (consentimento específico p/ análise de IA) | Pré-membro rejeitado/retirado: caminho #905 (cron dormante); mídia Art. 11 fora do dump (só URLs) |
| **Consentimento** | `consent_records` | PII + provas (`ip_hash`, `user_agent_hash` = pseudônimo) | Art. 8º (registro de consentimento) + Art. 37 (RoPA) | Ledger imutável — nunca deletado; revogação carimba `revoked_at` (sem efeito retroativo) |
| **Iniciativas/Boards** | `initiatives`, `boards`, `board_items`, `board_item_*` | Misto: metadados não-pessoais + `created_by`/assignments (PII por referência) | Art. 7º IX (legítimo interesse operacional) | Enquanto a iniciativa existir; confidenciais (`visibility='confidential'`) com acesso restrito (ADR-0105) |
| **Comunicação** | `campaign_*`, `notifications`, `email_webhook_events` | PII (email do destinatário) + operacional | Art. 7º IX + preferências (`communication_preferences`) | Logs Cat. C — purga programada (Block C `log-retention-monthly`) |
| **Gamificação** | `gamification_points`, `member_cycle_history`, rankings | PII por referência (XP por membro) — **decisão automatizada** | Art. 7º IX; **Art. 20** (revisão humana de decisão automatizada mediante solicitação) | Histórico do ciclo; visibilidade opt-out por membro |
| **Certificados** | `certificates`, `certificate_*` | PII (nome, badge, assinatura) | Art. 7º V (comprovação do vínculo) | Permanente (prova de participação) |
| **Auditoria** | `admin_audit_log`, `pii_access_log`, `z_archive.*` | PII por referência (`actor_id`, `target_id`) + trilha Art. 37 | Art. 37 (registro das operações de tratamento) | `z_archive` arquiva >5 anos, descarta >7 anos |
| **Configuração** | `site_config`, `platform_settings` | Não-pessoal — **mas contém segredos** | — | Dados via `export_redacted_settings()` (chaves `_secret`/`_token`/`_key` mascaradas) |

## Excluded from the dump (and why)

- **Schemas:** `auth` (hashes de senha Argon2/bcrypt, tokens OAuth — propriedade do operador Supabase; migrar
  pelo canal Auth próprio, NUNCA por SQL dump), `vault` (segredos cifrados), `storage` (binários), `realtime`,
  `supabase_migrations`.
- **Table data (DDL kept, rows dropped — reconstruível):** `cycle_tribe_dim` (matview), `preview_gate_eligibles_cache`
  (cache de trigger), `wiki_pages` (sync do GitHub `nucleo-ia-gp/wiki` — ADR-0010), `artia_status_reports`
  (cache da API Artia), `cron_run_log` (telemetria de cron).
- **Settings rows:** `site_config` / `platform_settings` — via `export_redacted_settings()` com segredos
  mascarados (hoje: `arm116_calendar_webhook_secret`).
- **Mídia Art. 11:** vídeo/áudio (voz/imagem) referenciados por URL — binários NÃO entram no dump; destino em
  encerramento segue o caminho #905 sob decisão do DPO.

## Reimport notes

- Formato: `pg_dump --format=plain` (SQL padrão: DDL + `COPY`), reimportável com `psql` num **Postgres 14+ compatível com Supabase** (o schema `auth` + `auth.uid()`/`auth.role()` devem pré-existir — as políticas RLS dumpadas os referenciam; Postgres puro exige pós-processar as RLS antes do restore).
- Tipos preservados nativamente: `text[]`, `jsonb`, `timestamptz`, `uuid`, enums.
- **RLS:** o dump re-cria as políticas (`--no-acl` não as remove). Após restore, criar os papéis
  `anon`/`authenticated`/`service_role` e verificar as políticas ANTES de expor dados a qualquer papel não-owner.
- Integridade: **completude de snapshot** (um ponto no tempo via `pg_dump` REPEATABLE READ). NÃO é prova de
  hash-chain append-only do audit log (isso é #574, não vivo).

## Não confundir com o direito individual (Art. 18, V)

Este export é **institucional** (migração/encerramento, controlador→sucessor). O direito de **portabilidade
individual** do titular é entregue separadamente por `export_my_data()` (#568) via o portal de privacidade.
São frameworks de conformidade distintos.
