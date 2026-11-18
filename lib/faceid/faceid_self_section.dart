import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'models/access_log.dart';
import 'models/person.dart';
import 'screens/bind_screen.dart';
import 'screens/camera_screen.dart';
import 'services/database_service.dart';
import 'services/faceid_sync_service.dart';
import 'services/location_service.dart';
import 'services/recognition_service.dart';
import 'services/settings_service.dart';
import 'theme.dart' as fid;
import 'widgets/geofence_dialog.dart';

/// Xodim (employee) roli uchun FaceID bo'limi.
///
/// Xodim bu yerda faqat o'z yuzi bilan davomat o'tadi. Yuz rasmlarini
/// bog'lash, o'chirish yoki sozlash imkoniyati yo'q — bularning barchasi
/// administrator tomonida, xodim kartasining FaceID bo'limida bajariladi.
class FaceIdSelfSection extends StatefulWidget {
  const FaceIdSelfSection({super.key});

  @override
  State<FaceIdSelfSection> createState() => _FaceIdSelfSectionState();
}

class _FaceIdSelfSectionState extends State<FaceIdSelfSection> {
  final _db = DatabaseService.instance;
  final _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  Person? _person;
  String? _coverPath;
  List<AccessLog> _logs = const [];
  int _todayEntries = 0;
  int _todayExits = 0;
  int _pendingSync = 0;
  bool _loading = true;
  bool _scanning = false;
  bool _enrolling = false;
  bool _requesting = false;
  bool _syncing = false;
  String? _error;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = Api.instance.user;
      final employeeId = user?.employeeId;
      if (user == null || employeeId == null) {
        throw Exception(
          "Hisobingiz xodim kartasiga bog'lanmagan. Administratorga "
          "murojaat qiling.",
        );
      }

      await SettingsService.instance.init();
      await SettingsService.instance.refreshInstitutionFromServer();
      await _db.database;
      await RecognitionService.instance.init();

