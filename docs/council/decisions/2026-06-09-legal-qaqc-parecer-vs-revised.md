# Legal QA/QC — Parecer 01/2026 × pacote revisado do time (pré-devolução)

- **Date:** 2026-06-09 (workflow iniciado 2026-06-08; concluído na sessão clean)
- **PM directive:** *"não acreditar na versão final"* — QA/QC independente do pacote revisado (`~/Downloads/nucleo-juridico-revisado/`) contra o **Parecer Técnico-Jurídico 01/2026** (Aaron Chaves) ANTES de devolver a Angeline/Aaron. A devolução validada inicia o clock G12 (#334).
- **Method:** Workflow `wf_a8c876c6-a2a` (re-run endurecido contra throttle: ondas de 4 + retry 4×; o `parallel([...19])` original morreu 2× num rate-limit server-side). 19 auditores independentes: 12 por-rec (a–l) + 6 consistência + 1 validador de email. Achados decisivos re-verificados à mão (grep nos `.docx` convertidos + leitura do Parecer §3/§4). Working agreement `working-agreement-decision-process-2026-06-07`.

## Veredito
Pacote **substantivamente forte** (vários instrumentos *over-deliver*), mas **NÃO pronto para devolver como estava**. A contabilidade do email do time ("10/12 integrais + 2 divergências e/j") é **levemente otimista** — internamente o time já reconhecia **3** divergências (e, j, art.49). Contagem honesta: **8 integrais + 2 divergências (e, j) + 2 substancialmente acolhidas (c, i)** + 1 correção editorial (art.49) + passe de limpeza cosmética.

### Acolhidas na íntegra (8): a, b, d, f, g, h, k, l
Verificado independente; várias superam o pedido. Ressalvas são pontos de validação dos advogados, não defeitos: (a) autoridade de ratificação PMI-GO + capítulos pré-existentes sem veto; (b) §-vs-cláusula-autônoma + art.42 LGPD cogente; (f) cross-ref 15.4.5(b) pende p/ retrofit pré-v2.7; (h) "designado ou a ser designado"→"designado" (DPO já existe); (k) condicionar eficácia à prova `.ots` *confirmada* (não pending) + só ramo blockchain é piso.

### Divergências conscientes (2): e, j
- **(e) imagem/voz institucional-gratuito (não comercial):** legítima, **aplicada de forma consistente** — verificado: doc2 Cl.11 e doc5 **sem "comercial"** (risco Termo×Adendo **descartado**; o auditor sinalizara "VERIFICAR" por julgar pela trilha redline, que ainda mostra "comercial" — entregue está limpo). Resíduos: trilha redline interna contraditória (higiene interna) + questão **art.11 LGPD** (dado sensível) → explícito aos advogados.
- **(j) fiscal remetido a Instrumento de Destinação/Rateio:** legítima. O pedaço **art.49** foi empacotado dentro de (j) como divergência — é **erro de citação** (não divergência), e pertence a (c).

### Substancialmente acolhidas, "integral" é otimista (2): c, i
- **(c) teto standby:** 24m/48m vinculado ao embargo, MAS extensão por ata até 48m pode descolar do fim do embargo = a "lacuna de fruição" que o Parecer mandou evitar (design defensável, mas sinalizar) + **art.49,IV errado em 5 docs**.
- **(i) mediação/recurso:** recurso interno 2 passos + imparcialidade + prazos Passo 1 + gancho 7.7. **Calibração:** "efeito suspensivo" e "prazo Passo 2" **NÃO são exigência literal** do Parecer (§4 só pede "instâncias de mediação + procedimento de recurso de forma minuciosa") — são completude + nuance "mediação"vs"conciliação". → apresentar como "implementada, com pontos a validar".

### art.49 IV→III — GROUNDED
`art.49,IV` (territorial) aparece **5×** (doc1 L431, doc2 L137, doc3 L360, doc5 L171, doc6 L112); `art.49,III` (prazo: "na ausência de estipulação escrita, prazo máx. 5 anos") = **0×**. Teto *temporal* deve ancorar em III, não no IV territorial — intuição do time correta. Ressalva: III é supletivo da ausência de prazo escrito; o teto do Núcleo é prazo expresso → talvez nem III nem IV, reancorar como prazo contratual expresso. **Decisão: NÃO auto-aplicar** (Híbrido) — advogados confirmam o inciso, depois aplica-se nos 5.

### Limpeza que bloqueia envio profissional (não são defeitos jurídicos)
Banners de export em todos os instrumentos; doc2 `{chapterName}` ×4; doc1 "Lacrado"×"review"; doc4 título duplo; doc3 "pendente curadoria"; DPA "Instrumento nº 9"≠arquivo 11. HANDOFF do time "P1 4/4 + P2 4/4 RESOLVIDO" superdeclara: pin v2.7 ✓ e doc5↔doc2 ✓ genuínos, mas banner só teve slug limpo e DPO-vocab/"obra coletiva" só token-level.

### Validação do email (draft Gmail `19ea496bea8d47fc`)
Claims em geral honestas; "ready_with_edits". Edições: Aaron no To; art.49 de (j)→(c); suavizar atribuição DPO ("se estiverem de acordo"); DPO framing já correto (erro "designar DPO" só no draft platform-side abandonado).

## Decisões do PM (2026-06-09)
1. **Caminho = Híbrido:** limpeza cosmética + reframe honesto do email AGORA; **não** auto-aplicar substância jurídica (art.49, efeito suspensivo, teto-embargo) → vão aos advogados como "achamos isto, validem".
2. **Tom dos 3 itens não-reconhecidos = todos explícitos** aos advogados: (A) art.49 IV→III (5 docs), (B) art.11 LGPD na rec (e), (C) reframe (c)/(i).

## Execução
- Email revisado (edições cirúrgicas, voz preservada) — pronto; aplicar ao draft Gmail mediante aprovação.
- Checklist de limpeza `.docx` (9 itens) — para o time aplicar / re-exportar do PDF oficial.
- **G12 clock (#334)** inicia no envio validado → logar timestamp em #334 quando o PM enviar.
- Relacional (não tomar partido): Aaron=redator do Parecer (sozinho); Angeline=OAB+DPO suplente; convite de filiação incondicional preservado.
