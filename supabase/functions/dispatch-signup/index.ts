// Public newsletter signup for the Tapt landing page (The Tapt Dispatch).
// Guards: method check, email validation, honeypot field, per-IP throttle,
// and idempotent upsert. Source and consent text come from the form the person
// actually used (see FORMS), not a single hardcoded string.
import { createClient } from "npm:@supabase/supabase-js@2";

const hits = new Map<string, { n: number; t: number }>();

// What each landing form actually says on screen, owned here so the stored
// consent record is the wording the person read rather than a stand-in. The
// page sends only the form key; it cannot supply its own consent text.
// Keep these in sync with landing/index.html when that copy changes.
const FORMS: Record<string, { source: string; consent: string }> = {
  dispatch: {
    source: "landing",
    consent:
      "Landing page, The Tapt Dispatch section: One free email a week. The Beer of the Week, fun facts, brewing history, and the stories behind beers, bars, and taprooms around the world.",
  },
  hero: {
    source: "landing_hero",
    consent:
      "Landing page hero, Get launch access: Signing up gets you The Tapt Dispatch, our free weekly beer email, plus a note the day Tapt lands. Unsubscribe any time.",
  },
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") {
    return Response.json({ error: "POST only" }, { status: 405, headers: CORS });
  }

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const now = Date.now();
  const h = hits.get(ip);
  if (h && now - h.t < 3600_000 && h.n >= 5) {
    return Response.json({ error: "try again later" }, { status: 429, headers: CORS });
  }
  hits.set(ip, { n: (h && now - h.t < 3600_000 ? h.n : 0) + 1, t: h && now - h.t < 3600_000 ? h.t : now });

  let body: { email?: string; website?: string; form?: string };
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "bad json" }, { status: 400, headers: CORS });
  }

  // Honeypot: real users never fill "website".
  if (body.website) return Response.json({ ok: true }, { headers: CORS });

  const email = (body.email ?? "").trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email) || email.length > 320) {
    return Response.json({ error: "invalid email" }, { status: 400, headers: CORS });
  }

  const supa = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  // Never resurrect an unsubscribed address from the public form: anyone can
  // type any email here, and an unsubscribe must stick (CAN-SPAM). Response
  // stays generic so the form can't be used to probe subscription state.
  const { data: existing } = await supa.from("newsletter_subscriber")
    .select("status").eq("email", email).maybeSingle();
  if (existing?.status === "unsubscribed") {
    return Response.json({ ok: true }, { headers: CORS });
  }
  const form = FORMS[body.form ?? ""] ?? FORMS.dispatch;
  const { error } = await supa.from("newsletter_subscriber").upsert(
    {
      email,
      source: form.source,
      status: "subscribed",
      consent_ui_text: form.consent,
    },
    { onConflict: "email" },
  );
  if (error) {
    return Response.json({ error: "could not subscribe" }, { status: 500, headers: CORS });
  }
  return Response.json({ ok: true }, { headers: CORS });
});
