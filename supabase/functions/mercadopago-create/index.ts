// Sin imports externos — usa fetch nativo de Deno para evitar boot_error

const SUPABASE_URL     = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_ACCESS_TOKEN  = Deno.env.get("MP_ACCESS_TOKEN")!;

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

    // Evitar crear preferencia para órdenes ya pagadas
    if (order.payment_status === "paid") {
      return json({ error: "Esta orden ya fue pagada" }, 409);
    }

    // Guardar web_return_url en la orden para que mercadopago-return sepa a dónde redirigir
    if (web_url) {
      await sbFetch(`/orders?id=eq.${encodeURIComponent(order.id)}`, {
        method: "PATCH",
        body: JSON.stringify({ web_return_url: web_url }),
      });
    }

    const returnUrl  = `${SUPABASE_URL}/functions/v1/mercadopago-return`;
    const notifyUrl  = `${SUPABASE_URL}/functions/v1/mercadopago-notify`;

    // Crear preferencia en Mercado Pago
    const mpRes = await fetch("https://api.mercadopago.com/checkout/preferences", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${MP_ACCESS_TOKEN}`,
      },
      body: JSON.stringify({
        items: [{
          id: `order-${order.id.slice(0, 12)}`,
          title: `Pedido Go Deli #${order.id.slice(0, 8)}`,
          quantity: 1,
          currency_id: "CLP",
          unit_price: Math.round(order.total),
        }],
        external_reference: order.id,
        back_urls: {
          success: returnUrl,
          failure: returnUrl,
          pending: returnUrl,
        },
        notification_url: notifyUrl,
        auto_return: "approved",
        statement_descriptor: "Go Deli",
        expires: true,
        expiration_date_to: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
      }),
    });

    const mpData = await mpRes.json();

    if (!mpRes.ok || !mpData.id || !mpData.init_point) {
      console.error("MP_CREATE_ERROR", JSON.stringify({ httpStatus: mpRes.status, body: mpData }));
      const mpError = mpData?.message ?? mpRes.statusText ?? "Error desconocido";
      return json({ error: "Error al crear preferencia Mercado Pago", detail: mpError, raw: mpData }, 502);
    }

    // Guardar preference_id en la orden
    await sbFetch(`/orders?id=eq.${order_id}`, {
      method: "PATCH",
      body: JSON.stringify({ mp_preference_id: mpData.id, payment_status: "pending", payment_method: "mercadopago" }),
    });

    return json({
      preference_id: mpData.id,
      init_point: mpData.init_point,
      sandbox_init_point: mpData.sandbox_init_point,
    });
  } catch (e) {
    console.error("mercadopago-create error:", e);
    return json({ error: String(e) }, 500);
  }
});
