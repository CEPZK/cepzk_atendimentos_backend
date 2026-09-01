-- =============================================================================
-- 002 — Dados de referência iniciais
--
-- Popula os catálogos com os valores iniciais do projeto. Todas as inserções
-- são idempotentes: reexecutar esta migration não duplica registros.
-- Ajuste livremente conforme a organização real do centro.
-- =============================================================================

insert into public.cepzk_departamento (nome)
select v.nome
from (values ('Atendimento Fraterno'), ('Fluidoterapia'), ('Mediúnico')) as v (nome)
where not exists (select 1 from public.cepzk_departamento d where d.nome = v.nome);

insert into public.cepzk_horario (nome)
select v.nome
from (values
    ('Terça-Feira 20h'),
    ('Sexta-Feira 19h'),
    ('Sexta-Feira 19h30'),
    ('Sábado 9h30')
) as v (nome)
where not exists (select 1 from public.cepzk_horario h where h.nome = v.nome);

-- Mapeamento setor -> departamento (definitivo) + prioridade de cada setor
insert into public.cepzk_setor (nome, departamento_id, precedencia_tratamento)
select s.nome, d.id, s.precedencia
from (values
    ('Atendimento Fraterno',    'Atendimento Fraterno', 0),
    ('Acolher com Amor',        'Fluidoterapia',        10),
    ('Desobsessão Infantil I',  'Mediúnico',            1),
    ('Desobsessão Infantil II', 'Mediúnico',            1)
) as s (nome, departamento, precedencia)
join public.cepzk_departamento d on d.nome = s.departamento
where not exists (select 1 from public.cepzk_setor t where t.nome = s.nome);

insert into public.aca_distonia (nome)
select v.nome
from (values ('TEA'), ('Esquizofrenia'), ('Outros')) as v (nome)
where not exists (select 1 from public.aca_distonia d where d.nome = v.nome);

insert into public.aca_queixa (nome)
select v.nome
from (values
    ('Convulsão'),
    ('Dificuldade de Comunicação'),
    ('Dificuldade de Interação Social'),
    ('Comportamentos Repetitivos'),
    ('Comportamentos Violentos')
) as v (nome)
where not exists (select 1 from public.aca_queixa q where q.nome = v.nome);

insert into public.aca_procedimento (nome)
select v.nome
from (values
    ('TEA Geral'),
    ('Distonias Mentais Geral'),
    ('Esquizofrenia'),
    ('Convulsões')
) as v (nome)
where not exists (select 1 from public.aca_procedimento p where p.nome = v.nome);
