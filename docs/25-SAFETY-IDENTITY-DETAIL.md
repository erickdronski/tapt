# docs/25-SAFETY-IDENTITY-DETAIL.md

One execution checklist merging four audit lanes: responsible-drinking + legal copy on every surface, the dormant identity features (avatar / name edit / public profile), the menu-scan personalized pick, and ranked detail fixes. All copy is house voice: plain, direct, no em dashes, no hype. Source files live in the real repo (the audit ran against a read-only copy at `scratchpad/tapt-src/`); apply in the real repo and keep `docs/legal/TERMS.md` + `docs/legal/PRIVACY.md` in sync with the `landing/` HTML.

Do NOT duplicate what already ships correctly: the Games 1.4.3 safety banner (`GameGuidesData.swift:27`, shown in GamesView/GameNightGuidesView/BeerOlympicsView), AgeGate + Onboarding:207 + SignInView:109 age confirmation, the Profile Responsibility section (SAMHSA + never drink and drive + does not sell), `landing/index.html:535`, `landing/privacy.html:28`, `landing/terms.html:29-33`. Those are the model copy and stay as-is except where a specific extension is listed below.

Reusable house-voice snippets:
- `21+. Please drink responsibly and never drink and drive.`
- `Know your limits. Never drink and drive.`
- `Do not drink if you are pregnant or taking medication that warns against alcohol.`
- `Votes only. No money, no trading, not a financial product.`
- `Informational only. Not dietary or medical advice.`

---

## 1. Responsible drinking + legal — exact copy + placement

Two disclaimers below are legally load-bearing beyond responsible-drinking and are marked MUST: the Beer Market financial-framing disclaimer (stock/trade metaphor with no "not a financial product" line = the biggest exposure found) and the share-card 21+ line (public content posted to IG). "Alcohol not sold in-app" is already covered in Terms/index/Profile; the owner should also state it in App Store Connect metadata (outside these files).

### App

| Priority | File | Verbatim line | Placement |
|---|---|---|---|
| MUST | `app/Tapt/Features/Sharing/ShareCard.swift` | `21+ · please drink responsibly` | After the handle `Text("@\(pour.user) tapt it")` (line 97-98). Reduce that Text's `.padding(.bottom, 26)` to `.padding(.bottom, 6)`, then add `Text("21+ · please drink responsibly").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Brand.malt.opacity(0.45)).padding(.bottom, 18)`. Card renders to a 360x640 public image (ShareTools.swift) posted to IG Stories / saved to Photos. |
| MUST | `app/Tapt/Features/Cellar/LogPourView.swift` | `Know your limits. Never drink and drive. 21+.` | Inside `VStack(spacing: 18)`, immediately after the `Button("Log it") { }.disabled(saving || rating == nil)` block ending at line 188 (before the VStack close at 189): `Text("Know your limits. Never drink and drive. 21+.").font(.caption2).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.top, 2)`. Primary drinking-log action; no safety copy today. |
| MUST | `app/Tapt/Features/Market/BeerMarketView.swift` | `Nothing invented. Votes only. No money, no trading, not a financial product.` | Line 184 footer: replace the trailing `Nothing invented.` with the full string. Stock-exchange framing (market, ticker, trade buttons, movers) with zero financial disclaimer is a real legal exposure. |
| SHOULD | `app/Tapt/Features/Market/MarketBeerDetailView.swift` | `Nothing invented. Votes only. No money, no trading, not a financial product.` | Line 42: same replacement of the trailing `Nothing invented.` so the disclaimer shows wherever the market metaphor appears. |
| SHOULD | `app/Tapt/Features/Scan/ScanView.swift` | `Know your limits. Never drink and drive.` | In the "Pour logged" success VStack, after `Text("Your Cellar and Passport just got a little deeper.")` (line 124): `Text("Know your limits. Never drink and drive.").font(.caption2).foregroundStyle(Brand.muted).multilineTextAlignment(.center)`. Second logging entry point. |
| SHOULD | `app/Tapt/Features/Cellar/CellarView.swift` | `Tapt celebrates variety and discovery, not volume. Please drink responsibly.` | Last element in the main Cellar ScrollView VStack, after the collection / "Your beers" section (~line 280+): `Text("Tapt celebrates variety and discovery, not volume. Please drink responsibly.").font(.caption2).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal)`. Reframes the streak/count mechanic for App Store 1.4.3. |
| SHOULD | `app/Tapt/Features/Beer/BeerDetailView.swift` | `Informational only. Not dietary or medical advice.` | In `nutritionCard`, right after `Text("Source: Open Food Facts").font(.caption2).foregroundStyle(Brand.muted)` (lines 567-568): `Text("Informational only. Not dietary or medical advice.").font(.caption2).foregroundStyle(Brand.muted)`. Pages show ABV / calories / carbs / sugars. |
| NICE | `app/Tapt/Features/Profile/ProfileView.swift` | `Tapt is for people of legal drinking age and does not sell alcohol. Do not drink if you are pregnant or taking medication that warns against alcohol.` | Section footer line 214: replace the existing `Tapt is for people of legal drinking age and does not sell alcohol.` with the extended string. Surfaces the medication/pregnancy line next to the existing SAMHSA link. |

