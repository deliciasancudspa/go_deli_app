-- Re-seed de comunas: INSERT ... ON CONFLICT DO NOTHING para añadir las que falten.
-- Datos extraídos de lib/core/constants/chile_data.dart (315 comunas en 16 regiones).

begin;

-- Función auxiliar para obtener region_id por nombre
create or replace function pg_temp.region_id(rname text) returns uuid as $$
  select id from public.regions where name = rname limit 1;
$$ language sql;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1  Arica y Parinacota (4)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Arica y Parinacota'), n from unnest(array['Arica','Camarones','General Lagos','Putre']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2  Tarapacá (7)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Tarapacá'), n from unnest(array['Iquique','Alto Hospicio','Camiña','Colchane','Huara','Pica','Pozo Almonte']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3  Antofagasta (9)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Antofagasta'), n from unnest(array['Antofagasta','Calama','Tocopilla','Mejillones','Sierra Gorda','Taltal','María Elena','San Pedro de Atacama','Ollagüe']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4  Atacama (9)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Atacama'), n from unnest(array['Copiapó','Vallenar','Caldera','Chañaral','Diego de Almagro','Freirina','Huasco','Tierra Amarilla','Alto del Carmen']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5  Coquimbo (14)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Coquimbo'), n from unnest(array['La Serena','Coquimbo','Ovalle','Illapel','Los Vilos','Salamanca','Vicuña','Paihuano','Río Hurtado','Canela','Andacollo','La Higuera','Monte Patria','Combarbalá']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6  Valparaíso (21)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Valparaíso'), n from unnest(array['Valparaíso','Viña del Mar','Quilpué','Villa Alemana','San Antonio','Quillota','Los Andes','San Felipe','Calera','La Cruz','La Ligua','Petorca','Zapallar','Puchuncaví','Quintero','Casablanca','Olmué','Limache','Concón','Juan Fernández','Isla de Pascua']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7  Metropolitana de Santiago (47)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Metropolitana de Santiago'), n from unnest(array['Santiago','Providencia','Las Condes','Maipú','Puente Alto','San Bernardo','La Florida','Ñuñoa','Vitacura','Lo Barnechea','Peñalolén','La Pintana','El Bosque','Quilicura','Pudahuel','Cerrillos','Renca','Huechuraba','Recoleta','Independencia','Cerro Navia','Lo Espejo','Lo Prado','Macul','Pedro Aguirre Cerda','San Joaquín','San Miguel','San Ramón','Estación Central','Colina','Lampa','Tiltil','Buin','Calera de Tango','Paine','San José de Maipo','Pirque','Melipilla','Alhué','María Pinto','San Pedro','Curacaví','Talagante','Padre Hurtado','Peñaflor','El Monte','Isla de Maipo']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8  O'Higgins (31)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('O''Higgins'), n from unnest(array['Rancagua','San Fernando','Pichilemu','Rengo','Machalí','Graneros','Peumo','Doñihue','Olivar','Codegua','Coínco','Coltauco','Las Cabras','Mostazal','Quinta de Tilcoco','Requínoa','San Vicente','Litueche','La Estrella','Marchihue','Navidad','Paredones','Chépica','Chimbarongo','Lolol','Nancagua','Palmilla','Peralillo','Placilla','Pumanque','Santa Cruz']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9  Maule (26)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Maule'), n from unnest(array['Talca','Curicó','Linares','Cauquenes','Constitución','San Clemente','Maule','Pelarco','Pencahue','Río Claro','San Rafael','Villa Alegre','Yerbas Buenas','Curepto','Empedrado','Rauco','Romeral','Sagrada Familia','Teno','Vichuquén','Longaví','Parral','Retiro','San Javier','Chanco','Pelluhue']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10 Ñuble (21)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Ñuble'), n from unnest(array['Chillán','Chillán Viejo','Bulnes','Cobquecura','Coelemu','Coihueco','El Carmen','Ninhue','Ñiquén','Pemuco','Pinto','Portezuelo','Quillón','Quirihue','Ránquil','San Carlos','San Fabián','San Ignacio','San Nicolás','Treguaco','Yungay']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11 Biobío (32)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Biobío'), n from unnest(array['Concepción','Talcahuano','Chiguayante','Coronel','Hualpén','Lota','Penco','San Pedro de la Paz','Santa Juana','Tomé','Hualqui','Florida','Los Ángeles','Cabrero','Laja','Mulchén','Nacimiento','Negrete','Quilaco','Quilleco','San Rosendo','Santa Bárbara','Tucapel','Yumbel','Antuco','Arauco','Cañete','Contulmo','Curanilahue','Lebu','Los Álamos','Tirúa']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 12 La Araucanía (30)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('La Araucanía'), n from unnest(array['Temuco','Padre Las Casas','Villarrica','Pucón','Angol','Collipulli','Curacautín','Ercilla','Lonquimay','Los Sauces','Lumaco','Purén','Renaico','Traiguén','Victoria','Carahue','Cholchol','Freire','Galvarino','Gorbea','Lautaro','Loncoche','Melipeuco','Nueva Imperial','Perquenco','Pitrufquén','Cunco','Teodoro Schmidt','Toltén','Vilcún']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 13 Los Ríos (12)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Los Ríos'), n from unnest(array['Valdivia','La Unión','Futrono','Lago Ranco','Lanco','Los Lagos','Máfil','Mariquina','Paillaco','Panguipulli','Río Bueno','Corral']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 14 Los Lagos (27)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Los Lagos'), n from unnest(array['Puerto Montt','Osorno','Puerto Varas','Castro','Ancud','Calbuco','Chonchi','Curaco de Vélez','Dalcahue','Fresia','Frutillar','Hualaihué','Llanquihue','Los Muermos','Maullín','Puerto Octay','Puqueldón','Purranque','Puyehue','Queilén','Quellón','Quemchi','Quinchao','Río Negro','San Juan de la Costa','San Pablo','Cochamó']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 15 Aysén (10)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Aysén'), n from unnest(array['Coyhaique','Puerto Aysén','Chile Chico','Cisnes','Cochrane','Guaitecas','Lago Verde','O''Higgins','Río Ibáñez','Tortel']) as n on conflict (region_id, name) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 16 Magallanes (11)
-- ═══════════════════════════════════════════════════════════════════════════════
insert into communes(region_id, name) select pg_temp.region_id('Magallanes'), n from unnest(array['Punta Arenas','Puerto Natales','Porvenir','Puerto Williams','Antártica','Cabo de Hornos','Laguna Blanca','Río Verde','San Gregorio','Timaukel','Torres del Paine']) as n on conflict (region_id, name) do nothing;

-- Limpiar función temporal
drop function pg_temp.region_id;

commit;
