-- Permitir que pg_net haga requests a la Edge Function de Supabase
-- La función puede llamarse allow_domain (singular) según la versión de pg_net
do $$
begin
  -- Intentar forma singular (versiones recientes)
  perform net.allow_domain('yxseolcaububyifhksud.supabase.co');
  raise notice 'net.allow_domain ejecutado correctamente';
exception when others then
  raise notice 'net.allow_domain falló: %. La extensión pg_net puede no estar configurada.', sqlerrm;
end;
$$;
