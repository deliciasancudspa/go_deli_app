// Sin imports externos — usa fetch nativo de Deno para evitar boot_error

const SUPABASE_URL     = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TBK_COMMERCE_CODE = Deno.env.get("TBK_COMMERCE_CODE") ?? "597055555532";
const TBK_API_KEY       = Deno.env.get("TBK_API_KEY") ?? "579B532A7440BB0C9079DED94D31EA1615BACEB56610332264630D42D0A36B1C";
const TBK_ENV           = Deno.env.get("TBK_ENV") ?? "integration";
const TBK_BASE = TBK_ENV === "production"
  ? "https://webpay3g.transbank.cl"
  : "https://webpay3gint.transbank.cl";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function sbFetch(path: string, options: RequestInit = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1${path}`, {
    ...options,
    headers: {
      "apikey": SUPABASE_SVC_KEY,
      "Authorization": `Bearer ${SUPABASE_SVC_KEY}`,
      "Content-Type": "application/json",
      "Prefer": "return=representation",
      ...(options.headers ?? {}),
    },
  });
  return res.json();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { order_id, web_url } = await req.json();
    if (!order_id) return json({ error: "order_id requerido" }, 400);

    // Buscar la orden
    const orders = await sbFetch(`/orders?id=eq.${order_id}&select=id,total,payment_status`);
    if (!Array.isArray(orders) || orders.length === 0) {
      return json({ error: "Orden no encontrada" }, 404);
    }
    const order = orders[0];

    // Evitar crear transacción para órdenes ya pagadas
    if (order.payment_status === "paid") {
      return json({ error: "Esta orden ya fue pagada" }, 409);
    }

    // buy_order debe ser único por intento. Si el usuario reintenta con la misma
    // orden (pago pendiente reutilizado), añadimos un sufijo temporal para que
    // Transbank no rechace la transacción por duplicado.
    const ts = Date.now().toString(36).slice(-4).toUpperCase();
    const buyOrder = `GD${order.id.replace(/-/g, "").slice(0, 18).toUpperCase()}${ts}`;
    // session_id también lleva timestamp + random para evitar colisiones
    const sessionId = `S${Date.now()}${Math.random().toString(36).slice(2, 6)}`;
    let returnUrl = `${SUPABASE_URL}/functions/v1/webpay-return`;
    if (web_url) returnUrl += `?web_url=${encodeURIComponent(web_url)}`;

    // Crear transacción en Transbank
    const tbkRes = await fetch(
      `${TBK_BASE}/rswebpaytransaction/api/webpay/v1.2/transactions`,
      {
        method: "POST",
        headers: {
          "Tbk-Api-Key-Id": TBK_COMMERCE_CODE,
          "Tbk-Api-Key-Secret": TBK_API_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          buy_order: buyOrder,
          session_id: sessionId,
          amount: order.total,
          return_url: returnUrl,
        }),
      },
    );

    const tbkData = await tbkRes.json();

    // Validar respuesta HTTP y errores de negocio de Transbank
    if (!tbkRes.ok || !tbkData.token || !tbkData.url) {
      console.error("TBK_CREATE_ERROR", JSON.stringify({ httpStatus: tbkRes.status, body: tbkData }));
      const tbkError = tbkData?.error_message ?? tbkRes.statusText ?? "Error desconocido";
      return json({ error: "Error al crear transacción WebPay", detail: tbkError, raw: tbkData }, 502);
    }

    // Actualizar orden con el token
    await sbFetch(`/orders?id=eq.${order_id}`, {
      method: "PATCH",
      body: JSON.stringify({ webpay_token: tbkData.token, payment_status: "pending" }),
    });

    return json({ token: tbkData.token, url: tbkData.url });
  } catch (e) {
    console.error("webpay-create error:", e);
    return json({ error: String(e) }, 500);
  }
});
