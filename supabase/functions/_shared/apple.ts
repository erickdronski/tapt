const encoder = new TextEncoder();

type AppleTokenResponse = {
  access_token?: string;
  expires_in?: number;
  id_token?: string;
  refresh_token?: string;
  token_type?: string;
  error?: string;
};

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function encodeJSON(value: unknown): string {
  return base64URL(encoder.encode(JSON.stringify(value)));
}

function privateKeyBytes(pem: string): Uint8Array {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  if (!base64) throw new Error("APPLE_SIGN_IN_KEY is empty");
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function required(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

async function clientSecret(): Promise<{ clientId: string; value: string }> {
  const teamId = required("APPLE_TEAM_ID");
  const keyId = required("APPLE_SIGN_IN_KEY_ID");
  const clientId = required("APPLE_CLIENT_ID");
  const privateKey = required("APPLE_SIGN_IN_KEY").replace(/\\n/g, "\n");
  const now = Math.floor(Date.now() / 1000);
  const header = encodeJSON({ alg: "ES256", kid: keyId, typ: "JWT" });
  const payload = encodeJSON({
    iss: teamId,
    iat: now,
    exp: now + 300,
    aud: "https://appleid.apple.com",
    sub: clientId,
  });
  const unsigned = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(unsigned),
  );
  return { clientId, value: `${unsigned}.${base64URL(new Uint8Array(signature))}` };
}

export async function exchangeAppleAuthorizationCode(
  authorizationCode: string,
): Promise<AppleTokenResponse> {
  const secret = await clientSecret();
  const response = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: secret.clientId,
      client_secret: secret.value,
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
  });
  const body = await response.json().catch(() => ({})) as AppleTokenResponse;
  if (!response.ok) {
    throw new Error(`Apple token exchange failed (${body.error ?? response.status})`);
  }
  return body;
}

export async function revokeAppleToken(token: string): Promise<void> {
  const secret = await clientSecret();
  const response = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: secret.clientId,
      client_secret: secret.value,
      token,
      token_type_hint: "refresh_token",
    }),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({})) as { error?: string };
    throw new Error(`Apple token revocation failed (${body.error ?? response.status})`);
  }
}

export function jwtPayload(token: string): Record<string, unknown> {
  const part = token.split(".")[1];
  if (!part) throw new Error("Apple identity token is malformed");
  const normalized = part.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return JSON.parse(atob(padded));
}
