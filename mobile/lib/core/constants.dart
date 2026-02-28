/// Application-wide constants for AfterMath BLE emergency network.
library;

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// BLE Protocol
// ---------------------------------------------------------------------------

/// Custom 128-bit service UUID used for SOS BLE advertisements.
/// Both scanner and advertiser filter on this UUID.
const String kSosServiceUuid = '0000BEEF-0000-1000-8000-00805F9B34FB';

/// Manufacturer ID embedded in BLE advertisement (Android only).
const int kManufacturerId = 0x1234;

/// Total BLE fragment packet size: 3-byte header + 10-byte payload.
const int kBlePacketSize = 13;

/// Header occupies the first 3 bytes of each packet.
const int kBleHeaderSize = 3;

/// Payload occupies the remaining 10 bytes (4B lat + 4B lon + 2B deviceHash).
const int kBlePayloadSize = 10;

/// Maximum time-to-live hops for mesh relay.
const int kDefaultTtl = 5;

/// Inter-chunk advertising delay.
const Duration kChunkDelay = Duration(milliseconds: 200);

/// How many times to repeat the full advertisement burst.
const int kAdvertiseBurstCount = 10;

/// Interval between full advertisement bursts.
const Duration kBurstInterval = Duration(seconds: 1);

// ---------------------------------------------------------------------------
// BLE Packet Flags (bit-field in header byte 2)
// ---------------------------------------------------------------------------

/// Bits 0-1: Message type.
class MsgType {
  static const int sos = 0x00;
  static const int ack = 0x01;
  static const int relay = 0x02;
  static const int cancel = 0x03;
}

/// Bit 2: payload is encrypted.
const int kFlagEncrypted = 0x04;

/// Bit 3: this is the last chunk.
const int kFlagLastChunk = 0x08;

// ---------------------------------------------------------------------------
// SOS Workflow
// ---------------------------------------------------------------------------

/// Seconds the user has to cancel before the SOS is committed.
const int kSosCancelCountdownSec = 5;

/// If no relay ACK within this duration, trigger SMS fallback.
const Duration kSmsFallbackTimeout = Duration(seconds: 30);

/// How long to keep a seen SOS ID before allowing rebroadcast.
const Duration kDeduplicationWindow = Duration(minutes: 5);

/// Maximum age of a packet before it is silently dropped.
const Duration kPacketMaxAge = Duration(minutes: 10);

// ---------------------------------------------------------------------------
// GPS Encoding
// ---------------------------------------------------------------------------

/// Scale factor for compressing lat/lon into signed int32 (4 bytes each).
/// int32 = value × 1e7 → ~1 cm precision.  Range ±2 147 483 647 covers
/// ±214.7° which exceeds the ±180° needed for longitude.
const double kGpsScale = 10000000.0;

// ---------------------------------------------------------------------------
// Network / Backend
// ---------------------------------------------------------------------------

/// Base URL for the AfterMath backend API.
/// Override with environment variable or remote config in production.
const String kApiBaseUrl = 'https://api.aftermath.local/v1';

/// Endpoint: ingest an SOS event.
const String kApiSosIngest = '/sos/ingest';

/// Endpoint: acknowledge an SOS event.
const String kApiSosAck = '/sos/acknowledge';

/// Endpoint: fetch currently active SOS events.
const String kApiSosActive = '/sos/active';

// ---------------------------------------------------------------------------
// Local Database
// ---------------------------------------------------------------------------

/// SQLite database filename for the store-and-forward queue.
const String kQueueDbName = 'aftermath_queue.db';

/// Table name for outgoing SOS packets.
const String kQueueTable = 'outgoing_packets';

// ---------------------------------------------------------------------------
// App Strings
// ---------------------------------------------------------------------------

const String kAppName = 'AfterMath';
const String kForegroundNotifTitle = 'AfterMath Active';
const String kForegroundNotifBody =
    'Monitoring for nearby emergency SOS alerts.';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Size of the 20-byte CORE SOS packet.
const int kCorePacketSize = 20;

/// Pre-built empty fragment packet (useful for comparisons).
final Uint8List kEmptyPacket = Uint8List(kBlePacketSize);
