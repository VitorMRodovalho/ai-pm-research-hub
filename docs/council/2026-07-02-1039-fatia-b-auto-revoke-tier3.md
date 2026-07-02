# Council Tier-3 — #1039 Fatia B: alumni-only auto-approve/auto-revoke de Drive no offboard

**Date:** 2026-07-02 · **Trigger:** mandato explícito do PM no roteamento do issue #1039 ("sessão
Fable 5 + council Tier-3, síntese multi-lente ADR/AL/LGPD/reversibilidade") · **Input:** design spec
grounded ao vivo (fila 10/10 `revoked`, 21 alumni / 6 inactive, `re_engagement_pipeline` vazio, cron
63/64 ativos, invariante AL verbatim) · **Output pareado:** decision record
`decisions/2026-07-02-1039-drive-auto-revoke-alumni-only.md` · **Amendment:** ADR-0107 Amendment 1 ·
**Migration:** `20260805000319`.

## 0. Verdict at a glance

| Lens | Verdict | Headline |
|------|---------|----------|
| legal-counsel | APPROVE_WITH_CONDITIONS | Auto-revoke **cumpre** o dever do Art. 16 (fecha a lacuna do manual); 3 condições **pré-go-live** (não pré-ship): comms ao titular (janela ≤1h), `skip_reason` estrutural, issue de retenção PII 5y + ROPA |
| security-engineer | APPROVE_WITH_CONDITIONS | Arquitetura sólida e consistente com os padrões; 2 must-fix de implementação: kill-switch NULL-safe **fail-closed** + literais JSONB consistentes (seed × comparação) |
| data-architect | APPROVE_WITH_CONDITIONS | Mecanicamente correto; 4 disciplinas travadas pré-migração: corpo VIVO das funções reconstruídas (Phase C), ordem explícita dos passos, queue-clear ANTES do UPDATE do membro, `skip_reason` obrigatório em `skipped` via CHECK |
| accountability-advisor | APPROVE_WITH_CONDITIONS | Cadeia de governança certa (amendment same-file + decision record + runbook); 3 lacunas documentais: fechar a narrativa do gate original + linha de ratificação do PM, decision record commitado JUNTO da migração, flip do kill-switch com INSERT em `admin_audit_log` (a CAUSA, não só os efeitos) |

**Zero blockers.** Todas as condições foram incorporadas no ship (migração `20260805000319` + EF +
runbook + ADR-0107 Amendment 1) ou viram follow-up gate de go-live (ver decision record).

## 1. legal-counsel (LGPD)

- **Enquadramento central:** revogar permissão de Drive NÃO é "eliminação de dados do titular" — é o
  controlador removendo o próprio grant. O dado pessoal é o `permission_email` na fila. O Art. 16
  impõe ao CONTROLADOR encerrar tratamento desnecessário; a auto-revogação É o cumprimento — o
  modelo manual deixava o dever pendente por dias/semanas. **Auto-revoke fortalece a conformidade.**
- **Art. 18:** direitos exercidos PELO titular a pedido; não há dever legal de notificação proativa
  da revogação. PORÉM a aceleração dias→≤1h muda a expectativa do ex-membro → **COND-1**: Aviso de
  Privacidade / comms de desligamento devem citar a janela ≤1h ANTES do go-live (Art. 9 I c/c
  Art. 6 VI). *Incorporado: Privacy Notice §6 (3 idiomas) + linha de comms no runbook C3 §3.*
- **COND-2:** `skipped` com dois significados distinguidos só por `notes` texto-livre não é evidência
  estrutural (Art. 37 / fiscalização ANPD). → coluna `skip_reason` enum CHECK. *Incorporado.*
- **COND-3:** linhas terminais retêm `permission_email` (PII) sem prazo — lacuna PRÉ-EXISTENTE da
  Fatia A, agravada marginalmente. Retenção justificada (Art. 16 I — a trilha É a prova do
  cumprimento), mas exige prazo: **5 anos** (CC Art. 206 §3 V + prazo administrativo) + cron de
  anonimização. Não bloqueia o ship; **bloqueia o go-live sem issue aberta + ROPA**. *Follow-up
  issue filado.*
