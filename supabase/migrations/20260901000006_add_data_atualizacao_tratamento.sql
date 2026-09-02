-- =============================================================================
-- 006 — data_atualizacao em cepzk_tratamento
--
-- Adiciona a coluna `data_atualizacao` (not null default now()).
-- A aplicação é responsável por atualizá-la a cada update.
-- =============================================================================

alter table public.cepzk_tratamento
    add column if not exists data_atualizacao timestamptz not null default now();
