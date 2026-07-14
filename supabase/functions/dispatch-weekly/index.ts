// The Tapt Dispatch, weekly newsletter builder + sender.
// Assembles a real issue from live data (build_dispatch_content RPC), then either
// returns it (mode=preview) or sends it to subscribed addresses via Resend
// (mode=send, gated by the CRON_SECRET header). Gracefully no-ops when
// RESEND_API_KEY is missing or there are no subscribers, so it never errors.
// CAN-SPAM: every send carries a per-recipient unsubscribe link, RFC 8058
// one-click headers, and the postal address; sends refuse to run until
// MAIL_POSTAL_ADDRESS is configured.
// Owner secrets: RESEND_API_KEY (send), CRON_SECRET (authorize the weekly
// send), MAIL_POSTAL_ADDRESS (required for send).
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, authorization, x-cron-secret",
};
const FROM = Deno.env.get("RESEND_FROM") ?? "Tapt <onboarding@resend.dev>";
const KEY = Deno.env.get("RESEND_API_KEY");
const CRON_SECRET = Deno.env.get("CRON_SECRET");
const POSTAL = Deno.env.get("MAIL_POSTAL_ADDRESS");
const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const LANDING = "https://taptbeer.com";
const UNSUB_FN = `${SUPA_URL}/functions/v1/newsletter-unsubscribe`;

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] as string));
}

function rangeText(min: unknown, max: unknown, unit: string): string {
  if (min == null && max == null) return "";
  if (min != null && max != null) return `${min}-${max}${unit}`;
  return `${min ?? max}${unit}`;
}

function issueHtml(c: any, footerExtra = ""): string {
  const f = c.featured ?? {};
  const s = c.style ?? {};
  const abvRange = rangeText(s.abv_min, s.abv_max, "% ABV");
  const ibuRange = rangeText(s.ibu_min, s.ibu_max, " IBU");
  return `<div style="font-family:-apple-system,Inter,Arial,sans-serif;max-width:560px;margin:0 auto;color:#1A1206;background:#FBF6EC;padding:8px">
  <div style="font-weight:800;font-size:1.5rem;padding:8px 4px">Tapt<span style="color:#F2A900">.</span></div>
  <div style="font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:#B4531F;font-weight:700;padding:0 4px">The Tapt Dispatch</div>

  <div style="background:#fff;border-radius:16px;overflow:hidden;margin:14px 0;border:1px solid rgba(26,18,6,.08)">
    ${f.image ? `<img src="${esc(f.image)}" alt="${esc(f.name)}" style="width:100%;max-height:280px;object-fit:cover;display:block">` : ""}
    <div style="padding:18px">
      <div style="font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#B4531F;font-weight:700">This week's pour</div>
      <div style="font-family:Poppins,-apple-system,Arial;font-size:1.35rem;font-weight:800;margin:4px 0">${esc(f.name)}</div>
      <div style="color:#6B6459;font-size:.95rem">${esc(f.brewery)}${f.country ? ", " + esc(f.country) : ""} &middot; ${esc(f.style)}${f.abv ? " &middot; " + esc(f.abv) + "% ABV" : ""}</div>
    </div>
  </div>

  <div style="background:#1A1206;color:#FBF6EC;border-radius:16px;padding:18px;margin:14px 0">
    <div style="font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#F2A900;font-weight:700">Style to know</div>
    <div style="font-family:Poppins,-apple-system,Arial;font-size:1.2rem;font-weight:800;margin:4px 0">${esc(s.style_name)}</div>
    <div style="color:rgba(251,246,236,.8);font-size:.95rem">${esc(s.description)}</div>
    <div style="color:rgba(251,246,236,.6);font-size:.82rem;margin-top:8px">${esc(s.style_family)}${abvRange ? " &middot; " + abvRange : ""}${ibuRange ? " &middot; " + ibuRange : ""}</div>
  </div>

  <div style="background:#fff;border-radius:16px;padding:18px;margin:14px 0;border:1px solid rgba(26,18,6,.08)">
    <div style="font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#B4531F;font-weight:700">What the world is pouring</div>
    <div style="color:#6B6459;font-size:.95rem;margin-top:6px">New beers, breweries, and venues land on the Tapt map every week, all free to explore.</div>
    <div style="margin-top:14px"><a href="${LANDING}" style="background:#F2A900;color:#1A1206;font-weight:700;padding:11px 22px;border-radius:999px;text-decoration:none;display:inline-block">Open Tapt</a></div>
  </div>

  <div style="font-size:12px;color:#6B6459;padding:8px 4px">Real data only: beers from Open Food Facts, styles from the BJCP 2021 guidelines, venues from Open Brewery DB. Blank beats invented.</div>
  <hr style="border:none;border-top:1px solid rgba(26,18,6,.1);margin:16px 4px">
  <div style="font-size:12px;color:#6B6459;padding:0 4px">Tapt, THE Beer Superapp. Enjoy responsibly, 21+/legal drinking age. <a href="${LANDING}" style="color:#B4531F">taptbeer.com</a>${footerExtra}</div>
</div>`;
}

