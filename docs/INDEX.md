# 📚 Documentação — AI & PM Research Hub

Índice de toda a documentação do projeto.

---

## Para todos

| Documento | Descrição |
|-----------|-----------|
| [../README.md](../README.md) | Visão geral, stack, key numbers |
| [SITE_MAP.md](SITE_MAP.md) | Mapa de páginas + access tiers |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Arquitetura do sistema, camadas, padrões de segurança |

## Para desenvolvedores

| Documento | Descrição |
|-----------|-----------|
| [../CLAUDE.md](../CLAUDE.md) | Regras do projeto: pre-commit validation, i18n, database, MCP, deploy |
| [ADMIN_ARCHITECTURE.md](ADMIN_ARCHITECTURE.md) | Estrutura admin module (42 pages) |
| [MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md) | Setup MCP server local + clients (Claude.ai, ChatGPT, Cursor) |
| [PERMISSIONS_MATRIX.md](PERMISSIONS_MATRIX.md) | Matriz V4 actions × engagement kinds × roles |
| [DEPLOY_CHECKLIST.md](DEPLOY_CHECKLIST.md) | Pre-deploy validation steps |
| [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md) | Recovery procedures (Supabase outage, Cloudflare, etc.) |
| [adr/README.md](adr/README.md) | Architecture Decision Records (ADR-0001..0076) |
| [refactor/DOMAIN_MODEL_V4_MASTER.md](refactor/DOMAIN_MODEL_V4_MASTER.md) | V4 refactor master tracking (concluído 2026-04-13) |
| [reference/V4_AUTHORITY_MODEL.md](reference/V4_AUTHORITY_MODEL.md) | V4 authority audit checklist (4-step antes de seed expansion) |

## Para operadores (GP / Deputy)

| Documento | Descrição |
|-----------|-----------|
| [RUNBOOK.md](RUNBOOK.md) | Deploy, pg_cron, email, auth, monitoramento, emergências |
| [GOVERNANCE_CHANGELOG.md](GOVERNANCE_CHANGELOG.md) | Histórico de decisões estruturais (GC-001 → GC-141+) |
| [RELEASE_LOG.md](RELEASE_LOG.md) | Release notes por sprint (Pacote A/B/C/...) |
| [governance/README.md](governance/README.md) | Governance docs index (Política IP, Termo Voluntário, Código de Conduta) |

## Para planejamento e tracking

| Documento | Descrição |
|-----------|-----------|
| [BACKLOG.md](BACKLOG.md) | Ponteiro: GitHub Issues + memory log + ADRs + handoffs |
| [council/README.md](council/README.md) | Multi-agent council structure (12 sub-agents em 3 tiers) |
| [council/decisions/](council/decisions/) | Decision log de revisões estratégicas |
| [strategy/](strategy/) | Strategy audits (ARM pillars audit, multi-client gaps, directorate mapping) |
| [research/](research/) | Web research deep-dives (Sympla, Airmeet, NFS-e, multi-tenant SaaS) |

## Por área de conteúdo

| Diretório | Tipo | Exemplos |
|---|---|---|
| [adr/](adr/) | Decisões arquiteturais | ADR-0001..0076 |
| [refactor/](refactor/) | Refactor master docs | DOMAIN_MODEL_V4_MASTER, HERLON_VEP_PARALLEL_TRACK |
| [strategy/](strategy/) | Strategy audits | ARM_PILLARS_AUDIT_P107, p134_omega_a_* |
| [research/](research/) | Web research | p134_sympla_landscape, p134_airmeet_landscape, p134_nfse_nacional_2026 |
| [council/](council/) | Council reviews | p134_omega_a_council_consolidated, p134_omega_a_product-leader_synthesis |
| [audit/](audit/) | Audit reports | RPC_BODY_DRIFT_AUDIT_P50 |
| [specs/](specs/) | Feature specs from Claude Chat | Various S-XXX |
| [drafts/](drafts/) | Governance docs HTML staging | Pre-WYSIWYG drafts |
| [reference/](reference/) | Reference materials | V4_AUTHORITY_MODEL, key data structures |
| [reports/](reports/) | Operational reports | Pre-deploy reports |
| [editorial/](editorial/) | Editorial decisions | Pitch positioning per audience |
| [instrumentos-ip/](instrumentos-ip/) | IP-related instruments | Author license templates |
| [blog/](blog/) | Blog post sources | MDX + assets |

---

## Convenções

- **GC-XXX:** Governance Changelog entry — decisão estrutural documentada
- **CR-XXX:** Change Request — proposta de mudança pendente de aprovação
- **S-XXX:** Sprint/spec identifier (ex: S-SENTRY-1, S-RM1)
- **W-XXX:** Work item identifier (ex: W106, W139)
- **H-X:** Horizon item (H3, H4 = short/medium-term goals)
- **Ω-X:** Onda (wave) identifier para refactors multi-sessão (Ω-A, Ω-B, ...)
- **p<NNN>:** Sprint/handoff session (p87, p133, p134, ...)
