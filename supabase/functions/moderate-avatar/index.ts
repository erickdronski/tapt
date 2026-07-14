import { createClient } from "npm:@supabase/supabase-js@2.106.2";
import { avatarPathFromURL, removeAvatarPaths } from "../_shared/avatars.ts";

const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CORS = {
  "Access-Control-Allow-Origin": "https://taptbeer.com",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, authorization, apikey, x-client-info",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status, headers: CORS });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (request.method !== "POST") return json({ error: "POST only" }, 405);

  const authorization = request.headers.get("Authorization") ?? "";
  const caller = createClient(SUPA_URL, ANON, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ error: "sign in required" }, 401);
  const { data: isAdmin, error: adminCheckError } = await caller.rpc("is_admin");
  if (adminCheckError || isAdmin !== true) return json({ error: "admin only" }, 403);

  let userId = "";
  let decision = "";
  try {
    const body = await request.json() as { userId?: string; decision?: string };
    userId = body.userId?.trim() ?? "";
    decision = body.decision?.trim() ?? "";
  } catch {
    return json({ error: "bad json" }, 400);
  }
  if (!UUID.test(userId) || !["approve", "reject"].includes(decision)) {
    return json({ error: "invalid moderation request" }, 422);
  }

  const admin = createClient(SUPA_URL, SERVICE);
  const { data: claimed, error: claimError } = await admin.rpc("claim_avatar_moderation", {
    p_user: userId,
    p_decision: decision,
    p_moderator: user.id,
  });
  const row = Array.isArray(claimed) ? claimed[0] : claimed;
  if (claimError || !row?.pending_avatar_url) {
    console.error("moderate-avatar claim", claimError?.message ?? "pending avatar missing");
    return json({ error: "Avatar is no longer awaiting review." }, 409);
  }

  const pendingURL = String(row.pending_avatar_url);
  const oldURL = typeof row.previous_avatar_url === "string" ? row.previous_avatar_url : null;
  const path = avatarPathFromURL(decision === "approve" ? oldURL : pendingURL, userId);
  try {
    await removeAvatarPaths(admin, [path]);
  } catch (error) {
    await admin.rpc("release_avatar_moderation", {
      p_user: userId,
      p_expected_url: pendingURL,
    });
    console.error("moderate-avatar storage", error instanceof Error ? error.message : String(error));
    return json({ error: "Avatar storage cleanup failed. Nothing was published." }, 503);
  }

  const finish = () => admin.rpc("finish_avatar_moderation", {
    p_user: userId,
    p_decision: decision,
    p_expected_url: pendingURL,
    p_moderator: user.id,
  });
  let { error: finishError } = await finish();
  if (finishError) ({ error: finishError } = await finish());
  if (finishError) {
    console.error("moderate-avatar finish", finishError.message);
    return json({ error: "Avatar review is still processing. Retry this action." }, 503);
  }
  return json({ moderated: true, decision });
});
