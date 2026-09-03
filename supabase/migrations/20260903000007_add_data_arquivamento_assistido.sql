-- =============================================================================
-- 007 — data_arquivamento em cepzk_assistido
--
-- Adiciona a coluna `data_arquivamento` (nullable) para permitir o
-- arquivamento de assistidos. Um valor null indica que o assistido está
-- ativo; quando preenchido, registra a data/hora em que foi arquivado.
-- =============================================================================

alter table public.cepzk_assistido
    add column if not exists data_arquivamento timestamptz;
