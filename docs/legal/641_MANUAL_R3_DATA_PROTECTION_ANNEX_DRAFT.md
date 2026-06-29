# Anexo R3 — Protecao de Dados em Cooperacao Federada (#641)

> **Status:** RASCUNHO operacional para Manual de Governanca R3. Linguagem juridica final
> bloqueada por retorno G12 / advogado licenciado.
>
> **Origem:** decisao registrada no #628, SPEC-625 §6.2/§6.3. Os 4 acordos bilaterais
> assinados PMI-GO ↔ PMI-CE/DF/MG/RS nao contem clausulas especificas de dados pessoais.
> O caminho recomendado foi incorporar disciplina de dados via Manual de Governanca R3,
> que os acordos incorporam por referencia, em vez de abrir 4 emendas bilaterais separadas.
>
> **Nao e aconselhamento juridico.** Este texto e um esqueleto para revisao juridica,
> baseado no enquadramento ja aprovado no #628 e em referencias ANPD/PMI citadas na spec.

## 1. Finalidade do anexo

Estabelecer a disciplina minima de protecao de dados pessoais para a cooperacao federada
entre o PMI-GO, como capitulo sede do Programa Nucleo IA, e os capitulos parceiros que
aderem ao Programa por acordos bilaterais de cooperacao.

O anexo cobre:

- tratamento de dados de participacao no Programa;
- verificacao de filiacao PMI e radar de renovacao;
- compartilhamento agregado com capitulos parceiros;
- condicoes futuras para compartilhamento nominal controladora-controladora;
- clausula-modelo para novos acordos e aditivos.

## 2. Premissas juridico-operacionais

1. O Nucleo IA nao possui personalidade juridica propria. Para fins contratuais e de
   protecao de dados, o Programa opera sob a lideranca institucional do PMI-GO, capitulo
   sede.
2. O PMI-GO e controlador dos dados tratados no contexto de participacao no Programa e
   da plataforma operacional do Nucleo IA, conforme politica de governanca vigente.
3. Cada capitulo parceiro e controlador dos dados de filiacao dos seus proprios membros.
4. A plataforma `nucleoia.vitormr.dev` atua como operadora em relacao ao tratamento
   realizado por conta do PMI-GO, nos limites do instrumento especifico PMI-GO ↔ plataforma.
5. Diretores, pontos focais e demais representantes que acessam dados pessoais atuam como
   agentes autorizados da respectiva controladora, nao como operadores independentes.
6. Compartilhamento nominal com capitulos parceiros nao e habilitado por padrao no v1;
   permanece gated como F2.1 no SPEC-625.

## 3. Agentes de tratamento e papeis

| Contexto | Controladora | Operadora / agente autorizado | Observacao |
|---|---|---|---|
| Participacao no Programa Nucleo IA | PMI-GO | Plataforma Nucleo IA, quando processa dados por conta do PMI-GO | Dados de onboarding, voluntariado, governanca, comunicacao, gamificacao e participacao. |
| Verificacao de filiacao PMI | PMI-GO | Diretoria de Filiacao do PMI-GO como agente autorizado nominal | Nao e DPA; exige ateste de finalidade/confidencialidade e trilha de acesso. |
| Dados de filiacao de membros de um capitulo parceiro | Capitulo parceiro correspondente | Seus representantes autorizados | O capitulo parceiro segue controlador dos seus proprios registros de filiacao. |
| Relatorio agregado por capitulo | PMI-GO | Plataforma Nucleo IA | Sem lista nominal no v1; dados por capitulo apenas em agregados. |
| F2.1 nominal futuro | PMI-GO + capitulo parceiro, conforme caso concreto | Plataforma Nucleo IA se processar a lista | Compartilhamento controladora-controladora, sujeito a base, finalidade, opt-out, DPO e registro. |

## 4. Regras minimas para tratamento

### 4.1 Finalidade

Os dados pessoais tratados no ambito da cooperacao federada somente podem ser usados para:

- executar o Programa Nucleo IA;
- verificar elegibilidade e status de filiacao PMI quando isso for requisito do Programa;
- coordenar voluntariado, governanca, certificacoes, comunicacao e acompanhamento operacional;
- prestar contas aos capitulos parceiros em nivel agregado;
- cumprir obrigacoes legais, auditoria e direitos dos titulares.

Fica vedado o uso para campanhas proprias, prospeccao comercial, envio massivo ou finalidade
estranha ao Programa sem base juridica propria, transparencia adequada e registro da decisao.

### 4.2 Minimizacao

Cada relatorio, exportacao ou tela deve limitar os campos ao minimo necessario para a
finalidade aprovada. No v1:

