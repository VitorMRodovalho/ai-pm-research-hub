# RoPA + LIA — Verificação de Filiação PMI (#625 F1)

> **Registro de Operações de Tratamento (Art. 37 LGPD) + Avaliação de Legítimo Interesse
> (LIA, Art. 7º IX / Art. 10)** para o loop de verificação de filiação operado pela Diretoria
> de Filiação da sede (PMI-GO) na plataforma Núcleo IA.
>
> **Status:** RASCUNHO para ratificação do DPO/jurídico (gerado 2026-06-11 com o build do F1).
> **Controladora:** PMI Goiás (CNPJ 06.065.645/0001-99). **Operadora:** plataforma
> nucleoia.vitormr.dev. **DPO:** Ivan Lourenço Costa (titular) · Angeline Altair Silva Prado
> (substituta) — dpo@pmigo.org.br.
> **Refs:** SPEC_625 §6 · migrations `20260805000148` (loop) + `20260805000149` (ateste) ·
> ADR-0076 (PMI data / LIA / opt-out).

---

## 1. Registro da operação de tratamento (Art. 37)

| Campo | Conteúdo |
|---|---|
| **Operação** | Verificação e registro do status de filiação PMI dos membros do Programa Núcleo IA (ativa/inativa, capítulo, vencimento). |
| **Agente que trata** | Diretoria de Filiação do PMI-GO (cargo; titular atual: Welma Alves de Melo), agindo como **agente autorizado nominal da controladora** (não operadora — Guia ANPD de Agentes de Tratamento, 2021). |
| **Categorias de dado (Art. 5)** | Identificação (nome, e-mail), `pmi_id`, capítulo, status/vencimento de filiação PMI. **Sem dado sensível (Art. 5, II).** |
| **Titulares** | Membros e pré-onboarding do Programa (todos os capítulos federados). |
| **Finalidade** | Confirmar elegibilidade (filiação PMI ativa) exigida pelo Termo de Voluntariado; **e** monitorar a proximidade do vencimento da filiação para acionar o radar de renovação (notificações D-30/D-7 ao titular, com opt-out). |
| **Bases legais** | **Pré-onboarding:** Art. 7º, II (procedimento preparatório a contrato) + Art. 7º, IX (legítimo interesse — §3 abaixo). **Membro ativo / renovação:** Art. 7º, V (execução do Termo, que exige filiação ativa) + Art. 7º, IX. |
| **Retenção** | Enquanto o vínculo com o Programa existir; anonimização após 5 anos de inatividade do membro (cron `anonymize_inactive_members` — escopo estendido na mig 148). |
| **Destinatários** | Interno (Diretoria de Filiação + Voluntariado da sede). **Não há** compartilhamento nominal com capítulos parceiros no v1 (F2.1 gated — §6.3 da spec). |
| **Medidas de segurança (Art. 46)** | RLS deny-all + acesso só por RPCs SECURITY DEFINER; gate de autoridade por designation; **ateste de confidencialidade do agente** (§4); `pii_access_log` em toda leitura nominal (Art. 37); trilha append-only. |
| **Transparência (Art. 9º)** | Termo v2.7+ / notificação de onboarding informam o tratamento do status de filiação pela Diretoria de Filiação do PMI-GO. |

## 2. Direitos do titular (Art. 18)
Acesso/portabilidade (II) via `export_my_data()` — inclui as verificações do titular (com o nome
do verificador para contexto de eventual retificação, Art. 18, III). Correção (III), eliminação
quando aplicável (VI), e oposição/revisão da decisão de legítimo interesse (§ Art. 18 + Art. 20)
endereçadas via canal do DPO.

## 3. LIA — teste de legítimo interesse (Art. 7º IX c/c Art. 10)
*(Documentação recomendada pela ANPD; cf. ADR-0076 Princípio 2.)*

1. **Finalidade legítima, específica e informada.** Verificar que o voluntário/candidato cumpre
   o requisito de filiação PMI ativa — condição do Programa e do Termo de Voluntariado. Finalidade
   institucional do capítulo, não comercial; informada no Termo e nesta entrada do RoPA.
