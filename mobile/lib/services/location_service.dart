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

  /// Encode latitude and longitude into an 8-byte compact format.
  ///
  /// Layout: `[lat (4B int32)] [lon (4B int32)]` — signed × 1e7 encoding.
  static Uint8List encodeLatLon(double latitude, double longitude) {
    final bd = ByteData(8);
    bd.setInt32(0, (latitude * kGpsScale).round(), Endian.big);
    bd.setInt32(4, (longitude * kGpsScale).round(), Endian.big);
    return bd.buffer.asUint8List();
  }

  /// Decode an 8-byte buffer back to (latitude, longitude).
  static ({double latitude, double longitude}) decodeLatLon(Uint8List buf) {
    final bd = ByteData.sublistView(buf, 0, 8);
    return (
      latitude: bd.getInt32(0, Endian.big) / kGpsScale,
      longitude: bd.getInt32(4, Endian.big) / kGpsScale,
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