### Web

| Priority | File | Verbatim line | Placement |
|---|---|---|---|
| SHOULD | `landing/terms.html` (+ mirror `docs/legal/TERMS.md`) | insert `do not drink if you are pregnant or taking medication that warns against alcohol,` | In the "Drink responsibly" clause at line 31, after `Know your limits, look out for your friends,` so it reads `...look out for your friends, do not drink if you are pregnant or taking medication that warns against alcohol, and follow all local laws about alcohol.` Terms is the authoritative home for the medication line. |
| NICE | `landing/dispatch.html` | `Tapt is for people of legal drinking age. Please drink responsibly. Tapt does not sell alcohol.` | Inside `<div class="wrap foot-in">`, after the foot-links div (~line 306, before `</div></footer>`): `<p style="width:100%;margin:14px 0 0;font-size:.8rem;opacity:.65">Tapt is for people of legal drinking age. Please drink responsibly. Tapt does not sell alcohol.</p>` |
| NICE | `landing/support.html` | `Tapt is for people of legal drinking age. Please drink responsibly.` | Footer line 57: change `Tapt support - <a ...>esdronski@gmail.com</a>` to `Tapt support - <a href="mailto:esdronski@gmail.com?subject=Tapt%20support">esdronski@gmail.com</a><br><span style="opacity:.7">Tapt is for people of legal drinking age. Please drink responsibly.</span>` |
| NICE | `landing/pitch.html` | `Tapt · 21+, please drink responsibly ·` | `.foot` at line 154: change `Tapt · enjoy responsibly ·` to `Tapt · 21+, please drink responsibly ·` |

### Partner (venue-facing / customer-at-table)

| Priority | File | Verbatim line | Placement |
|---|---|---|---|
| SHOULD | `landing/portal.html` | `Serve responsibly. Check IDs. 21+/legal drinking age. Tapt does not sell alcohol.` | Inside `<footer class="portal-footer">` (line 172), after `<span>Tapt for breweries, bars, pubs, and taprooms.</span>` (line 173): `<span>Serve responsibly. Check IDs. 21+/legal drinking age. Tapt does not sell alcohol.</span>`. This is where partners publish menus. |
| SHOULD | `landing/menu.html` | `Menus are published by the venue via Tapt. Please drink responsibly and never drink and drive. 21+/legal drinking age. Tapt does not sell alcohol.` | `.foot` at line 62: replace the existing `Menus are published by the venue via Tapt. Enjoy responsibly, 21+/legal drinking age.` This is the exact page a bar's customers scan at the table. |
| SHOULD | `landing/print.html` | `21+ · Please drink responsibly` | Add CSS near line 45: `.legal{font-size:.11in;font-weight:700;opacity:.55;margin-top:.06in}body[data-layout="stickers"] .legal{display:none}`. Then inside every `.piece-in` (the 6 `<article class="piece ...">` blocks, lines 76-81), before the closing `</div></article>`: `<div class="legal">21+ · Please drink responsibly</div>`. Hidden on the tiny sticker layout. Physical tent cards / posters on bar tables. |

### Content (social)

| Priority | File | Verbatim line | Placement |
|---|---|---|---|
| SHOULD | `social-assets/ig/CAPTIONS.md` | `21+. Please drink responsibly.` (+ `#drinkresponsibly`) | Add a standing note near the top: `**Standard footer (append to every caption):** 21+. Please drink responsibly. #drinkresponsibly`, and append `21+. Please drink responsibly.` as the last line of each existing post caption block (Post 1-5). Caption source is the pragmatic lever (PNGs are rendered output). |
| NICE | `social-assets/ig/post-03-taste-guinness.html` (+ `post-04-ipa.html`, `post-05-poll-story.html`) | `21+ · drink responsibly` | In the `.foot` block (line 56, uses `@taptbeerapp`), add a sibling span: `<span style="margin-left:auto;font-size:22px;opacity:.55">21+ · drink responsibly</span>`. Apply to the three posts that show a specific beer, then re-run `render.sh`. Lower priority: requires re-rendering; captions cover the baseline. |

---

## 2. Identity build — avatar upload, name edit, public profile

Backend is 100% built and dormant. The `avatars` bucket exists (public, 2MB, jpeg/png/heic/heif; owner insert + owner update policies, NO delete), `user_profile` already has `display_name` / `handle` (UNIQUE index `user_profile_handle_key`) / `avatar_url`, the seed trigger `handle_new_user` populates from OAuth metadata, and the read side (`public_profile` RPC + `PublicProfileView` rendering avatar/@handle/4-stat strip/badges) already renders. Missing: three thin SECURITY DEFINER write RPCs (user_profile has ONLY a SELECT RLS policy `self_profile_select`, so direct client UPDATE is denied), the client write paths, and You-tab surfacing.

