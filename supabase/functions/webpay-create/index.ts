import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL     = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Credenciales Transbank — en integración usa los valores públicos de prueba.
// Para producción, setear TBK_COMMERCE_CODE, TBK_API_KEY y TBK_ENV=production
// en los secrets de Supabase (Dashboard → Edge Functions → Secrets).
const TBK_COMMERCE_CODE = Deno.env.get("TBK_COMMERCE_CODE") ?? "597055555532";
const TBK_API_KEY       = Deno.env.get("TBK_API_KEY")       ?? "579B532A7440BB0C9079DED94D31EA1615BACEB56610332264630D42D0A36B1C";
const TBK_ENV           = Deno.env.get("TBK_ENV")           ?? "integration";

const TBK_BASE = TBK_ENV === "production"
  ? "https://webpay3g.transbank.cl"
  : "https://webpay3gint.transbank.cl";

function buildReturnUrl(webUrl?: string): string {
  let url = `${SUPABASE_URL}/functions/v1/webpay-return`;
  if (webUrl) {
    url += `?web_url=${encodeURIComponent(webUrl)}`;
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
    if (!order_id) {
      return json({ error: "order_id requerido" }, 400);
    }

    const sb = createClient(SUPABASE_URL, SUPABASE_SVC_KEY);
    const { data: order, error } = await sb
      .from("orders")
      .select("id, total")
      .eq("id", order_id)
      .single();

    if (error || !order) return json({ error: "Orden no encontrada" }, 404);

    // buy_order debe ser único y ≤ 26 caracteres
    const buyOrder = `GD${order.id.replace(/-/g, "").slice(0, 20).toUpperCase()}`;
    const sessionId = `S${Date.now()}`;

    const tbkRes = await fetch(
      `${TBK_BASE}/rswebpaytransaction/api/webpay/v1.2/transactions`,
      {
        method: "POST",
        headers: {
          "Tbk-Api-Key-Id":     TBK_COMMERCE_CODE,
          "Tbk-Api-Key-Secret": TBK_API_KEY,
          "Content-Type":       "application/json",
        },
        body: JSON.stringify({
          buy_order:  buyOrder,
          session_id: sessionId,
          amount:     order.total,
          return_url: buildReturnUrl(web_url),
        }),
      },
    );

    const tbkData = await tbkRes.json();

    if (!tbkData.token || !tbkData.url) {
      return json({ error: "Error Transbank", detail: tbkData }, 500);
    }

    // Guardar token y web_url para identificar la orden al confirmar
    await sb.from("orders").update({
      webpay_token:   tbkData.token,
      payment_status: "pending_webpay",
    }).eq("id", order_id);

    return json({ token: tbkData.token, url: tbkData.url });
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
