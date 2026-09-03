-- =============================================================================
-- 008 — data_arquivamento em cepzk_tratamento
--
-- Adiciona a coluna `data_arquivamento` (nullable), no mesmo formato usado
-- para o arquivamento de assistidos (migration 007). Um valor null indica
-- que o tratamento está ativo; quando preenchido, registra a data/hora em
-- que foi arquivado.
-- =============================================================================

alter table public.cepzk_tratamento
    add column if not exists data_arquivamento timestamptz;
