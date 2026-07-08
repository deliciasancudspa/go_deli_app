-- ============================================================================
-- 2026-07-08: Eliminar duplicados en config y agregar UNIQUE en key
-- ============================================================================
-- Problema: saveConfig() usaba upsert sin onConflict, creando nuevas filas
-- cada vez. Esto rompía maybeSingle() en Flutter y web.
-- La tabla config es key-value: columnas key (text) y value (text/jsonb).
-- No tiene columna id ni created_at.
-- ============================================================================

-- 1. Eliminar duplicados: conservar solo UNA fila por cada key (la primera)
delete from public.config a
using public.config b
where a.key = b.key
  and a.ctid < b.ctid;

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
