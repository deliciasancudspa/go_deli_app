import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL     = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Khipu redirige aquí al usuario tras completar (o cancelar) el pago.
// El pago real se confirma vía webhook (khipu-notify), que puede llegar antes o
// después del return. Verificamos el estado en BD y mostramos la pantalla correspondiente.
serve(async (req) => {
  try {
    const url     = new URL(req.url);
    const orderId = url.searchParams.get("order_id");

    if (!orderId) return htmlPage("error", null);

    const sb = createClient(SUPABASE_URL, SUPABASE_SVC_KEY);
    const { data: order } = await sb
      .from("orders")
      .select("id, total, payment_status")
      .eq("id", orderId)
      .maybeSingle();

    const status = order?.payment_status === "paid" ? "approved" : "pending";
    return htmlPage(status, orderId);
  } catch (_) {
    return htmlPage("error", null);
  }
});

function htmlPage(status: string, orderId: string | null): Response {
  const approved = status === "approved";
  const pending  = status === "pending";

  const icon    = approved ? "✅" : pending ? "⏳" : "❌";
  const title   = approved ? "¡Transferencia recibida!" : pending ? "Verificando pago..." : "Error";
  const message = approved
    ? "Tu pedido ha sido confirmado."
    : pending
    ? "Tu transferencia está siendo verificada. En unos minutos recibirás confirmación."
    : "No pudimos verificar tu pago. Contacta soporte si ya realizaste la transferencia.";

  const deepLink = `godeli-webpay://done?status=${approved ? "approved" : pending ? "pending" : "error"}&order_id=${orderId ?? ""}`;

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
         font-size:16px;font-weight:700;text-decoration:none}
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
    setTimeout(function(){ window.location.href='${deepLink}'; }, 800);
  </script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}
