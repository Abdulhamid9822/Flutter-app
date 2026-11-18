import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import 'settings_service.dart';

enum GeofenceStatus {
  notConfigured,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  outside,
  inside,
  error,
}

class LocationFailure implements Exception {
  const LocationFailure(this.status, this.message);

  final GeofenceStatus status;
  final String message;

  @override
  String toString() => message;
}

class GeofenceResult {
  const GeofenceResult({
    required this.status,
    this.distanceMeters,
    this.accuracyMeters,
    this.latitude,
    this.longitude,
    this.message = '',
  });

  final GeofenceStatus status;
  final double? distanceMeters;
  final double? accuracyMeters;
  final double? latitude;
  final double? longitude;
  final String message;

  bool get isInside => status == GeofenceStatus.inside;
  bool get isConfigured => status != GeofenceStatus.notConfigured;
  bool get hasDistance => distanceMeters != null;
}

class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  Future<LocationPermission> _ensurePermission({required bool request}) async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && request) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  /// Joriy GPS joylashuvini oladi. Ruxsat yoki xizmat bo'lmasa
  /// [LocationFailure] tashlaydi.
  Future<Position> getCurrentPosition({bool requestPermission = true}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationFailure(
        GeofenceStatus.serviceDisabled,
        "Qurilmada joylashuv xizmati o'chirilgan. GPS/lokatsiyani yoqing.",
      );
    }

    final permission = await _ensurePermission(request: requestPermission);
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationFailure(
        GeofenceStatus.permissionDenied,
        "Joylashuvdan foydalanishga ruxsat berilmagan.",
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        GeofenceStatus.permissionDeniedForever,
        "Joylashuv ruxsati butunlay rad etilgan. "
        "Ilova sozlamalaridan ruxsat bering.",
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        ),
      );
    } on TimeoutException {
      // Ba'zi telefonlarda binoda GPS sekin javob beradi. 5 daqiqadan
      // yangi oxirgi ma'lum joylashuv bo'lsa, undan foydalanamiz.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          DateTime.now().difference(last.timestamp).inMinutes <= 5) {
        return last;
      }
      throw const LocationFailure(
        GeofenceStatus.error,
        "GPS joylashuvini aniqlab bo'lmadi. Ochiq joyda qayta urinib ko'ring.",
      );
    } on LocationServiceDisabledException {
      throw const LocationFailure(
        GeofenceStatus.serviceDisabled,
        "Qurilmada joylashuv xizmati o'chirilgan. GPS/lokatsiyani yoqing.",
      );
    } on PermissionDeniedException {
      throw const LocationFailure(
        GeofenceStatus.permissionDenied,
        "Joylashuvdan foydalanishga ruxsat berilmagan.",
      );
    }
  }

  /// Muassasa koordinatasi atrofidagi radiusni tekshiradi.
  Future<GeofenceResult> checkInstitution({
    bool requestPermission = true,
  }) async {
    final settings = SettingsService.instance;
    if (!settings.hasInstitutionLocation) {
      return const GeofenceResult(
        status: GeofenceStatus.notConfigured,
        message:
            "Muassasa joylashuvi hali sozlanmagan. "
            "Administratorga murojaat qiling.",
      );
    }

    try {
      final position = await getCurrentPosition(
        requestPermission: requestPermission,
      );
      final distance = distanceMeters(
        settings.institutionLat!,
        settings.institutionLng!,
        position.latitude,
        position.longitude,
      );
      final radius = settings.institutionRadiusMeters;
      // GPS aniqligi past bo'lsa, radiusga kichik tolerans qo'shamiz.
      final accuracy = position.accuracy.isFinite ? position.accuracy : 0.0;
      final tolerance = accuracy.clamp(0.0, 30.0);
      final inside = distance <= radius + tolerance;
      return GeofenceResult(
        status: inside ? GeofenceStatus.inside : GeofenceStatus.outside,
        distanceMeters: distance,
        accuracyMeters: position.accuracy,
        latitude: position.latitude,
        longitude: position.longitude,
        message: inside
            ? "Muassasa hududidasiz."
            : "Muassasa hududidan tashqaridasiz.",
      );
    } on LocationFailure catch (error) {
      return GeofenceResult(status: error.status, message: error.message);
    } catch (error) {
      return GeofenceResult(
        status: GeofenceStatus.error,
        message: "Joylashuvni aniqlashda xatolik: $error",
      );
    }
  }

  Future<void> openSettingsFor(GeofenceStatus status) async {
    if (status == GeofenceStatus.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else if (status == GeofenceStatus.permissionDeniedForever) {
      await Geolocator.openAppSettings();
    }
  }

  /// Ikki koordinata orasidagi masofa (metr).
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _radians(double degrees) => degrees * math.pi / 180.0;
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