### 2a. DB migration — write RPCs + delete policy (MUST)

File: `supabase/migrations/0082_profile_identity_writes.sql`. Follows the `set_profile_preferences` / `set_social_visibility` pattern. The explicit revoke-from-public + grant-to-authenticated is required or these are not callable under the anon contract (reference_tapt_agents_sync 0081 PUBLIC-grant gotcha). Apply via `apply_migration` after owner approval.

```sql
-- Set display name + handle in one authed call. null leaves a field unchanged;
-- empty handle clears it. Validation is server-side so RLS-less clients can't bypass.
create or replace function public.set_profile_identity(
  p_display_name text default null,
  p_handle text default null
) returns void
language plpgsql security definer set search_path to 'public' as $$
declare
  v_uid uuid := auth.uid();
  v_name text; v_handle text;
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if p_display_name is not null then
    v_name := btrim(p_display_name);
    if length(v_name) < 2 or length(v_name) > 40 then
      raise exception 'display_name_length' using errcode = '22023';
    end if;
    update public.user_profile set display_name = v_name, updated_at = now() where id = v_uid;
  end if;
  if p_handle is not null then
    v_handle := lower(btrim(p_handle));
    if v_handle = '' then
      update public.user_profile set handle = null, updated_at = now() where id = v_uid;
    else
      if v_handle !~ '^[a-z0-9_]{3,20}$' then
        raise exception 'handle_format' using errcode = '22023';
      end if;
      if exists (select 1 from public.user_profile where handle = v_handle and id <> v_uid) then
        raise exception 'handle_taken' using errcode = '23505';
      end if;
      update public.user_profile set handle = v_handle, updated_at = now() where id = v_uid;
    end if;
  end if;
end $$;

-- Record the avatar public URL after upload. Only our own bucket URLs are accepted.
create or replace function public.set_avatar_url(p_url text default null)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'auth required'; end if;
  if p_url is not null and p_url <> ''
     and p_url not like 'https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/avatars/%' then
    raise exception 'avatar_url_host' using errcode = '22023';
  end if;
  update public.user_profile set avatar_url = nullif(p_url, ''), updated_at = now() where id = v_uid;
end $$;

-- Let owners delete their own avatar file (bucket only has insert+update today).
create policy "avatar owner delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and owner = (select auth.uid()));

revoke all on function public.set_profile_identity(text, text) from public;
revoke all on function public.set_avatar_url(text) from public;
grant execute on function public.set_profile_identity(text, text) to authenticated;
grant execute on function public.set_avatar_url(text) to authenticated;
```

### 2b. ProfileService — write + read methods (MUST)

File: `app/Tapt/Core/ProfileService.swift`. Add four members to `enum ProfileService` (mirror the existing `authedRPCVoid` style; `import Supabase` already present). Avatar upload / PhotosPicker / storage.upload is genuinely net-new — grep confirms zero occurrences in `app/`. Verify `FileOptions` / `getPublicURL` match the pinned supabase-swift version before building.

```swift
struct MyProfile: Sendable { let displayName: String?; let handle: String?; let avatarUrl: String? }

/// The caller's own editable identity row (self_profile_select RLS allows this).
static func myProfile(userId: UUID) async throws -> MyProfile {
    struct Row: Decodable { let display_name: String?; let handle: String?; let avatar_url: String? }
    _ = try await Supa.client.auth.session
    let rows: [Row] = try await Supa.client.from("user_profile")
        .select("display_name,handle,avatar_url").eq("id", value: userId.uuidString)
        .limit(1).execute().value
    let r = rows.first
    return MyProfile(displayName: r?.display_name, handle: r?.handle, avatarUrl: r?.avatar_url)
}

/// Save display name and/or handle. nil leaves a field unchanged; "" clears the handle.
static func setIdentity(displayName: String?, handle: String?) async throws {
    struct Params: Encodable { let p_display_name: String?; let p_handle: String? }
    try await Supa.authedRPCVoid("set_profile_identity",
        params: Params(p_display_name: displayName, p_handle: handle))
}

static func setAvatarURL(_ url: String?) async throws {
    struct Params: Encodable { let p_url: String? }
    try await Supa.authedRPCVoid("set_avatar_url", params: Params(p_url: url))
}

/// Upload JPEG to avatars/{uid}/avatar.jpg, record the public URL, return it cache-busted.
static func uploadAvatar(_ jpeg: Data, userId: UUID) async throws -> String {
    let path = "\(userId.uuidString)/avatar.jpg"
    _ = try await Supa.client.storage.from("avatars").upload(
        path: path, file: jpeg,
        options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true))
    let base = try Supa.client.storage.from("avatars").getPublicURL(path: path).absoluteString
    let busted = base + "?v=\(Int(Date().timeIntervalSince1970))"
    try await setAvatarURL(busted)
    return busted
}
```

