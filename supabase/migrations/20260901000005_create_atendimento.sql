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
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Catálogo de atendimentos
-- -----------------------------------------------------------------------------

create table public.cepzk_atendimento (
    id         smallserial primary key,
    setor_id   smallint not null references public.cepzk_setor (id),
    horario_id smallint not null references public.cepzk_horario (id),
    -- Um setor não repete o mesmo horário
    unique (setor_id, horario_id),
    -- Chave alternativa que sustenta a FK composta de cepzk_tratamento
    -- (garante que o setor gravado no tratamento é o setor do atendimento)
    unique (id, setor_id)
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

insert into public.cepzk_atendimento (setor_id, horario_id)
select s.id, h.id
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
insert into public.cepzk_atendimento (setor_id, horario_id)
select distinct x.setor_id, x.horario_id
from (
    select setor_id, horario_id from public.cepzk_escala
    union
    select setor_id, horario_id from public.cepzk_tratamento
) as x
where not exists (
    select 1 from public.cepzk_atendimento a
    where a.setor_id = x.setor_id and a.horario_id = x.horario_id
);

-- -----------------------------------------------------------------------------
-- 4. cepzk_escala — (voluntario_id, setor_id, horario_id) → (voluntario_id, atendimento_id)
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
-- 5. cepzk_tratamento — (setor_id, horario_id) → atendimento_id
--
-- `setor_id` permanece como coluna DERIVADA (preenchida por trigger a partir
-- do atendimento) por um único motivo: manter a regra `unique (assistido_id,
-- setor_id)` — um assistido não faz dois tratamentos no mesmo setor, mesmo em
-- horários diferentes. A FK composta abaixo garante que ela nunca divirja do
-- atendimento; a aplicação envia apenas `atendimento_id`.
-- -----------------------------------------------------------------------------

alter table public.cepzk_tratamento
    add column atendimento_id smallint;

update public.cepzk_tratamento t
set atendimento_id = a.id
from public.cepzk_atendimento a
where a.setor_id = t.setor_id and a.horario_id = t.horario_id;

alter table public.cepzk_tratamento
    alter column atendimento_id set not null;

alter table public.cepzk_tratamento
    drop column horario_id;

-- A FK simples setor -> cepzk_setor dá lugar à FK composta com o atendimento
do $$
declare
    fk text;
begin
    for fk in
        select con.conname
        from pg_constraint con
        where con.conrelid = 'public.cepzk_tratamento'::regclass
          and con.contype = 'f'
          and con.confrelid = 'public.cepzk_setor'::regclass
    loop
        execute format('alter table public.cepzk_tratamento drop constraint %I', fk);
    end loop;
end
$$;

alter table public.cepzk_tratamento
    add constraint cepzk_tratamento_atendimento_id_fkey
    foreign key (atendimento_id, setor_id)
    references public.cepzk_atendimento (id, setor_id)
    on update cascade;

create index cepzk_tratamento_atendimento_id_idx
    on public.cepzk_tratamento (atendimento_id);

-- Preenche/corrige setor_id a partir do atendimento: a aplicação nunca
-- precisa informá-lo
create or replace function public.cepzk_tratamento_setor_derivado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    setor smallint;
begin
    select a.setor_id into setor
    from public.cepzk_atendimento a
    where a.id = new.atendimento_id;

    if setor is null then
        raise exception 'atendimento_id % inexistente', new.atendimento_id
            using errcode = 'foreign_key_violation';
    end if;

    new.setor_id := setor;
    return new;
end;
$$;

drop trigger if exists on_tratamento_setor_derivado on public.cepzk_tratamento;
create trigger on_tratamento_setor_derivado
    before insert or update of atendimento_id, setor_id on public.cepzk_tratamento
    for each row
    execute function public.cepzk_tratamento_setor_derivado();

-- -----------------------------------------------------------------------------
-- 6. RLS do novo catálogo (mesma política da migration 003)
-- -----------------------------------------------------------------------------

alter table public.cepzk_atendimento enable row level security;

drop policy if exists autenticados_acesso_completo on public.cepzk_atendimento;
create policy autenticados_acesso_completo
    on public.cepzk_atendimento for all to authenticated
    using (true) with check (true);
