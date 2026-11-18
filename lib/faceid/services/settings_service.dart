import 'package:shared_preferences/shared_preferences.dart';

import '../../api.dart';

class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const _keyThreshold = 'match_threshold';
  static const _keyDuplicate = 'duplicate_threshold';
  static const _keyCooldown = 'cooldown_minutes';
  static const _keyCameraLens = 'camera_lens';
  static const _keyInstitutionName = 'institution_name';
  static const _keyInstitutionLat = 'institution_lat';
  static const _keyInstitutionLng = 'institution_lng';
  static const _keyInstitutionRadius = 'institution_radius';

  SharedPreferences? _prefs;

  double matchThreshold = 0.58;
  double duplicateThreshold = 0.65;
  double ambiguityMargin = 0.08;
  int cooldownMinutes = 2;
  String cameraLens = 'front';
  String institutionName = 'Muassasa';
  double? institutionLat;
  double? institutionLng;
  double institutionRadiusMeters = 100;

  bool get hasInstitutionLocation =>
      institutionLat != null && institutionLng != null;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    matchThreshold = _prefs?.getDouble(_keyThreshold) ?? 0.58;
    duplicateThreshold = _prefs?.getDouble(_keyDuplicate) ?? 0.65;
    cooldownMinutes = _prefs?.getInt(_keyCooldown) ?? 2;
    cameraLens = _prefs?.getString(_keyCameraLens) ?? 'front';
    institutionName = _prefs?.getString(_keyInstitutionName) ?? 'Muassasa';
    institutionLat = _prefs?.getDouble(_keyInstitutionLat);
    institutionLng = _prefs?.getDouble(_keyInstitutionLng);
    institutionRadiusMeters = _prefs?.getDouble(_keyInstitutionRadius) ?? 100;
  }

  Future<void> setMatchThreshold(double value) async {
    matchThreshold = value.clamp(0.40, 0.80);
    await _prefs?.setDouble(_keyThreshold, matchThreshold);
  }

  Future<void> setDuplicateThreshold(double value) async {
    duplicateThreshold = value.clamp(0.40, 0.90);
    await _prefs?.setDouble(_keyDuplicate, duplicateThreshold);
  }

  Future<void> setCooldownMinutes(int value) async {
    cooldownMinutes = value.clamp(1, 30);
    await _prefs?.setInt(_keyCooldown, cooldownMinutes);
  }

  Future<void> setCameraLens(String value) async {
    cameraLens = value;
    await _prefs?.setString(_keyCameraLens, cameraLens);
  }

  Future<void> setInstitutionName(String value) async {
    institutionName = value.trim().isEmpty ? 'Muassasa' : value.trim();
    await _prefs?.setString(_keyInstitutionName, institutionName);
  }

  Future<void> setInstitutionLocation(double latitude, double longitude) async {
    institutionLat = latitude;
    institutionLng = longitude;
    await _prefs?.setDouble(_keyInstitutionLat, latitude);
    await _prefs?.setDouble(_keyInstitutionLng, longitude);
  }

  Future<void> setInstitutionRadiusMeters(double value) async {
    institutionRadiusMeters = value.clamp(20, 1000);
    await _prefs?.setDouble(_keyInstitutionRadius, institutionRadiusMeters);
  }

  Future<void> clearInstitutionLocation() async {
    institutionLat = null;
    institutionLng = null;
    await _prefs?.remove(_keyInstitutionLat);
    await _prefs?.remove(_keyInstitutionLng);
  }

  /// Admin serverda belgilagan joylashuvni lokal keshga oladi.
  ///
  /// - Serverda joylashuv bo'lsa — lokal qiymatlar yangilanadi.
  /// - Admin tozalagan bo'lsa — lokal joylashuv ham o'chiriladi.
  /// - Server hali sozlanmagan bo'lsa, admin qurilmasidagi eski lokal
  ///   qiymat serverga bir marta yuboriladi (migratsiya).
  /// - Oflayn bo'lsa lokal kesh bilan ishlash davom etadi.
  Future<void> refreshInstitutionFromServer() async {
    if (_prefs == null) await init();
    try {
      final data = await Api.instance
          .faceIdSettingsGet()
          .timeout(const Duration(seconds: 4));
      if (data['configured'] == true) {
        final loc = (data['location'] as Map?)?.cast<String, dynamic>();
        final lat = (loc?['latitude'] as num?)?.toDouble();
        final lng = (loc?['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          await setInstitutionName((loc?['name'] ?? 'Muassasa').toString());
          await setInstitutionLocation(lat, lng);
          await setInstitutionRadiusMeters(
            (loc?['radius'] as num?)?.toDouble() ?? 100,
          );
        }
      } else if (data['cleared'] == true) {
        await clearInstitutionLocation();
      }
      // Serverda yozuv bo'lmasa lokal qiymat o'zgartirilmaydi. Joylashuv
      // faqat admin "Saqlash" bosganda serverga yoziladi — qurilmalar
      // o'z-o'zidan uni boshqasiga almashtirmaydi.
    } catch (_) {
      // Oflayn: lokal kesh bilan davom etamiz.
    }
  }
}
