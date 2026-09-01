-- =============================================================================
-- 003 — Row Level Security (RLS)
--
-- Habilita o RLS em todas as tabelas da aplicação e cria a política padrão
-- da versão 1: todo usuário autenticado (voluntário logado) tem acesso
-- completo (SELECT, INSERT, UPDATE, DELETE) a todas as tabelas.
--
-- O papel `service_role` do Supabase ignora o RLS e é usado apenas em
-- processos fora do navegador; o papel `anon` não tem acesso a nenhuma
-- tabela.
--
-- Próximos refinamentos (conforme as features forem implementadas):
--   * voluntário só altera sessões/relatórios dos setores em que atua
--     (via cepzk_escala);
--   * catálogos (departamento, setor, horário, aca_distonia, aca_queixa,
--     aca_procedimento) somente leitura;
--   * assistidos só podem ser alterados por quem atua no Atendimento Fraterno.
-- =============================================================================

do $$
declare
    t       text;
    tabelas text[] := array[
        'public.cepzk_departamento',
        'public.cepzk_setor',
        'public.cepzk_horario',
        'public.cepzk_voluntario',
        'public.cepzk_escala',
        'public.cepzk_assistido',
        'public.cepzk_tratamento',
        'public.aca_distonia',
        'public.aca_queixa',
        'public.aca_tratamento',
        'public.aca_tratamento_queixa',
        'public.aca_procedimento',
        'public.aca_sessao',
        'public.aca_sessao_procedimento',
        'public.aca_relatorio'
    ];
begin
    foreach t in array tabelas loop
        execute format('alter table %s enable row level security', t);
        execute format(
            'create policy autenticados_acesso_completo
               on %s for all to authenticated
               using (true) with check (true)',
            t
        );
    end loop;
end
$$;
