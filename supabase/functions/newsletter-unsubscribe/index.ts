// One-click + human unsubscribe for The Tapt Dispatch (CAN-SPAM / RFC 8058).
// GET  ?t=<token>  -> 303 redirect to the landing unsubscribe page (human path)
// POST ?t=<token> | {token} | form body -> unsubscribe immediately (one-click)
// Token-gated: the token is the secret, so no JWT. Responses are generic on
// purpose -- this endpoint must never confirm whether an address exists.
import { createClient } from "npm:@supabase/supabase-js@2.106.2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};
const LANDING = "https://taptbeer.com";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function tokenFrom(req: Request): Promise<string | null> {
  const url = new URL(req.url);
  const q = url.searchParams.get("t");
  if (q && UUID_RE.test(q)) return q;
  const type = req.headers.get("content-type") ?? "";
  try {
    if (type.includes("application/json")) {
      const body = await req.json();
      if (typeof body?.token === "string" && UUID_RE.test(body.token)) return body.token;
    } else if (type.includes("form")) {
      const form = await req.formData();
      const t = form.get("t") ?? form.get("token");
      if (typeof t === "string" && UUID_RE.test(t)) return t;
    }
  } catch { /* fall through: token stays null */ }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  if (req.method === "GET") {
    const t = new URL(req.url).searchParams.get("t") ?? "";
    const dest = UUID_RE.test(t) ? `${LANDING}/unsubscribe?t=${t}` : `${LANDING}/unsubscribe`;
    return new Response(null, { status: 303, headers: { ...CORS, Location: dest } });
  }

  if (req.method !== "POST") {
    return Response.json({ error: "POST only" }, { status: 405, headers: CORS });
  }

  const token = await tokenFrom(req);
  if (token) {
    const supa = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    await supa.from("newsletter_subscriber")
      .update({ status: "unsubscribed", unsubscribed_at: new Date().toISOString() })
      .eq("unsubscribe_token", token)
      .neq("status", "unsubscribed");
  }
  // Generic 200 whether or not the token matched anything.
  return Response.json({ ok: true }, { headers: CORS });
});
