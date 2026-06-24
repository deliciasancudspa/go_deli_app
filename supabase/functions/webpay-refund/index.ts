// Edge Function: Reembolso / anulación de transacciones Webpay Plus
// Soporta reembolso total y parcial. Usa el token original de la transacción.
//
// POST body: { order_id: string, amount?: number }
//   - amount omitido o igual al total → reembolso total
//   - amount menor al total → reembolso parcial

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
    const { order_id, amount } = await req.json();
    if (!order_id) return json({ error: "order_id requerido" }, 400);

    // Buscar la orden con su token de transacción
    const orders = await sbFetch(
      `/orders?id=eq.${encodeURIComponent(order_id)}&select=id,total,webpay_token,payment_status,refund_status,refund_amount`
    );
    if (!Array.isArray(orders) || orders.length === 0) {
      return json({ error: "Orden no encontrada" }, 404);
    }
    const order = orders[0];

    // Validar estado de pago
    if (order.payment_status !== "paid") {
      return json({ error: "Esta orden no tiene un pago confirmado que reembolsar", payment_status: order.payment_status }, 409);
    }

    if (!order.webpay_token) {
      return json({ error: "Orden sin token Webpay — no se puede reembolsar automáticamente" }, 422);
    }

    // Validar que no se haya reembolsado ya completamente
    if (order.refund_status === "full") {
      return json({ error: "Esta orden ya fue reembolsada completamente" }, 409);
    }

    // Determinar monto a reembolsar
    const totalPaid = Number(order.total);
    const alreadyRefunded = Number(order.refund_amount ?? 0);
    const remaining = totalPaid - alreadyRefunded;
    const refundAmount = amount != null ? Math.min(Number(amount), remaining) : remaining;

    if (refundAmount <= 0) {
      return json({ error: "No hay saldo pendiente para reembolsar", remaining: 0 }, 409);
    }

    console.log("REFUND_REQUEST", JSON.stringify({
      order_id,
      token: order.webpay_token,
      amount: refundAmount,
      totalPaid,
      alreadyRefunded,
      remaining,
    }));

    // Llamar a la API de reembolso de Transbank
    const tbkRes = await fetch(
      `${TBK_BASE}/rswebpaytransaction/api/webpay/v1.2/transactions/${order.webpay_token}/refunds`,
      {
        method: "POST",
        headers: {
          "Tbk-Api-Key-Id":     TBK_COMMERCE_CODE,
          "Tbk-Api-Key-Secret": TBK_API_KEY,
          "Content-Type":       "application/json",
        },
        body: JSON.stringify({ amount: refundAmount }),
      },
    );

    const tbkData = await tbkRes.json();

    console.log("REFUND_RESULT", JSON.stringify({
      httpStatus: tbkRes.status,
      body: tbkData,
    }));

    // Validar respuesta de Transbank
    if (!tbkRes.ok) {
      const tbkError = tbkData?.error_message ?? `HTTP ${tbkRes.status}`;
      console.error("REFUND_ERROR", JSON.stringify({ httpStatus: tbkRes.status, body: tbkData }));
      return json({ error: "Error al procesar reembolso", detail: tbkError, raw: tbkData }, 502);
    }

    // Determinar si fue reembolso total o parcial
    const newRefundTotal = alreadyRefunded + refundAmount;
    const isFull = newRefundTotal >= totalPaid;
    const refundStatus = isFull ? "full" : "partial";

    // Actualizar la orden
    await sbFetch(`/orders?id=eq.${encodeURIComponent(order_id)}`, {
      method: "PATCH",
      body: JSON.stringify({
        refund_amount:   newRefundTotal,
        refund_status:   refundStatus,
        refund_response: tbkData,
        refunded_at:     new Date().toISOString(),
        payment_status:  isFull ? "refunded" : "partial_refund",
        status:          isFull ? "cancelled" : order.status ?? "accepted",
      }),
    });

    return json({
      success: true,
      type: tbkData.type,              // "REVERSED" o "NULLIFIED"
      refunded_amount: refundAmount,
      total_refunded:  newRefundTotal,
      refund_status:   refundStatus,
      remaining:       totalPaid - newRefundTotal,
      authorization_code: tbkData.authorization_code ?? null,
    });

  } catch (e) {
    console.error("webpay-refund error:", e);
    return json({ error: String(e) }, 500);
  }
});
