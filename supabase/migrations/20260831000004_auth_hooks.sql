-- =============================================================================
-- 004 — Integração com o Supabase Auth
--
-- Cria automaticamente o registro em cepzk_voluntario quando um usuário
-- faz sign-up no Supabase Auth (insert em auth.users).
--
-- O nome do voluntário vem, nesta ordem:
--   1. raw_user_meta_data.nome  (campo "nome" enviado no sign-up);
--   2. raw_user_meta_data.name;
--   3. parte do e-mail antes do "@".
-- =============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.cepzk_voluntario (id, nome)
    values (
        new.id,
        coalesce(
            nullif(new.raw_user_meta_data ->> 'nome', ''),
            nullif(new.raw_user_meta_data ->> 'name', ''),
            split_part(coalesce(new.email, ''), '@', 1)
        )
    )
    on conflict (id) do update set nome = excluded.nome;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();
