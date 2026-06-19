-- ============================================================================
-- TARIFA DE SERVICIO GO DELI (interna) + cobertura 8 km
-- ============================================================================
-- orders.total YA incluye la tarifa de servicio (lo que paga el cliente y cobra
-- el rider). El aliado NO la ve: su total = total - service_fee. El admin sí.
-- Tramos (calculados en checkout):
--   0–3 km: $0 · 3–4: $480 · 4–5: $880 · 5–6: $990 · 6–7: $1250 · 7–8: $1490
-- ============================================================================

-- 1. Columna para la tarifa de servicio
alter table public.orders add column if not exists service_fee numeric not null default 0;

-- 2. Cobertura máxima a 8 km en la config (la leen cliente y web)
update public.config
   set value = jsonb_set(value::jsonb, '{max_distance_km}', '8'::jsonb, true)::text
 where key = 'delivery_fees';

insert into public.config (key, value)
select 'delivery_fees', '{"base_fee":1500,"fee_per_100m":35,"max_distance_km":8}'
where not exists (select 1 from public.config where key = 'delivery_fees');
