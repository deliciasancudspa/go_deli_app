-- ============================================================================
-- 2026-07-08: Eliminar duplicados en config y agregar UNIQUE en key
-- ============================================================================
-- Problema: saveConfig() usaba upsert sin onConflict, creando nuevas filas
-- cada vez. Esto rompía maybeSingle() en Flutter y web.
-- ============================================================================

-- 1. Eliminar duplicados: conservar solo la fila más reciente (mayor created_at o id)
delete from public.config
where id in (
  select id from (
    select id,
           row_number() over (partition by key order by created_at desc nulls last, id desc) as rn
    from public.config
  ) ranked
  where rn > 1
);

-- 2. Agregar UNIQUE constraint en key para prevenir futuros duplicados
--    (solo si no existe ya)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'config_key_unique'
      and conrelid = 'public.config'::regclass
  ) then
    alter table public.config add constraint config_key_unique unique (key);
  end if;
end $$;
