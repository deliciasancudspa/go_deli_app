import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FIREBASE_PROJECT_ID   = "godeli-fd48e";
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
const FIREBASE_PRIVATE_KEY  = Deno.env.get("FIREBASE_PRIVATE_KEY")!;
const SUPABASE_URL          = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY      = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Secreto compartido: debe coincidir con el header x-webhook-secret que envía
// el Database Webhook. Evita que cualquiera con la anon key dispare pushes.
const WEBHOOK_SECRET        = Deno.env.get("NOTIFY_WEBHOOK_SECRET") ?? "";

const STATUS_MESSAGES: Record<string, [string, string]> = {
  accepted:   ["✅ Pedido confirmado",     "El restaurante aceptó tu pedido"],
  preparing:  ["👨‍🍳 Preparando tu pedido", "El restaurante está preparando tu pedido"],
  ready:      ["🎉 ¡Pedido listo!",        "Tu pedido está listo para ser recogido"],
  assigned:   ["🛵 Repartidor asignado",   "Un repartidor está en camino al restaurante"],
  picked_up:  ["📦 Pedido recogido",       "El repartidor ya tiene tu pedido"],
  on_the_way: ["🚀 ¡En camino!",          "Tu pedido está en camino hacia ti"],
  delivered:  ["🏁 ¡Entregado!",          "¡Buen provecho! Tu pedido fue entregado"],
  cancelled:  ["❌ Pedido cancelado",      "Tu pedido fue cancelado"],
};

function base64url(data: string | Uint8Array): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let b64 = btoa(String.fromCharCode(...bytes));
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header  = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify({
    iss:   FIREBASE_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud:   "https://oauth2.googleapis.com/token",
    iat:   now,
    exp:   now + 3600,
  }));
  const toSign = `${header}.${payload}`;

  const pem     = FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n");
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8", keyBytes.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"],
  );
  const sigBytes = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(toSign));
  const jwt = `${toSign}.${base64url(new Uint8Array(sigBytes))}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await tokenRes.json();
  return tokenData.access_token as string;
}

serve(async (req) => {
  try {
    if (WEBHOOK_SECRET && req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
      return new Response("unauthorized", { status: 401 });
    }
    const rawPayload = await req.json();

    let client_id: string;
    let title: string;
    let body: string;

    if (rawPayload.record) {
      // Supabase webhook: { type, table, record: { client_id, status, ... } }
      const rec    = rawPayload.record;
      const oldRec = rawPayload.old_record ?? {};
      if (rec.status === oldRec.status) return new Response("no status change", { status: 200 });
      const msg = STATUS_MESSAGES[rec.status as string];
      if (!msg) return new Response("status not mapped", { status: 200 });
      client_id = rec.client_id as string;
      title     = msg[0];
      body      = msg[1];
    } else {
      client_id = rawPayload.client_id as string;
      title     = rawPayload.title     as string;
      body      = rawPayload.body      as string;
    }

    if (!client_id) return new Response("missing client_id", { status: 400 });

    const sb = createClient(SUPABASE_URL, SUPABASE_SVC_KEY);
    const { data: user, error } = await sb
      .from("users")
      .select("fcm_token")
      .eq("id", client_id)
      .single();

    if (error || !user?.fcm_token) {
      return new Response(JSON.stringify({ ok: false, reason: "no_token" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken();
    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: user.fcm_token,
            notification: { title, body },
            android: {
              priority: "high",
              notification: { channel_id: "go_deli_orders", sound: "default" },
            },
            data: { route: "orders" },
          },
        }),
      },
    );

    const result = await fcmRes.json();
    return new Response(JSON.stringify(result), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
