import type { SupabaseClient } from "npm:@supabase/supabase-js@2.106.2";

const PUBLIC_AVATAR_MARKER = "/storage/v1/object/public/avatars/";

export function avatarPathFromURL(value: string | null, userId: string): string | null {
  if (!value) return null;
  try {
    const path = decodeURIComponent(new URL(value).pathname);
    const marker = path.indexOf(PUBLIC_AVATAR_MARKER);
    if (marker < 0) return null;
    const objectPath = path.slice(marker + PUBLIC_AVATAR_MARKER.length);
    return objectPath.startsWith(`${userId}/`) ? objectPath : null;
  } catch {
    return null;
  }
}

export async function removeAvatarPaths(
  client: SupabaseClient,
  values: Array<string | null>,
): Promise<void> {
  const paths = [...new Set(values.filter((value): value is string => Boolean(value)))];
  for (let offset = 0; offset < paths.length; offset += 1000) {
    const { error } = await client.storage.from("avatars").remove(paths.slice(offset, offset + 1000));
    if (error) throw new Error(`Avatar removal failed: ${error.message}`);
  }
}

export async function removeAllUserAvatars(
  client: SupabaseClient,
  userId: string,
): Promise<void> {
  for (let batch = 0; batch < 100; batch += 1) {
    const { data, error } = await client.storage.from("avatars").list(userId, {
      limit: 1000,
      offset: 0,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw new Error(`Avatar listing failed: ${error.message}`);
    const paths = (data ?? [])
      .filter((item) => Boolean(item.id) && Boolean(item.name))
      .map((item) => `${userId}/${item.name}`);
    if (!paths.length) return;
    await removeAvatarPaths(client, paths);
    if (paths.length < 1000) return;
  }
  throw new Error("Avatar removal exceeded the reviewed batch limit");
}
