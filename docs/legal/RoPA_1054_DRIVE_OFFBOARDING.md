# RoPA - Revogacao automatica de acesso ao Google Drive de alumni (#1054 / #1039)

> **Registro de Operacoes de Tratamento (Art. 37 LGPD)** para a rotina de
> revogacao automatica de acessos a arquivos do Google Drive de ex-voluntarios
> apos o desligamento, com trilha de auditoria retida na plataforma Nucleo IA.
>
> **Status:** RASCUNHO para ratificacao do DPO/juridico (gerado 2026-07-11 com o
> build do #1054). A retencao/anonimizacao ja esta implementada (mig
> `20260805000425`); o go-live da revogacao automatica (kill-switch) permanece
> pendente de aprovacao do owner/DPO.
> **Controladora:** PMI Goias (CNPJ 06.065.645/0001-99). **Operadora:** plataforma
> nucleoia.vitormr.dev. **DPO:** Ivan Lourenco Costa (titular) - Angeline Altair
> Silva Prado (substituta) - dpo@pmigo.org.br.
> **Refs:** ADR-0014 (politica de retencao de logs) - decisao de conselho Tier-3
> `docs/council/decisions/2026-07-02-1039-drive-auto-revoke-alumni-only.md` (legal
> COND-3) - migrations `20260805000425` (retencao) + fatia B do #1039 (deteccao/
> revogacao) - tabela `drive_offboarding_audit`.

---

## 1. Registro da operacao de tratamento (Art. 37)

| Campo | Conteudo |
|---|---|
| **Operacao** | Deteccao e revogacao das permissoes de acesso a arquivos/pastas do Google Drive institucional detidas por ex-voluntarios apos o desligamento, e registro (trilha de auditoria) de cada evento de revogacao. |
| **Agente que trata** | Rotina automatizada da plataforma (cron/edge function), sob controle da GP/administracao, agindo em nome da controladora (PMI-GO). A revogacao efetiva depende de aprovacao (`approval_mode`) conforme a fatia B do #1039. |
| **Categorias de dado (Art. 5)** | Identificacao: e-mail do ex-membro associado a permissao no Drive (`permission_email`). Metadados tecnicos: id/nome/URL do arquivo, tipo e papel da permissao, id da permissao, status e datas da revogacao. **Sem dado sensivel (Art. 5, II).** |
| **Titulares** | Ex-voluntarios (alumni) do Programa Nucleo IA que detinham acesso a arquivos do Drive institucional. |
| **Finalidade** | Seguranca da informacao - eliminar acessos remanescentes de quem deixou o Programa (principio do menor privilegio), reduzindo o risco de acesso indevido a dados institucionais e de terceiros apos o fim do vinculo. |
| **Base legal do tratamento** | Art. 7, IX (legitimo interesse da controladora na seguranca da informacao e no controle de acessos - LIA resumida no par. 3) c/c Art. 7, V (execucao do Termo de Voluntariado, cujo fim do vinculo justifica a revogacao). Medidas de seguranca sob Art. 46/47/49. |
| **Base legal da retencao da trilha (5 anos)** | Art. 16, I (guarda para cumprimento de obrigacao regulatoria e de prestacao de contas da controladora - a trilha e evidencia de que a revogacao ocorreu) e para exercicio regular de direitos (Art. 7, VI / Art. 10, par. 3). |
| **Retencao** | Trilha de auditoria (`drive_offboarding_audit`) retida por **5 anos**. Ao completar 5 anos, o `permission_email` das linhas terminais (`revoked`/`failed`/`already_absent`/`skipped`) e **anonimizado** por pseudonimo estavel `sha256:<SHA-256(email + salt fixo)>` (hex). Metadados tecnicos do arquivo/permissao (nao PII do ex-membro) permanecem para a integridade do registro. Mecanismo: cron mensal `log-retention-monthly` (ADR-0014, funcao `purge_expired_logs`). |
| **Destinatarios** | **Google LLC** (Google Workspace), como operador/suboperador, via a service account institucional `nucleoia@pmigo.org.br` que executa a leitura/revogacao das permissoes. Internamente: GP/administracao da sede. Sem compartilhamento nominal com terceiros alem do necessario a operacao. |
| **Transferencia internacional** | Google Workspace (infraestrutura global). Coberta pelo inventario de suboperadores (`docs/legal/642_DPA_SUBPROCESSOR_INVENTORY.md`) e pelas salvaguardas contratuais do DPA controladora-operadora. |
| **Medidas de seguranca (Art. 46)** | Tabela com RLS; escrita apenas por rotinas SECURITY DEFINER com gate de contexto de sistema; anonimizacao do e-mail apos 5 anos (minimizacao/limitacao temporal); trilha append-only; funcao de retencao restrita a `service_role`. |
| **Transparencia (Art. 9)** | A ser informada ao titular no Termo de Voluntariado v2.8 (clausula informativa de revogacao de ferramentas ao termino do vinculo - REC-2, pendente do owner). |

