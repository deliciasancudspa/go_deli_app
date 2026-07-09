-- ============================================================================
-- TRIGGER: Enviar push FCM al cliente cuando cambia el estado de su pedido
-- ============================================================================
-- Usa pg_net para llamar a la Edge Function notify-client en cada cambio de
-- estado. Así el cliente recibe notificaciones incluso con la app en segundo
-- plano o cerrada (Android/iOS muestran el push automáticamente).
--
-- ⚠️ Requisito previo: habilitar la extensión pg_net en Supabase
--    Dashboard → Database → Extensions → buscar "pg_net" → Enable
--
-- ⚠️ También debe ejecutarse en Supabase SQL Editor:
--    select net.allow_domains('yxseolcaububyifhksud.supabase.co');
-- ============================================================================

-- 1. Extensión pg_net (equivale a CREATE EXTENSION IF NOT EXISTS)
create extension if not exists pg_net;

-- 2. Función trigger: llama a notify-client vía HTTP
create or replace function public.notify_client_on_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_secret       text;
  v_url          text;
  v_body         jsonb;
  v_headers      jsonb;
begin
  -- Solo enviar si el status realmente cambió (y no es null)
  if new.status is null or new.status = old.status then
    return new;
  end if;

  -- Solo para pedidos de delivery gestionados por Go Rider (no delivery propio)
  -- y solo si el cliente está asignado
  if new.client_id is null then
    return new;
  end if;

  -- URL de la Edge Function (hardcodeada: reemplazar si cambia el project ref)
  v_url := 'https://yxseolcaububyifhksud.supabase.co/functions/v1/notify-client';

  -- Intentar leer el secreto desde la tabla vault (si existe)
  begin
    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name = 'NOTIFY_WEBHOOK_SECRET';
  exception when others then
    v_secret := null;
  end;

  -- Payload: mismo formato que un Supabase Database Webhook
  v_body := jsonb_build_object(
    'type', 'UPDATE',
    'table', 'orders',
    'record', jsonb_build_object(
      'id', new.id,
      'client_id', new.client_id,
      'status', new.status,
      'store_id', new.store_id
    ),
    'old_record', jsonb_build_object(
      'status', old.status
    )
  );

  -- Headers (incluye webhook secret si está configurado)
  v_headers := jsonb_build_object(
    'Content-Type', 'application/json'
  );
  if v_secret is not null and v_secret != '' then
    v_headers := v_headers || jsonb_build_object('x-webhook-secret', v_secret);
  end if;

  -- Enviar HTTP POST asíncrono (no bloquea la transacción)
  begin
    perform net.http_post(
      url := v_url,
      body := v_body::text,
      headers := v_headers,
      timeout_milliseconds := 5000
    );
  exception when others then
    -- pg_net puede fallar si la extensión no está habilitada o la URL no está
    -- en la lista de dominios permitidos. El pedido se actualiza igual.
    raise warning 'notify_client trigger: pg_net error (%)', sqlerrm;
  end;

  return new;
end;
$$;

-- 3. Trigger AFTER UPDATE en orders
drop trigger if exists trg_notify_client_status on public.orders;
create trigger trg_notify_client_status
  after update on public.orders
  for each row
  execute function public.notify_client_on_status_change();
