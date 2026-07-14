import { createClient } from "npm:@supabase/supabase-js@2.106.2";
import { removeAllUserAvatars } from "../_shared/avatars.ts";

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

  let reportId = "";
  let decision = "";
  let note: string | null = null;
  try {
    const body = await request.json() as { reportId?: string; decision?: string; note?: string };
    reportId = body.reportId?.trim() ?? "";
    decision = body.decision?.trim() ?? "";
    note = body.note?.trim().slice(0, 500) || null;
  } catch {
    return json({ error: "bad json" }, 400);
  }
  if (!UUID.test(reportId) || !["remove", "dismiss"].includes(decision)) {
    return json({ error: "invalid moderation request" }, 422);
  }

  const admin = createClient(SUPA_URL, SERVICE);
  const { data: claimed, error: claimError } = await admin.rpc("claim_content_moderation", {
    p_report: reportId,
    p_decision: decision,
    p_moderator: user.id,
  });
  const row = Array.isArray(claimed) ? claimed[0] : claimed;
  if (claimError || !row?.target_type || !row?.target_id) {
    console.error("moderate-content claim", claimError?.message ?? "report unavailable");
    return json({ error: "Report is unavailable or the action is unsupported." }, 409);
  }

  if (decision === "remove" && row.target_type === "user") {
    try {
      await removeAllUserAvatars(admin, String(row.target_id));
    } catch (error) {
      await admin.rpc("release_content_moderation", {
        p_report: reportId,
        p_moderator: user.id,
      });
      console.error("moderate-content storage", error instanceof Error ? error.message : String(error));
      return json({ error: "User media cleanup failed. The report remains open." }, 503);
    }
  }

  const { error: finishError } = await admin.rpc("finish_content_moderation", {
    p_report: reportId,
    p_decision: decision,
    p_note: note,
    p_moderator: user.id,
  });
  if (finishError) {
    console.error("moderate-content finish", finishError.message);
    return json({ error: "Moderation did not complete. Retry this action." }, 503);
  }
  return json({ moderated: true, decision });
});
