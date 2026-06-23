import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL     = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TBK_COMMERCE_CODE = Deno.env.get("TBK_COMMERCE_CODE") ?? "597055555532";
const TBK_API_KEY       = Deno.env.get("TBK_API_KEY")       ?? "579B532A7440BB0C9079DED94D31EA1615BACEB56610332264630D42D0A36B1C";
const TBK_ENV           = Deno.env.get("TBK_ENV")           ?? "integration";

const TBK_BASE = TBK_ENV === "production"
  ? "https://webpay3g.transbank.cl"
  : "https://webpay3gint.transbank.cl";

// Transbank hace POST con application/x-www-form-urlencoded (o GET desde navegador)
serve(async (req) => {
  try {
    let tokenWs: string | null = null;
    let tbkToken: string | null = null;
    let webUrl: string | null = null;

    const ct = req.headers.get("content-type") ?? "";

    if (ct.includes("application/x-www-form-urlencoded")) {
      const text = await req.text();
      const params = new URLSearchParams(text);
      tokenWs  = params.get("token_ws");
      tbkToken = params.get("TBK_TOKEN");
    } else if (ct.includes("application/json")) {
      const body = await req.json();
      tokenWs  = body.token_ws  ?? null;
      tbkToken = body.TBK_TOKEN ?? null;
    } else {
      const url = new URL(req.url);
      tokenWs  = url.searchParams.get("token_ws");
      tbkToken = url.searchParams.get("TBK_TOKEN");
      webUrl   = url.searchParams.get("web_url");
    }

    // Usuario canceló en WebPay (Transbank envía TBK_TOKEN sin token_ws)
    if (!tokenWs && tbkToken) {
      return htmlPage("cancelled", null, null, webUrl);
    }

    if (!tokenWs) {
      return htmlPage("error", null, null, webUrl);
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
    const approved = result.response_code === 0;

    const sb = createClient(SUPABASE_URL, SUPABASE_SVC_KEY);

    const { data: order } = await sb
      .from("orders")
      .select("id, total")
      .eq("webpay_token", tokenWs)
      .maybeSingle();

    if (order) {
      await sb.from("orders").update({
        payment_status:  approved ? "paid" : "payment_failed",
        status:          approved ? "confirmed" : "pending",
        webpay_response: result,
      }).eq("id", order.id);
    }

    return htmlPage(
      approved ? "approved" : "rejected",
      order?.id ?? null,
      result.amount ?? null,
      webUrl,
    );
  } catch (e) {
    console.error("webpay-return error:", e);
    return htmlPage("error", null, null, null);
  }
});

function htmlPage(
  status: "approved" | "rejected" | "cancelled" | "error",
  orderId: string | null,
  amount: number | null,
  webUrl: string | null,
): Response {
  // Si hay web_url, es un cliente web → redirigir de vuelta a la app
  // con los parámetros de resultado en la URL
  if (webUrl) {
    const redirectUrl = new URL(webUrl);
    redirectUrl.searchParams.set("payment_status", status);
    if (orderId) redirectUrl.searchParams.set("order_id", orderId);
    return Response.redirect(redirectUrl.toString(), 302);
  }

  // Cliente móvil (WebView): mostrar HTML con deep link
  const ok        = status === "approved";
  const cancelled = status === "cancelled";

  const icon    = ok ? "✅" : cancelled ? "⚠️" : "❌";
  const title   = ok ? "¡Pago exitoso!" : cancelled ? "Pago cancelado" : "Pago rechazado";
  const message = ok
    ? `Tu pedido ha sido confirmado.${amount ? ` Total: $${Number(amount).toLocaleString("es-CL")}` : ""}`
    : cancelled
    ? "Cancelaste el proceso de pago."
    : "El pago no pudo procesarse. Intenta con otro método.";

  // La app Flutter intercepta el esquema godeli-webpay:// en el WebView
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
    // El WebView de Flutter intercepta godeli-webpay:// automáticamente
    setTimeout(function(){ window.location.href='${deepLink}'; }, 600);
  </script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}
