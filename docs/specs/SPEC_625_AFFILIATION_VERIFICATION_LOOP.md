# SPEC #625 — Loop de Verificação de Filiação + Visibilidade por Capítulo + Radar de Renovação

**Status:** Draft v3 — v2 pós-council `wf_c040df9e`; **§6.2/§6.3 re-enquadrados 2026-06-11 por correção do PM**
(o council havia INVERTIDO a relação controladora/operadora do RF-E; grounding: workflow `wf_1975e3fa` —
4 acordos de cooperação assinados + Policy Manual ed. julho/2025 + instrumentos ratificados do repo).
Legal-counsel no v3: GO_W_FIXES, todos foldados (âncora Art. 5º VII; parte da cláusula-modelo = PMI-GO
via plataforma; co-controle = Guia ANPD 2021, não Art. 42 §1º; pendência Art. 48 em §6.2.5 iv).
**F1 SHIPPED (2026-06-11, migration `20260805000148`):** loop de verificação + radar F3 (dry-run)
implementados; council-reviewed (3× GO_W_FIXES + verbatim-diff GO, todos os folds aplicados).
**Reconciliações vs o texto abaixo:** (a) designation = **`filiacao_director`** (segue a convenção
`*_director` dos diretores existentes; supersede `diretoria_filiacao` do §2.7/§4.2 — decisão PM no kickoff);
(b) anonimização (§4.1) é **FK-safe**: `member_id` mantido (linha de members anonimizada in-place),
`verified_by_member_id`→NULL, `verification_obs`→NULL, `source_ref`→hash (NÃO "UUID neutro" — violaria
FK RESTRICT); (c) periodicidade (§9.4) = **AMBAS** (radar contínuo D-30/D-7 + sinal de verificação obsoleta
>11 meses no mesmo cron); (d) **Welma provisionada** (designation + audit). **Pré-req institucional
remanescente antes do go-live operacional:** LIA Art. 7º IX documentada no RoPA + Confidentiality & Records
Compliance Agreement (por força do cargo PMI). **F2/F2.1 NÃO implementados** (gated).
**Origem:** Auditoria da jornada de pré-onboarding ciclo 4 (2026-06-10) + decisões PM 2026-06-10/11.
**Refs:** #625 (camadas 1-2), ADR-0004 (`organization_id`), ADR-0007 (`can()`), ADR-0012 (cache columns),
ADR-0042 (chapter dashboards), ADR-0076 (PMI data/LIA/opt-out), GC-162 (RLS/LGPD), #573 (EEE/UK), #571 (re-aceite).

---

## 1. Contexto e problema (grounded 2026-06-10)

| Achado (vivo) | Evidência |
|---|---|
| `members.pmi_id_verified = false` nos 25 do ciclo 4 | Campo existe; nenhum processo o marca |
| Filiação real (VEP `pmi_memberships`, multi-capítulo) diverge do perfil (`members.chapter`, single) | ≥5 casos (GO×RS, MG×PE/SE/UK, GO×MG/DF…) |
| Filiação PMI **expira** e nada monitora | Caso real: membro com filiação vencida declarada |
| `selection_applications.membership_status` órfã (vazia nos 25) | Coluna sem pipeline |
| Relatórios para diretorias = export manual sem loop de retorno | Relatório 2026-06-10 (`pii_access_log` ✓) |

## 2. Decisões ratificadas (PM 2026-06-10/11 + council folds)

1. **Verificação operacionalizada via Capítulo SEDE (PMI-GO)** — Diretoria de Filiação
   (Welma Alves). A sede verifica TODOS os membros do Núcleo, de qualquer capítulo.
2. **Capítulos parceiros = visibilidade, não operação** — e no **v1 SÓ AGREGADOS**
   (counts por status). Lista nominal = F2.1, gated em pré-requisitos jurídicos (§6.3).
