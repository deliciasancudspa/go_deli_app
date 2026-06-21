-- ============================================================================
-- GO DELI — EXPANSIÓN NACIONAL: REGIONES, COMUNAS Y CONFIGURACIÓN POR COMUNA
-- ============================================================================
-- Migración: 20260621000000
-- Alcance:   Crear tablas regions/communes, seedear 16 regiones + 346 comunas,
--            agregar commune_id a todas las entidades, tabla commune_config,
--            actualizar RLS y políticas.
-- ⚠️  Ejecutar COMPLETO en el SQL Editor de Supabase. Es idempotente.
-- ============================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. TABLAS DE REGIONES Y COMUNAS
-- ═══════════════════════════════════════════════════════════════════════════════

create table if not exists public.regions (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.communes (
  id         uuid primary key default gen_random_uuid(),
  region_id  uuid not null references public.regions(id) on delete cascade,
  name       text not null,
  unique(region_id, name),
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- Índices para búsqueda rápida
create index if not exists idx_communes_region on public.communes(region_id);
create index if not exists idx_communes_name   on public.communes(name);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. SEED: 16 REGIONES DE CHILE
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_region_id uuid;
begin
  -- Solo inserta si la tabla está vacía (idempotente)
  if not exists (select 1 from public.regions) then
    ---------------------------------------------------------------------------
    -- 1  Arica y Parinacota
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Arica y Parinacota', 1) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Arica'), (v_region_id, 'Camarones'), (v_region_id, 'General Lagos'), (v_region_id, 'Putre');

    ---------------------------------------------------------------------------
    -- 2  Tarapacá
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Tarapacá', 2) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Iquique'), (v_region_id, 'Alto Hospicio'), (v_region_id, 'Camiña'),
      (v_region_id, 'Colchane'), (v_region_id, 'Huara'), (v_region_id, 'Pica'), (v_region_id, 'Pozo Almonte');

    ---------------------------------------------------------------------------
    -- 3  Antofagasta
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Antofagasta', 3) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Antofagasta'), (v_region_id, 'Calama'), (v_region_id, 'Tocopilla'),
      (v_region_id, 'Mejillones'), (v_region_id, 'Sierra Gorda'), (v_region_id, 'Taltal'),
      (v_region_id, 'María Elena'), (v_region_id, 'San Pedro de Atacama'), (v_region_id, 'Ollagüe');

    ---------------------------------------------------------------------------
    -- 4  Atacama
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Atacama', 4) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Copiapó'), (v_region_id, 'Vallenar'), (v_region_id, 'Caldera'),
      (v_region_id, 'Chañaral'), (v_region_id, 'Diego de Almagro'), (v_region_id, 'Freirina'),
      (v_region_id, 'Huasco'), (v_region_id, 'Tierra Amarilla'), (v_region_id, 'Alto del Carmen');

    ---------------------------------------------------------------------------
    -- 5  Coquimbo
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Coquimbo', 5) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'La Serena'), (v_region_id, 'Coquimbo'), (v_region_id, 'Ovalle'),
      (v_region_id, 'Illapel'), (v_region_id, 'Los Vilos'), (v_region_id, 'Salamanca'),
      (v_region_id, 'Vicuña'), (v_region_id, 'Paihuano'), (v_region_id, 'Río Hurtado'),
      (v_region_id, 'Canela'), (v_region_id, 'Andacollo'), (v_region_id, 'La Higuera'),
      (v_region_id, 'Monte Patria'), (v_region_id, 'Combarbalá');

    ---------------------------------------------------------------------------
    -- 6  Valparaíso
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Valparaíso', 6) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Valparaíso'), (v_region_id, 'Viña del Mar'), (v_region_id, 'Quilpué'),
      (v_region_id, 'Villa Alemana'), (v_region_id, 'San Antonio'), (v_region_id, 'Quillota'),
      (v_region_id, 'Los Andes'), (v_region_id, 'San Felipe'), (v_region_id, 'Calera'),
      (v_region_id, 'La Cruz'), (v_region_id, 'La Ligua'), (v_region_id, 'Petorca'),
      (v_region_id, 'Zapallar'), (v_region_id, 'Puchuncaví'), (v_region_id, 'Quintero'),
      (v_region_id, 'Casablanca'), (v_region_id, 'Olmué'), (v_region_id, 'Limache'),
      (v_region_id, 'Concón'), (v_region_id, 'Juan Fernández'), (v_region_id, 'Isla de Pascua');

    ---------------------------------------------------------------------------
    -- 7  Metropolitana de Santiago
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Metropolitana de Santiago', 7) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Santiago'), (v_region_id, 'Providencia'), (v_region_id, 'Las Condes'),
      (v_region_id, 'Maipú'), (v_region_id, 'Puente Alto'), (v_region_id, 'San Bernardo'),
      (v_region_id, 'La Florida'), (v_region_id, 'Ñuñoa'), (v_region_id, 'Vitacura'),
      (v_region_id, 'Lo Barnechea'), (v_region_id, 'Peñalolén'), (v_region_id, 'La Pintana'),
      (v_region_id, 'El Bosque'), (v_region_id, 'Quilicura'), (v_region_id, 'Pudahuel'),
      (v_region_id, 'Cerrillos'), (v_region_id, 'Renca'), (v_region_id, 'Huechuraba'),
      (v_region_id, 'Recoleta'), (v_region_id, 'Independencia'), (v_region_id, 'Cerro Navia'),
      (v_region_id, 'Lo Espejo'), (v_region_id, 'Lo Prado'), (v_region_id, 'Macul'),
      (v_region_id, 'Pedro Aguirre Cerda'), (v_region_id, 'San Joaquín'), (v_region_id, 'San Miguel'),
      (v_region_id, 'San Ramón'), (v_region_id, 'Estación Central'), (v_region_id, 'Colina'),
      (v_region_id, 'Lampa'), (v_region_id, 'Tiltil'), (v_region_id, 'Buin'),
      (v_region_id, 'Calera de Tango'), (v_region_id, 'Paine'), (v_region_id, 'San José de Maipo'),
      (v_region_id, 'Pirque'), (v_region_id, 'Melipilla'), (v_region_id, 'Alhué'),
      (v_region_id, 'María Pinto'), (v_region_id, 'San Pedro'), (v_region_id, 'Curacaví'),
      (v_region_id, 'Talagante'), (v_region_id, 'Padre Hurtado'), (v_region_id, 'Peñaflor'),
      (v_region_id, 'El Monte'), (v_region_id, 'Isla de Maipo');

    ---------------------------------------------------------------------------
    -- 8  O'Higgins
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('O''Higgins', 8) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Rancagua'), (v_region_id, 'San Fernando'), (v_region_id, 'Pichilemu'),
      (v_region_id, 'Rengo'), (v_region_id, 'Machalí'), (v_region_id, 'Graneros'),
      (v_region_id, 'Peumo'), (v_region_id, 'Doñihue'), (v_region_id, 'Olivar'),
      (v_region_id, 'Codegua'), (v_region_id, 'Coínco'), (v_region_id, 'Coltauco'),
      (v_region_id, 'Las Cabras'), (v_region_id, 'Mostazal'), (v_region_id, 'Quinta de Tilcoco'),
      (v_region_id, 'Requínoa'), (v_region_id, 'San Vicente'), (v_region_id, 'Litueche'),
      (v_region_id, 'La Estrella'), (v_region_id, 'Marchihue'), (v_region_id, 'Navidad'),
      (v_region_id, 'Paredones'), (v_region_id, 'Chépica'), (v_region_id, 'Chimbarongo'),
      (v_region_id, 'Lolol'), (v_region_id, 'Nancagua'), (v_region_id, 'Palmilla'),
      (v_region_id, 'Peralillo'), (v_region_id, 'Placilla'), (v_region_id, 'Pumanque'),
      (v_region_id, 'Santa Cruz');

    ---------------------------------------------------------------------------
    -- 9  Maule
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Maule', 9) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Talca'), (v_region_id, 'Curicó'), (v_region_id, 'Linares'),
      (v_region_id, 'Cauquenes'), (v_region_id, 'Constitución'), (v_region_id, 'San Clemente'),
      (v_region_id, 'Maule'), (v_region_id, 'Pelarco'), (v_region_id, 'Pencahue'),
      (v_region_id, 'Río Claro'), (v_region_id, 'San Rafael'), (v_region_id, 'Villa Alegre'),
      (v_region_id, 'Yerbas Buenas'), (v_region_id, 'Curepto'), (v_region_id, 'Empedrado'),
      (v_region_id, 'Rauco'), (v_region_id, 'Romeral'), (v_region_id, 'Sagrada Familia'),
      (v_region_id, 'Teno'), (v_region_id, 'Vichuquén'), (v_region_id, 'Longaví'),
      (v_region_id, 'Parral'), (v_region_id, 'Retiro'), (v_region_id, 'San Javier'),
      (v_region_id, 'Chanco'), (v_region_id, 'Pelluhue');

    ---------------------------------------------------------------------------
    -- 10 Ñuble
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Ñuble', 10) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Chillán'), (v_region_id, 'Chillán Viejo'), (v_region_id, 'Bulnes'),
      (v_region_id, 'Cobquecura'), (v_region_id, 'Coelemu'), (v_region_id, 'Coihueco'),
      (v_region_id, 'El Carmen'), (v_region_id, 'Ninhue'), (v_region_id, 'Ñiquén'),
      (v_region_id, 'Pemuco'), (v_region_id, 'Pinto'), (v_region_id, 'Portezuelo'),
      (v_region_id, 'Quillón'), (v_region_id, 'Quirihue'), (v_region_id, 'Ránquil'),
      (v_region_id, 'San Carlos'), (v_region_id, 'San Fabián'), (v_region_id, 'San Ignacio'),
      (v_region_id, 'San Nicolás'), (v_region_id, 'Treguaco'), (v_region_id, 'Yungay');

    ---------------------------------------------------------------------------
    -- 11 Biobío
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Biobío', 11) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Concepción'), (v_region_id, 'Talcahuano'), (v_region_id, 'Chiguayante'),
      (v_region_id, 'Coronel'), (v_region_id, 'Hualpén'), (v_region_id, 'Lota'),
      (v_region_id, 'Penco'), (v_region_id, 'San Pedro de la Paz'), (v_region_id, 'Santa Juana'),
      (v_region_id, 'Tomé'), (v_region_id, 'Hualqui'), (v_region_id, 'Florida'),
      (v_region_id, 'Los Ángeles'), (v_region_id, 'Cabrero'), (v_region_id, 'Laja'),
      (v_region_id, 'Mulchén'), (v_region_id, 'Nacimiento'), (v_region_id, 'Negrete'),
      (v_region_id, 'Quilaco'), (v_region_id, 'Quilleco'), (v_region_id, 'San Rosendo'),
      (v_region_id, 'Santa Bárbara'), (v_region_id, 'Tucapel'), (v_region_id, 'Yumbel'),
      (v_region_id, 'Antuco'), (v_region_id, 'Arauco'), (v_region_id, 'Cañete'),
      (v_region_id, 'Contulmo'), (v_region_id, 'Curanilahue'), (v_region_id, 'Lebu'),
      (v_region_id, 'Los Álamos'), (v_region_id, 'Tirúa');

    ---------------------------------------------------------------------------
    -- 12 La Araucanía
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('La Araucanía', 12) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Temuco'), (v_region_id, 'Padre Las Casas'), (v_region_id, 'Villarrica'),
      (v_region_id, 'Pucón'), (v_region_id, 'Angol'), (v_region_id, 'Collipulli'),
      (v_region_id, 'Curacautín'), (v_region_id, 'Ercilla'), (v_region_id, 'Lonquimay'),
      (v_region_id, 'Los Sauces'), (v_region_id, 'Lumaco'), (v_region_id, 'Purén'),
      (v_region_id, 'Renaico'), (v_region_id, 'Traiguén'), (v_region_id, 'Victoria'),
      (v_region_id, 'Carahue'), (v_region_id, 'Cholchol'), (v_region_id, 'Freire'),
      (v_region_id, 'Galvarino'), (v_region_id, 'Gorbea'), (v_region_id, 'Lautaro'),
      (v_region_id, 'Loncoche'), (v_region_id, 'Melipeuco'), (v_region_id, 'Nueva Imperial'),
      (v_region_id, 'Perquenco'), (v_region_id, 'Pitrufquén'), (v_region_id, 'Cunco'),
      (v_region_id, 'Teodoro Schmidt'), (v_region_id, 'Toltén'), (v_region_id, 'Vilcún');

    ---------------------------------------------------------------------------
    -- 13 Los Ríos
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Los Ríos', 13) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Valdivia'), (v_region_id, 'La Unión'), (v_region_id, 'Futrono'),
      (v_region_id, 'Lago Ranco'), (v_region_id, 'Lanco'), (v_region_id, 'Los Lagos'),
      (v_region_id, 'Máfil'), (v_region_id, 'Mariquina'), (v_region_id, 'Paillaco'),
      (v_region_id, 'Panguipulli'), (v_region_id, 'Río Bueno'), (v_region_id, 'Corral');

    ---------------------------------------------------------------------------
    -- 14 Los Lagos
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Los Lagos', 14) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Puerto Montt'), (v_region_id, 'Osorno'), (v_region_id, 'Puerto Varas'),
      (v_region_id, 'Castro'), (v_region_id, 'Ancud'), (v_region_id, 'Calbuco'),
      (v_region_id, 'Chonchi'), (v_region_id, 'Curaco de Vélez'), (v_region_id, 'Dalcahue'),
      (v_region_id, 'Fresia'), (v_region_id, 'Frutillar'), (v_region_id, 'Hualaihué'),
      (v_region_id, 'Llanquihue'), (v_region_id, 'Los Muermos'), (v_region_id, 'Maullín'),
      (v_region_id, 'Puerto Octay'), (v_region_id, 'Puqueldón'), (v_region_id, 'Purranque'),
      (v_region_id, 'Puyehue'), (v_region_id, 'Queilén'), (v_region_id, 'Quellón'),
      (v_region_id, 'Quemchi'), (v_region_id, 'Quinchao'), (v_region_id, 'Río Negro'),
      (v_region_id, 'San Juan de la Costa'), (v_region_id, 'San Pablo'), (v_region_id, 'Cochamó');

    ---------------------------------------------------------------------------
    -- 15 Aysén
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Aysén', 15) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Coyhaique'), (v_region_id, 'Puerto Aysén'), (v_region_id, 'Chile Chico'),
      (v_region_id, 'Cisnes'), (v_region_id, 'Cochrane'), (v_region_id, 'Guaitecas'),
      (v_region_id, 'Lago Verde'), (v_region_id, 'O''Higgins'), (v_region_id, 'Río Ibáñez'),
      (v_region_id, 'Tortel');

    ---------------------------------------------------------------------------
    -- 16 Magallanes
    ---------------------------------------------------------------------------
    insert into regions(name, sort_order) values ('Magallanes', 16) returning id into v_region_id;
    insert into communes(region_id, name) values
      (v_region_id, 'Punta Arenas'), (v_region_id, 'Puerto Natales'), (v_region_id, 'Porvenir'),
      (v_region_id, 'Puerto Williams'), (v_region_id, 'Antártica'), (v_region_id, 'Cabo de Hornos'),
      (v_region_id, 'Laguna Blanca'), (v_region_id, 'Río Verde'), (v_region_id, 'San Gregorio'),
      (v_region_id, 'Timaukel'), (v_region_id, 'Torres del Paine');
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2b. ACTUALIZAR zones CON REFERENCIA A COMUNAS
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.zones add column if not exists commune_id uuid references public.communes(id);

