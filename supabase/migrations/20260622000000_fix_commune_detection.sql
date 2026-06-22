-- ============================================================================
-- GO DELI — FIX: DETECCIÓN DE COMUNA PARA USUARIOS ANÓNIMOS + FUZZY MATCHING
-- ============================================================================
-- Migración: 20260622000000
-- Problema:  find_commune() solo estaba grant a authenticated → usuarios
--            anónimos no podían detectar su comuna → _userCommuneId = null →
--            se mostraban TODAS las tiendas sin filtrar.
-- Fix:       Otorgar execute a anon + crear función fuzzy_match_commune
--            que normaliza nombres (sin acentos, lowercase) para matching
--            más tolerante.
-- ============================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. OTORGAR find_commune AL ROL anon
-- ═══════════════════════════════════════════════════════════════════════════════
grant execute on function public.find_commune(text, text) to anon;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. FUNCIÓN FUZZY_MATCH_COMMUNE — matching tolerante con normalización
-- ═══════════════════════════════════════════════════════════════════════════════

-- Helper: normaliza texto (quita acentos, lowercase, trim)
create or replace function public.normalize_text(t text)
returns text language sql immutable strict as $$
  select lower(regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(trim(t),
              '[áàâãäå]', 'a', 'g'),
            '[éèêë]',   'e', 'g'),
          '[íìîï]',   'i', 'g'),
        '[óòôõö]',   'o', 'g'),
      '[úùûü]',   'u', 'g'),
    '[ñ]',       'n', 'g')
  );
$$;

-- Busca una comuna por nombre con matching tolerante.
-- Estrategia (en orden):
--   1. Match exacto normalizado (sin acentos, case-insensitive)
--   2. Match parcial: el nombre de la comuna contiene el input O viceversa
--   3. Match por primera palabra >= 4 caracteres
-- Retorna el UUID de la comuna o null.
create or replace function public.fuzzy_match_commune(p_name text, p_region text default null)
returns uuid language plpgsql stable as $$
declare
  v_normalized text;
  v_result     uuid;
begin
  v_normalized := public.normalize_text(p_name);

  -- 1. Match exacto normalizado
  select c.id into v_result
  from communes c
  join regions r on r.id = c.region_id
  where public.normalize_text(c.name) = v_normalized
    and (p_region is null or public.normalize_text(r.name) = public.normalize_text(p_region))
    and c.is_active = true
  limit 1;
  if v_result is not null then return v_result; end if;

  -- 2. Match parcial: input contenido en nombre de comuna O viceversa
  select c.id into v_result
  from communes c
  join regions r on r.id = c.region_id
  where (public.normalize_text(c.name) like '%' || v_normalized || '%'
      or v_normalized like '%' || public.normalize_text(c.name) || '%')
    and c.is_active = true
  order by
    -- Preferir matches donde la región coincida
    case when p_region is null or public.normalize_text(r.name) = public.normalize_text(p_region) then 0 else 1 end,
    -- Preferir matches más cortos (más precisos)
    length(c.name)
  limit 1;
  if v_result is not null then return v_result; end if;

  -- 3. Match por primera palabra >= 4 caracteres del input
  --    (ej: "Santiago Centro" → buscar "santiago")
  declare
    v_word text;
    parts  text[];
  begin
    parts := string_to_array(v_normalized, ' ');
    foreach v_word in array parts loop
      if length(v_word) >= 4 then
        select c.id into v_result
        from communes c
        join regions r on r.id = c.region_id
        where public.normalize_text(c.name) like '%' || v_word || '%'
          and c.is_active = true
        order by length(c.name)
        limit 1;
        if v_result is not null then return v_result; end if;
      end if;
    end loop;
  end;

  return null;
end;
$$;

grant execute on function public.fuzzy_match_commune(text, text) to anon, authenticated;
grant execute on function public.normalize_text(text) to anon, authenticated;

commit;