2. **Necessidade (minimização).** Trata-se do mínimo: status/capítulo/vencimento. Não há base
   menos invasiva — o requisito de filiação é intrínseco ao vínculo. Telefone/dados extras não
   entram nesta operação. A verificação usa VEP + conferência manual (não sincroniza o
   ThoughtSpot linha-a-linha no v1).
3. **Balanceamento (legítima expectativa × direitos do titular).** O titular adere a um programa
   de voluntariado PMI sabendo que a filiação é requisito — há expectativa legítima de que o
   capítulo verifique. Salvaguardas que pendem a balança para o titular: finalidade restrita +
   vedação de uso próprio (ateste §4), `pii_access_log`, RLS deny-all, opt-out dos lembretes de
   renovação (não do voluntariado), **oposição ao tratamento de verificação exercível pelo canal
   do DPO (Art. 18, §2º), com avaliação de impacto na continuidade do vínculo voluntário**,
   retenção limitada + anonimização. Risco residual baixo;
   nenhum dado sensível; sem decisão automatizada com efeito jurídico (a verificação é humana).

**Conclusão:** legítimo interesse adequado como base (combinado com Art. 7º II/V conforme a fase),
sujeito às salvaguardas acima. Ratificação do DPO pendente.

## 4. Disciplina interna de acesso do agente — o ateste (§6.2.3 da spec)
O acesso de escrita ao loop exige um **ateste digital de confidencialidade/finalidade**, vigente
e logado (mig 149: `attest_affiliation_access` + trigger `trg_affiliation_attestation`), com
re-aceite anual. Ele **operacionaliza** (não substitui) o instrumento do cargo (Confidentiality
& Records Compliance Agreement do PMI, por força do cargo — Policy Manual ed. jul/2025 §6.3/§2.5.6).
`manage_member` (PM/superadmin) é isento (não é o agente fiduciário do loop).

### Texto canônico do ateste (exibido no modal de 1ª entrada / re-aceite — versão `v1-2026-06-11`)
> **Acesso à verificação de filiação — área de dados pessoais de terceiros**
>
> Você vai acessar e registrar dados de **filiação PMI de membros** (status, capítulo,
> vencimento) — dado pessoal de terceiros, do qual o **PMI Goiás é o controlador** e esta
> plataforma é operadora.
>
> Como agente autorizado da Diretoria de Filiação do PMI Goiás, você confirma que compreende e
> assumiu as seguintes obrigações no exercício do seu cargo:
> - **Finalidade restrita** — usar estes dados exclusivamente para o loop de verificação de
>   filiação do Programa Núcleo IA;
> - **Vedação de uso próprio** — não usar, copiar ou compartilhar os dados para qualquer fim
>   alheio a essa finalidade;
> - **Confidencialidade** — as obrigações de confidencialidade e de tratamento de registros do
>   seu cargo (acordo de voluntário fiduciário do PMI) e as políticas de segurança da plataforma;
> - **Base legal e registro** — o tratamento se apoia em legítimo interesse do PMI Goiás
>   (Art. 7º, IX LGPD) e na execução do Termo de Voluntariado (Art. 7º, V); todo acesso nominal é
>   registrado (Art. 37 LGPD), com data, autoria e evidência técnica do aceite (navegador; e
>   endereço IP quando disponível), retida como prova do ato;
> - **Validade condicionada ao cargo** — este aceite vincula-se ao exercício do cargo na Diretoria
>   de Filiação; ao deixar o cargo, o acesso é revogado independentemente do prazo de 12 meses.
>
> Este aceite vale por 12 meses ou até a renovação do mandato do cargo, o que ocorrer primeiro, e
> é renovável.
>
> ☑ **Declaro estar ciente e de acordo.**

## 5. Pendências para o DPO / advogado licenciado
- Ratificar este RoPA + LIA (assinatura/registro do DPO).
- Confirmar que o Confidentiality & Records Compliance Agreement do cargo cobre o contexto LGPD
  brasileiro da plataforma (ou se um addendum é desejável) — não bloqueia o ateste digital, refina.
- DPA controladora↔operadora ("Instrumento nº 9" do pacote) corre no workstream platform-readiness
  (§6.2.4 da spec) — não bloqueia F1.