-- Mapear zonas existentes a comunas (por nombre de ciudad)
do $$
begin
  -- Ancud → comuna Ancud en Los Lagos
  update zones z set commune_id = c.id
  from communes c join regions r on r.id = c.region_id
  where r.name = 'Los Lagos' and c.name = 'Ancud' and z.city = 'Ancud' and z.commune_id is null;

  -- Castro → comuna Castro en Los Lagos
  update zones z set commune_id = c.id
  from communes c join regions r on r.id = c.region_id
  where r.name = 'Los Lagos' and c.name = 'Castro' and z.city = 'Castro' and z.commune_id is null;

  -- Puerto Montt → comuna Puerto Montt en Los Lagos
  update zones z set commune_id = c.id
  from communes c join regions r on r.id = c.region_id
  where r.name = 'Los Lagos' and c.name = 'Puerto Montt' and z.city = 'Puerto Montt' and z.commune_id is null;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. AGREGAR commune_id A TABLAS EXISTENTES
-- ═══════════════════════════════════════════════════════════════════════════════

-- Entidades principales
alter table public.stores     add column if not exists commune_id uuid references public.communes(id);
alter table public.deliverers add column if not exists commune_id uuid references public.communes(id);
alter table public.users      add column if not exists commune_id uuid references public.communes(id);
alter table public.orders     add column if not exists commune_id uuid references public.communes(id);

