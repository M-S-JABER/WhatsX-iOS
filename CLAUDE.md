# WhatsX iOS — Project Conventions

## Language policy (hard rule, set by the repo owner)

**Everything code-related is English**: source comments, doc comments,
commit messages, PR titles and bodies, branch names, test names, log
messages inside CI workflows and fastlane lanes. Do not add new Arabic
text anywhere in the repo. Arabic remains only where it is *product
content* (user-facing strings in `Sources/Design/L10n.swift`, App Store
metadata in `APPSTORE.md`) or in legacy comments not yet translated —
translate those opportunistically when touching a file, never introduce
new ones.

## Build system

- `WhatsX.xcodeproj` is generated from `project.yml` (XcodeGen) on every
  CI run and is never committed.
- The repo is also a Swift Package (`Package.swift`) so it can be opened
  in Swift Playgrounds on iPad; keep `Sources/` compatible with both
  (see the `#if SWIFT_PACKAGE` shim in `Sources/Design/WXFont.swift`).
- Unit tests live in `Tests/`, hosted in the app target
  (`@testable import WhatsX`). The `ios-build` workflow runs them
  automatically on the simulator.

## Release pipeline (no Mac required)

- `ios-build`: every push/PR — unsigned build + tests.
- `ios-certificates`: one-time bootstrap already done; `verify` mode only.
- `ios-release`: manual dispatch (or `v*` tag) — signed build + upload to
  TestFlight. Build number = workflow run number, passed to gym via
  `CURRENT_PROJECT_VERSION` (do NOT reintroduce `increment_build_number`;
  the XcodeGen project has no Apple Generic Versioning).
- Bundle ID: `com.m-s-jaber.whatsx`. Certificates live encrypted in the
  private `M-S-JABER/certificates` repo (fastlane match).
- App Store Connect app records cannot be created via API (Apple
  limitation) — that step is manual, and already done.

## Security invariants

- The session cookie lives in `SessionCookies.store` (in-memory) and is
  persisted only through `CookieVault` (Keychain, this-device-only).
  Never route networking through `HTTPCookieStorage.shared` or
  `URLSession.shared`; AVPlayer call sites must pass
  `SessionCookies.all` via `AVURLAssetHTTPCookiesKey`.
- HTTPS only end-to-end (`AppConfig.normalized` upgrades http, `makeURL`
  rejects non-https, Realtime refuses ws://). Keep it that way.
- `ITSAppUsesNonExemptEncryption=false` in `Resources/Info.plist` — the
  app must not gain non-exempt crypto without revisiting it.
- Privacy manifest declares "no data collected" under the self-hosted
  model (each customer runs their own server). Revisit
  `Resources/PrivacyInfo.xcprivacy` before any centrally-hosted offering.