- **RECs:** registrar a operação no ROPA + informar o DPO; verificar cláusula de revogação de
  ferramentas no Termo vigente (incluir na v2.8 como informativa, sem re-aceite); documentar a
  assimetria alumni/inactive no ADR com fundamento técnico-jurídico ("sem demora injustificada" ≠
  instantâneo; revisão humana p/ reversíveis não é demora injustificada) — *incorporado no
  Amendment §2*; notificação de cortesia ao ex-membro (boa prática Art. 6 X, não obrigação) —
  *follow-up*; registrar no-auto-re-grant como escolha de MINIMIZAÇÃO (Art. 6 III), não só
  frequência-zero — *incorporado no Amendment §7*.

## 2. security-engineer

- **MUST-FIX 1 — kill-switch NULL-safe fail-closed:** `<> 'true'` puro seria fail-OPEN se a chave
  fosse deletada (NULL <> 'true' → NULL → falsy). *Incorporado:* `coalesce(v_enabled,
  'false'::jsonb) IS DISTINCT FROM 'true'::jsonb`.
- **MUST-FIX 2 — literais JSONB consistentes:** `site_config.value` é jsonb; seed e comparação na
  MESMA forma (boolean `'false'::jsonb` / `'true'::jsonb`), senão o switch trava para sempre.
  *Incorporado + coberto no contract test.*
- **Provenance:** `approved_by NULL + approval_mode='auto'` é ADEQUADO para Art. 37; melhoria
  incorporada — o registro de autorização (`drive_revocation_auto_approved`) carrega os `audit_ids`
  exatos (correlação forense O(1), sem join por timestamp).
- **Superfície do RPC:** gate `current_caller_role() IS DISTINCT FROM 'service_role'` + GRANT
  restrito espelham o precedente `get_offboarded_member_emails(uuid)`; `auth.role()` lê o claim do
  JWT original mesmo em cadeia SECDEF → sem escalação. *Teste de deny DB-gated exigido — incluído.*
- **Kill-switch write é superadmin-only** → GP não pausa o auto-revoke; runbook deve explicitar
  (*incorporado*) e um escape-hatch `unapprove` por linha fica como follow-up.
- **Edge residual documentado:** reativação × drain com janela de µs pode deixar linha `skipped` cuja
  permissão foi de fato deletada → runbook §Re-grant nomeia o caso para diagnóstico.
- **`approval_mode` no list RPC do GP:** benigno; estritamente melhor para operabilidade; sem PII nova.

## 3. data-architect

- **AL cláusula 1 emendada:** correta; sem falso-positivos (manual `revoked` sempre tem
  `approved_by`; auto tem `revoked_at` + mode). Falso-negativo delimitado: `already_absent` fora das
  checagens de proveniência — **pré-existente e semanticamente correto** (grant já ausente → não há
  prova de revogação a exigir); *documentado na descrição do invariante*.
- **Cláusula 1b:** dispara só para (a) auto com aprovador humano (incoerência) ou (b) auto ainda
  pendente (bypass) — terminais auto (`failed`/`already_absent`/`revoked`/`skipped`) avaliam falso.
  Sem falso-positivos.
- **MF-1 corpo vivo:** *satisfeito por verificação* — `scripts/audit-rpc-body-drift.mjs` = **0
  drifted** nas 4 funções-alvo em 2026-07-02 ⇒ arquivos de captura ≡ vivo (md5 normalizado); rebuild
  autorado por splice dos arquivos com substituições ancoradas (falha-alta).
- **MF-2 ordem dos passos:** coluna → seed → RPC novo → rebuilds → invariantes → NOTIFY.
  *Enumerada no header da migração.*
