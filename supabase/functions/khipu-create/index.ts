import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL     = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Credencial de Khipu — setear en Supabase Secrets: Dashboard → Edge Functions → Secrets
// Obtener en: khipu.com → Mis cuentas de cobro → API
const KHIPU_API_KEY = Deno.env.get("KHIPU_API_KEY") ?? "";

const KHIPU_API  = "https://payment-api.khipu.com/v3/payments";
const NOTIFY_URL = `${SUPABASE_URL}/functions/v1/khipu-notify`;

function buildReturnUrl(orderId: string, webUrl?: string): string {
  let url = `${SUPABASE_URL}/functions/v1/khipu-return?order_id=${orderId}`;
  if (webUrl) {
    url += `&web_url=${encodeURIComponent(webUrl)}`;
  }
  return url;
}

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { order_id, web_url } = await req.json();
    if (!order_id) return json({ error: "order_id requerido" }, 400);
    if (!KHIPU_API_KEY) return json({ error: "KHIPU_API_KEY no configurada" }, 500);

    const sb = createClient(SUPABASE_URL, SUPABASE_SVC_KEY);
    const { data: order, error } = await sb
      .from("orders")
      .select("id, total")
      .eq("id", order_id)
      .single();

    if (error || !order) return json({ error: "Orden no encontrada" }, 404);

    const res = await fetch(KHIPU_API, {
      method: "POST",
      headers: {
        "x-api-key":    KHIPU_API_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        subject:    `Pedido Go Deli #${order.id.slice(0, 8).toUpperCase()}`,
        currency:   "CLP",
        amount:     order.total,
        return_url: buildReturnUrl(order.id, web_url),
        notify_url: NOTIFY_URL,
        // Expiración en 30 minutos
        expires_date: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
      }),
    });

    const data = await res.json();

    if (!data.payment_id || !data.payment_url) {
      return json({ error: "Error Khipu", detail: data }, 500);
    }

    // Guardar payment_id para identificar la orden en el webhook
    await sb.from("orders").update({
      khipu_payment_id: data.payment_id,
      payment_status:   "pending_khipu",
    }).eq("id", order_id);

    return json({ payment_id: data.payment_id, payment_url: data.payment_url });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
