-- Renomeia o capítulo PMI-AM para "PMI Amazônia" a pedido do presidente do capítulo
-- João Leite (Presidente PMI Amazônia), 2026-07-09: "o nosso é PMI Amazônia, não é só Amazonas".
--
-- O capítulo cobre a região Amazônia, não só o estado do Amazonas. Corrige TODAS as telas:
--   - legal_name (dropdowns/tooltips, via get_active_chapters)
--   - state (card de afiliação do /perfil exibe este campo: "PMI-AM · <state>")
-- Mantém a resolução VEP robusta nos dois sentidos: vep_name_aliases guarda as variantes
-- "Amazônia Chapter" (o que o PMI Community realmente emite, caso-índice #1175) E "Amazonas,
-- Brazil Chapter"/"Amazonas Chapter" como rede de segurança agora que state deixou de ser
-- "Amazonas" (a convenção "<state>, Brazil Chapter" passou a gerar "Amazônia, Brazil Chapter").
--
-- Sem risco geográfico: worldMap.ts e os mapas de state-reach têm seus próprios dicionários
-- chaveados em "amazonas" e NÃO leem chapter_registry.state. O único consumidor SQL de
-- chapter_registry.state é resolve_br_chapter_code (coberto pelos aliases acima).
--
-- Verificado ao vivo (2026-07-09): get_active_chapters mostra "PMI Amazônia, Brazil Chapter";
-- perfil mostra "Amazônia"; resolve_br_chapter_code('Amazônia Chapter' | 'Amazonas, Brazil
-- Chapter' | 'Amazônia, Brazil Chapter' | 'Amazonia Chapter') = 'AM' nas 4 formas.

UPDATE public.chapter_registry
SET legal_name = 'PMI Amazônia, Brazil Chapter',
    state = 'Amazônia',
    vep_name_aliases = ARRAY['Amazônia Chapter','Amazonia Chapter','Amazonas, Brazil Chapter','Amazonas Chapter'],
    updated_at = now()
WHERE chapter_code = 'AM';