- **MF-3 queue-clear ANTES do UPDATE de members** (senão janela de violação AL cláusula-2 na mesma
  tx). *Comment-locked no corpo.*
- **MF-4 `skipped` ⇒ razão obrigatória via CHECK** (zero linhas skipped ao vivo → sem backfill).
  *Incorporado (via `skip_reason`, superseding notes-only).*
- **`skipped` reuse vs status `cancelled` novo:** reuse aceito COM as 3 condições (redefinição no
  ADR, razão obrigatória, tabela de lifecycle no runbook) — `cancelled` churnaria CHECK + reader +
  island + 3 dicts + teste. *As 3 condições incorporadas.*
- **RPC set-based > trigger AFTER INSERT:** trigger dispararia também nos refreshes do ON CONFLICT
  (chamadas vazias + ruído de audit) e é magia oculta em tabela de auditoria; fila tem UM writer.
- **Catch-up no-arg documentado** (*Amendment §8*); métrica `auto_approved` no overview reader
  (*incorporada*); trap da migração phantom nomeada no plano de apply; loop per-row do upsert (#209)
  flagged para refactor futuro (não introduzido por esta fatia).

## 4. accountability-advisor

- **Padrão de governança correto** (amendment same-file — precedente ADR-0071/0016/0039 — + decision
  record + runbook), condicionado a: **fechar a narrativa do gate original** (por que existia: role
  do SA pendente + caminho nunca executado; por que é seguro relaxar: elevação feita + 10/10
  zero-erro + escopo alumni-only com janela de pipeline) e **linha de ratificação nominal do PM** —
  *ambos incorporados no Amendment*.
- **Decision record commitado ANTES/JUNTO da migração** (princípio do bypass-audit: documentação
  precede a mudança) — *mesmo commit*.
- **Flip do kill-switch precisa registrar a CAUSA:** `site_config` não tem trigger de audit; o flip
  deixaria zero rastro. → checklist de go-live com UPDATE + INSERT `admin_audit_log`
  (`site_config_changed`, from/to, referência ao decision record) — *incorporado no runbook*.
- **NÃO expandir o bypass-audit semanal** para auto-revogações: code-governance ≠ data-governance;
  auto-revogações já vivem no `admin_audit_log`. *Acatado — nenhuma mudança no workflow semanal.*
- **Constraint multi-capítulo** (SA é PMI-GO; alumni-aqui/ativo-alhures seria revogado errado) —
  *registrada no Amendment como known future constraint*.
- **RECs:** `set_site_config` governado (flip+audit atômico) — *follow-up*; notificação de cortesia
  ao alumni (PMI Code of Ethics §2.3) — *follow-up*; runbook §Re-grant apontar o drill-down como
  fonte do "o que foi revogado" — *incorporado*.

## 5. Convergência

- **`skip_reason` estrutural** exigido independentemente por legal (COND-2) e data-arch (MF-4) —
  upgrade sobre o notes-only do spec; incorporado como coluna enum + CHECK.
- **Go-live gated em comms + retenção** (legal COND-1+COND-3 ⟂ accountability go-live checklist):
  ship dark unânime; flip auditado.
- **Notificação de cortesia ao ex-membro**: legal REC-4 ≡ accountability REC — mesmo follow-up.
- **Nenhuma lente contestou** alumni-only, no-auto-re-grant, provenance por coluna (vs sentinel), ou
  o mecanismo RPC set-based pós-upsert.

## 6. PM decisions (gate 2026-07-02, via AskUserQuestion na sessão)

1. **Re-grant na reativação: NENHUM automático** (recomendado + council 4/4) — manual GP contextual.
2. **Go-live: ship dark + comms nesta sessão** — Privacy Notice §6 + runbook C3 §3 atualizados;
   issue de retenção filado; flip fica com o PM via checklist do runbook.
3. **Pacote ratificado e implementado** — esta ratificação é a linha "Ratified" do ADR-0107
   Amendment 1.

---

**Assisted-By:** Claude (Anthropic)
