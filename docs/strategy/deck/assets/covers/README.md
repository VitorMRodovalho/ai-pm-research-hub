# Capas drop-in (material de terceiros, protegido)

O build (`build_kruel.py`) detecta automaticamente estes arquivos. Sem eles, o slide mostra
uma moldura `[ Capa ]` com o rótulo. Solte os arquivos aqui (png ou jpg) com EXATAMENTE estes nomes:

- `mckinsey.png`          -> slide "Onde os projetos de IA travam" (relatório McKinsey State of AI)
- `pmi_pulse.png`         -> mesmo slide (PMI Pulse of the Profession)
- `ansi_ai_standard.png`  -> slide "O PMI escreve o padrão" (capa do Standard for AI in PPP Mgmt, 2026)
- `pmbok.png`             -> mesmo slide (PMBOK Guide 7ª ed. / Standard for Project Management)

Depois rode: `~/.venvs/pmo/bin/python build_kruel.py`

Direito autoral: são capas de terceiros (McKinsey, PMI). Use como citação/thumbnail em material
de cooperação; não versionar no repo público (já coberto pelo .gitignore via assets/covers/ se
adicionado; confirme). Vitor tem acesso legítimo a esses arquivos.