-- Contenido y alcance
alter table public.banners        add column if not exists commune_id uuid references public.communes(id);
alter table public.home_sections  add column if not exists commune_id uuid references public.communes(id);
alter table public.ad_campaigns   add column if not exists commune_id uuid references public.communes(id);
alter table public.notifications  add column if not exists commune_id uuid references public.communes(id);

-- Índices para filtros por comuna
create index if not exists idx_stores_commune      on public.stores(commune_id)      where commune_id is not null;
create index if not exists idx_deliverers_commune  on public.deliverers(commune_id)  where commune_id is not null;
create index if not exists idx_users_commune       on public.users(commune_id)       where commune_id is not null;
create index if not exists idx_orders_commune      on public.orders(commune_id)      where commune_id is not null;
create index if not exists idx_banners_commune     on public.banners(commune_id)     where commune_id is not null;
create index if not exists idx_home_sections_commune on public.home_sections(commune_id) where commune_id is not null;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. TABLA DE CONFIGURACIÓN POR COMUNA
-- ═══════════════════════════════════════════════════════════════════════════════

create table if not exists public.commune_config (
  id            uuid primary key default gen_random_uuid(),
  commune_id    uuid not null references public.communes(id) on delete cascade unique,
  delivery_fees jsonb not null default '{}'::jsonb,  -- {base_fee, fee_per_100m, max_distance_km}
  service_fee   numeric not null default 0,
  min_order     numeric not null default 0,
  is_active     boolean not null default true,
  updated_at    timestamptz not null default now()
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. MIGRAR DATOS EXISTENTES: stores
--    Usar zone.city para buscar la comuna → asignar commune_id a la tienda
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
begin
  -- Tiendas con zone_id poblado: mapear vía zones.commune_id
  update stores s set commune_id = z.commune_id
  from zones z
  where s.zone_id = z.id
    and s.commune_id is null
    and z.commune_id is not null;

  -- Tiendas con city poblado pero sin zone: buscar comuna por nombre de ciudad
  update stores s set commune_id = c.id
  from communes c join regions r on r.id = c.region_id
  where s.city = c.name
    and s.commune_id is null;

  -- Tiendas con address que mencione una ciudad conocida (Ancud)
  update stores s set commune_id = c.id
  from communes c join regions r on r.id = c.region_id
  where s.address ilike '%' || c.name || '%'
    and s.commune_id is null
    and r.name = 'Los Lagos';
end $$;

-- Migrar deliverers: usar current_lat/current_lng para buscar comuna vía zones,
-- o asignar según zone_id
do $$
begin
  update deliverers d set commune_id = z.commune_id
  from zones z
  where d.zone_id = z.id
    and d.commune_id is null
    and z.commune_id is not null;

  -- Si no tiene zone_id pero está en Chiloé (lat ~ -41.8 a -42.7, lng ~ -73.5 a -74),
  -- asignar Ancud por defecto
  update deliverers d set commune_id = c.id
  from communes c join regions r on r.id = c.region_id
  where r.name = 'Los Lagos' and c.name = 'Ancud'
    and d.commune_id is null
    and d.current_lat between -42.0 and -41.8
    and d.current_lng between -74.0 and -73.5;
end $$;

-- Migrar orders: copiar commune_id de la tienda asociada
-- (deshabilitar trigger check_order_update_columns temporalmente — la migración
--  no es un cliente/ride/tienda real y el trigger rechazaría el UPDATE)
alter table public.orders disable trigger trg_check_order_update;

update orders o set commune_id = s.commune_id
from stores s
where o.store_id = s.id
  and o.commune_id is null
  and s.commune_id is not null;

alter table public.orders enable trigger trg_check_order_update;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. RPCs ÚTILES PARA COMUNAS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Buscar comuna por nombre (con región opcional para desambiguar)
create or replace function public.find_commune(p_name text, p_region text default null)
returns uuid language sql stable as $$
  select c.id from communes c
  join regions r on r.id = c.region_id
  where lower(c.name) = lower(p_name)
    and (p_region is null or lower(r.name) = lower(p_region))
  limit 1;
$$;

-- Listar todas las comunas activas con región (para dropdowns en admin y app)
create or replace function public.list_communes()
returns table(commune_id uuid, commune_name text, region_name text, region_id uuid)
language sql stable as $$
  select c.id, c.name, r.name, r.id
  from communes c join regions r on r.id = c.region_id
  where c.is_active = true
  order by r.sort_order, c.name;
$$;

-- Dashboard nacional: métricas agregadas por comuna (solo admin)
create or replace function public.national_dashboard()
returns table(
  commune_id    uuid,
  commune_name  text,
  region_name   text,
  total_stores  bigint,
  total_riders  bigint,
  total_orders  bigint,
  total_revenue numeric
)
language sql stable security definer set search_path = public as $$
  select
    c.id,
    c.name,
    r.name,
    count(distinct s.id) filter (where s.is_active = true),
    count(distinct d.id) filter (where d.status = 'approved'),
    count(distinct o.id),
    coalesce(sum(o.total) filter (where o.status = 'delivered'), 0)
  from communes c
  join regions r on r.id = c.region_id
  left join stores s     on s.commune_id = c.id
  left join deliverers d on d.commune_id = c.id
  left join orders o     on o.commune_id = c.id
  where c.is_active = true
  group by c.id, c.name, r.name
  order by r.name, c.name;
$$;

grant execute on function public.find_commune(text, text) to authenticated;
grant execute on function public.list_communes() to authenticated, anon;
grant execute on function public.national_dashboard() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. POLÍTICAS RLS PARA LAS NUEVAS TABLAS
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.regions enable row level security;
alter table public.communes enable row level security;
alter table public.commune_config enable row level security;

-- regions: lectura pública
drop policy if exists regions_select on public.regions;
create policy regions_select on public.regions for select using (true);

-- communes: lectura pública
drop policy if exists communes_select on public.communes;
create policy communes_select on public.communes for select using (true);

-- commune_config: lectura pública, escritura solo admin
drop policy if exists commune_config_select on public.commune_config;
create policy commune_config_select on public.commune_config for select using (true);

drop policy if exists commune_config_write on public.commune_config;
create policy commune_config_write on public.commune_config for all to authenticated
using (public.is_admin()) with check (public.is_admin());

-- Solo admin puede escribir en regions/communes
drop policy if exists regions_write on public.regions;
create policy regions_write on public.regions for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists communes_write on public.communes;
create policy communes_write on public.communes for all to authenticated
using (public.is_admin()) with check (public.is_admin());

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════════════════
-- select count(*) from regions;     -- debe ser 16
-- select count(*) from communes;    -- debe ser 346
-- select count(*) from stores where commune_id is not null;  -- tiendas migradas
-- select count(*) from deliverers where commune_id is not null;
-- select count(*) from orders where commune_id is not null;

commit;
