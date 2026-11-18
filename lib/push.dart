import 'dart:ui' show Color;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';

/// FCM push. google-services.json qo'yilmagan bo'lsa jimgina o'chiq turadi.
class PushService {
  /// Har bir ariza push'ida oshadi: Arizalar ro'yxati yangilanadi.
  static final ValueNotifier<int> excuseEvents = ValueNotifier(0);
  /// Bildirishnoma bosilganda oshadi: Arizalar tabi ochiladi.
  static final ValueNotifier<int> openExcuses = ValueNotifier(0);

  /// FaceID rasm yangilash so'rovi bosilganda oshadi.
  static final ValueNotifier<int> openFaceIdEnrollment = ValueNotifier(0);
  static String? pendingEnrollmentCode;
  static String? pendingEnrollmentExpiresAt;

  /// Xodim yuborgan rasm olish so'rovi bosilganda oshadi.
  static final ValueNotifier<int> openFaceIdAdminRequest = ValueNotifier(0);
  static String? pendingAdminRequestId;
  static String? pendingAdminRequestName;

  static void _handleOpen(RemoteMessage m) {
    final t = m.data['type'];
    if (t == 'faceid_enrollment_request') {
      pendingEnrollmentCode = m.data['code'];
      pendingEnrollmentExpiresAt = m.data['expires_at'];
      openFaceIdEnrollment.value++;
      return;
    }
    if (t == 'faceid_enrollment_admin_request') {
      pendingAdminRequestId = m.data['request_id'];
      pendingAdminRequestName = m.data['employee_name'];
      openFaceIdAdminRequest.value++;
      return;
    }
    if (t == 'excuse_new' || t == 'excuse_decided') {
      excuseEvents.value++;
      openExcuses.value++;
    }
  }

  static void clearPendingEnrollment() {
    pendingEnrollmentCode = null;
    pendingEnrollmentExpiresAt = null;
  }

  static void clearPendingAdminRequest() {
    pendingAdminRequestId = null;
    pendingAdminRequestName = null;
  }

  static bool _ready = false;
  static String? _token;
  static final _local = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'excuses',
    'Arizalar',
    description: 'Ariza va qarorlar haqida bildirishnomalar',
    importance: Importance.high,
  );

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      await _local.initialize(
          settings: const InitializationSettings(
              android: AndroidInitializationSettings('ic_notification'),
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              )));
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      await android?.requestNotificationsPermission();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      FirebaseMessaging.onMessage.listen((m) {
        final t = m.data['type'];
        if (t == 'excuse_new' || t == 'excuse_decided') excuseEvents.value++;
        if (t == 'faceid_enrollment_request') {
          pendingEnrollmentCode = m.data['code'];
          pendingEnrollmentExpiresAt = m.data['expires_at'];
          openFaceIdEnrollment.value++;
        }
        if (t == 'faceid_enrollment_admin_request') {
          pendingAdminRequestId = m.data['request_id'];
          pendingAdminRequestName = m.data['employee_name'];
          openFaceIdAdminRequest.value++;
        }
        _showForeground(m);
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleOpen(initial);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _token = t;
        _send(t);
      });
      _ready = true;
    } catch (e) {
      initError = '$e';
      debugPrint('Push o\'chiq: $e');
    }
  }

  static String? initError;

  /// Sinov: qurilmani qayta ro'yxatdan o'tkazib, serverdan o'zimizga push so'raydi.
  static Future<String> test() async {
    if (!_ready) return 'Firebase ishga tushmadi: ${initError ?? "nomalum"}';
    try {
      _token = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      return 'FCM token olinmadi: $e';
    }
    if (_token == null) return 'FCM token bo\'sh';
    try {
      await Api.instance.registerDevice(_token!);
      final d = await Api.instance.pushTest();
      if (d['service_account'] != true) return 'Serverda fcm-service-account.json yo\'q';
      if ((d['devices'] ?? 0) == 0) return 'Qurilma serverda ro\'yxatdan o\'tmadi';
      final errs = (d['errors'] as List?) ?? [];
      if (errs.isNotEmpty) return 'FCM xatosi: ${errs.first}';
      return 'Yuborildi (${d['sent']}). Bildirishnomani kuting.';
    } on ApiException catch (e) {
      return 'Server: ${e.message}';
    }
  }

  static Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;
    // iOS'da notification APNs orqali ko'rsatiladi; lokal bildirishnoma
    // bilan takrorlanmasligi uchun bu yerda qo'shimcha ko'rsatmaymiz.
    if (defaultTargetPlatform == TargetPlatform.iOS) return;
    await _local.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
          largeIcon: const DrawableResourceAndroidBitmap('ic_notification_large'),
          color: const Color(0xFFF95502),
        ),
      ),
    );
  }

  static Future<void> _send(String t) async {
    if (Api.instance.token == null) return;
    try {
      await Api.instance.registerDevice(t);
    } catch (_) {}
  }

  static Future<void> register() async {
    if (!_ready) return;
    try {
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) await _send(_token!);
    } catch (e) {
      debugPrint('Push token xatosi: $e');
    }
  }

  static Future<void> unregister() async {
    if (!_ready || _token == null) return;
    try {
      await Api.instance.unregisterDevice(_token!);
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
  }
}
