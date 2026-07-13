import { createClient } from "npm:@supabase/supabase-js@2.106.2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: CORS });
}

function isBeerCategory(tags: unknown): boolean {
  if (!Array.isArray(tags)) return false;
  return tags.some((value) => {
    if (typeof value !== "string") return false;
    const tag = value.toLowerCase().replace(/^.*:/, "");
    return /(^|[-_])beers?($|[-_])/.test(tag);
  });
}

function verifiedImageURL(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2_000) return null;
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    const isOFF = host === "openfoodfacts.org" ||
      host.endsWith(".openfoodfacts.org") ||
      host === "openfoodfacts.net" ||
      host.endsWith(".openfoodfacts.net");
    return url.protocol === "https:" && isOFF ? url.toString() : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token || token === authorization) return json({ error: "sign in required" }, 401);

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) return json({ error: "service unavailable" }, 503);

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "sign in required" }, 401);

  let body: { barcode?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid request" }, 400);
  }

  const barcode = typeof body.barcode === "string"
    ? body.barcode.replace(/[^0-9]/g, "")
    : "";
  if (barcode.length < 8 || barcode.length > 14) {
    return json({ error: "invalid barcode" }, 400);
  }

  const fields = "product_name,brands,categories_tags,image_front_url,nutriments";
  const offResponse = await fetch(
    `https://world.openfoodfacts.org/api/v2/product/${barcode}.json?fields=${fields}`,
    { headers: { "User-Agent": "Tapt/1.0 (hello@taptbeer.com)" } },
  );
  if (!offResponse.ok) return json({ error: "product lookup unavailable" }, 502);

  const off = await offResponse.json();
  const product = off?.status === 1 ? off.product : null;
  if (!product || !isBeerCategory(product.categories_tags)) {
    return json({ error: "product is not classified as beer" }, 422);
  }

  const name = typeof product.product_name === "string"
    ? product.product_name.trim()
    : "";
  if (name.length < 2 || name.length > 160) {
    return json({ error: "product name is unavailable" }, 422);
  }

  const brand = typeof product.brands === "string"
    ? product.brands.split(",")[0].trim().slice(0, 160) || null
    : null;
  const alcohol = product.nutriments?.alcohol_100g;
  const rawABV = typeof alcohol === "number"
    ? alcohol
    : typeof alcohol === "string" && alcohol.trim() !== ""
    ? Number(alcohol)
    : Number.NaN;
  const abv = Number.isFinite(rawABV) && rawABV >= 0 && rawABV <= 70
    ? rawABV
    : null;
  const imageURL = verifiedImageURL(product.image_front_url);

  const { data, error } = await admin.rpc("add_verified_beer_from_barcode", {
    p_user: authData.user.id,
    p_gtin: barcode,
    p_name: name,
    p_brand: brand,
    p_abv: abv,
    p_image_url: imageURL,
  });
  if (error) {
    console.error("verified barcode insert failed", error.code, error.message);
    return json({ error: "could not add product" }, 500);
  }

  return json({ beer: data?.[0] ?? null });
});
