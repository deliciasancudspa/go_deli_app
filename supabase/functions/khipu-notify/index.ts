import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL     = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const KHIPU_API_KEY    = Deno.env.get("KHIPU_API_KEY") ?? "";

// Khipu envía un POST con form-urlencoded al confirmar el pago
serve(async (req) => {
  try {
    let paymentId: string | null = null;

    const ct = req.headers.get("content-type") ?? "";
    if (ct.includes("application/x-www-form-urlencoded")) {
      const text = await req.text();
      const params = new URLSearchParams(text);
      paymentId = params.get("payment_id");
    } else if (ct.includes("application/json")) {
      const body = await req.json();
      paymentId = body.payment_id ?? null;
    }

    if (!paymentId) {
      return new Response("missing payment_id", { status: 400 });
    }

    // Verificar el pago con la API de Khipu
    const res = await fetch(`https://payment-api.khipu.com/v3/payments/${paymentId}`, {
      headers: { "x-api-key": KHIPU_API_KEY },
    });
    const payment = await res.json();

    // Solo procesar si el estado es "done" (pagado y conciliado)
    if (payment.status !== "done") {
      return new Response("not done yet", { status: 200 });
    }

    const sb = createClient(SUPABASE_URL, SUPABASE_SVC_KEY);
    await sb.from("orders").update({
      payment_status:  "paid",
      status:          "accepted",  // consistente con webpay-return (pending_payment → accepted)
      khipu_response:  payment,
    }).eq("khipu_payment_id", paymentId);

    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("khipu-notify error:", e);
    return new Response("error", { status: 500 });
  }
});
