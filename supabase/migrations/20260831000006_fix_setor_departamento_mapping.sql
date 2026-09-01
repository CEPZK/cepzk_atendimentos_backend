-- =============================================================================
-- 006 — Ajuste final no mapeamento setor -> departamento
--
-- Mapeamento definitivo:
--   Atendimento Fraterno    -> Atendimento Fraterno
--   Acolher com Amor        -> Fluidoterapia
--   Desobsessão Infantil I  -> Mediúnico
--   Desobsessão Infantil II -> Mediúnico
--
-- Também remove o setor "Mediúnico" (adicionado na migration 005), que não
-- faz parte do mapeamento definitivo.
-- Idempotente: reexecutar não altera nada.
-- =============================================================================

update public.cepzk_setor
set departamento_id = d.id
from public.cepzk_departamento d
where cepzk_setor.nome = 'Acolher com Amor'
  and d.nome = 'Fluidoterapia';

delete from public.cepzk_setor
where nome = 'Mediúnico';
