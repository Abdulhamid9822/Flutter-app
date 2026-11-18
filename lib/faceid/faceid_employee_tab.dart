import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'models/access_log.dart';
import 'models/person.dart';
import 'screens/bind_screen.dart';
import 'screens/employee_detail_screen.dart';
import 'services/database_service.dart';
import 'services/photo_store.dart';
import 'services/recognition_service.dart';
import 'services/settings_service.dart';
import 'theme.dart' as fid;
import 'widgets/enrollment_permission_dialog.dart';

/// Attendance ilovasidagi xodim kartasining ichidagi FaceID bo'limi.
///
/// Bu bo'lim faqat shu xodimning lokal yuz rasmlari bilan ishlaydi:
/// rasmlarni bog'lash, ko'rish va o'chirish. Boshqa xodimlarning yuzlari
/// bu yerda ko'rsatilmaydi.
class FaceIdEmployeeTab extends StatefulWidget {
  const FaceIdEmployeeTab({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  /// Attendance tizimidagi xodim IDsi (`external_id`).
  final int employeeId;
  final String employeeName;

  @override
  State<FaceIdEmployeeTab> createState() => _FaceIdEmployeeTabState();
}

class _FaceIdEmployeeTabState extends State<FaceIdEmployeeTab> {
  final _db = DatabaseService.instance;
  final _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  Person? _person;
  List<String> _images = const [];
  List<AccessLog> _logs = const [];
  int _todayEntries = 0;
  int _todayExits = 0;
  bool _loading = true;
  bool _granting = false;
  String? _error;

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
      await SettingsService.instance.init();
      await SettingsService.instance.refreshInstitutionFromServer();
      await _db.database;
      await RecognitionService.instance.init();
      await PhotoStore.cleanupTemp();
      final person = await _db.ensureExternalPerson(
        externalId: widget.employeeId,
        fullName: widget.employeeName,
        accountName: Api.instance.user?.account,
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
    final person =
        current ??
        await _db.ensureExternalPerson(
          externalId: widget.employeeId,
          fullName: widget.employeeName,
          accountName: Api.instance.user?.account,
        );
    final fresh = await _db.getPerson(person.id) ?? person;
    final images = await _db.getPersonImagePaths(fresh.id);
    final entries = await _db.countTodayForPerson(fresh.id, 'entry');
    final exits = await _db.countTodayForPerson(fresh.id, 'exit');
    final logs = await _db.getLogsForPerson(fresh.id, limit: 5);
    if (!mounted) return;
    setState(() {
      _person = fresh;
      _images = images;
      _todayEntries = entries;
      _todayExits = exits;
      _logs = logs;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _bindPhotos() async {
    final person = _person;
    if (person == null) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Yuz rasmlari bog'landi.")),
      );
    }
  }

  Future<void> _managePhotos() async {
    final person = _person;
    if (person == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: fid.faceIdTheme,
          child: FaceIdEmployeeScreen(personId: person.id),
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _grantEnrollmentPermission() async {
    if (_granting) return;
    setState(() => _granting = true);
    try {
      await showEnrollmentPermissionDialog(
        context,
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
      );
    } finally {
      if (mounted) setState(() => _granting = false);
    }
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
      onRefresh: _reload,
      color: AppColors.brandPrimary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDecoration(d),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.brandPrimary.withValues(
                    alpha: .16,
                  ),
                  backgroundImage: _images.isEmpty
                      ? null
                      : FileImage(File(_images.first)),
                  child: _images.isEmpty
                      ? Text(
                          person.fullName.isEmpty
                              ? '?'
                              : person.fullName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.brandPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
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
                        'Attendance ID: ${person.externalId ?? widget.employeeId}',
                        style: TextStyle(color: appMuted(d), fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          StatusPill(
                            ready ? 'TAYYOR' : 'RASM KERAK',
                            ready
                                ? AppColors.statusPresent
                                : AppColors.statusLate,
                          ),
                          StatusPill(
                            '${person.faceCount} rasm',
                            AppColors.brandCyan,
                          ),
                        ],
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
            onPressed: _bindPhotos,
            icon: const Icon(Icons.add_a_photo_outlined, size: 20),
            label: Text(
              person.faceCount == 0
                  ? "Yuz rasmlarini bog'lash"
                  : "Yana rasm qo'shish",
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _managePhotos,
            icon: const Icon(Icons.manage_accounts_outlined, size: 20),
            label: const Text("Yuzlarni boshqarish"),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _granting ? null : _grantEnrollmentPermission,
            icon: _granting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.vpn_key_outlined, size: 20),
            label: const Text('Xodimga rasm olishga ruxsat'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          SectionLabel('Yuz rasmlari (${_images.length})'),
          if (_images.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.statusLate.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.statusLate.withValues(alpha: .35),
                ),
              ),
              child: Text(
                "Bu xodimga hali yuz rasmi bog'lanmagan. Kamida 2 ta rasm "
                "qo'shing — shundan keyin u FaceID skanerlashda qatnashadi.",
                style: TextStyle(
                  color: AppColors.statusLate,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _images.length,
              itemBuilder: (context, index) {
                final path = _images[index];
                return Material(
                  color: appCardBackground(d),
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _previewImage(path),
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.image_not_supported_outlined,
                        color: appMuted(d),
                        size: 20,
                      ),
                    ),
                  ),
                );
              },
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
            "Yuz rasmlarini bog'lash va skanerlash faqat muassasa hududida "
            "ishlaydi. Yuz ma'lumotlari faqat shu qurilmada saqlanadi.",
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

  void _previewImage(String path) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .9),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
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