async function sendOne(to: string, subject: string, html: string, headers?: Record<string, string>) {
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to, subject, html, ...(headers ? { headers } : {}) }),
  });
  return r.ok;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return Response.json({ error: "POST only" }, { status: 405, headers: CORS });

  let body: { mode?: string } = {};
  try { body = await req.json(); } catch { /* default preview */ }
  const mode = body.mode ?? "preview";

  const admin = createClient(SUPA_URL, SERVICE);
  const { data: content, error } = await admin.rpc("build_dispatch_content");
  if (error || !content) return Response.json({ error: "could not build content", detail: error?.message }, { status: 500, headers: CORS });

  const subject = `The Tapt Dispatch, week ${content.week}`;
  const html = issueHtml(content);

  if (mode === "preview") {
    return Response.json({ subject, html, content }, { headers: CORS });
  }

  if (mode === "send") {
    const provided = req.headers.get("x-cron-secret") ?? "";
    // Authorize against the vault secret the weekly cron already sends
    // (dispatch_cron_ok), with the CRON_SECRET env var kept as a fallback. Either
    // path works, so there is no secret to keep in sync by hand.
    let authorized = false;
    try {
      const { data: ok } = await admin.rpc("dispatch_cron_ok", { p_secret: provided });
      authorized = ok === true;
    } catch { /* fall through to env fallback */ }
    if (!authorized && CRON_SECRET && provided === CRON_SECRET) authorized = true;
    if (!authorized) {
      return Response.json({ error: "forbidden: valid x-cron-secret required" }, { status: 403, headers: CORS });
    }
    if (!KEY) return Response.json({ sent: false, reason: "RESEND_API_KEY not configured" }, { headers: CORS });
    if (!POSTAL) {
      return Response.json(
        { sent: false, reason: "MAIL_POSTAL_ADDRESS not configured. CAN-SPAM requires a physical postal address in every newsletter; set the secret before sending." },
        { status: 412, headers: CORS },
      );
    }
    const { data: subs } = await admin.from("newsletter_subscriber")
      .select("email, unsubscribe_token")
      .eq("status", "subscribed");
    const list = subs || [];
    if (!list.length) return Response.json({ sent: false, reason: "no subscribers" }, { headers: CORS });
    let ok = 0;
    for (const s of list.slice(0, 100)) {
      const unsubUrl = `${UNSUB_FN}?t=${s.unsubscribe_token}`;
      const footer = `<br><a href="${unsubUrl}" style="color:#B4531F">Unsubscribe</a> &middot; ${esc(POSTAL)}`;
      const sent = await sendOne(s.email, subject, issueHtml(content, footer), {
        "List-Unsubscribe": `<${unsubUrl}>`,
        "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
      });
      if (sent) ok++;
    }
    // Archive the issue so it is hosted on the web and appears in the public archive.
    await admin.rpc("dispatch_publish_issue", {
      p_slug: `week-${content.week}`,
      p_title: subject,
      p_subtitle: content.featured?.name ?? null,
      p_content: content,
    });
    return Response.json({ sent: true, delivered: ok, total: list.length, week: content.week }, { headers: CORS });
  }

  return Response.json({ error: "unknown mode (use preview or send)" }, { status: 400, headers: CORS });
});
