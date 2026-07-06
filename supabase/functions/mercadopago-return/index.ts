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

  // GET request — verificación de disponibilidad del endpoint
  if (req.method === "GET") {
    const url = new URL(req.url);
    const collectionStatus = url.searchParams.get("collection_status");
    const externalRef = url.searchParams.get("external_reference");
    if (!collectionStatus && !externalRef) {
      return new Response(
        "<html><body><h2>Go Deli — MercadoPago Return OK</h2><p>Endpoint activo y disponible.</p></body></html>",
        { status: 200, headers: { ...CORS, "Content-Type": "text/html; charset=utf-8" } }
      );
    }
  }

  try {
    const reqUrl = new URL(req.url);

    // Mercado Pago redirige con query params en GET
    const collectionStatus = reqUrl.searchParams.get("collection_status");
    const externalRef      = reqUrl.searchParams.get("external_reference");  // nuestro order_id
    const paymentId        = reqUrl.searchParams.get("collection_id");
    const preferenceId     = reqUrl.searchParams.get("preference_id");
    const merchantOrderId  = reqUrl.searchParams.get("merchant_order_id");

    console.log("MP_RETURN_PARAMS", JSON.stringify({
      collectionStatus, externalRef, paymentId, preferenceId, merchantOrderId,
    }));

    // Sin external_reference no podemos identificar la orden
    if (!externalRef) {
      return buildResponse("error", null, null);
    }

    // Buscar la orden por external_reference (nuestro order_id)
    const orders = await sbFetch(
      `/orders?id=eq.${encodeURIComponent(externalRef)}&select=id,total,web_return_url,payment_status`
    );
    const order = Array.isArray(orders) && orders.length > 0 ? orders[0] : null;
    let webUrl: string | null = order?.web_return_url ?? null;

    // Si la orden ya fue actualizada por el webhook, respetar ese estado
    if (order?.payment_status === "paid") {
      return buildResponse("approved", order.id, webUrl);
    }

    // Determinar estado desde collection_status
    let status: "approved" | "rejected" | "pending" | "error" = "error";

    if (collectionStatus === "approved") {
      // Verificar con la API de MP (defense in depth)
      if (paymentId) {
        try {
          const mpRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
            headers: { "Authorization": `Bearer ${MP_ACCESS_TOKEN}` },
          });
          const payment = await mpRes.json();
          console.log("MP_VERIFY_RESULT", JSON.stringify({
            paymentId,
            httpStatus: mpRes.status,
            status: payment.status,
            status_detail: payment.status_detail,
          }));

          if (payment.status === "approved") {
            status = "approved";
          } else if (payment.status === "rejected" || payment.status === "cancelled") {
            status = "rejected";
          } else {
            // in_process, pending, authorized — no marcar como fallido aún
            status = "pending";
          }

          // Actualizar la orden
          if (order) {
            await sbFetch(`/orders?id=eq.${order.id}`, {
              method: "PATCH",
              body: JSON.stringify({
                payment_status: status === "approved" ? "paid" : status === "rejected" ? "failed" : "pending",
                status: status === "approved" ? "accepted" : status === "rejected" ? "cancelled" : order.payment_status,
                mp_payment_id: paymentId,
                mp_payment_response: payment,
              }),
            });
          }
        } catch (e) {
          console.error("MP_VERIFY_ERROR", e);
          // Si falla la verificación, confiar en collection_status
          status = "approved";
          if (order) {
            await sbFetch(`/orders?id=eq.${order.id}`, {
              method: "PATCH",
              body: JSON.stringify({
                payment_status: "paid",
                status: "accepted",
                mp_payment_id: paymentId,
                mp_preference_id: preferenceId,
              }),
            });
          }
        }
      } else {
        // Sin payment_id, confiar en collection_status
        status = "approved";
        if (order) {
          await sbFetch(`/orders?id=eq.${order.id}`, {
            method: "PATCH",
            body: JSON.stringify({
              payment_status: "paid",
              status: "accepted",
              mp_preference_id: preferenceId,
            }),
          });
        }
      }
    } else if (collectionStatus === "rejected" || collectionStatus === "null") {
      status = "rejected";
      if (order && order.payment_status !== "paid") {
        await sbFetch(`/orders?id=eq.${order.id}`, {
          method: "PATCH",
          body: JSON.stringify({
            payment_status: "failed",
            status: "cancelled",
            mp_payment_id: paymentId,
          }),
        });
      }
    } else {
      // in_process, pending, o sin collection_status — no marcar como fallido
      // (puede ser transferencia bancaria que demora)
      status = "pending";
      if (order && paymentId) {
        await sbFetch(`/orders?id=eq.${order.id}`, {
          method: "PATCH",
          body: JSON.stringify({
            mp_payment_id: paymentId,
            mp_preference_id: preferenceId,
          }),
        });
      }
    }

    const finalOrderId = order?.id ?? externalRef;
    return buildResponse(status, finalOrderId, webUrl);
  } catch (e) {
    console.error("mercadopago-return error:", e);
    return buildResponse("error", null, null);
  }
});

function buildResponse(
  status: "approved" | "rejected" | "pending" | "error",
  orderId: string | null,
  webUrl: string | null,
): Response {
  // Cliente web → redirigir a la app web con CORS
  if (webUrl) {
    const redirectUrl = new URL(webUrl);
    redirectUrl.searchParams.set("payment_status", status);
    if (orderId) redirectUrl.searchParams.set("order_id", orderId);
    return new Response(null, {
      status: 302,
      headers: { ...CORS, "Location": redirectUrl.toString() },
    });
  }

  // Cliente móvil → redirect al deep link compartido con Webpay/Khipu
  const deepLink = `godeli-webpay:///done?status=${status}&order_id=${orderId ?? ""}`;
  return new Response(null, {
    status: 302,
    headers: { ...CORS, "Location": deepLink },
  });
}
