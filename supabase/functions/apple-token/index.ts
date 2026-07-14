import { createClient } from "npm:@supabase/supabase-js@2.106.2";
import { exchangeAppleAuthorizationCode, jwtPayload } from "../_shared/apple.ts";

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

  let authorizationCode = "";
  try {
    const body = await request.json() as { authorizationCode?: string };
    authorizationCode = body.authorizationCode?.trim() ?? "";
  } catch {
    return Response.json({ error: "bad json" }, { status: 400 });
  }
  if (!authorizationCode || authorizationCode.length > 4096) {
    return Response.json({ error: "authorization code required" }, { status: 422 });
  }

  try {
    const token = await exchangeAppleAuthorizationCode(authorizationCode);
    if (!token.refresh_token || !token.id_token) {
      throw new Error("Apple did not return the required account-deletion token");
    }

    const payload = jwtPayload(token.id_token);
    const appleSubject = typeof payload.sub === "string" ? payload.sub : "";
    const appleAudience = typeof payload.aud === "string" ? payload.aud : "";
    const configuredClient = Deno.env.get("APPLE_CLIENT_ID")?.trim() ?? "";
    const appleIdentity = user.identities?.find((identity) => identity.provider === "apple");
    const identityData = appleIdentity?.identity_data as Record<string, unknown> | undefined;
    const knownSubjects = new Set([
      appleIdentity?.id,
      typeof identityData?.sub === "string" ? identityData.sub : undefined,
      typeof identityData?.provider_id === "string" ? identityData.provider_id : undefined,
    ].filter((value): value is string => Boolean(value)));

    if (!appleIdentity || !appleSubject || !knownSubjects.has(appleSubject)) {
      throw new Error("Apple credential does not match the signed-in account");
    }
    if (!configuredClient || appleAudience !== configuredClient) {
      throw new Error("Apple credential audience does not match Tapt");
    }

    const admin = createClient(SUPA_URL, SERVICE);
    const { error } = await admin.rpc("store_apple_refresh_token", {
      p_user: user.id,
      p_token: token.refresh_token,
    });
    if (error) throw error;
    return Response.json({ stored: true });
  } catch (error) {
    console.error("apple-token", error instanceof Error ? error.message : String(error));
    return Response.json(
      { error: "Apple sign-in could not be completed securely. Try again." },
      { status: 502 },
    );
  }
});
