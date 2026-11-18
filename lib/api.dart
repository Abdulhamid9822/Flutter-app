import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'push.dart';

class ApiException implements Exception {
  final String message;
  final bool unauthorized;

  /// Serverga umuman ulanib bo'lmagan holat (internet yo'q, timeout va h.k.).
  final bool network;
  final int? statusCode;

  ApiException(
    this.message, {
    this.unauthorized = false,
    this.network = false,
    this.statusCode,
  });

  @override
  String toString() => message;
}

class UserInfo {
  final String name;
  final String role;
  final int? employeeId;
  final String lang;
  final String account;
  UserInfo(this.name, this.role, this.employeeId,
      [this.lang = 'uz', this.account = '']);

  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
      j['name'] ?? '',
      j['role'] ?? 'employee',
      j['employee_id'] as int?,
      j['lang'] ?? 'uz',
      (j['account'] ?? '').toString());

  bool get isEmployee => role == 'employee';
  String get roleLabel => tr(
      {'employee': 'Xodim', 'branch': 'Filial admini', 'super': 'Super admin'}[role] ?? role);
}

class Api {
  static final Api instance = Api._();
  Api._();

  String baseUrl = '';
  String? token;
  UserInfo? user;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? '';
    token = p.getString('token');
    final u = p.getString('user');
    if (u != null) user = UserInfo.fromJson(jsonDecode(u));
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', baseUrl);
    if (token == null) {
      await p.remove('token');
      await p.remove('user');
    } else {
      await p.setString('token', token!);
      await p.setString(
          'user',
          jsonEncode({
            'name': user!.name,
            'role': user!.role,
            'employee_id': user!.employeeId,
            'lang': user!.lang,
            'account': user!.account
          }));
    }
  }

  Uri _uri(String action, [Map<String, String>? q]) {
    var base = baseUrl.trim();
    if (!base.startsWith('http')) base = 'https://$base';
    base = base.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/api/mobile.php').replace(queryParameters: {'action': action, ...?q});
  }

  Future<Map<String, dynamic>> _request(String action,
      {Map<String, String>? query, Map<String, dynamic>? body}) async {
    try {
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final uri = _uri(action, query);
      final res = body == null
          ? await http.get(uri, headers: headers).timeout(const Duration(seconds: 20))
          : await http
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        throw ApiException(tr(data['error']?.toString() ?? 'Xatolik'),
            unauthorized: res.statusCode == 401 && action != 'login',
            statusCode: res.statusCode);
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        tr('Serverga ulanib bo\'lmadi. Internet va server manzilini tekshiring.'),
        network: true,
      );
    }
  }

  /// Poster sozlamasidagi tilni serverdan olib, ilovaga qo'llaydi.
  Future<void> refreshLang() async {
    if (token == null) return;
    try {
      final d = await _request('me');
      final u = UserInfo.fromJson(d['user']);
      user = u;
      await AppLang.set(u.lang);
      await _save();
    } catch (_) {}
  }

  Future<void> login(String server, String phone, String pin) async {
    baseUrl = server;
    final d = await _request('login', body: {'phone': phone, 'pin': pin});
    token = d['token'];
    user = UserInfo.fromJson(d['user']);
    await AppLang.set(user!.lang);
    await _save();
    PushService.register();
  }

  Future<Map<String, dynamic>> pushTest() async =>
      (await _request('push_test'))['diag'] as Map<String, dynamic>;

  Future<void> registerDevice(String fcmToken) =>
      _request('register_device', body: {'fcm_token': fcmToken});

  Future<void> unregisterDevice(String fcmToken) =>
      _request('unregister_device', body: {'fcm_token': fcmToken});

  Future<void> logout() async {
    await PushService.unregister();
    try {
      await _request('logout', body: {});
    } catch (_) {}
    token = null;
    user = null;
    await _save();
  }

  Future<Map<String, dynamic>> salary(String month, {int? employeeId}) =>
      _request('salary', query: {'month': month, if (employeeId != null) 'employee_id': '$employeeId'});

  Future<Map<String, dynamic>> attendance(String month,
          {int? employeeId, String? from, String? to}) =>
      _request('attendance', query: {
        'month': month,
        'from': ?from,
        'to': ?to,
        if (employeeId != null) 'employee_id': '$employeeId',
      });

  /// FaceID skan natijasini MySQL attendance_data jadvaliga yozadi.
  /// Xodim faqat o'z nomidan yozadi. Admin/branch esa o'z accountidagi
  /// xodim nomidan ham yozishi mumkin (`employeeId` orqali).
  Future<Map<String, dynamic>> faceIdAttendance({
    required String direction,
    required DateTime timestamp,
    double? confidence,
    int? employeeId,
  }) =>
      _request('faceid_attendance', body: {
        'direction': direction,
        'timestamp': timestamp.toIso8601String(),
        'confidence': ?confidence,
        'employee_id': ?employeeId,
      });

  /// Admin belgilagan muassasa joylashuvini oladi. Bu sozlama accountdagi
  /// barcha qurilmalar uchun umumiy.
  Future<Map<String, dynamic>> faceIdSettingsGet() =>
      _request('faceid_settings_get');

  Future<Map<String, dynamic>> faceIdSettingsSet({
    required String name,
    required double latitude,
    required double longitude,
    required double radius,
  }) =>
      _request('faceid_settings_set', body: {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
      });

  Future<void> faceIdSettingsClear() =>
      _request('faceid_settings_clear', body: {});

  /// Admin xodimga bir martalik yuz rasmi olish ruxsatini beradi.
  Future<Map<String, dynamic>> faceIdEnrollmentGrant({int? employeeId}) =>
      _request('faceid_enrollment_grant', body: {
        if (employeeId != null) 'employee_id': employeeId,
      });

  /// Xodim admin bergan 6 xonali kodni tekshiradi (bir marta ishlaydi).
  Future<Map<String, dynamic>> faceIdEnrollmentValidate(String code) =>
      _request('faceid_enrollment_validate', body: {'code': code});

  /// Xodim yuz rasmini yangilash uchun admin ruxsatini so'raydi.
  Future<Map<String, dynamic>> faceIdEnrollmentRequestCreate() =>
      _request('faceid_enrollment_request_create', body: {});

  /// Admin uchun kutilayotgan rasm olish so'rovlari.
  Future<Map<String, dynamic>> faceIdEnrollmentRequests() =>
      _request('faceid_enrollment_requests');

  /// Admin so'rovni tasdiqlaydi yoki rad etadi.
  Future<Map<String, dynamic>> faceIdEnrollmentRequestDecide(
    int requestId,
    String decision,
  ) =>
      _request('faceid_enrollment_request_decide', body: {
        'request_id': requestId,
        'decision': decision,
      });

  Future<Map<String, dynamic>> dashboard(String from, String to, {int? spotId}) =>
      _request('dashboard', query: {
        'from': from,
        'to': to,
        if (spotId != null && spotId > 0) 'spot_id': '$spotId',
      });

  Future<Map<String, dynamic>> daily(String date, {int? spotId}) => _request('daily', query: {
        'date': date,
        if (spotId != null && spotId > 0) 'spot_id': '$spotId',
      });

  Future<Map<String, dynamic>> employees(String month, {String q = '', int? spotId}) =>
      _request('employees', query: {
        'month': month,
        if (q.isNotEmpty) 'q': q,
        if (spotId != null && spotId > 0) 'spot_id': '$spotId',
      });

  Future<Map<String, dynamic>> branches() => _request('branches');

  Future<Map<String, dynamic>> excuses({String? status}) =>
      _request('excuses', query: {'status': ?status});

  Future<void> createExcuse(String date, String type, String time, String reason) => _request(
      'excuse_create', body: {'date': date, 'type': type, 'time': time, 'reason': reason});

  Future<void> decideExcuse(int id, String decision, {String note = ''}) =>
      _request('excuse_decide', body: {'id': id, 'decision': decision, 'note': note});

  Future<void> setDayOff(int employeeId, String from, int days, String note) => _request('dayoff_set',
      body: {'employee_id': employeeId, 'from': from, 'days': days, 'note': note});

  Future<void> removeDayOff(int employeeId, String date) =>
      _request('dayoff_remove', body: {'employee_id': employeeId, 'from': date});

  Future<void> changePin(String oldPin, String newPin) =>
      _request('change_pin', body: {'old_pin': oldPin, 'new_pin': newPin});
}
