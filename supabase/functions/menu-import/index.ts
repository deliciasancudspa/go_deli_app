import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─────────────────────────────────────────────────────────────────────────────
// menu-import — Asistente IA del panel de aliados.
// Recibe la carta/catálogo de la tienda (foto, PDF, URL o texto), la analiza
// con Claude y devuelve un menú estructurado (categorías + productos) que el
// panel muestra como vista previa editable antes de insertarlo.
//
// Secretos requeridos: ANTHROPIC_API_KEY
// Autorización: JWT de un usuario dueño de la tienda (o admin).
// ─────────────────────────────────────────────────────────────────────────────

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const SUPABASE_URL      = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SVC_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });

// Esquema del menú estructurado que Claude debe devolver (salida garantizada)
const MENU_SCHEMA = {
  type: "object",
  properties: {
    categories: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string", description: "Nombre de la categoría (ej: Hamburguesas, Bebidas)" },
          items: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name:        { type: "string", description: "Nombre del producto" },
                description: { type: "string", description: "Descripción o ingredientes; cadena vacía si no hay" },
                price:       { type: "integer", description: "Precio en pesos chilenos, solo dígitos. 0 si no se indica" },
                emoji:       { type: "string", description: "Un emoji que represente el producto" },
              },
              required: ["name", "description", "price", "emoji"],
              additionalProperties: false,
            },
          },
        },
        required: ["name", "items"],
        additionalProperties: false,
      },
    },
    notes: {
      type: "string",
      description: "Observaciones para el dueño: productos sin precio, texto ilegible, dudas. Cadena vacía si no hay.",
    },
  },
  required: ["categories", "notes"],
  additionalProperties: false,
} as const;

const SYSTEM_PROMPT = `Eres el asistente de catálogo de Go Deli, una plataforma de delivery chilena.
Tu tarea: extraer el menú o catálogo de productos del material que entrega el dueño de una tienda y devolverlo estructurado.

Reglas:
- Agrupa los productos en las categorías que indique el material; si no hay categorías claras, crea categorías razonables según el tipo de negocio.
- Precios en pesos chilenos como entero (ej: "$5.990" → 5990, "5,5" en contexto de miles → 5500). Si un producto no tiene precio visible, usa 0 y menciónalo en notes.
- No inventes productos ni precios que no estén en el material.
- Conserva los nombres tal como aparecen (corrige solo mayúsculas/ortografía evidente).
- Las descripciones deben ser las del material; si no hay, genera una brevísima descripción neutra (máx 10 palabras) solo cuando el nombre sea poco descriptivo, si no, déjala vacía.
- Elige un emoji apropiado por producto.`;

// Llama a la API de Claude con los bloques de contenido dados
async function extractMenu(contentBlocks: unknown[], businessType: string) {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-opus-4-8",
      max_tokens: 16000,
      thinking: { type: "adaptive" },
      system: SYSTEM_PROMPT,
      output_config: { format: { type: "json_schema", schema: MENU_SCHEMA } },
      messages: [{
        role: "user",
        content: [
          ...contentBlocks,
          {
            type: "text",
            text: `Tipo de negocio: ${businessType}. Extrae el menú/catálogo completo de este material.`,
          },
        ],
      }],
    }),
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.error?.message ?? `Claude API ${res.status}`);
  }
  if (data.stop_reason === "max_tokens") {
    throw new Error("El material es demasiado extenso; intenta con una sección más pequeña.");
  }
  const text = (data.content ?? []).find((b: { type: string }) => b.type === "text")?.text;
  if (!text) throw new Error("Respuesta vacía del modelo");
  return JSON.parse(text);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    if (!ANTHROPIC_API_KEY) {
      return json({ ok: false, error: "ANTHROPIC_API_KEY no está configurada en los secretos" });
    }

    // ── Autorización: dueño de la tienda o admin ──
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ ok: false, error: "Sin autorización" });
    const sb = createClient(SUPABASE_URL, SUPABASE_SVC_KEY);
    const { data: { user } } = await sb.auth.getUser(jwt);
    if (!user) return json({ ok: false, error: "Sesión inválida" });

    const body = await req.json();
    const storeId = body.store_id as string;
    if (!storeId) return json({ ok: false, error: "Falta store_id" });

    const { data: profile } = await sb.from("users").select("id, role").eq("auth_id", user.id).single();
    const { data: store } = await sb.from("stores").select("id, owner_id, store_type").eq("id", storeId).single();
    if (!store) return json({ ok: false, error: "Tienda no encontrada" });
    if (store.owner_id !== profile?.id && profile?.role !== "admin") {
      return json({ ok: false, error: "No eres el dueño de esta tienda" });
    }

    // ── Construir bloques de contenido según la fuente ──
    const source = body.source as { type: string; data?: string; media_type?: string; url?: string; text?: string };
    const blocks: unknown[] = [];

    if (source.type === "image") {
      blocks.push({
        type: "image",
        source: { type: "base64", media_type: source.media_type ?? "image/jpeg", data: source.data },
      });
    } else if (source.type === "pdf") {
      blocks.push({
        type: "document",
        source: { type: "base64", media_type: "application/pdf", data: source.data },
      });
    } else if (source.type === "url") {
      const resp = await fetch(source.url!, { headers: { "User-Agent": "GoDeliBot/1.0" } });
      if (!resp.ok) return json({ ok: false, error: `No se pudo acceder a la URL (${resp.status})` });
      const ctype = resp.headers.get("content-type") ?? "";
      if (ctype.includes("pdf")) {
        const buf = new Uint8Array(await resp.arrayBuffer());
        let bin = "";
        for (let i = 0; i < buf.length; i += 0x8000) {
          bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
        }
        blocks.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: btoa(bin) } });
      } else if (ctype.startsWith("image/")) {
        blocks.push({ type: "image", source: { type: "url", url: source.url } });
      } else {
        let html = await resp.text();
        html = html
          .replace(/<script[\s\S]*?<\/script>/gi, "")
          .replace(/<style[\s\S]*?<\/style>/gi, "")
          .replace(/<[^>]+>/g, " ")
          .replace(/\s+/g, " ")
          .slice(0, 150_000);
        blocks.push({ type: "text", text: `Contenido de ${source.url}:\n\n${html}` });
      }
    } else if (source.type === "text") {
      blocks.push({ type: "text", text: (source.text ?? "").slice(0, 150_000) });
    } else {
      return json({ ok: false, error: "Tipo de fuente no soportado" });
    }

    const menu = await extractMenu(blocks, store.store_type ?? "restaurante");
    return json({ ok: true, menu });
  } catch (e) {
    return json({ ok: false, error: String((e as Error).message ?? e) });
  }
});
