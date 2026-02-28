/// SOS Type — categorises the emergency being signalled.
///
/// Encoded in bits 2-5 of the [CoreSosPacket.flags] byte (4 bits → 0-15).
/// Backward-compatible: old packets with bits 2-5 = 0 default to [general].
library;

import 'package:flutter/material.dart';

enum SosType {
  general(0, 'General SOS', Icons.warning_amber_rounded, Color(0xFFD32F2F)),
  fire(1, 'Fire Emergency', Icons.local_fire_department, Color(0xFFE65100)),
  crime(2, 'Crime Alert', Icons.gavel, Color(0xFF6A1B9A)),
  kidnap(3, 'Kidnap Alert', Icons.person_off, Color(0xFFB71C1C)),
  medical(4, 'Medical Emergency', Icons.medical_services, Color(0xFF1565C0)),
  disaster(5, 'Natural Disaster', Icons.tsunami, Color(0xFF00695C));

  const SosType(this.code, this.label, this.icon, this.color);

  /// Numeric code stored in the flags byte (bits 2-5).
  final int code;

  /// Human-readable label for UI and notifications.
  final String label;

  /// Material icon.
  final IconData icon;

  /// Signature colour for UI hints.
  final Color color;

  /// Encode this type into the flags byte (shift into bits 2-5).
  int toByte() => (code & 0x0F) << 2;

  /// Decode bits 2-5 of a flags byte into a [SosType].
  static SosType fromFlags(int flags) {
    final code = (flags >> 2) & 0x0F;
    return SosType.values.firstWhere(
      (t) => t.code == code,
      orElse: () => SosType.general,
    );
  }

  /// Map a volume-trigger event string to an SOS type.
  static SosType fromEventString(String event) {
    return switch (event) {
      'sos_general' => SosType.general,
      'sos_fire' => SosType.fire,
      'sos_crime' => SosType.crime,
      'sos_kidnap' => SosType.kidnap,
      'sos_medical' => SosType.medical,
      'sos_disaster' => SosType.disaster,
      // Legacy: existing double-volume-up maps to general.
      'double_volume_up' => SosType.general,
      _ => SosType.general,
    };
  }
}