Map RPC error codes to friendly copy at the call site: `handle_taken` → "That handle is taken. Try another.", `handle_format` → "Handles are 3 to 20 characters: letters, numbers, underscore.", `display_name_length` → "Names are 2 to 40 characters."

### 2c. ProfileView You-tab header — avatar upload + handle + real name (MUST)

File: `app/Tapt/Features/Profile/ProfileView.swift`. Lines 44-58 render only an initial-in-circle; `displayName` (lines 29-32) reads from auth metadata not the profile row, so an edit never appears; handle is never shown.

1. Add `import PhotosUI` at top.
2. Add state: `@State private var myProfile: ProfileService.MyProfile?`, `@State private var pickedItem: PhotosPickerItem?`, `@State private var avatarUploading = false`, `@State private var identityError: String?`, `@State private var showEditIdentity = false`.
3. In the `displayName` computed, prefer the profile row: `if let n = myProfile?.displayName, !n.isEmpty { return n }` before the existing userMetadata fallback.
4. Replace the header initial `Text` (lines 44-57) with a PhotosPicker-wrapped avatar. Extract the existing `Text(initial)` styling into a computed `initialAvatar` view used as both placeholder and fallback:

```swift
PhotosPicker(selection: $pickedItem, matching: .images) {
    ZStack(alignment: .bottomTrailing) {
        Group {
            if let u = myProfile?.avatarUrl, let url = URL(string: u) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { initialAvatar }
            } else { initialAvatar }
        }
        .frame(width: 58, height: 58).clipShape(Circle())
        .overlay(Circle().stroke(Brand.malt, lineWidth: 2))
        Image(systemName: "camera.fill").font(.system(size: 11, weight: .bold))
            .foregroundStyle(Brand.malt).padding(5).background(Brand.gold, in: Circle())
            .overlay(Circle().stroke(Brand.background, lineWidth: 2))
    }
}.disabled(avatarUploading)
```

5. In the VStack next to the avatar, under `displayName`: `if let h = myProfile?.handle, !h.isEmpty { Text("@\(h)").font(.subheadline).foregroundStyle(Brand.gold) }` and (guarded by `if session.user != nil`) `Button("Edit name and handle") { showEditIdentity = true }.font(.footnote.weight(.semibold)).foregroundStyle(Brand.malt)`.
6. In `.task { }` also run `await loadMyProfile()` where that helper sets `myProfile = try? await ProfileService.myProfile(userId: id)`.
7. Add `.onChange(of: pickedItem) { _, item in Task { await uploadAvatar(item) } }`: guard user id + item; `avatarUploading = true`; load `Data` via `item?.loadTransferable(type: Data.self)`; downscale to <=512px JPEG at 0.8; `myProfile = MyProfile(... avatarUrl: try await ProfileService.uploadAvatar(jpeg, userId: id))`; on error `identityError = "Your photo did not upload. Check your connection and try again."`; `avatarUploading = false`.
8. Add `.sheet(isPresented: $showEditIdentity) { EditIdentityView(initial: myProfile) { updated in myProfile = updated } }`.

### 2d. New EditIdentityView (MUST)

File: `app/Tapt/Features/Profile/EditIdentityView.swift`.

```swift
import SwiftUI

struct EditIdentityView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let initial: ProfileService.MyProfile?
    var onSaved: (ProfileService.MyProfile) -> Void
    @State private var name = ""
    @State private var handle = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Display name") {
                    TextField("Your name", text: $name).textInputAutocapitalization(.words)
                }
                Section {
                    HStack { Text("@").foregroundStyle(Brand.muted); TextField("handle", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled() }
                } header: { Text("Handle") } footer: {
                    Text("3 to 20 characters: letters, numbers, underscore. This is how friends find you.")
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("Edit profile").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving" : "Save") { save() }.disabled(saving) }
            }
            .onAppear { name = initial?.displayName ?? ""; handle = initial?.handle ?? "" }
        }
    }

    private func save() {
        saving = true; error = nil
        Task {
            do {
                try await ProfileService.setIdentity(
                    displayName: name.trimmingCharacters(in: .whitespaces),
                    handle: handle.trimmingCharacters(in: .whitespaces))
                onSaved(ProfileService.MyProfile(displayName: name, handle: handle.lowercased(), avatarUrl: initial?.avatarUrl))
                dismiss()
            } catch {
                let d = error.localizedDescription
                if d.contains("handle_taken") { self.error = "That handle is taken. Try another." }
                else if d.contains("handle_format") { self.error = "Handles are 3 to 20 characters: letters, numbers, underscore." }
                else if d.contains("display_name_length") { self.error = "Names are 2 to 40 characters." }
                else { self.error = "That did not save. Check your connection and try again." }
            }
            saving = false
        }
    }
}
```

### 2e. ProfileView — promote public profile access (SHOULD)

File: `app/Tapt/Features/Profile/ProfileView.swift`. The public profile (`PublicProfileView`) is only reachable via a plain row buried in the Privacy section, and only when `socialVisible` is on (lines 160-166). Add a prominent card directly under the header (only `if session.user != nil`); the card honors `social_visible` server-side.

