# Deploying the website (taptbeer.com)

`landing/` is a static site: plain HTML, one script (`embed.js`), a vendored
QR library, and images. There is no build step, no package manager, and no
server code. Vercel serves the folder as-is and applies `landing/vercel.json`
(`cleanUrls` plus security headers).

State on 2026-10-07: deployed. The Vercel project `tapt-landing` serves
`landing/` from `main` (Git-connected, so pushes to `main` redeploy), with
`taptbeer.com` as the production domain and `www.taptbeer.com` redirecting to it
with a 308. `/`, `/privacy`, `/terms`, and `/support` return 200. Step 1 below is
still open: data-driven pages wait on the paused Supabase project. The checklist
is kept as the procedure for rebuilding the project from scratch.

## Checklist

1. **Restore the backend first.** Every data-driven page (menus, partner portal,
   admin, newsletter signup and unsubscribe) calls Supabase project
   `qfwiizvqxrhjlthbjosz`, which is paused. `/`, `/privacy`, `/terms`, and
   `/support` load without it, but the home page's newsletter form needs it.
2. **Create the Vercel project** from `erickdronski/tapt`:
   - Project name: `tapt-landing`
   - Framework preset: `Other`
   - Root Directory: `landing`
   - Build, Output, and Install commands: leave the defaults. There is no
     `package.json`, so Vercel serves the directory as-is.
   - Production branch: `main` (Git-connected, so pushes to `main` deploy)
3. **Environment variables: none.** The Supabase URL and the publishable key are
   written into the pages on purpose; both are public, and row-level security
   and RPC grants decide what they can read. Never add a service-role key or
   any other server secret to a Vercel project that serves `landing/`.
4. **Domains:** add `taptbeer.com` as the production domain and
   `www.taptbeer.com` as a permanent (308) redirect to the apex.
5. **Supabase Auth URL configuration** (Dashboard, Authentication, URL
   Configuration): Site URL `https://taptbeer.com`; redirect URLs must allow
   `https://taptbeer.com/portal.html` and `https://taptbeer.com/admin.html`
   (the email sign-in links return to the page origin) and
   `tapt://auth-callback` for the app.
6. **Verify:**
   ```sh
   curl -sI https://taptbeer.com | head -1          # HTTP/2 200
   curl -sI https://www.taptbeer.com | head -1      # HTTP/2 308
   for p in privacy terms support; do curl -s -o /dev/null -w "$p %{http_code}\n" https://taptbeer.com/$p; done
   ```
   Then load `/portal` and request a sign-in code to confirm Supabase is
   reachable through the Content-Security-Policy.

The App Store listing links to `https://taptbeer.com/privacy`,
`/terms`, and `/support`, so those pages must be live before any new App Review
submission.

## If the backend moves to a new Supabase project

The project URL is hard-coded in `landing/vercel.json` (CSP `connect-src` and
`img-src`), in most pages, in the app, and in the data jobs. List every file
with:

```sh
grep -rl 'qfwiizvqxrhjlthbjosz' landing app/Tapt scripts .github .env.example
```

Update the URL and the publishable key in each. The service-role key only ever
lives in the `SUPABASE_SERVICE_ROLE_KEY` repository secret.
