# Tapt Status and Release Roadmap

Living release record, updated 2026-07-13. `AGENTS.md` is the coordination
source of truth. This document describes product state and release gates.

## Current State

### iOS

- Native Swift 6 and SwiftUI app generated with XcodeGen.
- Working email magic-link and six-digit-code authentication.
- Guest access covers Catalog, Near You, Discover, Learn, and Games without
  calling authenticated Tapt data surfaces.
- Catalog search, beer detail, Cellar, Passport, Beer Market, Beer of the Week,
  Tonight, community, partner tools, and account controls are wired to live
  Supabase data.
- Beer Pong uses SpriteKit physics and is the interaction-quality reference.
  Flip Cup, Quarters, and Darts are present but remain polish candidates.
- The current release candidate is not yet on TestFlight. It must pass GitHub's
  macOS build and test workflow before upload.

### Authentication Truth

- Email magic link and email code are enabled and have completed real sessions.
- Google is enabled and linked to the owner account, but has not completed a
  signed-device TestFlight callback proof.
- Apple is implemented in the client but disabled in Supabase pending Apple
  provider credentials.
- Facebook, X, and phone are disabled.
- Google remains visible so its signed-device callback can be tested. Apple,
  Facebook, and X stay hidden while disabled. Email is the verified primary
  sign-in path.

### Backend

- Production Supabase migrations and repository migration history are aligned
  through `0083_beer_name_quality_v4.sql`.
- Catalog, map, market, Tonight, Cellar, partner menu, media-processing, and
  No/Low read models are live.
- Public RPC access is limited to the four web surfaces documented in
  `AGENTS.md`; account and community data require an authenticated session.
- Partner logo replacement has the Storage permissions required for upsert.
- The Overture venue loader and media cutout pipeline are implemented. Their
  first reviewed production batches have not run yet.

### Web and Partner Portal

- `taptbeer.com` serves the landing page, partner portal, public menus, support,
  admin, dispatch, pitch, and app-preview surfaces through Vercel.
- The landing headline is `THE Beer Superapp. All of beer, one app.`
- Partner claim, approval, menu publishing, logo upload, hosted menu, and QR
  workflow are implemented.
- TestFlight feedback guidance is published on the support page. Screenshot
  feedback also requires assignment to a beta group with feedback enabled.
- A six-frame screenshot capture passed build and OCR checks. Visual review
  rejected the Beer Radar frame because its status-bar host background was
  black; the preview presentation and validator are being corrected before use.

## Release Gates

Complete these in order:

1. Commit and push each release batch with an `Agent: codex` or `Agent: claude`
   trailer after reconciling the latest `main`.
2. Pass the GitHub macOS build and test workflow. Local syntax parsing is not a
   substitute for an Xcode build.
3. Merge only after CI succeeds and verify the Vercel production deployment.
4. Upload the merged iOS commit through the dispatch-only TestFlight workflow.
5. Confirm TestFlight group assignment, feedback email, feedback enablement,
   beta description, and build metadata.
6. Test email link and email code on a signed TestFlight device.
7. Finish Google signed-device callback verification and Apple provider setup.
   Enable each button in `AuthProvidersService.deviceVerified` only after that
   provider creates a real session on the signed build.
8. Complete App Store Connect screenshots, metadata, privacy answers, age
   rating, review notes, and support links, then run a final submission audit.

## Product Work After the Release Candidate

- Run the attributed product-image cutout workflow and review every batch before
  exposing its output broadly.
- Improve Flip Cup, Quarters, and Darts one at a time, using Beer Pong's play and
  persistence quality as the reference.
- Add in-app venue claiming that hands off cleanly to the partner portal.
- Add partner approval and inquiry emails only after unsubscribe, sender,
  address, and secret configuration are verified.
- Add push notifications for useful local and social events after APNs
  credentials and notification controls are complete.
- Deepen local density with licensed venue data, partner-maintained menus, and
  first-party check-ins. Do not manufacture activity to fill empty states.
- Expand the Cellar and Passport with factual origin, style, and location context
  derived from each user's real history.

## Known Gaps

- Google and Apple sign-in are not release-verified. Facebook, X, and phone are
  intentionally disabled.
- The current branch still needs a real Xcode CI build and signed-device test.
- Production product imagery remains incomplete; the new pipeline is ready but
  its first reviewed batch has not run.
- Local market and community surfaces will be quiet until real activity exists.
- Newsletter collection and send code exist, but production delivery remains inactive until its sender and cron secrets are verified.
- Legal and App Store metadata require an owner review before submission.
- Supabase reports outstanding invoices; service continuity is a release risk
  until the owner resolves them.

## Release Principle

Ship only what has passed the real path: production data, GitHub Xcode build,
signed TestFlight device, and App Store Connect audit. Empty and unavailable
states must remain honest until the underlying capability works.
