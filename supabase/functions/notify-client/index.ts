import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

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

async function sendFcm(accessToken: string, token: string, title: string, body: string, extraData?: Record<string,string>): Promise<boolean> {
  const data: Record<string,string> = { route: extraData?.route || "orders" };
  if (extraData) Object.assign(data, extraData);
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          android: {
            priority: "high",
            notification: { channel_id: "go_deli_orders", sound: "default" },
          },
          data,
        },
      }),
    },
  );
  return res.ok;
}

// ¿La petición viene de un admin autenticado? (panel web → functions.invoke
// adjunta el JWT de la sesión en Authorization)
async function isAdminRequest(req: Request, sb: ReturnType<typeof createClient>): Promise<boolean> {
  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return false;
    const { data: { user } } = await sb.auth.getUser(jwt);
    if (!user) return false;
    const { data } = await sb.from("users").select("role").eq("auth_id", user.id).single();
    return data?.role === "admin";
  } catch {
    return false;
  }
}

// CORS: el panel admin llama esta función desde el navegador
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-webhook-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const sb = createClient(SUPABASE_URL, SUPABASE_SVC_KEY);
    const secretOk = WEBHOOK_SECRET !== "" &&
      req.headers.get("x-webhook-secret") === WEBHOOK_SECRET;

    if (WEBHOOK_SECRET && !secretOk && !(await isAdminRequest(req, sb))) {
      return new Response("unauthorized", { status: 401, headers: corsHeaders });
    }
    const rawPayload = await req.json();

    // ── Broadcast del admin a todos los clientes ──────────────────────────
    // Siempre exige secreto o JWT de admin, aunque NOTIFY_WEBHOOK_SECRET no
    // esté configurado: nadie con la anon key puede spamear a toda la base.
    if (rawPayload.broadcast === true) {
      if (!secretOk && !(await isAdminRequest(req, sb))) {
        return new Response(JSON.stringify({ ok: false, reason: "solo admin" }), {
          status: 401, headers: { "Content-Type": "application/json", ...corsHeaders },
        });
      }
      const bTitle = String(rawPayload.title ?? "Go Deli");
      const bBody  = String(rawPayload.body ?? "");
      if (!bBody) return new Response("missing body", { status: 400, headers: corsHeaders });

      // Si se especifica comuna, filtrar solo clientes de esa comuna
      let clientsQuery = sb
        .from("users")
        .select("fcm_token")
        .eq("role", "client")
        .not("fcm_token", "is", null);
      if (rawPayload.commune_id) {
        clientsQuery = clientsQuery.eq("commune_id", rawPayload.commune_id);
      }
      const { data: clients } = await clientsQuery;
      const tokens = [...new Set((clients ?? []).map((c) => c.fcm_token).filter(Boolean))];

      // Armar datos de redirección para el FCM data payload
      const redirectType = String(rawPayload.redirect_type ?? "home");
      const fcmData: Record<string,string> = {};
      switch (redirectType) {
        case "store":
          fcmData.route = "store";
          if (rawPayload.store_id) fcmData.store_id = String(rawPayload.store_id);
          break;
        case "product":
          fcmData.route = "product";
          if (rawPayload.store_id) fcmData.store_id = String(rawPayload.store_id);
          if (rawPayload.product_id) fcmData.product_id = String(rawPayload.product_id);
          break;
        case "url":
          fcmData.route = "url";
          if (rawPayload.url) fcmData.url = String(rawPayload.url);
          break;
        default:
          fcmData.route = "home";
      }

      const accessToken = await getAccessToken();
      let sent = 0, failed = 0;
      for (let i = 0; i < tokens.length; i += 20) {
        await Promise.all(tokens.slice(i, i + 20).map(async (t) => {
          (await sendFcm(accessToken, t as string, bTitle, bBody, fcmData)) ? sent++ : failed++;
        }));
      }
      return new Response(JSON.stringify({ ok: true, sent, failed }), {
        status: 200, headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

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
      status: 500, headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
