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
    const tokenWs = url.searchParams.get("token_ws");
    const tbkToken = url.searchParams.get("TBK_TOKEN");
    const tbkIdSesion = url.searchParams.get("TBK_ID_SESION");
    if (!tokenWs && !tbkToken && !tbkIdSesion) {
      return new Response(
        "<html><body><h2>Go Deli — Webpay Return OK</h2><p>Endpoint activo y disponible.</p></body></html>",
        { status: 200, headers: { ...CORS, "Content-Type": "text/html; charset=utf-8" } }
      );
    }
  }

  try {
    let tokenWs: string | null = null;
    let tbkToken: string | null = null;
    let tbkIdSesion: string | null = null;
    let tbkOrdenCompra: string | null = null;
    let webUrl: string | null = null;

    // web_url NO viene en el query string — se lee de la orden más abajo
    // (se guardó en webpay-create porque Transbank no maneja bien query params preexistentes)
    const reqUrl = new URL(req.url);

    const ct = req.headers.get("content-type") ?? "";

    if (ct.includes("application/x-www-form-urlencoded")) {
      const text = await req.text();
      const params = new URLSearchParams(text);
      tokenWs        = params.get("token_ws");
      tbkToken       = params.get("TBK_TOKEN");
      tbkIdSesion    = params.get("TBK_ID_SESION");
      tbkOrdenCompra = params.get("TBK_ORDEN_COMPRA");
      // fallback: Transbank a veces manda token_ws también en query params
      if (!tokenWs) tokenWs = reqUrl.searchParams.get("token_ws");
    } else if (ct.includes("application/json")) {
      const body = await req.json();
      tokenWs        = body.token_ws        ?? null;
      tbkToken       = body.TBK_TOKEN       ?? null;
      tbkIdSesion    = body.TBK_ID_SESION   ?? null;
      tbkOrdenCompra = body.TBK_ORDEN_COMPRA ?? null;
    } else {
      tokenWs        = reqUrl.searchParams.get("token_ws");
      tbkToken       = reqUrl.searchParams.get("TBK_TOKEN");
      tbkIdSesion    = reqUrl.searchParams.get("TBK_ID_SESION");
      tbkOrdenCompra = reqUrl.searchParams.get("TBK_ORDEN_COMPRA");
    }

    console.log("WEBPAY_RETURN_PARAMS", JSON.stringify({ tokenWs, tbkToken, tbkIdSesion, tbkOrdenCompra }));

    // Timeout: solo llegan TBK_ID_SESION y TBK_ORDEN_COMPRA, sin token
    if (!tokenWs && !tbkToken && tbkIdSesion) {
      return buildResponse("cancelled", null, null, webUrl);
    }

    // Error formulario o cancelación: llega TBK_TOKEN (con o sin token_ws)
    if (!tokenWs && tbkToken) {
      return buildResponse("cancelled", null, null, webUrl);
    }

    // Error formulario con todos los params: token_ws + TBK_TOKEN + TBK_ID_SESION + TBK_ORDEN_COMPRA
    // En este caso token_ws puede ser inválido — intentamos confirmar pero tratamos error como cancelación
    if (!tokenWs) {
      return buildResponse("cancelled", null, null, webUrl);
    }

    // Confirmar transacción con Transbank
    const tbkRes = await fetch(
      `${TBK_BASE}/rswebpaytransaction/api/webpay/v1.2/transactions/${tokenWs}`,
      {
        method: "PUT",
        headers: {
          "Tbk-Api-Key-Id":     TBK_COMMERCE_CODE,
          "Tbk-Api-Key-Secret": TBK_API_KEY,
          "Content-Type":       "application/json",
        },
      },
    );

    const result = await tbkRes.json();
    console.log("WEBPAY_RESULT", JSON.stringify({
      token: tokenWs,
      httpStatus: tbkRes.status,
      status: result.status,
      response_code: result.response_code,
      vci: result.vci,
      authorization_code: result.authorization_code,
      amount: result.amount,
      buy_order: result.buy_order,
    }));

    // Transbank requiere validar AMBOS: response_code === 0 Y status === "AUTHORIZED"
    const approved = result.response_code === 0 && result.status === "AUTHORIZED";

    // Buscar y actualizar la orden (token URL-encodeado por si acaso)
    const orders = await sbFetch(`/orders?webpay_token=eq.${encodeURIComponent(tokenWs)}&select=id,total,web_return_url`);
    const order = Array.isArray(orders) && orders.length > 0 ? orders[0] : null;

    // Recuperar web_url de la orden (se guardó en webpay-create)
    if (order?.web_return_url) webUrl = order.web_return_url;

    if (order) {
      await sbFetch(`/orders?id=eq.${order.id}`, {
        method: "PATCH",
        body: JSON.stringify({
          payment_status:  approved ? "paid" : "failed",
          status:          approved ? "accepted" : "pending",
          webpay_response: result,
        }),
      });
    }

    const status = approved ? "approved" : "rejected";
    const finalOrderId = order?.id ?? null;
    return buildResponse(status, finalOrderId, result.amount ?? null, webUrl);
  } catch (e) {
    console.error("webpay-return error:", e);
    return buildResponse("error", null, null, null);
  }
});

