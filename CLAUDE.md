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
- The WebRTC binary package (stasel/WebRTC) is linked into the XcodeGen
  app target ONLY. `Package.swift` must stay dependency-free so Swift
  Playgrounds keeps loading — gate any WebRTC-touching code on
  `#if canImport(WebRTC)` (see `CallAudioEngine.swift`).
- Calls ring through CallKit (`CallKitBridge.swift`); WebRTC runs in
  manual-audio mode, started only from the provider's `didActivate`.
  Apple's hard rule: EVERY VoIP push must surface a CallKit call before
  the PushKit callback returns — never add an early return to
  `VoIPPush.didReceiveIncomingPush`/`CallCenter.handleVoipPush` that
  skips the report. The server contract is `docs/VOIP_PUSH.md`.
- Message pushes (`MessagePush.swift`) are sender-name-only BY OWNER
  DECISION — message text must never appear in a remote push payload
  (it would transit Apple's servers; see the privacy stance below).

## Release pipeline (no Mac required)

- `ios-build`: every push/PR — unsigned build + tests.
- `ios-certificates`: bootstrap already done — routine use is `verify`.
  `refresh-profiles` mode (CREATE-gated) exists for App ID capability
  changes: it enables the capability via Spaceship and regenerates the
  match profile (`force: true`, certificate reused). Run it once after
  merging any change to `Resources/WhatsX.entitlements`, BEFORE the next
  `ios-release`, or signing fails.
- `ios-release`: manual dispatch (or `v*` tag) — signed build + upload to
  TestFlight. Build number = workflow run number, passed to gym via
  `CURRENT_PROJECT_VERSION` (do NOT reintroduce `increment_build_number`;
  the XcodeGen project has no Apple Generic Versioning).
- Bundle ID: `com.m-s-jaber.whatsx`. Certificates live encrypted in the
  private `M-S-JABER/certificates` repo (fastlane match).
- App Store Connect app records cannot be created via API (Apple
  limitation) — that step is manual, and already done.

## External memory (Notion — Mustafa Brain)

The owner keeps cross-project memory in Notion. Claude sessions that have
the Notion MCP connected follow the owner's memory kit rules; this
project's row in the Projects database is page
`3c4e6e1b-8fb5-814f-81cf-e85fbe785c40`.

- Record significant architectural/technical decisions in the Decisions
  database (Decision / Why / Alternatives Rejected / Category, linked to
  the project) and reusable fixes in Knowledge.
- Update the project row's `Next Step` after finishing a major task.
- Never write Work Log entries by hand — `.github/workflows/notion-sync.yml`
  logs every push to main automatically (requires the `NOTION_TOKEN` and
  `NOTION_PROJECT_PAGE_ID` repo secrets; it skips gracefully without them).
- Memory summaries are written in Arabic (≤3 lines) — they are owner-side
  content in Notion, so the repo's English-only rule does not apply there.

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