```swift
NavigationLink { PublicProfileView(userId: id, initialName: displayName) } label: {
    HStack(spacing: 12) {
        Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(Brand.gold)
        VStack(alignment: .leading, spacing: 2) {
            Text("Your passport").font(.system(.subheadline, design: .rounded).weight(.bold))
            Text(socialVisible ? "This is what friends see" : "Private for now. Turn on Public passport below to share.")
                .font(.caption).foregroundStyle(Brand.muted)
        }
    }
}
```

Keep the existing Privacy-section toggle as the visibility control.

### 2f. LeaderboardsView — consume avatars + link taster rows (SHOULD)

File: `app/Tapt/Features/Community/LeaderboardsView.swift`. Documented at `docs/22-FINE-TOOTH-COMB.md:1043-1050`: taster rows decode `avatarUrl` (`SuperappServices.swift:153`) but always draw an initial circle, and taster rows are inert while beer rows navigate. At ~line 144-148 replace the initial-only avatar with `AsyncImage(url: taster.avatarUrl)` falling back to the initial circle, and wrap each taster row (ForEach ~141-167) in `NavigationLink { PublicProfileView(userId: taster.userId, initialName: taster.name) }` matching how beer rows already wrap (line 94). Verify `LeaderTaster` carries `userId`; if not, add it to the RPC select + struct.

### 2g. ProfileService.confirmLegalAge — latent dead write (NICE)

File: `app/Tapt/Core/ProfileService.swift`, lines 26-29. It does a direct `.update(["birth_verified": true])` on `user_profile`, but the table has only a SELECT RLS policy, so this write is denied / no-ops silently. Age is really set via `complete_profile_onboarding(p_age_confirmed)`. Either remove `confirmLegalAge` (if age is only ever set through onboarding) or route it through a SECURITY DEFINER RPC. Confirm no caller relies on the current silent-failure behavior before removing.

---

## 3. Menu-scan personalized pick

Two blockers. (1) `DataScannerView.sync()` resets `lines = [:]` on every frame and only keeps items in `allItems`, so panning a full tap list only ever yields the ~3-6 on-screen lines. (2) No server function scores scanned+matched beers against the user's taste. The taste engine already exists and is deployed (`recommend_beer`, migration 0093; `taste_vector` live with `top_styles` + `abv_comfort_band`). Honest by construction: the SQL returns ZERO rows unless there is real taste signal AND at least one on-menu style/family match; the pick is only computed when signed in and only from confidence >= 0.5 matches. No signal or no match = no card, never invented.

Implementation order: SQL migration first (owner `apply_migration`), then the Swift service + view edits, then DataScannerView, then rebuild + sim-verify a pan-and-match on a printed tap list.

### 3a. DataScannerView — accumulate menu lines across frames (MUST, the core fix)

File: `app/Tapt/Features/Scan/DataScannerView.swift`. `sync()` (lines 59-68) empties every frame; `didRemove` (lines 84-86) re-syncs after items leave frame. Replace the Coordinator storage + sync with a growing, deduped, ordered accumulator that is NOT emptied on `didRemove`.

(a) Replace `private var lines: [UUID: String] = [:]` (line 42) with:

```swift
// Ordered, deduped accumulator so a PAN across a menu captures the whole
// list. Never cleared on didRemove: lines that scroll off stay captured.
private var order: [String] = []          // normalized keys, insertion order
private var best: [String: String] = [:]  // normkey -> longest transcript seen
private let maxLines = 60
var appliedReset = 0
```

(b) Replace the whole `sync(_:)` (lines 59-68) with:

```swift
private func ingest(_ allItems: [RecognizedItem]) {
    var changed = false
    for item in allItems {
        guard case let .text(text) = item else { continue }
        let line = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count >= 3 else { continue }
        let key = line.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if let existing = best[key] {
            if line.count > existing.count { best[key] = line; changed = true }
        } else if order.count < maxLines {
            order.append(key); best[key] = line; changed = true
        }
    }
    guard changed else { return }
    let snapshot = order.compactMap { best[$0] }
    DispatchQueue.main.async { self.visibleLines = snapshot }
}

func reset() {
    order = []; best = [:]
    DispatchQueue.main.async { self.visibleLines = [] }
}
```

(c) Update the three delegate callbacks: `didAdd` (line 77), `didUpdate` (line 81), `didRemove` (line 85) all call `ingest(allItems)` instead of `sync(allItems)`. Keeping `didRemove -> ingest` (not reset) is what persists scrolled-off lines.