3. **Radar de renovação da filiação é obrigatório** (F3).
4. **Re-sync VEP antes de qualquer relatório/reunião** com diretorias.
5. **Termo v2.7 não exige dados novos do assinante** (0 ocorrências de CPF no draft;
   identificação via `{chapterName}` + nome/e-mail + evidência hash/IP/UA). Atenção ao regime
   EEE/UK (cláusulas 13/14 → #573) se algum assinante residir fora do Brasil.
6. **Versionamento**: documentos aprovados entram como **v0 real** (numeração de draft não migra).
7. **Autoridade (decidido AGORA, não na implementação)**: Welma = engagement
   `chapter_board/liaison` no PMI-GO (kind sem termo de voluntário; ADR-0042 já dá
   `view_chapter_dashboards`) **+ designation `diretoria_filiacao`**. O RPC de verificação
   gateia na **designation** (Path 2 do `V4_AUTHORITY_MODEL.md`) com escopo inline (Path 3)
   — **NÃO criar seed novo em `engagement_kind_permissions`** (anti-pattern documentado).
   PM/superadmin via `manage_member` como sempre.
8. **Gate do termo no v1 = FAROL, não bloqueio** — bloquear sobre um campo que nunca foi
   escrito travaria a coorte inteira antes do loop operar. A assinatura grava
   `affiliation_unverified=true` nos metadados do audit (permite ao v2 distinguir termos
   pré-loop × pós-loop ao avaliar a política de bloqueio).
9. **Cache `members.pmi_id_verified` = atualizado pelo RPC no v1** (não trigger):
   `pmi_id_verified := p_active AND (p_expires_on IS NULL OR p_expires_on > CURRENT_DATE)`
   como efeito do INSERT. Trigger só se surgirem outros caminhos de escrita (aí ADR-0012).
10. **Enquadramento LGPD (PM 2026-06-11 — supersede o council legal HIGH do §6.2 v2)**:
    filiação é domínio institucional do CAPÍTULO → **PMI-GO = controladora** dos dados de
    filiação; **plataforma = operadora** (direção do RF-E/parecer 2026-04-19, que o council
    citou invertido). A Diretora de Filiação atua como **agente autorizada nominal da
    controladora** — não como operadora; o instrumento dela é confidencialidade + designação
    nominal, não DPA. Ver §6.2.

## 3. Atores e contatos institucionais (sede PMI-GO)

| Papel no loop | Diretoria / contato |
|---|---|
| **Verificador operacional** (escreve na plataforma) | Diretoria de Filiação — `filiacao@pmigo.org.br` · Welma Alves `welma@pmigo.org.br` |
| Consumidor primário do status | Diretoria de Voluntariado — `diretoriavoluntariado@pmigo.org.br` |
| Patrocínio/escalação | Presidência (Ivan Lourenço `ivan.lourenco@pmigo.org.br`) · `vice-presidencia@pmigo.org.br` |
| Interlocução com capítulos parceiros | Relações Institucionais — `relacoesinstitucionais@pmigo.org.br` |
| Demais (informativo) | Certificação `certificacao@pmigo.org.br` · Desenv. Profissional `desenvolvimento.profissional@pmigo.org.br` · Eventos `diretoria.eventos@pmigo.org.br` · Adm/Finanças `diretoria.financas@pmigo.org.br` |
| **Capítulos parceiros** (visibilidade agregada v1) | Diretorias de filiação + voluntariado de cada capítulo conveniado (Acordos de Cooperação vigentes) |

## 4. Modelo de dados

### 4.1 Nova tabela `member_affiliation_verifications` (histórico append-only)

```sql
id uuid PK · organization_id (ADR-0004, FK RESTRICT) · member_id FK members
verified_by_member_id FK members           -- quem da sede verificou
chapter_verified text                      -- capítulo confirmado na verificação
membership_active boolean                  -- filiação ativa no momento da verificação
membership_expires_on date NULL            -- ⚓ âncora do radar de renovação (F3)
method text CHECK (method IN ('vep_sync','sede_manual','self_attested'))
source_ref text NULL                       -- APENAS identificador técnico (lote/relatório); nunca texto livre sobre pessoas
verification_obs text NULL CHECK (char_length(verification_obs) <= 500)
                                           -- observação EXCLUSIVAMENTE sobre o resultado da
                                           -- verificação; UI exibe aviso "não incluir dados
                                           -- pessoais além do necessário" (council legal MEDIUM)
created_at timestamptz DEFAULT now()
```
- **Append-only** (re-verificação = nova linha; o histórico é a trilha).
- RLS deny-all + acesso exclusivamente via SECURITY DEFINER RPCs (GC-162).
- `COMMENT ON TABLE`: retenção (5y de inatividade do membro), campos anonimizados vs retidos,
  referência à entrada do RoPA.
- **Anonimização (critério de aceitação F1, não "confirmar depois")**: a migration estende o
  escopo do cron LGPD — `member_id`/`verified_by_member_id` → UUID neutro, `verification_obs`
  → NULL, `source_ref` → hash; `chapter_verified` + `membership_expires_on` mantidos
  (estatística não-nominal). Cuidado ADR-0076 Risco 2: o cron usa UPDATE, não cascata de FK.
- **Direito de acesso (Art. 18 II)**: `export_my_data()` passa a incluir as linhas de
  verificação do titular (incl. `verification_obs` — dado de terceiro sobre o titular).

### 4.2 Autoridade — DECIDIDA (ver §2.7)

Designation `diretoria_filiacao` + escopo inline no RPC. Sem seed novo em
`engagement_kind_permissions`. Provisionamento da Welma = critério de aceitação F1 (§8).

## 5. Superfícies (fases)

### F1 — Loop de verificação (prioridade)
- **RPC `verify_member_affiliation(p_member_id, p_chapter, p_active, p_expires_on, p_method, p_obs)`**
  — gate por designation (§2.7); INSERT na tabela; atualiza cache (§2.9); `admin_audit_log`
  (`affiliation.verified`); `pii_access_log` quando a chamada envolver leitura nominal prévia.
- **RPC batch `verify_member_affiliations_bulk(p_member_ids uuid[], ...)`** (council HIGH):
  a fila exibe `vep_status_raw` + `vep_last_seen_at` inline (já presentes no
  `admin_list_members`) e permite seleção múltipla + "marcar como verificado via VEP"
  (`method='vep_sync'`) num clique — sem isso, "25 em ≤1h" é irreal (seria navegação +
  conferência manual × 25).
- **Fila de verificação** em `/admin/members` (aproveita o filtro `pre_onboarding` de #626).
- **Farol no gate do termo** (§2.8) — sem bloqueio no v1.

### F2 — Painel de visibilidade por capítulo (AGREGADOS no v1)
- RPC `get_chapter_member_dimension(p_chapter)` → **somente counts** por status de exibição
  (ativos operando, pré-onboarding, onboarding, alumni, desligados). Sem PII no v1.
- Acesso: `chapter_board` do capítulo vê **só o próprio capítulo**; sede vê consolidado.
- **Limitação documentada (council HIGH)**: o filtro usa `members.chapter` (single) — membros
  multi-capítulo (≥5 hoje) aparecem APENAS no capítulo declarado no perfil. A investigação
  do modelo multi-capítulo é **pré-requisito da camada 2 do #625**; se a camada 2 mudar o
  modelo (junction), F2 é re-avaliado. Não construir silenciosamente sobre o single-value.
- **F2.1 (lista nominal p/ parceiros) — gated em 4 pré-requisitos**: (a) cláusula de
  compartilhamento adicionada via emenda §7 ou anexo no Manual de Governança (texto-modelo no
  §6.3 — os acordos assinados NÃO têm cláusula de dados hoje), (b) RoPA atualizado,
  (c) `pii_access_log` em toda chamada nominal, (d) **emenda na política de privacidade** —
  `/privacy` S4 + S3 (linha "Acompanhamento por diretorias de capítulos parceiros") hoje
  prometem "dados agregados por capítulo (sem PII individual)"; lista nominal sem emenda
  publicada violaria a promessa.

### F3 — Radar de renovação de filiação
- **Cron NOVO `v4_notify_expiring_affiliations`** (council MEDIUM: NÃO estender
  `v4_notify_expiring_engagements` — opera em tabela diferente; apenas SEGUE o padrão dele):
  lê `membership_expires_on`, D-30/D-7, **`p_dry_run=true` até sign-off do PM** (lição Gap-1).
- Template da notificação (ADR-0076 §9): remetente identificado, referência ao requisito de
  filiação do termo, **link de opt-out dos lembretes** (não do voluntariado).
- Farol no card do membro (verde vigente · amarelo ≤30d · vermelho vencida/não-verificada).

## 6. LGPD / governança do compartilhamento

### 6.1 Bases legais (duais, registradas no RoPA — council legal LOW)
- **Pré-onboarding**: Art. 7º, II (procedimento preparatório a contrato) + Art. 7º, IX
  (legítimo interesse em verificar elegibilidade) — **com LIA documentada** (ADR-0076 Princ. 2).
- **Membro ativo / renovação (F3)**: Art. 7º, V (execução do termo de voluntariado vigente,
  que exige filiação PMI ativa) + Art. 7º, IX (radar) — a notificação D-30/D-7 referencia a
  cláusula do termo.
- **Transparência (Art. 9º, I)**: para a SEDE, a verificação é tratamento próprio da
  controladora (PMI-GO) — não "compartilhamento" (§6.2). O termo v2.7+ (ou notificação de
  onboarding) informa (a) o tratamento do status de filiação pela Diretoria de Filiação do
  PMI-GO e (b) para membros de capítulos PARCEIROS, que "dados de participação podem ser
  compartilhados com o capítulo PMI de filiação do membro para fins de gestão de
  voluntariado" (§6.3).

### 6.2 Cadeia de agentes de tratamento (REFRAME PM 2026-06-11 — supersede o council legal HIGH do v2)

> **Correção registrada**: o texto v2 desta seção enquadrava a Welma como "operadora em nome
> do Núcleo" citando o RF-E como autoridade — o RF-E diz o OPOSTO: "DPA formal entre PMI-GO e
> plataforma nucleoia.vitormr.dev... contrato escrito **controlador↔operador**" (parecer
> 2026-04-19). PMI-GO = controladora; plataforma = operadora. A Diretora de Filiação ver se o
> filiado está em dia/ativo e de qual capítulo é o exercício NORMAL do domínio institucional
> do capítulo — não um tratamento terceirizado.

#### 6.2.1 Cadeia de controle

| Camada | Papel | Fontes |
|---|---|---|
| PMI Global | Sistema de registro da filiação (ThoughtSpot); dado de membro é **propriedade do PMI** cedida ao capítulo para o negócio do capítulo | Policy Manual ed. julho/2025: "Ownership of information" (§6.11), "Chapter use of PMI membership information and data" (§6.2) |
| **PMI-GO (sede)** | **CONTROLADORA** — filiação é domínio institucional do capítulo; entidade juridicamente responsável pelo Programa | Política de PI v2.2 §1.1/§2.1 ("capítulo sede e controlador dos dados tratados no âmbito do Programa"); Termo v2.2 Cl. 9 §2 ("PMI-GO, na condição de controlador"); `/privacy` S1 (CNPJ 06.065.645/0001-99 · DPO Ivan Lourenço Costa / Angeline Prado substituta, dpo@pmigo.org.br) |
| **Plataforma** (nucleoia.vitormr.dev) | **OPERADORA** — trata por conta da controladora (direção do RF-E); operadores de infraestrutura = Supabase/Cloudflare/etc. (`/privacy` S4) | RF-E (parecer 2026-04-19); `/privacy` S4 |

- O **Núcleo não tem personalidade jurídica** (Política de PI v2.2 §1.1; os 4 acordos o definem
  como projeto "sob a liderança do PMI Goiás") → **nunca é parte de instrumento**. O v2 citava
  "Acordos de Cooperação PMI-GO×Núcleo" — instrumento que não pode existir; os Acordos reais
  são bilaterais PMI-GO×capítulo-parceiro.
- Nunca escrever "PMI-GO é dona do dado": a formulação é **controladora localmente responsável**
  pelo domínio de filiação do capítulo, dentro de cadeia em que o dado de membro permanece
  propriedade do PMI (Policy Manual ed. julho/2025 §6.11-6.13, com deveres de devolução/deleção).

#### 6.2.2 Recorte de escopo (mesma controladora, fontes de dever distintas)

| Fatia | Regime de deveres |
|---|---|
| **Dados de filiação PMI** (status, capítulo, expiração — trilho ThoughtSpot/VEP) | Deveres do sistema PMI: uso restrito ao negócio do capítulo, sem compartilhamento fora de PMI/capítulo sem permissão escrita do President & CEO (§6.2); opt-out honrado com record-keeping (§6.4/§6.6); venda proibida (§6.10); confidencialidade + devolução no término (§6.11-6.13). **Gate**: Attachments D-G do Charter Agreement (DPA/Model Clauses incorporados por referência, §6.2 ¶2) verificados sob LGPD ANTES de dado linha-a-linha do trilho do capítulo entrar na plataforma — o v1 deste spec NÃO sincroniza ThoughtSpot (usa VEP + verificação manual); o gate D-G pertence ao trilho pmigo/Onda 2 (cf. #617). Nota: o registro `member_affiliation_verifications` inserido pela Welma é dado GERADO PELO NÚCLEO (linha de baixo) — não uma linha do ThoughtSpot |
| **Dados gerados pelo Núcleo** (participação, XP, `verification_obs`, trilha de auditoria) | Deveres LGPD puros sob a política de privacidade do PMI-GO: bases duais (§6.1), RoPA, direitos Art. 18, retenção/anonimização (§4.1) |

#### 6.2.3 Welma = agente autorizada nominal da controladora (NÃO operadora) — PRÉ-REQUISITO de F1

Pessoa natural agindo sob autoridade direta do controlador (diretora do capítulo) É o
controlador agindo — não agente de tratamento separado. **Âncora LGPD**: o Art. 5º, VII define
"operador" como quem trata "em nome do controlador" — pressuposto que se aplica a terceiros;
agentes internos (diretores, voluntários em cargo fiduciário) operam dentro do domínio do
próprio controlador, e o instrumento aplicável é disciplina interna de acesso, não DPA
(consistente com RGPD Art. 29 e com o Guia ANPD de Agentes de Tratamento, 2021). Acesso de
líder a dado de membro é o modo sancionado pelo próprio PMI (acesso diário via ThoughtSpot —
Policy Manual ed. julho/2025, "Membership and prospect database information policy" §6.3). **Antes do acesso de escrita**
(itens (1)-(5) do council v2 SOBREVIVEM, recast como disciplina interna de acesso):
1. **Confidentiality & Records Compliance Agreement** assinado — o instrumento anual que o PMI
   prescreve para voluntários em papéis fiduciários ("Chapter volunteer onboarding package"
   §2.5.6; template oficial no acervo do PMO) — customizado: referência LGPD + deleção-na-saída
   + cláusula de sobrevivência;
2. **Registro nominal da assinatura** + designation `diretoria_filiacao` (§2.7) — o acesso
   segue o CARGO, não a pessoa (espelha "Maintenance of officer listings" §2.7.3 e a revogação
   de acesso pelo PMI em §14.2-14.3);
3. **Finalidade restrita** ao loop de verificação + **vedação de uso próprio** ("Unpermitted
   use of membership data" §6.6);
4. **`pii_access_log` em toda leitura/escrita nominal** (Art. 37; logging exigido também por
   "Activity monitoring" §4.9.10);
5. **Revogação ao deixar o cargo** + submissão às políticas de segurança da plataforma.

#### 6.2.4 Controladora ↔ operadora (o instrumento RF-E)

- O DPA do RF-E é **PMI-GO ↔ plataforma** — e o pacote jurídico revisado JÁ contém um DPA
  ("Instrumento nº 9"; cf. QA/QC 2026-06-09). **Verificar as partes desse instrumento** antes
  de comissionar qualquer instrumento novo. Acompanha o workstream platform-readiness
  (e-mail legal G12) — não bloqueia F1, que usa VEP + verificação manual (ver gate §6.2.2).
- Tensão a resolver com o advogado licenciado: a Política de PI v2.2 §2.5.3 e o Termo v2.2
  Cl. 14.1 declaram os servidores "operados pelo PMI-GO como controlador" (leitura: plataforma
  = sistema próprio do controlador; operadores = vendors de infra, como publica `/privacy` S4).
  As duas leituras convergem na prática; a escolha define quem assina o quê no Instrumento nº 9.
- Restrições de vendor que o instrumento espelha: uso/retenção limitados ao negócio do capítulo
  ("Personal Data Protection" §4.9.12); atestação independente de segurança ("Chapter vendor
  and third-party security" §4.9.16 — SOC 2 Supabase/Cloudflare); cascata de incidente
  plataforma → capítulo → canal PMI Chapter Support ("Incident reporting" §4.9.13); contas de
  infraestrutura organizacionais com MFA + offboarding (Volunteer Digital Technology Systems
  Policy rev. out/2024 §3.1.5).

#### 6.2.5 Pendências para o advogado licenciado

(i) Partes do Instrumento nº 9 — cobre o RF-E (PMI-GO↔plataforma)? (ii) aplicação dos
Attachments D-G do Charter Agreement sob LGPD (gate pré-trilho, §6.2.2); (iii) o caveat de
co-controle do v2 foi MOVIDO para o eixo federado (§6.3) — um órgão do capítulo não pode ser
controlador conjunto da própria entidade; a questão só é real entre capítulos (nota: a LGPD
não tem figura expressa de controladoria conjunta; a referência correta é o co-controle
fático do Guia ANPD de Agentes de Tratamento 2021 — o Art. 42, §1º citado no v2 trata de
responsabilidade solidária, não de co-controle); (iv) cadeia de notificação de incidente
(plataforma → PMI-GO → DPO → ANPD se aplicável) com prazo interno documentado em instrumento
formal (Instrumento nº 9 ou manual de incident response) — o v2 propunha 24h interno; o
Art. 48 LGPD rege a comunicação à ANPD/titular.

### 6.3 Compartilhamento com capítulos parceiros (eixo federado — controladora↔controladora)

Cada capítulo parceiro (MG/CE/DF/RS) é **controlador dos dados de filiação dos PRÓPRIOS
membros**; PMI-GO é controladora dos dados de PARTICIPAÇÃO no Núcleo desses membros (aderem ao
Programa sob a política do PMI-GO — Política de PI v2.2 §2.2). F2.1 (lista nominal de volta ao
parceiro) é portanto **compartilhamento controladora→controladora**, permitido pelo Policy
Manual ed. julho/2025 ("Member list exchanges among chapters" §6.8 — permissivo, com 2
condições: finalidade chapter-sponsored + exclusão de opt-outs).

**Fato verificado (full-text dos 4 instrumentos assinados, 2026-06-11): os Acordos GO↔MG
(2025-12-08), GO↔CE e GO↔DF (2025-12-09) e GO↔RS (2025-12-10) NÃO contêm nenhuma cláusula de
dados** — zero ocorrências de LGPD/dados pessoais/controlador/operador/tratamento/plataforma;
a única âncora é a confidencialidade genérica do §7 ("informações estratégicas ou sensíveis").
A cláusula-modelo abaixo precisa ser **ADICIONADA**, por um de dois caminhos (ambos previstos
nos próprios acordos):
- **Emenda via §7** ("formalmente validada pelos representantes legais... registrada para
  efeito de auditoria") — 4 instrumentos bilaterais a emendar; ou
- **Anexo de governança de dados no Manual de Governança do Núcleo IA** — os 4 acordos o
  incorporam por referência (Preâmbulo, §2, §4 e §7: "rege-se... pelos regulamentos estipulados
  no Manual de Governança") — 1 documento. **Caminho recomendado.**

v1 = agregados (sem base contratual nova necessária). Para F2.1 (nominal), cláusula-modelo:
> "O PMI-GO, por intermédio da sua plataforma de gestão de voluntariado (nucleoia.vitormr.dev),
> poderá compartilhar com a Diretoria de Filiação e de Voluntariado do CAPÍTULO a relação
> nominal de membros filiados ao CAPÍTULO que estejam participando do Programa Núcleo IA,
> incluindo status de participação e situação de filiação PMI, para fins exclusivos de
> coordenação de voluntariado e renovação de filiação, vedado uso para fins próprios do
> CAPÍTULO, excluídos os membros que tenham exercido o direito de opt-out de divulgação de
> seus dados de contato, com devolução ou eliminação dos dados ao término da parceria ou em
> prazo não superior a 30 (trinta) dias após a solicitação por qualquer das partes."

(Δ vs v2: a parte empoderada é o **PMI-GO** — "O Núcleo IA" não é pessoa jurídica e não pode
ser designado instrumento de representação; "Programa Núcleo IA" mantém a marca sem atribuir
personalidade; adicionadas a exclusão de opt-outs (condição do §6.8, linguagem Art. 18 LGPD)
e o destino do dado no término com prazo — o §6 dos acordos é perpétuo com saída de 30 dias e
silente sobre dados. Council legal 2026-06-11.)

**Notas federadas**: (a) só o acordo GO↔CE ratifica retroativamente a parceria desde o ciclo
2025; MG/DF/RS cobrem do Ciclo 3 (2026-1) em diante; (b) questão a levar ao PMI Chapter
Engagement (canal indicado em §6.6) ANTES do F2.1: uma plataforma operada para ~15 capítulos
permanece em §6.8 (capítulo↔capítulo) ou tangencia §6.9 (regime de entidades não-PMI, que
exige comunicação prévia ao PMI)?; (c) **co-controle fático** (figura do Guia ANPD de Agentes
de Tratamento 2021 — a LGPD não tem artigo expresso de controladoria conjunta; não confundir
com a responsabilidade solidária do Art. 42, §1º) — caveat movido do §6.2 para cá: avaliar
com o advogado SE os parceiros passarem a determinar finalidades/meios do loop (ex.: campanhas
próprias de renovação via plataforma) — hoje não é o caso;
(d) citar os acordos pela data de assinatura (o corpo do GO↔MG traz "2026" por typo);
a numeração deles salta o §5 em todos os 4 (vai de §4 a §6).

### 6.4 Minimização e trilha
Relatórios por capítulo contêm SÓ os membros daquele capítulo; consolidado só para a sede.
Campos mínimos por finalidade. Todo export/leitura nominal → `pii_access_log` (Art. 37) —
já praticado (relatório 2026-06-10, 25 leituras logadas). Telefone: coletar no onboarding com
finalidade declarada; armazenar em `phone_encrypted`.

## 7. Fora de escopo (v1)

- Write-back automático para o VEP/PMI (verificação é interna; VEP segue fonte de leitura).
- Multi-organização.
- Lista nominal para parceiros (= F2.1, gated §6.3).
- `selection_applications.membership_status`: permanece órfã no v1 (não escrever nela);
  depreciação ou backfill em follow-up próprio (**filar issue de tracking** — council NIT).
- Modelo multi-capítulo no perfil (pré-requisito de investigação da camada 2 do #625).

## 8. Critérios de aceitação

- **F1**:
  - [ ] Welma provisionada (`chapter_board/liaison` PMI-GO + designation `diretoria_filiacao`)
        e smoke: auth dela chama `verify_member_affiliation` com sucesso (council LOW — sem
        isso F1 passa no teste e nasce morto em produção)
  - [ ] **Confidentiality & Records Compliance Agreement assinado + registro nominal da
        designação ANTES do acesso de escrita** (§6.2.3 — instrumento de agente interno da
        controladora; NÃO é DPA)
  - [ ] Instrumento RF-E (DPA PMI-GO↔plataforma) endereçado: partes do "Instrumento nº 9"
        verificadas com o jurídico (§6.2.4 — corre no workstream platform-readiness, não
        bloqueia F1)
  - [ ] Fila com VEP inline + ação bulk: 25 membros verificáveis em ≤1h REAL
  - [ ] `pmi_id_verified` reflete via RPC (§2.9); trilha completa (quem/quando/método)
  - [ ] Migration estende o cron LGPD para a nova tabela (§4.1 — critério, não "confirmar depois")
  - [ ] `export_my_data()` inclui as verificações do titular
  - [ ] Assinatura do termo grava o estado do farol nos metadados (§2.8)
- **F2**: parceiro vê SÓ agregados do próprio capítulo; sede vê consolidado; limitação
  single-chapter documentada na superfície.
- **F3**: farol ≥30 dias antes; zero notificação em dry-run até sign-off; template com
  remetente/base/opt-out (ADR-0076 §9).

## 9. Perguntas abertas (PM) — reduzidas pós-council

1. ~~Farol ou bloqueio~~ → **FAROL no v1** (decidido, §2.8).
2. ~~Kind da Welma~~ → **`chapter_board/liaison` + designation** (decidido, §2.7) — resta o
   Confidentiality & Records Compliance Agreement customizado (§6.2.3) + verificação das
   partes do Instrumento nº 9 (§6.2.4) com o jurídico.
3. ~~Nominal ou agregados no F2~~ → **agregados no v1** (decidido; nominal = F2.1 gated).
4. Periodicidade da re-verificação em massa: anual no aniversário do ciclo, ou contínua via
   radar F3? (única pergunta remanescente — pode ser decidida no kickoff de F1).
