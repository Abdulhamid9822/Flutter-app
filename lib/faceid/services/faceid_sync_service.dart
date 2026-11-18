import '../../api.dart';
import 'database_service.dart';

/// Bitta sinxronizatsiya urinishi natijasi.
class FaceIdSyncResult {
  const FaceIdSyncResult({
    required this.sent,
    required this.pending,
    required this.failed,
    this.offline = false,
    this.error,
  });

  /// MySQLga muvaffaqiyatli yuborilgan yozuvlar soni.
  final int sent;

  /// Hali navbatda qolgan yozuvlar soni.
  final int pending;

  /// Server rad etgan (qayta urinish mumkin bo'lgan) yozuvlar soni.
  final int failed;

  /// Internet/server bilan aloqa yo'qligi sababli to'xtatilgan.
  final bool offline;

  final String? error;

  bool get success => failed == 0 && !offline;
}

/// Xodimning lokal FaceID skanlarini MySQL attendance_data jadvaliga
/// yuboradi. Har bir yozuv bir marta yuboriladi; tarmoq bo'lmasa lokal
/// navbatda qoladi va keyingi safar qayta uriniladi.
class FaceIdSyncService {
  FaceIdSyncService._();

  static final FaceIdSyncService instance = FaceIdSyncService._();

  Future<FaceIdSyncResult>? _active;

  /// Navbatdagi yozuvlarni yuboradi. Bir vaqtda faqat bitta urinish
  /// ishlaydi — parallel chaqiriqlar mavjud natijani kutadi.
  Future<FaceIdSyncResult> syncPending() {
    final active = _active;
    if (active != null) return active;
    final future = _run().whenComplete(() => _active = null);
    _active = future;
    return future;
  }

  Future<FaceIdSyncResult> _run() async {
    var user = Api.instance.user;
    // Eski o'rnatishlarda account maydoni saqlanmagan bo'lishi mumkin.
    if (user != null && user.account.trim().isEmpty) {
      await Api.instance.refreshLang();
      user = Api.instance.user ?? user;
    }

    if (user == null) {
      return const FaceIdSyncResult(sent: 0, pending: 0, failed: 0);
    }

    final db = DatabaseService.instance;
    final account = user.account.trim();
    final isEmployee = user.role == 'employee';
    final ownEmployeeId = user.employeeId;

    if (isEmployee) {
      // Xodim faqat o'zining skanlarini yuboradi; server ham boshqa
      // xodim nomidan yozishga ruxsat bermaydi.
      if (ownEmployeeId == null) {
        return const FaceIdSyncResult(sent: 0, pending: 0, failed: 0);
      }
    } else if (account.isEmpty) {
      // Admin uchun account noma'lum bo'lsa, boshqa account yozuvlarini
      // yuborib yubormaslik uchun kutamiz. Navbatda nima borligini
      // ko'rsatib turamiz.
      var waiting = 0;
      try {
        waiting = await db.countPendingSync();
      } catch (_) {}
      return FaceIdSyncResult(
        sent: 0,
        pending: waiting,
        failed: 0,
        error: 'Account ma\'lumoti yuklanmadi',
      );
    }

    var sent = 0;
    var failed = 0;
    var offline = false;
    String? error;

    try {
      final logs = await db.getPendingSyncLogs(
        externalId: isEmployee ? ownEmployeeId : null,
        accountName: account.isEmpty ? null : account,
      );
      for (final item in logs) {
        try {
          await Api.instance.faceIdAttendance(
            direction: item.log.action,
            timestamp: item.log.timestamp,
            confidence: item.log.confidence,
            employeeId: item.externalId,
          );
          await db.markLogSynced(item.log.id);
          sent++;
        } on ApiException catch (e) {
          error = e.message;
          if (e.unauthorized || e.network) {
            offline = e.network;
            break;
          }
          // Vaqt/sana kabi validatsiya xatosi boshqa yozuvlarni
          // bloklamasin — keyingi yozuvga o'tamiz.
          failed++;
        } catch (e) {
          error = e.toString();
          failed++;
          break;
        }
      }
    } catch (e) {
      error = e.toString();
      failed++;
    }

    var pending = 0;
    try {
      pending = await db.countPendingSync(
        externalId: isEmployee ? ownEmployeeId : null,
        accountName: account.isEmpty ? null : account,
      );
    } catch (_) {
      // Navbat sonini o'qish xatosi sinxronizatsiya natijasini
      // bekor qilmaydi.
    }

    return FaceIdSyncResult(
      sent: sent,
      pending: pending,
      failed: failed,
      offline: offline,
      error: error,
    );
  }
}