## 2. Direitos do titular (Art. 18)
Acesso (II) e correcao (III) via canal do DPO. A trilha de revogacao integra os
registros da controladora; a eliminacao (VI) e ponderada contra a retencao legal
de 5 anos (Art. 16, I). Apos a anonimizacao, o `permission_email` deixa de ser
dado pessoal identificavel diretamente (pseudonimo unidirecional com salt fixo).
Oposicao/revisao (Art. 18 / Art. 20) ao legitimo interesse enderecada ao DPO.

## 3. LIA - teste de legitimo interesse (Art. 7 IX c/c Art. 10)
1. **Finalidade legitima e informada.** Revogar acessos remanescentes de ex-membros
   e requisito de seguranca da informacao e de protecao dos dados institucionais e
   de terceiros; finalidade institucional, nao comercial.
2. **Necessidade (minimizacao).** Trata-se do minimo: o e-mail que identifica a
   permissao a revogar e os metadados tecnicos do arquivo. Nao ha meio menos
   invasivo de identificar e remover a permissao correta. A retencao da trilha e
   limitada no tempo (5 anos) e o e-mail e anonimizado ao fim do prazo.
3. **Balanceamento (expectativa legitima x direitos do titular).** O titular adere
   a um programa de voluntariado sabendo que o acesso a ferramentas e vinculado ao
   vinculo ativo; ha expectativa legitima de que o acesso seja revogado ao sair.
   Salvaguardas que pendem a balanca para o titular: revogacao aprovada (nao
   silenciosa), trilha auditavel, retencao limitada + anonimizacao apos 5 anos,
   ausencia de dado sensivel, sem decisao automatizada com efeito juridico sobre o
   titular. Risco residual baixo.

**Conclusao:** legitimo interesse adequado como base (combinado com Art. 7, V para o
fim do vinculo e Art. 16, I para a retencao da trilha), sujeito as salvaguardas
acima. Ratificacao do DPO pendente.

## 4. Pendencias owner-gated (NAO executadas por esta issue)
- **REC-1:** informar o DPO (dpo@pmigo.org.br) da nova operacao automatizada e
  obter a ratificacao deste RoPA.
- **REC-2:** avaliar clausula informativa de revogacao de ferramentas no Termo de
  Voluntario v2.8 (informativa, sem re-aceite - deferivel).
- **Go-live:** flip do kill-switch `platform_settings.drive_auto_revoke_enabled`
  (hoje OFF) apos codigo + ROPA prontos e ratificacao do DPO.

## 5. Implementacao (referencia tecnica)
- Anonimizacao: funcao `public.purge_expired_logs` (ADR-0014), categoria
  `drive_offboarding_audit`, modo `anonymize` a 1825 dias. Migration
  `supabase/migrations/20260805000425_1054_drive_offboarding_audit_retention.sql`.
- Idempotencia: pseudonimo prefixado `sha256:` e excluido de novas execucoes.
- Contrato: `tests/contracts/1054-drive-offboarding-retention.test.mjs` +
  `tests/contracts/log-retention.test.mjs` (9a tabela coberta).
- Salt: constante fixa documentada no corpo da funcao (D1, decisao do owner
  2026-07-11). Threat model: re-identificacao casual apos 5 anos e aceitavel para
  a finalidade de trilha; nao ha salt por-registro no v1.
