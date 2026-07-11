#!/usr/bin/env node
/**
 * Tapt partner inbox — review brewery/bar inquiries and turn them into live partners.
 *
 * Inquiries from the in-app "Partner with Tapt" form land in `partner_inquiry`
 * (status=new). This is the owner's review desk. Uses the service-role key, so run
 * it locally — never ship the key.
 *
 *   SUPABASE_SERVICE_KEY=... node tools/partner-inbox.mjs            # list inquiries
 *   SUPABASE_SERVICE_KEY=... node tools/partner-inbox.mjs new        # only new ones
 *   SUPABASE_SERVICE_KEY=... node tools/partner-inbox.mjs status <id> contacted
 *   SUPABASE_SERVICE_KEY=... node tools/partner-inbox.mjs promote <id>   # -> live Featured partner
 *
 * Statuses: new -> contacted -> partnered | declined
 */
const URL = process.env.SUPABASE_URL || "https://qfwiizvqxrhjlthbjosz.supabase.co";
const KEY = process.env.SUPABASE_SERVICE_KEY;
if (!KEY) {
  console.error("Set SUPABASE_SERVICE_KEY (Supabase dashboard → Project Settings → API → service_role).");
  process.exit(1);
}
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" };
const rest = (p, opts = {}) => fetch(`${URL}/rest/v1/${p}`, { ...opts, headers: { ...H, ...(opts.headers || {}) } });

const [cmd, id, arg] = process.argv.slice(2);

async function list(filter) {
  let q = "partner_inquiry?order=created_at.desc&select=*";
  if (filter === "new") q += "&status=eq.new";
  const rows = await (await rest(q)).json();
  if (!rows.length) return console.log("No inquiries yet.");
  console.log(`\n${rows.length} inquir${rows.length === 1 ? "y" : "ies"}:\n`);
  for (const r of rows) {
    const badge = { new: "🟡 NEW", contacted: "🔵 CONTACTED", partnered: "🟢 PARTNERED", declined: "⚪️ DECLINED" }[r.status] || r.status;
    console.log(`${badge}  ${r.business_name}  (${r.business_kind})`);
    console.log(`   ${r.contact_email}  ·  ${[r.city, r.region, r.country].filter(Boolean).join(", ")}`);
    if (r.message) console.log(`   "${r.message}"`);
    console.log(`   id: ${r.id}   ${new Date(r.created_at).toLocaleString()}\n`);
  }
}

async function setStatus(inqId, status) {
  const ok = ["new", "contacted", "partnered", "declined"];
  if (!ok.includes(status)) return console.error(`status must be one of: ${ok.join(", ")}`);
  const res = await rest(`partner_inquiry?id=eq.${inqId}`, {
    method: "PATCH", headers: { Prefer: "return=representation" },
    body: JSON.stringify({ status, updated_at: new Date().toISOString() }),
  });
  const [row] = await res.json();
  console.log(row ? `✓ ${row.business_name} → ${status}` : "Inquiry not found.");
}

async function promote(inqId) {
  const [inq] = await (await rest(`partner_inquiry?id=eq.${inqId}&select=*`)).json();
  if (!inq) return console.error("Inquiry not found.");
  const res = await rest("featured_partner", {
    method: "POST", headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      kind: inq.business_kind || "brewery",
      title: inq.business_name,
      city: inq.city, region: inq.region, country: inq.country,
      tier: "partner", active: true, sort_rank: 100,
      starts_at: new Date().toISOString(),
    }),
  });
  const [fp] = await res.json();
  if (!fp) return console.error("Could not create partner:", await res.text());
  await setStatus(inqId, "partnered");
  console.log(`\n🍺 ${fp.title} is now a live Featured partner (id ${fp.id}).`);
  console.log("   Add blurb / cta_url / tier='spotlight' in the DB to feature them harder.");
}

if (cmd === "status") await setStatus(id, arg);
else if (cmd === "promote") await promote(id);
else await list(cmd);
