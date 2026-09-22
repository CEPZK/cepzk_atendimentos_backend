-- =============================================================================
-- 011 — idade em cepzk_assistido
--
-- Adiciona a coluna `idade` (smallint, nullable): a idade do assistido.
-- Um valor null indica idade não informada — a coluna é opcional no cadastro.
-- =============================================================================

alter table public.cepzk_assistido
    add column if not exists idade smallint;
