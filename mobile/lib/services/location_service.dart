/// Location service.
library;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'package:aftermath/core/constants.dart';

class LocationService {
  Position? _lastPosition;

  Position? get lastPosition => _lastPosition;

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
      _lastPosition = await Geolocator.getLastKnownPosition();
      return _lastPosition;
    }
  }

  static Uint8List encodeLatLon(double latitude, double longitude) {
    final bd = ByteData(8);
    bd.setInt32(0, (latitude * kGpsScale).round(), Endian.big);
    bd.setInt32(4, (longitude * kGpsScale).round(), Endian.big);
    return bd.buffer.asUint8List();
  }

  static ({double latitude, double longitude}) decodeLatLon(Uint8List buf) {
    final bd = ByteData.sublistView(buf, 0, 8);
    return (
      latitude: bd.getInt32(0, Endian.big) / kGpsScale,
      longitude: bd.getInt32(4, Endian.big) / kGpsScale,
    );
  }

  static double distanceMetres(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }
}
