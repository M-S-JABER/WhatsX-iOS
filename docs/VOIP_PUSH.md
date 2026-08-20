# VoIP push — server integration spec

Audience: the WhatsX **server** team (`whatsapp.m-s-jaber.com`).
Written by the iOS side; the app code referencing this contract shipped in
iOS 1.18.0 (`VoIPPush.swift`, `CallKitBridge.swift`, `VoipPayload.swift`).

## Why

The iOS app can only ring while it is open: call signaling arrives over the
`/ws` socket, and iOS suspends the process shortly after the user leaves the
app. Apple's mechanism for waking an app for a call is a **VoIP push**
(PushKit): the system launches the app in the background, the app reports
the call to CallKit, and the phone rings with the native call UI — including
on the lock screen.

The iOS side of this is fully shipped and dormant. **Calls ring while the
app is closed as soon as the server implements the three items below.**
Nothing breaks if it never does — the in-app ring keeps working as today.

## Prerequisite: an APNs auth key

One-time, in the Apple Developer account (owner: M-S-JABER):
Users and Access → Keys → **Apple Push Notifications service (APNs)** →
create key, download the `.p8`, note the **Key ID** and the **Team ID**.
This key is NOT the App Store Connect API key the CI uses — it is a
separate key type. Store it in the server's secrets.

APNs connection details:

- Host: `https://api.push.apple.com` (production — TestFlight uses
  production APNs too). No sandbox fallback logic is needed.
- Auth: JWT signed with the `.p8` (ES256), `iss` = Team ID, `kid` = Key ID.
- **Topic** (`apns-topic` header): `com.m-s-jaber.whatsx.voip`
  (the app bundle id + `.voip` — mandatory suffix for VoIP pushes).
- Headers: `apns-push-type: voip`, `apns-priority: 10`,
  `apns-expiration: 0` (a call push has no value once the ring window ends).

## 1. Token registration endpoint

```http
POST /api/devices/voip-token
Cookie: (the operator's normal session)
Content-Type: application/json

{ "token": "<64+ hex chars>", "platform": "ios", "environment": "production" }
```

- Store per (user, token) — upsert, a device re-registers on every launch
  and after every token rotation. Multiple devices per user are normal.
- Answer `204`/`200` on success. The app sends this after each login and
  whenever PushKit rotates the token; it silently tolerates `404` (that is
  what it gets today, before this spec is implemented).
- Delete a token when APNs answers `410 Unregistered` for it (see below).

## 2. Send a VoIP push on every incoming WhatsApp call

When a `voice_call_incoming` (fresh offer, not the sdpType=="answer" reuse)
is about to be broadcast on `/ws`, ALSO send a VoIP push to every registered
iOS device of every user whose WhatsApp-number permissions include the
call's instance — the same audience filter the socket already applies.

Payload (JSON body of the push):

```json
{
  "type": "voice_call_incoming",
  "callId": "…",
  "displayName": "…",
  "phone": "…",
  "instanceId": "…",
  "sdpOffer": "v=0\r\n…"
}
```

- `callId` is required; everything else is optional but `displayName`/
  `phone` make the lock-screen UI meaningful.
- **Size cap**: APNs rejects VoIP payloads over 5 KB. Meta's audio-only
  offers usually fit; if the assembled payload would exceed ~4.5 KB, OMIT
  `sdpOffer` — the app then falls back to endpoint 3.
- Send the push and the socket event both, always: the app dedupes by
  `callId`. Do not try to detect whether the app is open.
- APNs responses: `410 Unregistered` → delete that token; other errors →
  log, don't retry more than once (the ring window is short).
- Do NOT send "call ended/claimed" VoIP pushes. Apple requires every VoIP
  push to surface a ringing call, so a cancel push is impossible. A claimed
  or expired call stops ringing on the device via the app's own 45s timeout,
  or at answer time via endpoint 3 / the answer endpoint failing.

## 3. Offer fetch for oversized payloads

```http
GET /api/voice/whatsapp/calls/{callId}/offer
Cookie: (session)

200 → { "sdpOffer": "v=0\r\n…" }
404 → call unknown, already resolved, or no longer ringing
```

The app calls this at answer time only when the push had no `sdpOffer`.
Keep the offer available while the call is ringing; after resolution a 404
is correct and makes the app end the CallKit call gracefully. Answering a
call another operator already claimed will also surface as a failure of
`POST /api/voice/whatsapp/answer` — answer it with a clear 409/410 and the
app ends the call quietly.

## Rollout order

1. Implement endpoint 1 and deploy — tokens start accumulating immediately
   (iOS 1.18.0+ registers on every login).
2. Implement endpoints 2 and 3 behind a flag; test against the pilot
   operator's device.
3. Enable for everyone. No iOS release is needed for any of this.
