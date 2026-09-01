-- =============================================================================
-- 004 — Integração com o Supabase Auth
--
-- O sistema usa apenas magic link (link enviado por e-mail, sem senha).
-- O voluntário é criado automaticamente no primeiro clique no link (o
-- sign-up é automático nesse fluxo), mantendo o mesmo id do auth.users.
--
-- O nome do voluntário vem, nesta ordem:
--   1. raw_user_meta_data.nome  (campo "nome" enviado no login);
--   2. raw_user_meta_data.name;
--   3. parte do e-mail antes do "@".
--
-- Quando o usuário atualiza seus metadados (ex.: supabase.auth.updateUser
-- com um novo nome), o registro em cepzk_voluntario é sincronizado.
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

-- Cria o voluntário no sign-up (insert em auth.users)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.cepzk_voluntario (id, nome)
    values (new.id, public.voluntario_nome(new.raw_user_meta_data, new.email))
    on conflict (id) do update set nome = excluded.nome;
    return new;
end;
$$;

-- Sincroniza o nome quando os metadados do usuário mudam
create or replace function public.handle_updated_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.raw_user_meta_data is distinct from old.raw_user_meta_data then
        update public.cepzk_voluntario
        set nome = public.voluntario_nome(new.raw_user_meta_data, new.email)
        where id = new.id;
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
