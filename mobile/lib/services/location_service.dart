/// Location Service — GPS coordinate acquisition and compact encoding.
library;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'package:aftermath/core/constants.dart';

class LocationService {
  Position? _lastPosition;

  /// Most recently acquired position, or `null` if unavailable.
  Position? get lastPosition => _lastPosition;

  // -------------------------------------------------------------------------
  // Acquisition
  // -------------------------------------------------------------------------

  /// Get the current GPS position with high accuracy.
  ///
  /// Falls back to last known position if the hardware request times out.
  Future<Position?> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[LocationService] Location services are disabled.');
        return _lastPosition;
      }

      _lastPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return _lastPosition;
    } catch (e) {
      debugPrint('[LocationService] Position error: $e');
      // Try last known as fallback.
      _lastPosition = await Geolocator.getLastKnownPosition();
      return _lastPosition;
    }
  }

  // -------------------------------------------------------------------------
  // Compact encoding helpers
  // -------------------------------------------------------------------------

  /// Encode latitude and longitude into a 6-byte compact format.
  ///
  /// Layout: `[lat (3B)] [lon (3B)]` — shift-and-scale encoding.
  static Uint8List encodeLatLon(double latitude, double longitude) {
    final buf = Uint8List(6);
    final latScaled = ((latitude + 90.0) * kGpsScale).round();
    final lonScaled = ((longitude + 180.0) * kGpsScale).round();

    buf[0] = (latScaled >> 16) & 0xFF;
    buf[1] = (latScaled >> 8) & 0xFF;
    buf[2] = latScaled & 0xFF;

    buf[3] = (lonScaled >> 16) & 0xFF;
    buf[4] = (lonScaled >> 8) & 0xFF;
    buf[5] = lonScaled & 0xFF;

    return buf;
  }

  /// Decode a 6-byte buffer back to (latitude, longitude).
  static ({double latitude, double longitude}) decodeLatLon(Uint8List buf) {
    final latScaled = (buf[0] << 16) | (buf[1] << 8) | buf[2];
    final lonScaled = (buf[3] << 16) | (buf[4] << 8) | buf[5];
    return (
      latitude: (latScaled / kGpsScale) - 90.0,
      longitude: (lonScaled / kGpsScale) - 180.0,
    );
  }

  /// Calculate distance in metres between two coordinates.
  static double distanceMetres(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) =>
      Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
}