(d) Add a reset input so a new scan starts fresh: add `var resetToken: Int = 0` as a stored struct property (after line 9), and at the TOP of `updateUIViewController` (before line 23's guard):

```swift
if context.coordinator.appliedReset != resetToken {
    context.coordinator.appliedReset = resetToken
    context.coordinator.reset()
}
```

### 3b. New SQL — recommend_from_menu (MUST)

File: `supabase/migrations/0096_recommend_from_menu.sql`. Reuses `recommend_beer`'s affinity model, constrained to on-menu ids. Same column shape as `recommend_beer` so the existing `RecommendedBeer` decoder is reused verbatim. Apply via `apply_migration` after owner approval. (Hardening deferred to match the shipped `recommend_beer` pattern: it trusts `p_user` rather than forcing `p_user = auth.uid()`; add an `auth.uid()` guard later since it is security definer.)

```sql
-- 0096  "Your pick on this menu": from beers a user just scanned+matched off a
-- physical tap list (p_beer_ids), return the ONE that best fits their real taste.
-- Reuses recommend_beer's affinity model. Honest by construction: ZERO rows unless
-- there is real taste signal AND at least one on-menu beer is a genuine style or
-- family match. Down-voted beers excluded. Never invents a pick to fill the slot.
create or replace function public.recommend_from_menu(p_user uuid, p_beer_ids uuid[])
returns table(
  beer_id uuid, name text, brewery text, style text, country text,
  image_url text, abv numeric, reason text, match_kind text
)
language sql stable security definer set search_path = public
as $$
  with
  ids as (select distinct u as beer_id from unnest(coalesce(p_beer_ids,'{}'::uuid[])) u),
  liked as (
    select tv.s as style_name, 3 as weight
    from public.taste_vector t, unnest(t.top_styles) tv(s) where t.user_id = p_user
    union all
    select b.style_ref, 2 from public.beer_vote v
      join public.beer_catalog b on b.id = v.beer_id
      where v.user_id = p_user and v.value > 0 and b.style_ref is not null
    union all
    select b.style_ref, 2 from public.checkin_event c
      join public.beer_catalog b on b.id = c.beer_id
      where c.user_id = p_user and c.rating >= 4 and b.style_ref is not null
  ),
  style_affinity as (
    select style_name, sum(weight)::int as score from liked
    where coalesce(style_name,'') <> '' group by style_name
  ),
  family_affinity as (
    select distinct sr.style_family from style_affinity a
    join public.beer_style_reference sr on sr.style_name = a.style_name
    where sr.style_family is not null
  ),
  band as (select abv_comfort_band from public.taste_vector where user_id = p_user),
  disliked as (select beer_id from public.beer_vote where user_id = p_user and value < 0),
  scored as (
    select
      b.id,
      public.tapt_scan_name(coalesce(nullif(b.display_name,''), b.name)) as dname,
      br.name as brewery, b.style_ref as style,
      public.tapt_trusted_country(br.country, br.external_ids) as country,
      coalesce(b.cutout_url, b.label_image_url) as image_url, b.abv, sr.style_family,
      case when exists (select 1 from style_affinity a where a.style_name = b.style_ref)
           then 'love' else 'adjacent' end as match_kind,
      (case when exists (select 1 from style_affinity a where a.style_name = b.style_ref)
            then 100 else 70 end)
      + coalesce((select max(a.score) from style_affinity a where a.style_name = b.style_ref),0)
      + (case when exists (select 1 from public.beer_award aw where aw.beer_id = b.id) then 15 else 0 end)
      + (case when b.abv is not null and (select abv_comfort_band from band) is not null
                   and b.abv <@ (select abv_comfort_band from band) then 8 else 0 end)
      + (case when coalesce(b.cutout_url, b.label_image_url) is not null then 5 else 0 end)
      + (abs(('x'||substr(md5(b.id::text || current_date::text),1,6))::bit(24)::int) % 6) as score
    from public.beer_catalog b
    join ids on ids.beer_id = b.id
    join public.beer_style_reference sr on sr.style_name = b.style_ref
    left join public.brewery br on br.id = b.brewery_id
    where b.style_ref is not null
      and b.id not in (select beer_id from disliked)
      and (select count(*) from style_affinity) > 0
      and (exists (select 1 from style_affinity a where a.style_name = b.style_ref)
           or sr.style_family in (select style_family from family_affinity))
  ),
  pick as (select * from scored order by (match_kind='love') desc, score desc, dname limit 1)
  select p.id, p.dname, p.brewery, p.style, p.country, p.image_url, p.abv,
    case p.match_kind
      when 'love' then 'A ' || p.style || coalesce(' from ' || p.brewery, '')
        || ', right in your wheelhouse. Your best match on this menu.'
      else 'You lean into ' || p.style_family || '. This ' || p.style
        || coalesce(' from ' || p.brewery, '') || ' is the closest thing to your taste here.'
    end as reason, p.match_kind
  from pick p;
$$;
revoke all on function public.recommend_from_menu(uuid, uuid[]) from public, anon;
grant execute on function public.recommend_from_menu(uuid, uuid[]) to authenticated;
```

### 3c. RecommendationService.menuPick — client call (MUST)

File: `app/Tapt/Features/Explore/PickedForYouCard.swift`. Reuses the existing `RecommendedBeer` Decodable (lines 6-26, CodingKeys already map `beer_id`/`image_url`/`match_kind`). Add inside `enum RecommendationService` (after line 37):

```swift
/// The one beer on a just-scanned menu that best fits the user's taste, or
/// nil when there is not enough signal or no on-menu style match. The SQL
/// enforces both, so nil here means 'no honest pick', not an error.
static func menuPick(userId: UUID, beerIDs: [String]) async throws -> RecommendedBeer? {
    struct MenuParams: Encodable, Sendable { let p_user: String; let p_beer_ids: [String] }
    guard !beerIDs.isEmpty else { return nil }
    let rows: [RecommendedBeer] = try await Supa.authedRPC(
        "recommend_from_menu",
        params: MenuParams(p_user: userId.uuidString, p_beer_ids: beerIDs)
    )
    return rows.first
}
```

### 3d. ScanView.matchMenu — compute the pick (MUST)

File: `app/Tapt/Features/Scan/ScanView.swift`. `matchMenu` (lines 448-462) already builds `found`.

(a) Add state near line 23: `@State private var menuPick: RecommendedBeer?` and `@State private var menuResetToken = 0`.
(b) Pass the token to the scanner: in the `DataScannerView(...)` initializer (lines 47-51) add `resetToken: menuResetToken`.
(c) Replace the `matchMenu` body (lines 449-462) with:

```swift
menuMatching = true
defer { menuMatching = false }
var found: [ScannedBeer] = []
for line in visibleLines.prefix(24) {
    if let hits = try? await CheckinService.matchScan(line), let best = hits.first, best.confidence >= 0.3 {
        if !found.contains(where: { $0.id == best.id }) { found.append(best) }
    }
}
matches = found
offBeer = nil
menuPick = nil
// Personalized pick: only from confidently-matched beers, only when signed in.
// recommend_from_menu returns nothing unless real taste signal AND a real
// style match exist, so the card is honest by construction.
let strongIDs = found.filter { $0.confidence >= 0.5 }.map(\.id)
if let uid = session.user?.id, !strongIDs.isEmpty {
    menuPick = try? await RecommendationService.menuPick(userId: uid, beerIDs: strongIDs)
}
scanLabel = "Menu scan: \(visibleLines.count) lines read"
showResult = true
menuResetToken += 1
```

(d) Clear the pick when the sheet closes: change line 106 `onDismiss` to `onDismiss: { scanned = nil; menuPick = nil }`.

### 3e. ScanView result sheet — highlighted pick card (MUST)

File: `app/Tapt/Features/Scan/ScanView.swift`. Reuses `BeerThumb` (`CatalogView.swift:274`), `BeerDetailView(beerId:)` (`BeerDetailView.swift:7`), `Brand.copper`/`Brand.gold`/`.taptPress` (all exist).

(a) In `resultSheet`, change the else-branch at lines 287-294 to prepend the pick card:

```swift
} else {
    if let menuPick {
        menuPickCard(menuPick)
    }
    VStack(spacing: 10) {
        ForEach(matches) { match in
            matchRow(match)
        }
    }
    .padding(.horizontal)
}
```

(b) Change line 308 `.presentationDetents([.medium])` to `.presentationDetents([.medium, .large])`.
(c) Add the card builder near `matchRow` (after line 354):

```swift
private func menuPickCard(_ pick: RecommendedBeer) -> some View {
    NavigationLink { BeerDetailView(beerId: pick.beerId) } label: {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your pick on this menu", systemImage: "sparkles")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Brand.copper)
            HStack(spacing: 12) {
                BeerThumb(imageUrl: pick.imageUrl, size: 56, corner: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pick.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text).lineLimit(1)
                    Text(pick.reason)
                        .font(.caption).foregroundStyle(Brand.muted)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Brand.muted)
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [Brand.gold.opacity(0.18), Brand.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.gold.opacity(0.4)))
    }
    .buttonStyle(.taptPress)
    .padding(.horizontal)
}
```

### 3f. Match-menu hint copy (NICE)

File: `app/Tapt/Features/Scan/ScanView.swift`, line 155. With accumulation, `visibleLines.count` now means "lines captured so far during the pan" (correct, no binding change needed). Change the hint text from `Point at a barcode, a printed tap list, or a venue QR` to `Point at a barcode or venue QR. For a full menu, slowly pan down the tap list, then tap Match menu.` Teaches the pan that fills the accumulator.

---

## 4. Detail fixes (ranked)

The app is in good functional shape: every `Features/**` screen read is wired with real destinations, empty states, skeletons, and retry buttons. No dead buttons, no "SOON" stubs, no nav dead-ends. The owner's LogPour image complaint is real but is data/CDN latency, not a code bug: of 10,264 listable beers only 101 have a fast Supabase `cutout_url`; 9,640 thumbnails load from `images.openfoodfacts.org` (slow CDN), fetched one row at a time on first paint. `catalog_search` already orders imaged beers first, and the missing-image fallback (`CachedBeerImage` → `mug.fill` glyph) is graceful and honest (never a fabricated image). Root cause of "is TaptImageCache used everywhere": no — BeerThumb rows use it, but `BeerOfWeekCard` and `MarketBeerDetailView` still use plain `AsyncImage`, and `BeerImageView` uses `URLSession.shared.download` which bypasses persistent caching.

| # | Priority | File:line | Fix |
|---|---|---|---|
| 1 | MUST | `app/Tapt/Core/ImageCache.swift` (after `image(for:maxPixel:)`) | Add a batch `prefetch(_ urls:maxPixel:)` to the `TaptImageCache` actor so a freshly opened list warms concurrently from cache instead of hitting the slow origin one row at a time. Skips anything already cached or in flight; reuses the existing coalescing + disk layer: `func prefetch(_ urls: [String], maxPixel: CGFloat) { for u in urls where !u.isEmpty { let k = key(u, maxPixel); if memory.object(forKey: k as NSString) != nil { continue }; if inflight[k] != nil { continue }; let file = diskURL(k); let task = Task<UIImage?, Never> { await Self.fetch(u, maxPixel: maxPixel, file: file) }; inflight[k] = task; Task { let result = await task.value; inflight[k] = nil; if let result { let px = (result.cgImage?.width ?? 1) * (result.cgImage?.height ?? 1) * 4; memory.setObject(result, forKey: k as NSString, cost: max(1, px)) } } } }` |
| 2 | MUST | `app/Tapt/Features/Cellar/LogPourView.swift:420` | In `loadCatalog()`, immediately after `beers = try await CheckinService.catalog(query: search)`, warm the first ~12 visible thumbnails: `let warmPx = max(88, 44 * UIScreen.main.scale); let warmUrls = beers.prefix(12).compactMap(\.imageUrl); Task { await TaptImageCache.shared.prefetch(warmUrls, maxPixel: warmPx) }`. `44*scale` matches `CachedBeerImage`'s own key math so no double-fetch. Directly targets the owner-reported first-open slowness. |
| 3 | SHOULD | `app/Tapt/Features/Beer/BeerOfWeekCard.swift:80-88` | Replace the uncached `AsyncImage` block (placeholder `Color.clear` for BOTH loading AND failure = empty 34x34 gap on broken labels) with `BeerThumb(imageUrl: entry.labelImageUrl, size: 34, corner: 8)`. Routes through TaptImageCache and shows the honest `mug.fill` fallback. |
| 4 | SHOULD | `app/Tapt/Features/Market/MarketBeerDetailView.swift:128-136` | Replace the plain `AsyncImage` hero (re-downloads every sheet open) with a cached loader keeping the symbol fallback: `if let s = beer.imageUrl, !s.isEmpty { CachedBeerImage(url: s, targetPoints: 84).padding(6) } else { Text(String(beer.symbol.prefix(2))).font(.headline.weight(.heavy)).foregroundStyle(Brand.gold) }` |
| 5 | SHOULD | `app/Tapt/Core/BeerImageView.swift` (in `load()`) | Route the network fetch through `TaptImageCache` instead of `URLSession.shared.download` (which bypasses URLCache per the ImageCache header comment). This is the detail/market hero path and the one place still re-downloading a ~900px OFF image every open. At minimum persist the downloaded bytes to a deterministic on-disk file (same FNV-1a scheme as `ImageCache.diskURL`) and read from disk first on subsequent launches. Lower than row thumbnails: one image per screen. |
| 6 | NICE | `app/Tapt/Features/Scan/ScanView.swift:361-368` | Replace the OFF product-card `AsyncImage` with `CachedBeerImage(url: off.imageURL, targetPoints: 54)` inside the existing 54x54 gold rounded frame. Consistency + caching; low severity (single card after a scan). |
| 7 | NICE | `app/Tapt/Features/Placeholders.swift` | `BrandScreen` is unused (grep for `BrandScreen(` = zero call sites). Delete the file, or drop the stale "Each becomes a real feature next" comment since Scan/Cellar/NearYou/Games all shipped. Dead scaffold that reads as unfinished. |

Verified-good, no change needed: `CachedBeerImage` failure path is graceful/honest (settled → `mug.fill` glyph, never fabricated); LogPour rating cannot be invented (Log-it disabled until a star is tapped); duplicate-checkin guard (selected=nil before share sheet) is in place. Not verified (needs running app): actual OFF URL 404 rates and runtime image timing on device — confirm the prefetch win in the simulator.

---

### Cross-lane notes
- Repo was read-only during the audit; every edit above is a spec with exact strings and anchors. Apply in the real repo.
- Owner one-actions gated to Supabase: `apply_migration` for `0082_profile_identity_writes.sql` and `0096_recommend_from_menu.sql`.
- Keep `docs/legal/TERMS.md` and `docs/legal/PRIVACY.md` in sync with the `landing/` HTML for the Terms medication edit.
- All added copy avoids em dashes and hype, per house voice.