-- =============================================================================
-- 004 — Integração com o Supabase Auth
--
-- O sistema usa apenas magic link (link enviado por e-mail, sem senha) e o
-- acesso é somente por convite (invite-only). O voluntário é criado
-- automaticamente no momento do convite (o inviteUserByEmail já insere em
-- auth.users), mantendo o mesmo id do auth.users.
--
-- O nome do voluntário vem, nesta ordem:
--   1. raw_user_meta_data.nome  (campo "nome" enviado no convite);
--   2. raw_user_meta_data.name;
--   3. parte do e-mail antes do "@".
--
-- Quando o usuário atualiza metadados ou e-mail (ex.: supabase.auth.
-- updateUser), nome e e-mail em cepzk_voluntario são sincronizados.
--
-- Proteção de privilégio: a alteração de `papel` só é permitida para
-- admin logado, para o service_role (Edge Functions) e para o dono da
-- tabela (administração local, ex.: SQL Editor/CLI no Supabase).
-- Alterações de papel feitas por outros usuários são revertidas.
-- =============================================================================

-- Extrai o nome a partir dos metadados do usuário do Auth
create or replace function public.voluntario_nome(meta jsonb, email text)
returns text
language sql
stable
as $$
    select coalesce(
        nullif(meta ->> 'nome', ''),
        nullif(meta ->> 'name', ''),
        split_part(coalesce(email, ''), '@', 1)
    );
$$;

-- Cria o voluntário no momento do convite (insert em auth.users)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.cepzk_voluntario (id, nome, email)
    values (new.id, public.voluntario_nome(new.raw_user_meta_data, new.email), new.email)
    on conflict (id) do update
    set nome  = excluded.nome,
        email = excluded.email;
    return new;
end;
$$;

-- Sincroniza nome/e-mail quando os dados do usuário mudam
create or replace function public.handle_updated_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.raw_user_meta_data is distinct from old.raw_user_meta_data
       or new.email is distinct from old.email then
        update public.cepzk_voluntario
        set nome  = public.voluntario_nome(new.raw_user_meta_data, new.email),
            email = new.email
        where id = new.id;
    end if;
    return new;
end;
$$;

-- Reverte alteração de `papel` por quem não tem privilégio.
-- SECURITY INVOKER (de propósito): current_user precisa refletir o papel
-- efetivo de quem está executando (authenticated/anon/service_role na
-- API; o dono da tabela na administração local).
create or replace function public.protetor_papel_voluntario()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
    dono text;
begin
    if new.papel is distinct from old.papel then
        select pg_get_userbyid(c.relowner) into dono
        from pg_class c
        where c.oid = 'public.cepzk_voluntario'::regclass;

        if current_user <> dono
           and current_user <> 'service_role'
           and not exists (
               select 1 from public.cepzk_voluntario v
               where v.id = auth.uid() and v.papel = 'admin'
           ) then
            new.papel := old.papel;
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
    after update on auth.users
    for each row
    execute function public.handle_updated_user();

drop trigger if exists on_voluntario_papel_protected on public.cepzk_voluntario;
create trigger on_voluntario_papel_protected
    before update on public.cepzk_voluntario
    for each row
    execute function public.protetor_papel_voluntario();