- capitulos parceiros recebem apenas indicadores agregados do proprio capitulo;
- a sede pode operar visao consolidada;
- listas nominais para parceiros permanecem bloqueadas ate a F2.1;
- telefone e dados de contato ampliados exigem finalidade expressa de onboarding ou operacao.

### 4.3 Transparencia e direitos do titular

O Programa deve manter informacoes claras sobre:

- quem e a controladora;
- quais dados sao tratados;
- finalidade de verificacao de filiacao e participacao;
- canal do DPO;
- direitos previstos na LGPD, incluindo acesso, correcao, oposicao e eliminacao quando aplicavel.

Exportacoes de dados do titular devem incluir registros de verificacao de filiacao e eventos
de governanca pessoalmente relacionados ao titular.

### 4.4 Auditoria e seguranca

Leituras nominais, exportacoes e alteracoes em dados de filiacao devem gerar trilha de auditoria
com, no minimo, ator, titular, finalidade, data/hora e superficie tecnica. A plataforma deve
manter:

- RLS e RPCs SECURITY DEFINER para superficies sensiveis;
- logs de acesso nominal em `pii_access_log` ou trilha equivalente;
- ateste anual de confidencialidade/finalidade para agentes autorizados;
- revogacao de acesso ao termino do cargo ou da necessidade operacional;
- retencao e anonimização conforme politica vigente.

## 5. Eixo federado: compartilhamento com capitulos parceiros

### 5.1 Regime v1 — agregados

No v1, o compartilhamento com capitulos parceiros e limitado a agregados do respectivo
capitulo, sem exposicao de lista nominal. Exemplos permitidos:

- quantidade de membros ativos por capitulo;
- presenca media agregada;
- certificacoes e producao agregadas;
- riscos operacionais em nivel nao identificavel.

### 5.2 F2.1 — nominal futuro, gated

Qualquer compartilhamento nominal com capitulo parceiro exige decisao especifica antes da
ativacao. O pacote minimo de aprovacao deve conter:

1. finalidade exclusiva e documentada;
2. campos estritamente necessarios;
3. confirmacao de opt-out quando aplicavel;
4. base legal e registro RoPA/LIA ou instrumento equivalente;
5. DPO/juridico ciente;
6. prazo de devolucao, eliminacao ou expiracao do acesso;
7. trilha de auditoria de exportacao/leitura.

Enquanto esses itens nao forem aprovados, a plataforma deve permanecer em agregados-only para
capitulos parceiros.

### 5.3 Auditor institucional externo — eixo distinto, agregado program-wide, gated

Alem do eixo sede↔capitulo parceiro (§5.1/§5.2), o Programa pode conceder a um **orgao institucional
externo** da rede PMI (ex.: PMI LATAM, PMI Global, iniciativa PMIxAI) um acesso de **leitura agregada
program-wide** para fins de prestacao de contas (accountability) institucional — caso de uso: a
apresentacao do LIM.

Esse eixo e **distinto** do compartilhamento com capitulos parceiros e nao se confunde com ele:

- o auditor institucional **nao e capitulo parceiro** — nao possui membros no Programa e nao e
  controlador de nenhum dado tratado aqui; e **destinatario** de agregados, nao agente de tratamento;
- recebe **apenas indicadores agregados** program-wide, **sem dado pessoal individual por construcao**
  (allowlist de 8 RPCs SECDEF zero-PII verificadas — ADR-0111), sem recorte nominal de capitulo, sem
  dados de selecao, sem escrita. O PMI-GO adota supressao de celula pequena (k-anonimato) quando algum
  subgrupo for identificavel, conforme protocolado em
  `docs/legal/INSTITUTIONAL_AUDITOR_COOPERATION_AND_PROVISIONING.md` §2.3/§8 (garantia de processo, nao
  de resultado absoluto enquanto a supressao nao estiver implementada);
- o acesso e **GP-only para provisionar**, com **prazo (`end_date`) obrigatorio**, e **revogavel**;
- esta sujeito a um **gate de governanca proprio** (acordo de cooperacao + ciencia dos capitulos
  parceiros + ratificacao RoPA/LIA do DPO) antes do primeiro provisionamento.

