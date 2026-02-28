# AfterMath: Decentralised BLE Mesh Emergency Alert System

**Technical Whitepaper — February 2026**

---

## Table of Contents

1. [Abstract](#1-abstract)
2. [Problem Statement](#2-problem-statement)
3. [System Architecture Overview](#3-system-architecture-overview)
4. [BLE Mesh Protocol](#4-ble-mesh-protocol)
   - 4.1 [Addressing and Identity](#41-addressing-and-identity)
   - 4.2 [Core SOS Packet V2](#42-core-sos-packet-v2)
   - 4.3 [Legacy Fragment Packet](#43-legacy-fragment-packet)
   - 4.4 [Advertising Mechanism](#44-advertising-mechanism)
   - 4.5 [Integrity Checking](#45-integrity-checking)
5. [SOS Lifecycle](#5-sos-lifecycle)
   - 5.1 [Trigger and Countdown](#51-trigger-and-countdown)
   - 5.2 [BLE Broadcast](#52-ble-broadcast)
   - 5.3 [Mesh Relay](#53-mesh-relay)
   - 5.4 [Deduplication and TTL](#54-deduplication-and-ttl)
   - 5.5 [Backend Ingestion](#55-backend-ingestion)
   - 5.6 [Escalation and SMS Fallback](#56-escalation-and-sms-fallback)
6. [Privacy Model](#6-privacy-model)
7. [Backend Architecture](#7-backend-architecture)
   - 7.1 [HTTP API Surface](#71-http-api-surface)
   - 7.2 [Authentication](#72-authentication)
   - 7.3 [Database Schema](#73-database-schema)
   - 7.4 [Request Logging and Correlation](#74-request-logging-and-correlation)
   - 7.5 [Rate Limiting](#75-rate-limiting)
8. [User Identity and Onboarding](#8-user-identity-and-onboarding)
   - 8.1 [Signup](#81-signup)
   - 8.2 [BLE UID Generation](#82-ble-uid-generation)
   - 8.3 [Emergency Contacts and Medical Profile](#83-emergency-contacts-and-medical-profile)
   - 8.4 [KYC via Aadhaar](#84-kyc-via-aadhaar)
9. [Mobile Application Architecture](#9-mobile-application-architecture)
   - 9.1 [State Management](#91-state-management)
   - 9.2 [Foreground Service](#92-foreground-service)
   - 9.3 [Store-and-Forward Queue](#93-store-and-forward-queue)
   - 9.4 [Location Service](#94-location-service)
10. [Escalation Pipeline Detail](#10-escalation-pipeline-detail)
11. [Security Considerations](#11-security-considerations)
12. [Deployment](#12-deployment)
13. [Glossary](#13-glossary)

---

## 1. Abstract

AfterMath is a civic emergency-alert system that enables a registered user to broadcast a distress signal (SOS) over Bluetooth Low Energy (BLE), forming an ad-hoc relay mesh of nearby smartphones, and ultimately delivering the alert to a cloud backend that triggers SMS notifications to emergency contacts and a central dispatcher. The system is intentionally infrastructure-independent at the BLE layer: a victim with no internet connectivity can still reach bystanders within radio range, and those bystanders forward the event to the internet when connectivity is available. Identity is privacy-first — the BLE packet carries a static pseudonymous 6-byte UID rather than GPS coordinates, and the receiving device attaches its own location when relaying to the backend.

---

## 2. Problem Statement

Conventional emergency-call systems require the victim to have an active cellular connection and to be capable of placing a call. In dense urban environments, network congestion during a mass-casualty event can make calls impossible. In remote or underground locations, there is no signal. AfterMath addresses this by layering a BLE mesh underneath the internet path. Any registered smartphone within Bluetooth range of the victim automatically becomes a relay node, regardless of whether the victim's phone is connected. The system degrades gracefully: if the backend cannot be reached in real time, events are queued locally and uploaded retroactively, and a direct device-to-contact SMS is sent as a final fallback.

---

## 3. System Architecture Overview

```
+------------------+      BLE Advert.      +---------------------+
|  Victim Device   | ----(Core V2 Packet)-> |  Bystander Device 1 |
|  (Flutter App)   |                        |  (Flutter App)      |
|                  | <-(optional relay)---  |                     |
+------------------+                        +----------+----------+
                                                       |
                                                HTTPS POST /v1/sos/ingest
                                                       |
                                           +-----------v-----------+
                                           |   AfterMath Backend   |
                                           |   (Node.js / Express) |
                                           |                       |
                                           |  +------------------+ |
                                           |  |  PostgreSQL DB   | |
                                           |  +------------------+ |
                                           |                       |
                                           |  +------------------+ |
                                           |  |  Twilio SMS API  | |
                                           |  +------------------+ |
                                           +-----------------------+
```

There are three distinct layers:

**BLE Layer:** A 10-byte Core SOS V2 packet is broadcast as a non-connectable BLE advertisement. Any AfterMath app in the vicinity scans for this service UUID, parses the packet, attaches receiver location, and enqueues it for upload.

**Transport Layer:** The Flutter app POSTs the enriched event JSON to the REST backend over HTTPS. If the POST fails, the event is stored in a local SQLite queue and retried every 30 seconds.

**Backend Layer:** The Node.js server validates, persists, and manages the SOS lifecycle. It runs a 30-second escalation timer per event; if no acknowledgement arrives, it fires an SMS via Twilio to the registered dispatcher and to the victim's emergency contacts.

---

## 4. BLE Mesh Protocol

### 4.1 Addressing and Identity

Every registered user is assigned a static **BLE UID**: a 6-byte (48-bit) pseudonymous identifier derived server-side as the first 6 bytes of `SHA-256(userId || SERVER_SECRET)`. This UID is returned to the device at signup and stored securely. It is the only identifier broadcast over BLE. It contains no name, phone number, or GPS data. The backend resolves which user triggered the SOS by looking up the raw bytes in the `users.ble_uid` column.

The hex-encoded form (`aabbccddee01`) is used in JSON and logs. The binary form (a `BYTEA` column) is indexed for sub-millisecond lookups.

BLE UID deduplication key format used as the SOS event ID: `uid:<bleUidHex>:<sequenceNumber>`.

### 4.2 Core SOS Packet V2

The primary packet used for all SOS broadcasts. Size: **10 bytes**.

```
 Byte  Field         Size    Description
 ----  ----------    -----   ------------------------------------------
  0    version       1 B     Protocol version = 2
  1    flags         1 B     Bit-field (see below)
  2-7  bleUid        6 B     Static pseudonymous BLE UID
  8    sequence      1 B     Wrapping 8-bit counter (0-255)
  9    crc8          1 B     CRC-8 (poly 0x07, init 0x00) over bytes 0-8
```

**Flags bit-field:**

| Bit | Name              | Meaning                          |
|-----|-------------------|----------------------------------|
| 0   | SOS_ACTIVE        | Set when SOS is active           |
| 1   | MEDICAL_EMERGENCY | Set for medical emergency type   |
| 2-7 | (reserved)        |                                  |

The sequence number allows receivers to distinguish repeated bursts from new activations by the same UID. Together with the UID, it forms the globally unique deduplication key.

### 4.3 Legacy Fragment Packet

An older 13-byte fragmented packet format is also supported for backwards compatibility. It carries a 10-byte payload split into fragments if the full SOS message exceeds a single BLE advertisement.

```
 Byte  Field         Size    Description
 ----  ----------    -----   ------------------------------------------
  0    sequence      1 B     Fragment index (0-based)
  1    totalChunks   1 B     Total fragments for this message
  2    flags         1 B     Bit-field (see below)
  3-12 payload       10 B    Fragment payload
```

**Flags bit-field (fragment packet):**

| Bits | Name        | Meaning                                     |
|------|-------------|---------------------------------------------|
| 0-1  | msgType     | 0x00=SOS, 0x01=ACK, 0x02=RELAY, 0x03=CANCEL |
| 2    | encrypted   | Payload is AES-encrypted                    |
| 3    | lastChunk   | This is the final fragment                  |
| 4-7  | TTL         | Time-to-live hop count (max 15)             |

The `PacketReassembler` service in the mobile app collects fragments and assembles the full payload before acting on them.

### 4.4 Advertising Mechanism

The victim's device advertises using the following parameters:

- **Service UUID:** `0000BEEF-0000-1000-8000-00805F9B34FB` (custom 128-bit UUID, both scanner and advertiser filter on it)
- **Manufacturer ID:** `0x1234` (embedded in manufacturer-specific data on Android)
- **Mode:** Non-connectable advertisement (no GATT connection required)
- **TX Power:** High
- **Burst count:** 10 repetitions
- **Burst interval:** 1 second between bursts
- **Inter-chunk delay:** 200 ms

Each burst stops any active advertising slot before starting, because Android BLE controllers typically allow only 4-5 concurrent advertising sets. This prevents slot exhaustion and ensures clean teardown between bursts.

Scanners filter on the service UUID and manufacturer ID. On receiving a match, they extract manufacturer data and attempt to decode it first as a Core V2 packet, then fall back to the legacy fragment format.

### 4.5 Integrity Checking

**CRC-8** (polynomial `0x07`, initial value `0x00`) is computed over bytes 0-8 of the Core V2 packet and stored as byte 9. Any received packet with a mismatched CRC is silently discarded rather than triggering an error UI.

**CRC-16-CCITT** (polynomial `0x1021`, initial value `0xFFFF`) is used by the legacy fragmented packet format, appended as the final 2 bytes of the assembled payload, big-endian.

---

## 5. SOS Lifecycle

### 5.1 Trigger and Countdown

A user activates SOS through the SOS screen. A 5-second countdown (`kSosCancelCountdownSec = 5`) begins, during which the user can cancel. This prevents accidental activations. If not cancelled, `_commitSos()` is called. The state machine (`SosPhase`) transitions as follows:

```
idle -> countdown -> broadcasting -> awaitingAck -> sent
                              \                  \-> smsFallback -> sent
                               \-> error
      -> cancelled (if user taps Cancel during countdown)
```

### 5.2 BLE Broadcast

On commit, the notifier:
1. Reads the stored BLE UID from secure storage.
2. Increments a wrapping 8-bit sequence counter.
3. Constructs a `CoreSosPacket` with `flags = 0x01` (SOS_ACTIVE).
4. Calls `BleAdvertiserService.broadcastCoreSos()`, which performs 10 burst cycles, each holding the advertisement for 1 second then stopping.
5. In parallel, acquires the device's current GPS position via the `LocationService` and attaches it as `receiverLocation` on the `SosEvent` object.

The GPS coordinates are **not** embedded in the BLE packet. They are attached by the receiving device — which may be the victim's own phone, or any bystander's phone — before the event is uploaded to the backend.

### 5.3 Mesh Relay

Any AfterMath app running in the background with BLE scanning active will receive the advertisement. The `MeshRelayService.onSosReceived()` method runs:

1. Checks the in-memory `_relayedIds` set. If the event ID is already present (seen within `kDeduplicationWindow = 5 minutes`), it is ignored.
2. Checks `event.isExpired` (age > `kPacketMaxAge = 10 minutes`). If expired, it is dropped.
3. Adds the event ID to `_relayedIds` and schedules its removal after the deduplication window.
4. Records the RSSI of the received signal onto the event.
5. Attempts to get GPS position and attaches `receiverLocation`.
6. Enqueues the event in the local SQLite store.
7. Fires `_uploadToBackend()` immediately (async, fire-and-forget relative to the relay decision).
8. After a random jitter of 100-500 ms (to prevent relay storms), calls `_rebroadcast()`, which increments `relayHops`, reconstructs a `CoreSosPacket` from the original `bleUid` and `sequence`, and broadcasts it again over BLE.

The relay bystanders themselves thus re-emit the SOS signal, extending range beyond the victim's direct BLE coverage.

### 5.4 Deduplication and TTL

**In-memory deduplication:** Each device maintains a `Set<String>` of recently relayed event IDs. An event ID is `uid:<bleUidHex>:<sequence>`. If a second device relays the same packet back into range, the first device ignores it. The set entry expires after 5 minutes.

**TTL in fragment packets:** The legacy fragment packet carries a 4-bit TTL (max 15 hops) in the flags byte. Each relay calls `withDecrementedTtl()`, which returns a copy with `TTL -= 1`. Packets with `TTL = 0` throw a `StateError` and are not re-broadcast. The Core V2 packet does not embed TTL; the relay mesh relies solely on the deduplication window to bound propagation.

**Max age filter:** Packets older than 10 minutes are dropped at the relay and not uploaded.

### 5.5 Backend Ingestion

The relay bystander (or the victim's own phone) POSTs the event JSON to `POST /v1/sos/ingest`. The body is validated by `sosIngestSchema` (Zod):

```json
{
  "id": "uid:aabbccddee01:42",
  "bleUid": "aabbccddee01",
  "flags": 1,
  "sequence": 42,
  "timestamp": "2026-02-28T10:00:00.000Z",
  "status": "active",
  "relayHops": 0,
  "receiverLocation": { "lat": 19.076, "lon": 72.8777, "accuracy": 12.5 },
  "rssi": -68,
  "message": "Help!"
}
```

The backend performs a **UID resolution** step: it converts the hex `bleUid` to a 6-byte buffer and queries `SELECT * FROM users WHERE ble_uid = $1`. If a match is found, `userId` is attached to the stored event. This links anonymous BLE activity to a registered identity for escalation enrichment.

The `SosRepository.upsert()` uses `INSERT ... ON CONFLICT (id) DO UPDATE` semantics: if the same event arrives multiple times (from multiple relays), `relay_hops` is updated to the maximum observed value and `status` is updated to the latest value. The original data is not overwritten.

### 5.6 Escalation and SMS Fallback

After a successful upsert, if the event status is `active` or `relayed`, `startEscalationTimer()` is called. This arms a 30-second in-process timer (`setTimeout`). The timer is cancelled if `POST /v1/sos/acknowledge` is received before it fires.

If the timer fires, the backend:
1. Re-fetches the event from the database to confirm it is still unacknowledged.
2. Calls `sendEscalationSms()` via Twilio, which sends a formatted SMS to the central `TWILIO_ESCALATION_NUMBER` including the SOS ID, timestamp, GPS coordinates, and a Google Maps link.
3. If the event has a resolved `userId`, `getFullUserProfile()` fetches the user's name, emergency contacts, and medical profile, and `sendContactSms()` is called for each registered contact (in parallel with the dispatcher SMS).

On the mobile side, if the initial backend POST fails (network unreachable), the `SosNotifier` immediately enqueues the event locally and calls `SmsFallbackService.sendSos()`, which sends an SMS directly from the device to each registered emergency contact using an Android platform channel (`SmsManager`) or prompts on iOS.

---

## 6. Privacy Model

The BLE packet never contains GPS coordinates, a phone number, a real name, or a Firebase/account UID. The only identifier on-air is the static 6-byte BLE UID.

The UID is pseudonymous: without access to the backend's `SERVER_SECRET` and the `users` table, a passive BLE observer cannot determine who is broadcasting. The mapping between a UID and a real identity lives exclusively in the PostgreSQL database behind the authenticated backend.

GPS coordinates are attached by the **receiver** device, not the victim. This means the location logged is an approximation (the relay node's position), not the victim's precise location, which has both a privacy benefit and a practical limitation.

Aadhaar-based KYC uses a zero-knowledge proof path (`@anon-aadhaar/core`) that derives a `nullifier_hash` — a one-way commitment that proves the user passed identity verification without revealing the Aadhaar number itself. The nullifier is stored in `users.aadhaar_nullifier` to prevent the same Aadhaar from being used to register multiple accounts.

A lightweight Aadhaar QR XML path is available as an alternative when the ZK proof pipeline is not available on the device. This parses demographics directly from the signed XML but also does not store the raw Aadhaar number — only derived fields (age above 18, gender, state).

---

## 7. Backend Architecture

The backend is a TypeScript Node.js application built with Express. It runs inside Docker alongside a PostgreSQL 16 database.

### 7.1 HTTP API Surface

All routes are prefixed with `/v1`.

```
GET    /v1/health                          — Liveness + DB health check
POST   /v1/auth/token                      — Issue a JWT (testing/admin)
POST   /v1/onboarding/signup               — Register new user
POST   /v1/onboarding/verify-aadhaar       — Submit ZK proof for KYC
POST   /v1/onboarding/verify-aadhaar-qr    — Submit Aadhaar QR XML for KYC
GET    /v1/onboarding/me                   — Current user profile (JWT required)
GET    /v1/onboarding/status/:userId       — Onboarding/KYC status
POST   /v1/sos/ingest                      — Receive SOS event from mobile
POST   /v1/sos/acknowledge                 — Acknowledge active SOS
GET    /v1/sos/active                      — List active/relayed events
POST   /v1/users                           — Create user (legacy path)
GET    /v1/users/:id                       — Fetch user profile
POST   /v1/users/:id/contacts              — Add emergency contacts
POST   /v1/users/:id/medical               — Set medical profile
```

`POST /v1/sos/ingest` and `GET /v1/sos/active` use `optionalAuth` — they function without a token but attach user context if one is provided.

All user-management routes under `/v1/users` use `requireAuth`.

### 7.2 Authentication

JWT Bearer tokens are issued by `POST /v1/auth/token` (admin/test) or by `POST /v1/onboarding/signup` (production). Tokens contain `{ sub: userId, role }` and are signed with `JWT_SECRET` (minimum 32 characters). Expiry defaults to `1h`.

Roles: `civilian`, `responder`, `admin`.

The middleware stack has two modes:
- `requireAuth`: Rejects with `401` if no valid token is present.
- `optionalAuth`: Attaches `req.user` if a token is present but continues unauthenticated if not. Used for SOS routes so that bystanders without accounts can relay events.

### 7.3 Database Schema

**`sos_events`**

| Column          | Type            | Notes                                              |
|-----------------|-----------------|----------------------------------------------------|
| `id`            | TEXT PK         | `uid:<bleUidHex>:<sequence>`                       |
| `ble_uid`       | TEXT            | Hex-encoded 6-byte UID                             |
| `flags`         | INTEGER         | BLE flags byte                                     |
| `sequence`      | INTEGER         | BLE sequence number                                |
| `timestamp`     | TIMESTAMPTZ     | Device-reported event time                         |
| `status`        | TEXT            | `active|relayed|acknowledged|resolved|cancelled`  |
| `relay_hops`    | INTEGER         | Highest hop count seen (GREATEST on upsert conflict)|
| `message`       | TEXT            | Optional free-text message (max 64 chars)          |
| `receiver_lat`  | DOUBLE PRECISION| Relay node latitude                                |
| `receiver_lon`  | DOUBLE PRECISION| Relay node longitude                               |
| `rssi`          | INTEGER         | BLE signal strength (dBm)                          |
| `user_id`       | UUID            | Resolved user (nullable if UID unregistered)       |
| `created_at`    | TIMESTAMPTZ     |                                                    |
| `updated_at`    | TIMESTAMPTZ     | Auto-updated by trigger on each change             |

Indexes: `status`, `created_at`, `ble_uid`, `user_id`.

**`users`**

| Column                | Type        | Notes                                           |
|-----------------------|-------------|-------------------------------------------------|
| `id`                  | UUID PK     |                                                 |
| `name`                | TEXT        | Nullable display name                           |
| `phone`               | TEXT UNIQUE | Required, used for lookup and contact SMS       |
| `ble_uid`             | BYTEA UNIQUE| 6-byte binary BLE UID                           |
| `language`            | TEXT        | Preferred language code                         |
| `role`                | TEXT        | `civilian|responder|admin`                      |
| `kyc_status`          | TEXT        | `pending|verified|rejected|expired`             |
| `aadhaar_nullifier`   | TEXT UNIQUE | ZK nullifier hash (anti-duplicate)              |
| `aadhaar_verified_at` | TIMESTAMPTZ |                                                 |
| `aadhaar_age_above_18`| BOOLEAN     | Demographics from KYC                           |
| `aadhaar_gender`      | TEXT        |                                                 |
| `aadhaar_state`       | TEXT        |                                                 |
| `created_at`          | TIMESTAMPTZ |                                                 |
| `updated_at`          | TIMESTAMPTZ | Auto-updated by trigger                         |

Indexes: `phone`, `ble_uid`, `aadhaar_nullifier`, `kyc_status`.

**`emergency_contacts`**

| Column     | Type    | Notes                                   |
|------------|---------|-----------------------------------------|
| `id`       | UUID PK |                                         |
| `user_id`  | UUID FK | References `users(id)` CASCADE DELETE   |
| `name`     | TEXT    |                                         |
| `phone`    | TEXT    | Destination for distress SMS            |
| `priority` | INTEGER | Lower = higher priority                 |

Index: `user_id`.

**`medical_profiles`**

| Column       | Type    | Notes                                   |
|--------------|---------|-----------------------------------------|
| `user_id`    | UUID PK | References `users(id)` CASCADE DELETE   |
| `blood_group`| TEXT    |                                         |
| `allergies`  | TEXT    | Free-text, max 1000 chars               |
| `conditions` | TEXT    | Free-text, max 1000 chars               |

Medical profile data is included in the escalation SMS body sent to the dispatcher to assist first responders dispatched to the scene.

### 7.4 Request Logging and Correlation

Every incoming request is assigned a 4-byte hex request ID (`reqId`) generated with `crypto.randomBytes(4)`. All log lines for that request — including the DB call timing and the final response status — carry this ID. Sensitive fields (`password`, `token`, `secret`, `authorization`, `rawXml`) are recursively redacted from logged request bodies before writing.

### 7.5 Rate Limiting

A global rate limiter (`express-rate-limit`) applies to all routes. Defaults: 100 requests per 60 seconds per IP. Both values are configurable via `RATE_LIMIT_MAX` and `RATE_LIMIT_WINDOW_MS` environment variables.

---

## 8. User Identity and Onboarding

### 8.1 Signup

`POST /v1/onboarding/signup` accepts:

```json
{
  "name": "Priya Sharma",
  "phone": "+919876543210",
  "language": "hi",
  "emergencyContacts": [
    { "name": "Ravi Sharma", "phone": "+919876543211", "priority": 1 }
  ],
  "medicalProfile": {
    "bloodGroup": "O+",
    "allergies": "Penicillin",
    "conditions": "Asthma"
  }
}
```

On success, the response includes:
- `user` object with `id`, `name`, `phone`, `bleUid` (hex), `role`, `kycStatus`
- `token` — a JWT valid for the returned `userId`
- `signalHash` — a hex value the mobile app uses as the `signal` input when generating an Anon Aadhaar ZK proof, derived as `SHA-256(userId)` truncated to match the SNARK field modulus

### 8.2 BLE UID Generation

```
bleUid = SHA-256(userId || SERVER_SECRET)[0:6]
```

The server secret is a 16+ character string configured as `SERVER_SECRET`. The first 6 bytes of the SHA-256 digest become the BLE UID. This is deterministic: the same userId and secret always produce the same UID. The UID is stored as raw bytes (`BYTEA`) in the database.

A uniqueness collision (probability 1 in 2^48 per user, approximately 1 in 281 trillion) is handled by catching the `UNIQUE` constraint violation (`pg error code 23505`) and returning `409 BLE UID collision — please retry`.

### 8.3 Emergency Contacts and Medical Profile

Emergency contacts can be submitted as part of signup or added separately via `POST /v1/users/:id/contacts`. Up to 10 contacts per request, each with `name`, `phone`, and `priority`. They are stored in `emergency_contacts` and used during escalation.

Medical profile is upserted via `POST /v1/users/:id/medical` with `bloodGroup`, `allergies`, and `conditions`. This data is included verbatim in the escalation SMS body to assist responding medical personnel.

### 8.4 KYC via Aadhaar

**ZK Proof path (`POST /v1/onboarding/verify-aadhaar`):**
The mobile app uses the `@anon-aadhaar/core` SDK to generate a zero-knowledge proof from the scanned Aadhaar QR code. The proof attests to:
- The Aadhaar was issued by UIDAI (verified against the UIDAI RSA-2048 public key).
- The holder's age is above 18.
- The signal field equals `SHA-256(userId)` — binding the proof to this specific account.

The `nullifier_hash` is a deterministic one-way value that identifies the Aadhaar without revealing it. If the nullifier is already in the database for a different user, registration is rejected (`409`).

**QR XML path (`POST /v1/onboarding/verify-aadhaar-qr`):**
The raw Aadhaar QR XML is submitted. The server parses `PrintLetterBarcodeData` attributes (`name`, `gender`, `dob`, `yob`, `state`) and computes `ageAbove18` using the date-of-birth field. This path does not generate a nullifier and cannot prevent multiple account registrations from the same Aadhaar. It is intended for the MVP onboarding flow before full ZK integration is complete.

---

## 9. Mobile Application Architecture

The mobile app is built with Flutter and uses **Riverpod** for state management. It targets Android (primary) and iOS (partial, limited by platform SMS constraints).

### 9.1 State Management

Key providers:

- `sosNotifierProvider` (`StateNotifier<SosState>`) — manages the SOS trigger state machine.
- `bleAdvertiserProvider` — singleton `BleAdvertiserService` for outbound advertising.
- `bleScannerProvider` — singleton `BleScannerService` for inbound scanning.
- `meshRelayServiceProvider` — connects scanner output to relay logic.
- `backendServiceProvider` — REST client (`BackendService`).
- `queueServiceProvider` — SQLite queue (`QueueService`).
- `locationServiceProvider` — GPS wrapper (`LocationService`).
- `smsFallbackProvider` — `SmsFallbackService`.
- `bleUidProvider` — `FutureProvider<Uint8List>` that reads the stored BLE UID from secure storage.

### 9.2 Foreground Service

An Android foreground service (`flutter_foreground_task`) is started at app launch and set to `autoRunOnBoot = true`. It holds a `WAKE_LOCK` and `WIFI_LOCK` to prevent the BLE scanner from being killed by Doze mode or battery optimisation. The notification reads "Safety network active" with a low importance to avoid disturbing the user.

The foreground task fires a `repeat(5000)` event every 5 seconds, which can be used to confirm the scanner is still running and restart it if needed.

### 9.3 Store-and-Forward Queue

`QueueService` maintains a SQLite database (`aftermath_queue.db`) with a single `outgoing_packets` table:

```
id         TEXT PRIMARY KEY
payload    TEXT NOT NULL       (JSON-serialised SosEvent)
uploaded   INTEGER DEFAULT 0   (0 = pending, 1 = uploaded)
created_at TEXT NOT NULL
```

Events are enqueued before any upload attempt. Once successfully ingested by the backend, `markUploaded(id)` sets `uploaded = 1`. A periodic timer every 30 seconds calls `flushQueue()` on `MeshRelayService`, which reads all pending events and retries upload. A separate purge timer every 2 minutes deletes rows older than `kPacketMaxAge = 10 minutes`.

### 9.4 Location Service

`LocationService.getCurrentPosition()` is called both when the victim triggers SOS and when a bystander relays a received packet. The GPS position is attached as `receiverLocation: { lat, lon, accuracy }` on the `SosEvent` before it is enqueued and uploaded. If GPS is unavailable (denied or timed out), the event is uploaded without a location rather than being dropped.

---

## 10. Escalation Pipeline Detail

The full enriched escalation flow when a victim is registered:

```
1. Bystander POSTs SOS to backend
2. Backend resolves bleUid -> userId
3. Backend upserts event with userId
4. Backend calls startEscalationTimer(sosId, lat, lon, ...)
   - Sets setTimeout(30s)
5. If acknowledged within 30s:
   a. POST /v1/sos/acknowledge received
   b. cancelEscalationTimer(sosId)
   c. No SMS sent
6. If NOT acknowledged after 30s:
   a. Timer fires; re-checks event status in DB
   b. If still active or relayed:
      i.  sendEscalationSms() -> Twilio -> TWILIO_ESCALATION_NUMBER
          Body includes: SOS ID, timestamp, lat/lon, Google Maps URL,
          optional message, unacknowledged warning
      ii. getFullUserProfile(pool, userId)
          Returns: user.name, user.phone, contacts[], medical{}
      iii. For each emergency contact (in priority order):
           sendContactSms() -> Twilio -> contact.phone
           Body includes: victim name, approx location, Maps URL,
           timestamp, optional message, blood group, allergies, conditions
```

The dispatcher SMS and all contact SMSes are triggered independently. All Twilio calls are made with API Key authentication (`TWILIO_API_KEY_SID` + `TWILIO_API_KEY_SECRET`) rather than the Account SID + Auth Token pair, following Twilio's production security guidance.

If the victim's phone has no internet access, the mobile `SmsFallbackService` sends a direct SMS from the device using `SmsManager` (Android) to each registered emergency contact, bypassing the backend entirely.

---

## 11. Security Considerations

**BLE Advertising:** The BLE UID is pseudonymous but static. A persistent adversary scanning BLE advertisements over time could track a registered user by their UID without knowing their identity. Rotation of BLE UIDs is not currently implemented but is a planned extension.

**Replay attacks:** The `(bleUid, sequence)` composite key provides weak replay protection; a sequence number wraps at 255. The `kDeduplicationWindow` of 5 minutes limits the window in which a captured packet can be re-broadcast by an attacker.

**Encryption flag:** The fragment packet format includes an `encrypted` flag (bit 2 of flags). AES encryption of the payload using `BLE_ENCRYPTION_SECRET` (32-byte key configured server-side) is implemented in the protocol definition but the current relay path does not enforce encryption for Core V2 packets in the MVP.

**JWT security:** Tokens are HS256-signed with a minimum 32-character secret and expire in 1 hour. The `POST /v1/auth/token` endpoint issues tokens without further authentication and is intended for administrative and testing use only; it should be removed or gated in production.

**Aadhaar data:** Raw Aadhaar numbers are never stored. The ZK path stores only a nullifier hash. The XML QR path stores only derived boolean/string demographics. Raw XML submitted in requests is redacted from logs by the `REDACT_KEYS` middleware.

**Rate limiting:** 100 requests per minute per IP provides basic protection against enumeration and flood attacks. SOS ingest routes are included in the global limiter; in a production deployment, a separate, higher limit should be applied specifically to `/v1/sos/ingest` to avoid legitimate high-frequency relays being throttled during a mass-casualty event.

---

## 12. Deployment

The system is containerised with Docker. `docker-compose.yml` defines two services:

**postgres:** `postgres:16-alpine` with a health check (`pg_isready`). Data persisted in a named volume `pgdata`.

**backend:** Built from `./backend/DockerFile`. On startup, runs `npm run migrate` (idempotent DDL) then `npm run dev` (or the production equivalent). Depends on `postgres` health. Communicates over the internal bridge network `aftermath-net`.

Environment is configured via `./backend/.env`. Required variables:

```
DATABASE_URL             postgresql://...
BLE_ENCRYPTION_SECRET    32-byte hex key
SERVER_SECRET            arbitrary string, min 16 chars
TWILIO_ACCOUNT_SID       AC...
TWILIO_AUTH_TOKEN        ...
TWILIO_API_KEY_SID       SK...
TWILIO_API_KEY_SECRET    ...
TWILIO_FROM_NUMBER       +1...
TWILIO_ESCALATION_NUMBER +1...
JWT_SECRET               min 32 chars
USE_TEST_AADHAAR         true|false
```

The mobile app's `kApiBaseUrl` (`https://api.aftermath.local/v1`) must be updated to point to the deployed backend host.

---

## 13. Glossary

| Term              | Definition                                                                 |
|-------------------|----------------------------------------------------------------------------|
| BLE UID           | 6-byte pseudonymous identifier advertised over Bluetooth                   |
| Core V2 Packet    | The 10-byte primary BLE SOS packet format                                  |
| Fragment Packet   | The 13-byte legacy BLE packet supporting multi-fragment SOS messages       |
| SOS               | Save-Our-Souls; a distress signal triggered by the victim                  |
| Relay             | A bystander device that received and re-broadcast an SOS                   |
| relay_hops        | Number of BLE relay hops a packet has traversed                            |
| Escalation        | The process of sending SMS alerts when an SOS is not acknowledged in time  |
| KYC               | Know Your Customer; identity verification via Aadhaar                      |
| ZK Proof          | Zero-Knowledge Proof; attests to Aadhaar validity without revealing data   |
| Nullifier         | One-way commitment derived from Aadhaar, prevents duplicate registrations  |
| Store-and-forward | Queue events locally and upload when connectivity is restored              |
| TTL               | Time-to-Live; hop counter that limits relay propagation in fragment mode   |
| CRC-8             | 8-bit cyclic redundancy check used for Core V2 packet integrity            |
| CRC-16-CCITT      | 16-bit cyclic redundancy check used for legacy fragment packet integrity   |
| reqId             | Per-request 4-byte hex correlation ID used in server logs                  |
