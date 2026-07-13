// Tapt transactional + newsletter email via Resend.
// Owner sets: RESEND_API_KEY (sends), MAIL_POSTAL_ADDRESS (required for
// newsletter blasts -- CAN-SPAM physical address). Optional: RESEND_FROM.
// Gracefully no-ops (never errors the app) when the key is absent.
import { createClient } from "npm:@supabase/supabase-js@2.106.2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, authorization",
};
const FROM = Deno.env.get("RESEND_FROM") ?? "Tapt <onboarding@resend.dev>";
const KEY = Deno.env.get("RESEND_API_KEY");
const POSTAL = Deno.env.get("MAIL_POSTAL_ADDRESS");
const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const LANDING = "https://taptbeer.com";
const UNSUB_FN = `${SUPA_URL}/functions/v1/newsletter-unsubscribe`;
const DISPATCH_LIMIT = 100;

const HTML_ENTITIES: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};
const escapeHTML = (value: string) => value.replace(
  /[&<>"']/g,
  (character) => HTML_ENTITIES[character] ?? character,
);

const emailSubject = (value: string) => value.replace(/[\r\n]+/g, " ").trim();

async function sendEmail(
  to: string | string[],
  subject: string,
  html: string,
  headers?: Record<string, string>,
) {
  if (!KEY) return { sent: false, reason: "RESEND_API_KEY not configured" };
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to, subject, html, ...(headers ? { headers } : {}) }),
  });
  const body = await r.json().catch(() => ({}));
  return { sent: r.ok, status: r.status, body };
}

// footerExtra: unsubscribe link + postal address for newsletter sends.
const shell = (inner: string, footerExtra = "") => `<div style="font-family:-apple-system,Inter,Arial,sans-serif;max-width:520px;margin:0 auto;color:#1A1206">
<div style="font-weight:800;font-size:1.4rem">Tapt<span style="color:#F2A900">.</span></div>
${inner}
<hr style="border:none;border-top:1px solid #eee;margin:24px 0">
<div style="font-size:12px;color:#6B6459">Tapt, THE Beer Superapp. Enjoy responsibly, 21+/legal drinking age. <a href="${LANDING}" style="color:#B4531F">tapt</a>${footerExtra}</div>
</div>`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return Response.json({ error: "POST only" }, { status: 405, headers: CORS });

  let body: { kind?: string; venue_id?: string; claim_id?: string; subject?: string; html?: string };
  try { body = await req.json(); } catch { return Response.json({ error: "bad json" }, { status: 400, headers: CORS }); }

  const authHeader = req.headers.get("Authorization") ?? "";
  const asCaller = createClient(SUPA_URL, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: authHeader } },
  });
  const admin = createClient(SUPA_URL, SERVICE);

  const { data: { user } } = await asCaller.auth.getUser();
  if (!user) return Response.json({ error: "sign in required" }, { status: 401, headers: CORS });

  // 1. Partner welcome + QR: caller must own an APPROVED claim on the venue.
  //    An app admin may send for the exact claim they just approved. The
  //    service-role lookup stays server-side and is allowed only after is_admin.
  if (body.kind === "partner_welcome" && body.venue_id) {
    const { data: claims } = await asCaller.rpc("my_venue_claims");
    const owned = (claims || []).find((c: any) => c.venue_id === body.venue_id && c.status === "approved");
    let recipient = user.email ?? "";
    let venueName = String(owned?.venue_name ?? "").trim();

    if (!owned) {
      const { data: isAdmin } = await asCaller.rpc("is_admin");
      if (!isAdmin || !body.claim_id) {
        return Response.json({ error: "not your approved venue" }, { status: 403, headers: CORS });
      }
      const { data: claim, error: claimError } = await admin
        .from("venue_claim")
        .select("business_email, status, venue_id")
        .eq("id", body.claim_id)
        .eq("venue_id", body.venue_id)
        .maybeSingle();
      if (claimError) {
        return Response.json({ error: "approved claim lookup failed" }, { status: 500, headers: CORS });
      }
      if (!claim || claim.status !== "approved") {
        return Response.json({ error: "claim is not approved" }, { status: 403, headers: CORS });
      }
      const { data: venue, error: venueError } = await admin
        .from("venue")
        .select("name")
        .eq("id", body.venue_id)
        .maybeSingle();
      if (venueError || !venue) {
        return Response.json({ error: "venue lookup failed" }, { status: 500, headers: CORS });
      }
      recipient = claim.business_email;
      venueName = String(venue.name ?? "").trim();
    }

    if (!recipient || !venueName) {
      return Response.json({ error: "approved claim is missing delivery details" }, { status: 422, headers: CORS });
    }
    const menuUrl = `${LANDING}/menu?v=${body.venue_id}`;
    const portalUrl = `${LANDING}/portal`;
    const html = shell(`<h2 style="margin:14px 0 6px">${escapeHTML(venueName)} is live on Tapt 🍺</h2>
<p>Your free hosted menu is ready. Print the QR for your tables, update your taps anytime.</p>
<p><a href="${menuUrl}" style="background:#F2A900;color:#1A1206;font-weight:700;padding:11px 22px;border-radius:999px;text-decoration:none;display:inline-block">View menu + print QR</a></p>
<p style="font-size:14px;color:#6B6459">Update your tap list any time at <a href="${portalUrl}" style="color:#B4531F">the portal</a>. Free, forever.</p>`,
      POSTAL ? `<br>${escapeHTML(POSTAL)}` : "");
    const res = await sendEmail(recipient, `${emailSubject(venueName)} is live on Tapt`, html);
    return Response.json(res, { headers: CORS });
  }

  // 2. Dispatch newsletter blast: caller must be admin. CAN-SPAM hard gates:
  //    a physical postal address must be configured, and every email carries
  //    a working per-recipient unsubscribe link + one-click headers (RFC 8058).
  if (body.kind === "dispatch" && body.subject && body.html) {
    const { data: isAdmin } = await asCaller.rpc("is_admin");
    if (!isAdmin) return Response.json({ error: "admin only" }, { status: 403, headers: CORS });
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
    if (list.length > DISPATCH_LIMIT) {
      return Response.json({
        sent: false,
        total: list.length,
        reason: `Dispatch has ${list.length} recipients, above the reviewed ${DISPATCH_LIMIT}-recipient batch limit. Use a queued sender before continuing.`,
      }, { status: 409, headers: CORS });
    }
    // Individual sends ensure each recipient gets a unique unsubscribe token.
    let ok = 0;
    for (const s of list) {
      const unsubUrl = `${UNSUB_FN}?t=${s.unsubscribe_token}`;
      const footer = `<br><a href="${unsubUrl}" style="color:#B4531F">Unsubscribe</a> · ${escapeHTML(POSTAL)}`;
      const res = await sendEmail(s.email, emailSubject(body.subject), shell(body.html, footer), {
        "List-Unsubscribe": `<${unsubUrl}>`,
        "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
      });
      if (res.sent) ok++;
    }
    return Response.json({
      sent: ok === list.length,
      delivered: ok,
      total: list.length,
      ...(ok === list.length ? {} : { reason: `${list.length - ok} messages were not accepted by the email provider.` }),
    }, { headers: CORS });
  }

  return Response.json({ error: "unknown kind" }, { status: 400, headers: CORS });
});
