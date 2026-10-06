# Changelog

All notable changes to Tapt are documented in this file. The project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `docs/web-deploy.md`, a checklist for redeploying `taptbeer.com` on Vercel.

### Changed

- README status now states that the app is not on the App Store, that the
  backend and website are offline, and that GitHub Actions is disabled.
- Release Integrity runs the live anon RPC contract check as its own job.
- Scheduled data jobs are paused until the Supabase project is restored.

### Fixed

- Image backfill workflows no longer report success when the script fails.
- Main-actor isolation warnings reported by Xcode 27.

## [1.0.0-beta.1] - 2026-07-23

### Added

- Initial public engineering baseline for the iOS application and supporting data workflows.
- Automated build, integrity, ingestion, screenshot, and release workflows.
- Explicit environment gates for TestFlight and App Store Connect operations.

[Unreleased]: https://github.com/erickdronski/tapt/compare/v1.0.0-beta.1...HEAD
[1.0.0-beta.1]: https://github.com/erickdronski/tapt/releases/tag/v1.0.0-beta.1
