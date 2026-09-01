-- =============================================================================
-- 001 — Esquema principal
--
-- Tabelas do sistema de controle de atendimentos de tratamentos.
--
-- Convenções de tipos:
--   * smallserial/smallint → catálogos de pequeno porte
--     (departamentos, setores, horários, distonias, queixas, procedimentos);
--   * serial/int           → dados transacionais
--     (assistidos, tratamentos, sessões, relatórios);
--   * uuid                 → qualquer referência a usuário do Supabase Auth.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Catálogos: departamentos, setores e horários
-- -----------------------------------------------------------------------------

-- Ex.: Atendimento Fraterno, Fluidoterapia, Mediúnico
create table public.cepzk_departamento (
    id   smallserial primary key,
    nome text not null
);

-- Ex.: Atendimento Fraterno, Acolher com Amor, Desobsessão Infantil I
create table public.cepzk_setor (
    id              smallserial primary key,
    nome            text not null,
    departamento_id smallint not null references public.cepzk_departamento (id),
    -- Prioridade do tratamento do setor (menor número = mais prioritário);
    -- null = setor sem prioridade definida
    precedencia_tratamento smallint
);

-- Ex.: Terça-Feira 20h, Sexta-Feira 19h, Sábado 9h30
create table public.cepzk_horario (
    id   smallserial primary key,
    nome text not null
);

-- -----------------------------------------------------------------------------
-- Voluntários — espelhados 1:1 com auth.users do Supabase Auth
-- -----------------------------------------------------------------------------

-- Papéis do voluntário. Por ora, coordenador e colaborador têm as mesmas
-- permissões; a diferenciação entre eles é previsível para o futuro.
create type public.papel_voluntario as enum ('admin', 'coordenador', 'colaborador');

create table public.cepzk_voluntario (
    -- Mesmo identificador do usuário no Supabase Auth (auth.users.id)
    id           uuid primary key,
    nome         text not null,
    -- Sobrenome do voluntário (opcional)
    sobrenome    text,
    -- E-mail do voluntário; o admin o usa para enviar o convite.
    -- Sincronizado automaticamente com auth.users.
    email        text not null unique,
    -- Preenchido pelo próprio voluntário
    telefone     text,
    -- Somente 'admin' envia convites e altera papéis
    papel        public.papel_voluntario not null default 'colaborador',
    data_criacao timestamptz not null default now()
);

-- Escala: nos setores/horários em que cada voluntário atua
create table public.cepzk_escala (
    voluntario_id uuid     not null references public.cepzk_voluntario (id) on delete cascade,
    setor_id      smallint not null references public.cepzk_setor (id),
    horario_id    smallint not null references public.cepzk_horario (id),
    primary key (voluntario_id, setor_id, horario_id)
);

-- -----------------------------------------------------------------------------
-- Assistidos e tratamentos
-- -----------------------------------------------------------------------------

create table public.cepzk_assistido (
    id               serial   primary key,
    nome_completo    text     not null unique,
    -- Voluntário (Atendimento Fraterno) que realizou a entrevista
    entrevistador_id uuid     not null references public.cepzk_voluntario (id),
    data_criacao     timestamptz not null default now()
);

create table public.cepzk_tratamento (
    id         serial   primary key,
    assistido_id int    not null references public.cepzk_assistido (id) on delete cascade,
    setor_id   smallint not null references public.cepzk_setor (id),
    horario_id smallint not null references public.cepzk_horario (id),
    obs        text,
    -- Estado do tratamento ('pendente' até a alta; o voluntário marca
    -- como completo quando o assistido recebe alta)
    estado     text     not null default 'pendente',
    unique (assistido_id, setor_id)
);

-- -----------------------------------------------------------------------------
-- Acolher com Amor (ACA) — extensões específicas do tratamento
-- -----------------------------------------------------------------------------

-- Ex.: TEA, Esquizofrenia, Outros
create table public.aca_distonia (
    id   smallserial primary key,
    nome text not null unique
);

-- Ex.: Convulsão, Dificuldade de Comunicação, Comportamentos Violentos
create table public.aca_queixa (
    id   smallserial primary key,
    nome text not null unique
);

-- Extensão 1:1 do tratamento para os casos do Acolher com Amor
create table public.aca_tratamento (
    id          int primary key references public.cepzk_tratamento (id) on delete cascade,
    distonia_id smallint not null references public.aca_distonia (id)
);

-- Queixas registradas no tratamento (N:M)
create table public.aca_tratamento_queixa (
    tratamento_id int      not null references public.cepzk_tratamento (id) on delete cascade,
    queixa_id     smallint not null references public.aca_queixa (id) on delete cascade,
    primary key (tratamento_id, queixa_id)
);

-- Ex.: TEA Geral, Distonias Mentais Geral, Convulsões
create table public.aca_procedimento (
    id   smallserial primary key,
    nome text not null unique
);

-- Agenda de sessões de cada assistido em tratamento no ACA
create table public.aca_sessao (
    id            serial      primary key,
    tratamento_id int         not null references public.cepzk_tratamento (id) on delete cascade,
    data          timestamptz not null
);

-- Procedimentos realizados em cada sessão (N:M)
create table public.aca_sessao_procedimento (
    sessao_id       int      not null references public.aca_sessao (id) on delete cascade,
    procedimento_id smallint not null references public.aca_procedimento (id) on delete cascade,
    primary key (sessao_id, procedimento_id)
);

-- Relatório da sessão: ponte (médium) e dirigente responsáveis
create table public.aca_relatorio (
    id           serial primary key,
    sessao_id    int    not null references public.aca_sessao (id) on delete cascade,
    ponte_id     uuid   not null references public.cepzk_voluntario (id),
    dirigente_id uuid   not null references public.cepzk_voluntario (id),
    obs          text,
    data_criacao timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Índices em colunas de chave estrangeira (consultas frequentes)
-- -----------------------------------------------------------------------------

create index cepzk_setor_departamento_id_idx
    on public.cepzk_setor (departamento_id);

create index cepzk_escala_setor_id_idx
    on public.cepzk_escala (setor_id);

create index cepzk_escala_horario_id_idx
    on public.cepzk_escala (horario_id);

create index cepzk_assistido_entrevistador_id_idx
    on public.cepzk_assistido (entrevistador_id);

create index cepzk_tratamento_assistido_id_idx
    on public.cepzk_tratamento (assistido_id);

create index cepzk_tratamento_setor_id_idx
    on public.cepzk_tratamento (setor_id);

create index cepzk_tratamento_horario_id_idx
    on public.cepzk_tratamento (horario_id);

create index aca_tratamento_distonia_id_idx
    on public.aca_tratamento (distonia_id);

create index aca_sessao_tratamento_id_idx
    on public.aca_sessao (tratamento_id);

create index aca_sessao_data_idx
    on public.aca_sessao (data);

create index aca_relatorio_ponte_id_idx
    on public.aca_relatorio (ponte_id);

create index aca_relatorio_dirigente_id_idx
    on public.aca_relatorio (dirigente_id);