function buildResponse(
  status: "approved" | "rejected" | "cancelled" | "error",
  orderId: string | null,
  amount: number | null,
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

  // Cliente móvil → redirect directo al deep link (más confiable que JS en WebView Android)
  const deepLink = `godeli-webpay://done?status=${status}&order_id=${orderId ?? ""}`;
  return new Response(null, {
    status: 302,
    headers: { ...CORS, "Location": deepLink },
  });
}

// HTML de respaldo (no se usa actualmente, reservado para debugging)
function _htmlPage(
  status: "approved" | "rejected" | "cancelled" | "error",
  orderId: string | null,
  amount: number | null,
  _webUrl: string | null,
): Response {
  const ok        = status === "approved";
  const cancelled = status === "cancelled";
  const icon    = ok ? "✅" : cancelled ? "⚠️" : "❌";
  const title   = ok ? "¡Pago exitoso!" : cancelled ? "Pago cancelado" : "Pago rechazado";
  const message = ok
    ? `Tu pedido ha sido confirmado.${amount ? ` Total: $${Number(amount).toLocaleString("es-CL")}` : ""}`
    : cancelled
    ? "Cancelaste el proceso de pago."
    : "El pago no pudo procesarse. Intenta con otro método.";

  const deepLink = `godeli-webpay://done?status=${status}&order_id=${orderId ?? ""}`;

  const html = `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Go Deli — ${title}</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
         background:#f5f5f5;display:flex;align-items:center;
         justify-content:center;min-height:100vh}
    .card{background:#fff;border-radius:24px;padding:40px 32px;
          text-align:center;max-width:360px;width:90%;
          box-shadow:0 8px 32px rgba(0,0,0,.08)}
    .icon{font-size:72px;margin-bottom:20px}
    h1{font-size:22px;font-weight:800;color:#1a1a2e;margin-bottom:12px}
    p{font-size:15px;color:#666;line-height:1.6;margin-bottom:28px}
    .btn{display:inline-block;background:linear-gradient(135deg,#6c63ff,#ff6b35);
         color:#fff;padding:14px 32px;border-radius:14px;
         font-size:16px;font-weight:700;text-decoration:none;cursor:pointer}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">${icon}</div>
    <h1>${title}</h1>
    <p>${message}</p>
    <a class="btn" href="${deepLink}">Volver a Go Deli</a>
  </div>
  <script>
    setTimeout(function(){ window.location.href='${deepLink}'; }, 600);
  </script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: { ...CORS, "Content-Type": "text/html; charset=utf-8" },
  });
}