      final person = await _db.ensureExternalPerson(
        externalId: employeeId,
        fullName: user.name,
        accountName: user.account,
      );
      await RecognitionService.instance.invalidateIndex();
      await _reload(person);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reload([Person? current]) async {
    final user = Api.instance.user;
    final employeeId = user?.employeeId;
    if (employeeId == null) return;
    final person =
        current ??
        await _db.ensureExternalPerson(
          externalId: employeeId,
          fullName: user?.name ?? '',
          accountName: user?.account,
        );
    final fresh = await _db.getPerson(person.id) ?? person;
    final images = await _db.getPersonImagePaths(fresh.id);
    final entries = await _db.countTodayForPerson(fresh.id, 'entry');
    final exits = await _db.countTodayForPerson(fresh.id, 'exit');
    final logs = await _db.getLogsForPerson(fresh.id, limit: 10);
    final pending = await _db.countPendingSync(
      externalId: employeeId,
      accountName: user?.account,
    );
    if (!mounted) return;
    setState(() {
      _person = fresh;
      _coverPath = images.isEmpty ? null : images.first;
      _todayEntries = entries;
      _todayExits = exits;
      _logs = logs;
      _pendingSync = pending;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _refresh() async {
    await SettingsService.instance.refreshInstitutionFromServer();
    await _reload();
  }

  Future<void> _requestPermission() async {
    if (_requesting || _enrolling) return;
    setState(() => _requesting = true);
    try {
      final data = await Api.instance.faceIdEnrollmentRequestCreate();
      if (!mounted) return;
      final already = data['already_pending'] == true;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              already
                  ? "So‘rov allaqachon yuborilgan. Admin javobini kuting."
                  : "So‘rov yuborildi. Admin tasdiqlagach kod push orqali "
                        "keladi.",
            ),
          ),
        );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Xatolik: $error')));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _scan() async {
    final person = _person;
    if (person == null || _scanning) return;
    if (person.faceCount < 2) {
      await _showInfo(
        icon: Icons.admin_panel_settings_outlined,
        color: AppColors.statusLate,
        title: "Yuzingiz hali bog'lanmagan",
        message:
            "Davomat uchun avval yuz rasmingizni bog'lash kerak. "
            "Admin ruxsat kodi bilan \"Admin ruxsati bilan rasmga "
            "tushish\" tugmasidan foydalaning.",
      );
      return;
    }

    setState(() => _scanning = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Theme(
            data: fid.faceIdTheme,
            child: FaceIdCameraScreen(
              onlyPersonId: person.id,
              onlyPersonName: person.fullName,
            ),
          ),
        ),
      );
      if (!mounted) return;
      // Skan paytida boshlangan yuborish tugashini kutamiz, so'ng
      // navbat va bugungi holatni yangilaymiz.
      try {
        await FaceIdSyncService.instance.syncPending();
      } catch (_) {
        // Navbatni yuborishdagi xato skanerlash oqimini to'xtatmaydi.
      }
      if (mounted) await _reload();
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<String?> _askEnrollmentCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Admin ruxsat kodi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Admin sizga bergan 6 xonali kodni kiriting. Kod bir marta "
              "ishlaydi va 15 daqiqa amal qiladi. Har bir rasm olish "
              "uchun yangi kod kerak.",
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                hintText: '000000',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length == 6) {
                Navigator.of(dialogContext).pop(value);
              }
            },
            child: const Text('Davom etish'),
          ),
        ],
      ),
    );
    controller.dispose();
    return code;
  }

  Future<void> _selfEnroll() async {
    final person = _person;
    if (person == null || _enrolling || _scanning) return;
    final code = await _askEnrollmentCode();
    if (code == null || !mounted) return;

    // Ruxsat kodini ishlatishdan oldin hududni tekshiramiz — kod behuda
    // ketmasin.
    final geofence = await LocationService.instance.checkInstitution();
    if (!mounted) return;
    if (!geofence.isInside) {
      await showGeofenceDialog(context, geofence);
      return;
    }

    setState(() => _enrolling = true);
    try {
      await Api.instance.faceIdEnrollmentValidate(code);
      if (!mounted) return;
      final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => Theme(
            data: fid.faceIdTheme,
            child: FaceBindScreen(person: person),
          ),
        ),
      );
      if (added == true && mounted) {
        await _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Yuz rasmingiz saqlandi.')),
          );
      }
    } on ApiException catch (error) {
      await _showInfo(
        icon: Icons.vpn_key_off_rounded,
        color: AppColors.statusAbsent,
        title: 'Ruxsat xatosi',
        message: error.message,
      );
    } catch (error) {
      await _showInfo(
        icon: Icons.error_outline_rounded,
        color: AppColors.statusAbsent,
        title: 'Xatolik',
        message: 'Yuz rasmini saqlashda xatolik:\n$error',
      );
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      final result = await FaceIdSyncService.instance.syncPending();
      if (!mounted) return;
      setState(() {
        _pendingSync = result.pending;
        _syncError = result.error;
      });
      if (result.sent > 0 && result.pending == 0) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text("Davomat yozuvlari MySQL bazasiga yuborildi."),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showInfo({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tushunarli'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _person == null) {
      return ErrorBox(
        "FaceID bo'limini yuklab bo'lmadi:\n${_error ?? 'Xodim topilmadi'}",
        onRetry: _initialize,
      );
    }

    final person = _person!;
    final ready = person.faceCount >= 2;
    final d = isDarkOf(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.brandPrimary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: cardDecoration(d),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.brandPrimary.withValues(
                    alpha: .16,
                  ),
                  backgroundImage: _coverPath == null
                      ? null
                      : FileImage(File(_coverPath!)),
                  child: _coverPath == null
                      ? Text(
                          person.fullName.isEmpty
                              ? '?'
                              : person.fullName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.brandPrimary,
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: appText(d),
                          height: 1.25,
                        ),
                      ),
                      if ((person.position ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          person.position!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: appSubtext(d),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        'Attendance ID: ${person.externalId ?? '—'}',
                        style: TextStyle(color: appMuted(d), fontSize: 11),
                      ),
                      const SizedBox(height: 9),
                      StatusPill(
                        ready ? 'TAYYOR' : 'RASM KERAK',
                        ready
                            ? AppColors.statusPresent
                            : AppColors.statusLate,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Bugun kirdi',
                  value: '$_todayEntries',
                  icon: Icons.login_rounded,
                  color: AppColors.statusPresent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Bugun chiqdi',
                  value: '$_todayExits',
                  icon: Icons.logout_rounded,
                  color: AppColors.statusEarly,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_front_rounded, size: 21),
            label: const Text("FaceID bilan davomat o'tish"),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
            ),
          ),
          const SizedBox(height: 9),
          FilledButton.icon(
            onPressed: _requesting || _enrolling || _scanning
                ? null
                : _requestPermission,
            icon: _requesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined, size: 20),
            label: const Text('Admin ruxsatini so‘rash'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandPrimary.withValues(alpha: .14),
              foregroundColor: AppColors.brandPrimary,
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 7),
          OutlinedButton.icon(
            onPressed: _enrolling || _scanning || _requesting
                ? null
                : _selfEnroll,
            icon: _enrolling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.vpn_key_outlined, size: 20),
            label: const Text('Kodni qo‘lda kiritish'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildSyncCard(d),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.brandPrimary.withValues(alpha: .35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: AppColors.brandPrimary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Skanerlashda faqat sizning yuzingiz tekshiriladi. "
                    "Boshqa odamning yuzi tanilmaydi va davomat yozuvi "
                    "yaratilmaydi.\n\n"
                    "Yuz rasmini yangilash uchun admin ruxsatini so‘rang "
                    "yoki admin bergan kodni kiriting. Admin tasdiqlasa, "
                    "kod push notification orqali keladi.",
                    style: TextStyle(
                      color: appSubtext(d),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_logs.isNotEmpty) ...[
            const SectionLabel("So'nggi harakatlar"),
            Container(
              decoration: cardDecoration(d),
              child: Column(
                children: [
                  for (var i = 0; i < _logs.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: appCardBorder(d)),
                    _LogRow(log: _logs[i], dateFormat: _dateFormat),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            "Skanerlash faqat muassasa hududida ishlaydi. Yuz ma'lumotlari "
            "shu qurilmada saqlanadi, davomat yozuvi esa MySQL bazasiga "
            "yuboriladi.",
            style: TextStyle(
              color: appMuted(d),
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCard(bool d) {
    final allSynced = _pendingSync == 0;
    final color = allSynced ? AppColors.statusPresent : AppColors.statusLate;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: d ? Colors.white.withValues(alpha: .03) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: appCardBorder(d)),
      ),
      child: Row(
        children: [
          Icon(
            allSynced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allSynced
                      ? 'MySQL bazasi bilan sinxron'
                      : '$_pendingSync ta yozuv yuborilishi kutilmoqda',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: appText(d),
                  ),
                ),
                if (_syncError != null && !allSynced) ...[
                  const SizedBox(height: 2),
                  Text(
                    "Internet bo'lganda avtomatik qayta yuboriladi.",
                    style: TextStyle(fontSize: 10, color: appMuted(d)),
                  ),
                ],
              ],
            ),
          ),
          if (!allSynced)
            TextButton(
              onPressed: _syncing ? null : _syncNow,
              child: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Yuborish'),
            ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: cardDecoration(d),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: appText(d),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: appSubtext(d)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log, required this.dateFormat});

  final AccessLog log;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    final color = log.isEntry
        ? AppColors.statusPresent
        : AppColors.statusEarly;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(
            log.isEntry ? Icons.login_rounded : Icons.logout_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              log.isEntry ? 'Kirdi' : 'Chiqdi',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: appText(d),
              ),
            ),
          ),
          Text(
            dateFormat.format(log.timestamp),
            style: TextStyle(fontSize: 11, color: appMuted(d)),
          ),
        ],
      ),
    );
  }
}