Regime, RoPA/LIA, protocolo de provisionamento e template de ciencia dos capitulos parceiros estao
em `docs/legal/INSTITUTIONAL_AUDITOR_COOPERATION_AND_PROVISIONING.md` (#952 FU-4) e na implementacao
tecnica do ADR-0111 (`institutional_auditor` + `view_aggregate_analytics`, allowlist por construcao).
Enquanto esse gate nao for satisfeito, o tier permanece **dormante** (nenhum acesso concedido).

## 6. Incidentes e comunicacao

Incidentes envolvendo dados pessoais no contexto da cooperacao federada devem seguir cadeia
documentada:

1. identificacao tecnica ou operacional do incidente;
2. registro interno com hora, escopo, sistemas e categorias de titulares;
3. notificacao ao responsavel operacional do PMI-GO;
4. avaliacao do DPO sobre risco relevante;
5. comunicacao a ANPD e titulares quando exigida pela LGPD e orientacoes aplicaveis.

Prazos internos podem ser mais curtos que o prazo legal, mas nao substituem a avaliacao do
DPO sobre a comunicacao externa.

## 7. Clausula-modelo para novos acordos ou aditivos

> **Protecao de dados pessoais e compartilhamento federado.** As Partes reconhecem que o
> PMI-GO, na qualidade de capitulo sede do Programa Nucleo IA, trata dados pessoais dos
> participantes do Programa para fins de governanca, coordenacao de voluntariado, verificacao
> de elegibilidade, comunicacao operacional, certificacoes, gamificacao e prestacao de contas.
> Cada capitulo parceiro permanece controlador dos dados de filiacao de seus proprios membros.
>
> O PMI-GO, por intermedio da plataforma operacional do Programa, podera disponibilizar ao
> CAPITULO parceiro relatorios agregados sobre a participacao de seus membros no Programa,
> observados os principios de finalidade, adequacao, necessidade, seguranca, transparencia e
> responsabilizacao previstos na LGPD.
>
> Qualquer compartilhamento nominal de dados pessoais entre PMI-GO e CAPITULO parceiro
> dependera de finalidade especifica, base legal adequada, registro de tratamento, respeito a
> opt-outs aplicaveis, medidas de seguranca, restricao de acesso a agentes autorizados e prazo
> definido para devolucao, eliminacao ou expiracao do acesso, sendo vedado uso para finalidade
> propria alheia ao Programa sem novo fundamento juridico e nova transparencia ao titular.
>
> Os agentes autorizados das Partes que acessarem dados pessoais no contexto do Programa
> deverao observar confidencialidade, finalidade restrita, minimizacao e registro de acesso,
> respondendo a Parte correspondente por sua designacao, supervisao e revogacao de acesso.
>
> Em caso de incidente de seguranca envolvendo dados pessoais, as Partes cooperarao com a
> apuracao, mitigacao, preservacao de evidencias e comunicacao ao DPO, sem prejuizo das
> comunicacoes a titulares e autoridades competentes quando legalmente exigidas.

## 8. Checklist de incorporacao no Manual R3

- [ ] Confirmar com juridico se o Manual R3 e veiculo suficiente para incorporar o anexo aos
      4 acordos vigentes ou se algum parceiro exige emenda bilateral.
- [ ] Validar a clausula-modelo G12 antes de promover o Manual R3.
- [ ] Referenciar explicitamente os acordos PMI-GO ↔ PMI-CE/DF/MG/RS como instrumentos ja
      assinados e silentes sobre dados pessoais.
- [ ] Marcar F2.1 como "nominal gated" no roadmap operacional e na matriz de privacidade.
- [ ] Atualizar `/privacy` se algum compartilhamento nominal deixar de ser agregados-only.
- [ ] Registrar DPO/juridico e data da ratificacao na trilha de governanca.
- [ ] Garantir que o texto nao atribui personalidade juridica ao Nucleo IA.

## 9. Pendencias para G12

1. Linguagem final da clausula-modelo.
2. Confirmacao se "controladora-controladora" deve ser chamado de co-controle fatico ou
   compartilhamento entre controladoras no caso concreto.
3. Prazo interno de notificacao de incidente entre plataforma, PMI-GO e DPO.
4. Tratamento de opt-out em listas de filiacao PMI quando o dado vier de fonte institucional
   do capitulo parceiro.
5. Necessidade ou nao de emenda bilateral complementar para cada acordo assinado.

## 10. Referencias

- SPEC-625 §6.2/§6.3 — `docs/specs/SPEC_625_AFFILIATION_VERIFICATION_LOOP.md`.
- Issue/PR #628 — reframe PMI-GO controladora, plataforma operadora.
- Issue #641 — tracker deste anexo.
- RoPA/LIA #625 F1 — `docs/legal/RoPA_625_AFFILIATION_VERIFICATION_LIA.md`.
- Auditor institucional externo (§5.3) — `docs/legal/INSTITUTIONAL_AUDITOR_COOPERATION_AND_PROVISIONING.md` (#952 FU-4) + ADR-0111.
- ANPD — Guia Orientativo para Definicoes dos Agentes de Tratamento de Dados Pessoais e
  do Encarregado: https://www.gov.br/anpd/pt-br/centrais-de-conteudo/materiais-educativos-e-publicacoes/2021.05.27GuiaAgentesdeTratamento_Final.pdf
- ANPD — Comunicacao de Incidente de Seguranca:
  https://www.gov.br/anpd/pt-br/assuntos/comunicacao-de-incidentes-de-seguranca-cis
