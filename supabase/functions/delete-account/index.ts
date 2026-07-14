import { createClient } from "npm:@supabase/supabase-js@2.106.2";
import { revokeAppleToken } from "../_shared/apple.ts";
import { removeAllUserAvatars } from "../_shared/avatars.ts";

const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "POST only" }, { status: 405 });
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const caller = createClient(SUPA_URL, ANON, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) {
    return Response.json({ error: "sign in required" }, { status: 401 });
  }

  const admin = createClient(SUPA_URL, SERVICE);
  const hasAppleIdentity = user.identities?.some((identity) => identity.provider === "apple") ?? false;
  let manualAppleRevocationRequired = false;

  if (hasAppleIdentity) {
    const { data: refreshToken, error: tokenError } = await admin.rpc(
      "get_apple_refresh_token",
      { p_user: user.id },
    );
    if (tokenError) {
      console.error("delete-account token lookup", tokenError.message);
      return Response.json({ error: "Account deletion is temporarily unavailable." }, { status: 503 });
    }
    if (typeof refreshToken === "string" && refreshToken) {
      try {
        await revokeAppleToken(refreshToken);
      } catch (error) {
        console.error("delete-account Apple revoke", error instanceof Error ? error.message : String(error));
        return Response.json(
          { error: "Apple authorization could not be revoked. Try again." },
          { status: 502 },
        );
      }
    } else {
      // Legacy Apple accounts created before token capture still have to be
      // deleted immediately. The client can direct them to Apple account settings.
      manualAppleRevocationRequired = true;
    }
  }

  try {
    await removeAllUserAvatars(admin, user.id);
  } catch (error) {
    console.error("delete-account avatar cleanup", error instanceof Error ? error.message : String(error));
    return Response.json({ error: "Account media could not be removed. Try again." }, { status: 503 });
  }

  const { error: deleteError } = await admin.rpc("delete_account_data", { p_user: user.id });
  if (deleteError) {
    console.error("delete-account data removal", deleteError.message);
    return Response.json({ error: "Account deletion did not complete." }, { status: 500 });
  }

  return Response.json({ deleted: true, manualAppleRevocationRequired });
});
