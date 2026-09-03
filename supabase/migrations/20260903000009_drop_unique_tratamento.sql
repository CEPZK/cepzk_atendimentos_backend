-- =============================================================================
-- 009 — remove o unique (assistido_id, atendimento_id) de cepzk_tratamento
--
-- A regra "um tratamento por assistido em cada atendimento" passa a ser
-- responsabilidade da aplicação: um novo tratamento para o mesmo par
-- (assistido, atendimento) só pode ser criado se o existente estiver
-- arquivado (`data_arquivamento` preenchido).
--
-- O índice em (assistido_id, atendimento_id) criado pelo unique cai junto com
-- a constraint; mantemos os índices simples já existentes para as FKs.
-- =============================================================================

alter table public.cepzk_tratamento
    drop constraint if exists cepzk_tratamento_assistido_id_atendimento_id_key;

create index if not exists cepzk_tratamento_assistido_id_atendimento_id_idx
    on public.cepzk_tratamento (assistido_id, atendimento_id);
