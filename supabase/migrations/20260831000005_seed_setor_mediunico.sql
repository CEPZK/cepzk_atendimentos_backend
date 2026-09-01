-- =============================================================================
-- 005 — Ajuste no seed: setor Mediúnico
--
-- Inclui o setor "Mediúnico" (departamento "Mediúnico") nos dados de
-- referência. Adicionado como nova migration para que projetos que já
-- aplicaram a migration 002 recebam o ajuste normalmente.
-- Idempotente: reexecutar não duplica registros.
-- =============================================================================

insert into public.cepzk_setor (nome, departamento_id)
select 'Mediúnico', d.id
from public.cepzk_departamento d
where d.nome = 'Mediúnico'
  and not exists (select 1 from public.cepzk_setor t where t.nome = 'Mediúnico');
