// Sin imports externos — usa fetch nativo de Deno para evitar boot_error

const SUPABASE_URL     = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_ACCESS_TOKEN  = Deno.env.get("MP_ACCESS_TOKEN")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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
    let paymentId: string | null = null;
    let type: string | null = null;

    // Mercado Pago envía webhook con query params: ?data.id=PAYMENT_ID&type=payment
    const url = new URL(req.url);
    paymentId = url.searchParams.get("data.id");
    type      = url.searchParams.get("type");

    // También puede venir en el body como JSON
    if (!paymentId && req.method === "POST") {
      const ct = req.headers.get("content-type") ?? "";
      if (ct.includes("application/json")) {
        try {
          const body = await req.json();
          paymentId = body.data?.id ?? body.data_id ?? null;
          type      = body.type ?? body.action ?? null;
        } catch (_) { /* ignorar */ }
      }
    }

    if (!paymentId || type !== "payment") {
      // Retornar 200 para que MP no reintente notificaciones que no son de pago
      return new Response("ok", { status: 200, headers: CORS });
    }

    console.log("MP_NOTIFY", JSON.stringify({ paymentId, type }));

    // Buscar la orden por mp_payment_id (puede que ya haya sido actualizada)
    const existing = await sbFetch(
      `/orders?mp_payment_id=eq.${encodeURIComponent(paymentId)}&select=id,payment_status`
    );
    const existingOrder = Array.isArray(existing) && existing.length > 0 ? existing[0] : null;

    // Si ya está paid, no hacer nada (idempotente)
    if (existingOrder?.payment_status === "paid") {
      return new Response("ok", { status: 200, headers: CORS });
    }

    // Verificar el pago con la API de Mercado Pago
    const mpRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
      headers: { "Authorization": `Bearer ${MP_ACCESS_TOKEN}` },
    });
    const payment = await mpRes.json();

    console.log("MP_NOTIFY_PAYMENT", JSON.stringify({
      paymentId,
      httpStatus: mpRes.status,
      status: payment.status,
      status_detail: payment.status_detail,
      external_reference: payment.external_reference,
    }));

    const orderId = existingOrder?.id ?? payment.external_reference;

    if (!orderId) {
      console.error("MP_NOTIFY_NO_ORDER", "No se pudo identificar la orden para el pago", paymentId);
      return new Response("ok", { status: 200, headers: CORS });
    }

    if (payment.status === "approved") {
      // Verificar que la orden no esté ya paid (race condition con mercadopago-return)
      const check = await sbFetch(
        `/orders?id=eq.${encodeURIComponent(orderId)}&select=payment_status`
      );
      const current = Array.isArray(check) && check.length > 0 ? check[0] : null;
      if (current?.payment_status === "paid") {
        return new Response("ok", { status: 200, headers: CORS });
      }

      await sbFetch(`/orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: "PATCH",
        body: JSON.stringify({
          payment_status: "paid",
          status: "accepted",
          mp_payment_id: paymentId,
          mp_payment_response: payment,
        }),
      });
    } else if (payment.status === "rejected" || payment.status === "cancelled") {
      await sbFetch(`/orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: "PATCH",
        body: JSON.stringify({
          payment_status: "failed",
          status: "cancelled",
          mp_payment_id: paymentId,
          mp_payment_response: payment,
        }),
      });
    }
    // Para "in_process", "pending", "authorized" — no actualizar, esperar siguiente notificación

    return new Response("ok", { status: 200, headers: CORS });
  } catch (e) {
    console.error("mercadopago-notify error:", e);
    // Siempre retornar 200 para que MP no reintente indefinidamente
    return new Response("ok", { status: 200, headers: CORS });
  }
});
