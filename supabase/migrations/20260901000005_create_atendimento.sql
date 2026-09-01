-- =============================================================================
-- 005 — Atendimento (substitui a dupla setor_id + horario_id)
--
-- Antes, `cepzk_escala` e `cepzk_tratamento` referenciavam setor e horário
-- separadamente, o que permitia combinações inexistentes na casa
-- (ex.: Acolher com Amor na Terça-Feira 8h).
--
-- Agora existe o catálogo `cepzk_atendimento`: cada linha é uma combinação
-- setor + horário realmente oferecida. Escala e tratamento passam a
-- referenciar um único `atendimento_id`.
--
-- Atendimentos oferecidos:
--   * Atendimento Fraterno    — Terça-Feira 8h
--   * Atendimento Fraterno    — Sexta-Feira 19h
--   * Desobsessão Infantil I  — Sexta-Feira 19h30
--   * Desobsessão Infantil II — Sexta-Feira 19h30
--   * Acolher com Amor        — Sábado 9h30
--
-- Migração de dados: as combinações já existentes em escala/tratamento são
-- preservadas (viram atendimentos) para que nenhum registro se perca.
--
-- Esta migration também:
--   * encerra a regra "um tratamento por setor" (o assistido pode ter
--     tratamentos no mesmo setor em horários diferentes);
--   * move a precedência de `cepzk_setor.precedencia_tratamento` para
--     `cepzk_atendimento.precedencia`, preservando os valores atuais.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Catálogo de atendimentos
-- -----------------------------------------------------------------------------

create table public.cepzk_atendimento (
    id         smallserial primary key,
    setor_id   smallint not null references public.cepzk_setor (id),
    horario_id smallint not null references public.cepzk_horario (id),
    -- Prioridade do tratamento neste atendimento (menor = mais prioritário);
    -- null = sem prioridade definida. Herdada de cepzk_setor na migração.
    precedencia smallint,
    -- Um setor não repete o mesmo horário
    unique (setor_id, horario_id)
);

create index cepzk_atendimento_setor_id_idx
    on public.cepzk_atendimento (setor_id);

create index cepzk_atendimento_horario_id_idx
    on public.cepzk_atendimento (horario_id);

-- -----------------------------------------------------------------------------
-- 2. Horário novo: o Atendimento Fraterno de terça é às 8h
--    ('Terça-Feira 20h' continua no catálogo, apenas sem atendimento ligado)
-- -----------------------------------------------------------------------------

insert into public.cepzk_horario (nome)
select v.nome
from (values ('Terça-Feira 8h')) as v (nome)
where not exists (select 1 from public.cepzk_horario h where h.nome = v.nome);

-- -----------------------------------------------------------------------------
-- 3. Atendimentos oferecidos (idempotente)
-- -----------------------------------------------------------------------------

insert into public.cepzk_atendimento (setor_id, horario_id, precedencia)
select s.id, h.id, s.precedencia_tratamento
from (values
    (1, 'Atendimento Fraterno',    'Terça-Feira 8h'),
    (2, 'Atendimento Fraterno',    'Sexta-Feira 19h'),
    (3, 'Desobsessão Infantil I',  'Sexta-Feira 19h30'),
    (4, 'Desobsessão Infantil II', 'Sexta-Feira 19h30'),
    (5, 'Acolher com Amor',        'Sábado 9h30')
) as v (ordem, setor, horario)
join public.cepzk_setor   s on s.nome = v.setor
join public.cepzk_horario h on h.nome = v.horario
where not exists (
    select 1 from public.cepzk_atendimento a
    where a.setor_id = s.id and a.horario_id = h.id
)
-- ids seguem a ordem da lista acima (previsível entre ambientes)
order by v.ordem;

-- Preserva combinações já em uso que não estejam na lista acima
-- (bancos com dados anteriores a esta migration)
insert into public.cepzk_atendimento (setor_id, horario_id, precedencia)
select distinct x.setor_id, x.horario_id, s.precedencia_tratamento
from (
    select setor_id, horario_id from public.cepzk_escala
    union
    select setor_id, horario_id from public.cepzk_tratamento
) as x
join public.cepzk_setor s on s.id = x.setor_id
where not exists (
    select 1 from public.cepzk_atendimento a
    where a.setor_id = x.setor_id and a.horario_id = x.horario_id
);

-- -----------------------------------------------------------------------------
-- 4. A precedência passa a ser do atendimento, não do setor
--
-- Os valores acabaram de ser copiados de cepzk_setor.precedencia_tratamento
-- (todo atendimento herdou a precedência do seu setor), então a coluna antiga
-- pode sair.
-- -----------------------------------------------------------------------------

alter table public.cepzk_setor
    drop column if exists precedencia_tratamento;

-- -----------------------------------------------------------------------------
-- 5. cepzk_escala — (voluntario_id, setor_id, horario_id) → (voluntario_id, atendimento_id)
-- -----------------------------------------------------------------------------

alter table public.cepzk_escala
    add column atendimento_id smallint references public.cepzk_atendimento (id);

update public.cepzk_escala e
set atendimento_id = a.id
from public.cepzk_atendimento a
where a.setor_id = e.setor_id and a.horario_id = e.horario_id;

alter table public.cepzk_escala
    alter column atendimento_id set not null;

-- Troca a PK (os índices de setor_id/horario_id somem junto com as colunas)
do $$
declare
    pk text;
begin
    select con.conname into pk
    from pg_constraint con
    where con.conrelid = 'public.cepzk_escala'::regclass and con.contype = 'p';

    if pk is not null then
        execute format('alter table public.cepzk_escala drop constraint %I', pk);
    end if;
end
$$;

alter table public.cepzk_escala
    drop column setor_id,
    drop column horario_id;

alter table public.cepzk_escala
    add primary key (voluntario_id, atendimento_id);

create index cepzk_escala_atendimento_id_idx
    on public.cepzk_escala (atendimento_id);

-- -----------------------------------------------------------------------------
-- 6. cepzk_tratamento — (setor_id, horario_id) → atendimento_id
--
-- Não há mais a regra "um tratamento por setor": o assistido pode ter
-- tratamentos no mesmo setor em horários diferentes. O `unique` agora é por
-- atendimento, apenas para evitar o mesmo assistido duplicado no mesmo
-- atendimento.
-- -----------------------------------------------------------------------------

alter table public.cepzk_tratamento
    add column atendimento_id smallint references public.cepzk_atendimento (id);

update public.cepzk_tratamento t
set atendimento_id = a.id
from public.cepzk_atendimento a
where a.setor_id = t.setor_id and a.horario_id = t.horario_id;

alter table public.cepzk_tratamento
    alter column atendimento_id set not null;

-- Remove as colunas antigas. Junto com elas caem, automaticamente, a FK para
-- cepzk_setor, o unique (assistido_id, setor_id) e os índices de setor_id e
-- horario_id.
alter table public.cepzk_tratamento
    drop column setor_id,
    drop column horario_id;

alter table public.cepzk_tratamento
    add constraint cepzk_tratamento_assistido_id_atendimento_id_key
    unique (assistido_id, atendimento_id);

create index cepzk_tratamento_atendimento_id_idx
    on public.cepzk_tratamento (atendimento_id);

-- -----------------------------------------------------------------------------
-- 7. RLS do novo catálogo (mesma política da migration 003)
-- -----------------------------------------------------------------------------

alter table public.cepzk_atendimento enable row level security;

drop policy if exists autenticados_acesso_completo on public.cepzk_atendimento;
create policy autenticados_acesso_completo
    on public.cepzk_atendimento for all to authenticated
    using (true) with check (true);
