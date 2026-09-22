-- =============================================================================
-- 010 — Unifica a Desobsessão Infantil (remove o setor "Desobsessão Infantil I")
--
-- A casa passa a ter uma única Desobsessão Infantil:
--   * "Desobsessão Infantil II" é renomeado para "Desobsessão Infantil";
--   * "Desobsessão Infantil I" é removido.
--
-- Migração de dados — nenhum registro se perde:
--   * cada atendimento de DI I é reaproveitado no setor renomeado com o mesmo
--     horário (criado ali, se ainda não existir, herdando a precedência);
--   * a escala e os tratamentos que apontavam para esses atendimentos passam a
--     apontar para o atendimento de destino;
--   * na escala, o voluntário que já atua no atendimento de destino é mantido
--     uma única vez — a linha de DI I é descartada (a PK é
--     voluntario_id + atendimento_id).
--
-- Idempotente: se os setores já não existirem com esses nomes, a migration não
-- altera nada.
-- =============================================================================

do $$
declare
    setor_removido_id smallint;  -- 'Desobsessão Infantil I'
    setor_destino_id  smallint;  -- 'Desobsessão Infantil'
    atendimento       record;    -- atendimento de DI I em migração
    destino_id        smallint;  -- atendimento equivalente no setor de destino
begin
    -- ---------------------------------------------------------------------
    -- 1. 'Desobsessão Infantil II' -> 'Desobsessão Infantil'
    --
    -- Se um setor já se chamar 'Desobsessão Infantil', ele é o destino e nada
    -- é renomeado (a tabela não tem unique em nome, então renomear criaria um
    -- duplicado). O 'Desobsessão Infantil II' remanescente fica para revisão
    -- manual.
    -- ---------------------------------------------------------------------

    select id into setor_destino_id
    from public.cepzk_setor
    where nome = 'Desobsessão Infantil';

    if setor_destino_id is null then
        update public.cepzk_setor
        set nome = 'Desobsessão Infantil'
        where nome = 'Desobsessão Infantil II'
        returning id into setor_destino_id;
    elsif exists (
        select 1 from public.cepzk_setor where nome = 'Desobsessão Infantil II'
    ) then
        raise notice
            'Setor "Desobsessão Infantil" já existe: "Desobsessão Infantil II" '
            'foi mantido para revisão manual.';
    end if;

    -- ---------------------------------------------------------------------
    -- 2. O setor que sai de cena
    -- ---------------------------------------------------------------------

    select id into setor_removido_id
    from public.cepzk_setor
    where nome = 'Desobsessão Infantil I';

    if setor_removido_id is null then
        return;
    end if;

    if setor_destino_id is null then
        raise exception
            'Não é possível remover "Desobsessão Infantil I": o setor de '
            'destino "Desobsessão Infantil" não existe.';
    end if;

    -- ---------------------------------------------------------------------
    -- 3. Reaponta atendimentos, escala e tratamentos
    -- ---------------------------------------------------------------------

    for atendimento in
        select a.id, a.horario_id, a.precedencia
        from public.cepzk_atendimento a
        where a.setor_id = setor_removido_id
        order by a.horario_id
    loop
        select a.id into destino_id
        from public.cepzk_atendimento a
        where a.setor_id = setor_destino_id
          and a.horario_id = atendimento.horario_id;

        -- Horário que só existia em DI I: o atendimento é criado no setor de
        -- destino para preservar escala e tratamentos daquele horário.
        if destino_id is null then
            insert into public.cepzk_atendimento (setor_id, horario_id, precedencia)
            values (setor_destino_id, atendimento.horario_id, atendimento.precedencia)
            returning id into destino_id;
        end if;

        -- Voluntário que já atua no atendimento de destino: a linha de DI I é
        -- descartada para não ferir a PK (voluntario_id, atendimento_id).
        delete from public.cepzk_escala e
        where e.atendimento_id = atendimento.id
          and exists (
              select 1
              from public.cepzk_escala d
              where d.atendimento_id = destino_id
                and d.voluntario_id = e.voluntario_id
          );

        update public.cepzk_escala
        set atendimento_id = destino_id
        where atendimento_id = atendimento.id;

        -- Tratamento: não há restrição unique em (assistido_id, atendimento_id)
        -- (removida na migration 009), então basta reapontar — o histórico de
        -- DI I continua íntegro, agora sob o setor unificado.
        update public.cepzk_tratamento
        set atendimento_id = destino_id
        where atendimento_id = atendimento.id;

        delete from public.cepzk_atendimento where id = atendimento.id;
    end loop;

    -- ---------------------------------------------------------------------
    -- 4. Sem atendimentos (e, portanto, sem escala/tratamento), o setor sai
    -- ---------------------------------------------------------------------

    delete from public.cepzk_setor where id = setor_removido_id;
end
$$;
