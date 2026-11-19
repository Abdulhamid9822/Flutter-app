import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/person.dart';
import '../services/camera_session.dart';
import '../services/database_service.dart';
import '../services/faceid_sync_service.dart';
import '../services/location_service.dart';
import '../services/photo_store.dart';
import '../services/recognition_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/geofence_dialog.dart';
import '../widgets/ui.dart';

class FaceIdCameraScreen extends StatefulWidget {
  const FaceIdCameraScreen({
    super.key,
    this.onlyPersonId,
    this.onlyPersonName,
  });

  /// Faqat shu xodimning yuzlari bilan solishtiriladi. Xodim o'z loginida
  /// boshqa odamning yuzi bilan davomat qila olmasligi uchun ishlatiladi.
  final int? onlyPersonId;
  final String? onlyPersonName;

  @override
  State<FaceIdCameraScreen> createState() => _FaceIdCameraScreenState();
}

class _FaceIdCameraScreenState extends State<FaceIdCameraScreen> {
  static const int _shotCount = 3;

  final _db = DatabaseService.instance;
  final _settings = SettingsService.instance;

  late final CameraSession _session;
  bool _busy = false;
  String _status = '';
  int _shot = 0;

  @override
  void initState() {
    super.initState();
    _session = CameraSession(
      preferredLens: _settings.cameraLens == 'back'
          ? CameraLensDirection.back
          : CameraLensDirection.front,
    );
    _session.addListener(_onSessionChanged);
    _session.start();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_busy) return;
    if (!_session.isReady) {
      _showSnack("Kamera hali tayyor emas. Bir oz kuting.");
      return;
    }

    setState(() {
      _busy = true;
      _shot = 0;
      _status = 'Joylashuv tekshirilmoqda...';
    });

    if (!_settings.hasInstitutionLocation) {
      await SettingsService.instance.refreshInstitutionFromServer();
    }
    final geofence = await LocationService.instance.checkInstitution();
    if (!mounted) return;
    if (!geofence.isInside) {
      setState(() {
        _busy = false;
        _status = '';
      });
      await showGeofenceDialog(context, geofence);
      return;
    }

    setState(() => _status = 'Rasmlar olinmoqda...');

    final paths = <String>[];
    ScanOutcome? outcome;
    try {
      for (var i = 0; i < _shotCount; i++) {
        if (i > 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (!mounted) return;
        setState(() {
          _shot = i + 1;
          _status = 'Rasm ${i + 1}/$_shotCount olinmoqda...';
        });
        await HapticFeedback.selectionClick();
        final path = await _session.takePhoto();
        paths.add(path);
      }

      if (!mounted) return;
      setState(() {
        _shot = 0;
        _status = 'Yuzlar tahlil qilinmoqda...';
      });
      outcome = await RecognitionService.instance.scanPhotos(
        paths,
        onlyPersonId: widget.onlyPersonId,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() => _status = 'Tahlil: $done/$total');
        },
      );
    } on NoKnownFacesException catch (error) {
      await _showInfo(
        icon: Icons.face_retouching_off_rounded,
        color: AppColors.yellow,
        title: widget.onlyPersonId == null
            ? "Yuzlar bazasi bo'sh"
            : "Yuzingiz bog'lanmagan",
        message: error.message,
      );
    } catch (error) {
      await _showInfo(
        icon: Icons.error_outline_rounded,
        color: AppColors.red,
        title: 'Xatolik',
        message: "Skanerlashda xatolik yuz berdi:\n$error",
      );
    } finally {
      for (final path in paths) {
        await PhotoStore.deleteQuietly(path);
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
          _shot = 0;
        });
      }
    }

    if (!mounted || outcome == null) return;
    await _handleOutcome(outcome);
  }

  Future<void> _handleOutcome(ScanOutcome outcome) async {
    final selected = outcome.selected;
    if (selected == null) {
      await _showInfo(
        icon: Icons.face_retouching_off_rounded,
        color: AppColors.yellow,
        title: 'Yuz aniqlanmadi',
        message:
            "Rasmda yuz topilmadi. Kameraga yaqinroq turing va yaxshi "
            "yorug'likda qayta urinib ko'ring.",
      );
      return;
    }

    if (selected.faceCount > 1) {
      await _showInfo(
        icon: Icons.groups_2_outlined,
        color: AppColors.yellow,
        title: 'Bir nechta yuz aniqlandi',
        message:
            "Kadrda bir nechta yuz ko'rindi. Iltimos, skanerlash paytida "
            "kamerada faqat bitta odam bo'lsin.",
      );
      return;
    }

    if (selected.faceCount == 0) {
      final details = selected.error?.trim();
      await _showInfo(
        icon: Icons.face_retouching_off_rounded,
        color: AppColors.yellow,
        title: 'Yuz aniqlanmadi',
        message: details == null || details.isEmpty
            ? "Rasmda yuz topilmadi. Kameraga yaqinroq turing va yaxshi "
                  "yorug'likda qayta urinib ko'ring."
            : "Rasmni tahlil qilib bo'lmadi.\n$details",
      );
      return;
    }

    final match = selected.match;
    if (match == null || match.bestPersonId == null) {
      await _showInfo(
        icon: Icons.error_outline_rounded,
        color: AppColors.red,
        title: 'Tahlil xatosi',
        message:
            "Yuzni tahlil qilib bo'lmadi. Qayta skanerlashga urinib ko'ring.",
      );
      return;
    }

    if (match.ambiguous) {
      final best = await _db.getPerson(match.bestPersonId!);
      final second = match.secondPersonId == null
          ? null
          : await _db.getPerson(match.secondPersonId!);
      final names = [
        if (best != null) best.fullName,
        if (second != null) second.fullName,
      ].join(' va ');
      await _showInfo(
        icon: Icons.compare_arrows_rounded,
        color: AppColors.yellow,
        title: "Aniqlik yetarli emas",
        message:
            "Natija bir nechta xodimga o'xshash bo'ldi"
            "${names.isEmpty ? '' : ': $names'}.\n"
            "Yaxshiroq yorug'likda, to'g'ri burchakdan qayta skanerlang.",
      );
      return;
    }

    if (!match.matched) {
      if (widget.onlyPersonId != null) {
        final expected = widget.onlyPersonName ?? 'sizning';
        await _showInfo(
          icon: Icons.person_off_rounded,
          color: AppColors.red,
          title: "Bu sizning yuzingiz emas",
          message:
              "Bu yuz \"$expected\" profilidagi yuzga mos kelmadi.\n\n"
              "Faqat o'z yuzingiz bilan davomat qilishingiz mumkin. "
              "Boshqa xodimning yuzi bilan yozuv yaratilmaydi.",
        );
        return;
      }
      await _showInfo(
        icon: Icons.person_search_rounded,
        color: AppColors.red,
        title: 'Yuz tanilmadi',
        message:
            "Bu yuz bazadagi xodimlarga mos kelmadi.\n\n"
            "Eng yaqin moslik: ${(match.bestScore * 100).toStringAsFixed(0)}% · "
            "Talab: ${(match.threshold * 100).toStringAsFixed(0)}%",
      );
      return;
    }

    final person = await _db.getPerson(match.bestPersonId!);
    if (person == null) {
      await _showInfo(
        icon: Icons.error_outline_rounded,
        color: AppColors.red,
        title: 'Xodim topilmadi',
        message:
            "Tanish natijasi eskirgan bo'lishi mumkin. Xodimlar bo'limini "
            "yangilab, qayta urinib ko'ring.",
      );
      return;
    }

    final now = DateTime.now();
    final last = await _db.lastAction(person.id);
    final cooldown = Duration(minutes: _settings.cooldownMinutes);
    if (last != null) {
      final elapsed = now.difference(last.timestamp);
      if (elapsed < cooldown) {
        await _showInfo(
          icon: Icons.hourglass_top_rounded,
          color: AppColors.yellow,
          title: 'Kuting',
          message:
              "${person.fullName} yaqinda qayd etilgan "
              "(${formatDateTime(last.timestamp)}).\n\n"
              "Qayta skanerlash uchun "
              "${formatWait(cooldown - elapsed)} kutish kerak.",
        );
        return;
      }
    }

    final action = await _showDirectionDialog(
      person: person,
      score: match.bestScore,
      time: now,
    );
    if (!mounted || action == null) return;

    try {
      final selfScan = widget.onlyPersonId != null;
      // Xodimning o'z skanerida surat saqlanmaydi: davomat yozuvi va
      // vaqt saqlanadi, yuz tasviri esa qurilmada qoldirilmaydi.
      final photoPath = selfScan
          ? null
          : await PhotoStore.saveScanPhoto(
              person.id,
              action,
              selected.analysis.normalizedJpeg,
              time: now,
            );
      await _db.insertLog(
        personId: person.id,
        personName: person.fullName,
        employeeCode: person.employeeCode,
        action: action,
        confidence: match.bestScore,
        timestamp: now,
        photoPath: photoPath,
        // Serverdagi xodimga bog'langan barcha skanlar MySQLga yuboriladi:
        // xodimning o'z skaneri ham, admin/branch umumiy skaneri ham.
        syncToServer: person.externalId != null,
      );
      if (person.externalId != null) {
        // Dialogni kutib turmasdan MySQLga yuborishga harakat qilamiz.
        // Internet bo'lmasa yozuv lokal navbatda qoladi va keyin
        // avtomatik qayta yuboriladi.
        unawaited(FaceIdSyncService.instance.syncPending());
      }
      await HapticFeedback.heavyImpact();
      await SystemSound.play(SystemSoundType.click);
      if (!mounted) return;
      final again = await _showSuccessDialog(
        person: person,
        action: action,
        score: match.bestScore,
        time: now,
        photo: selfScan ? Uint8List(0) : selected.analysis.normalizedJpeg,
      );
      if (!mounted) return;
      if (again == false) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      await _showInfo(
        icon: Icons.error_outline_rounded,
        color: AppColors.red,
        title: 'Saqlash xatosi',
        message: "Natijani saqlab bo'lmadi:\n$error",
      );
    }
  }

  Future<String?> _showDirectionDialog({
    required Person person,
    required double score,
    required DateTime time,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'XODIM TANILDI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.subtext,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                person.fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(score * 100).toStringAsFixed(1)}% · ${formatTime(time)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.subtext,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Davomat turini tanlang',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop('entry'),
                      icon: const Icon(Icons.login_rounded, size: 21),
                      label: const Text('Kirish'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop('exit'),
                      icon: const Icon(Icons.logout_rounded, size: 21),
                      label: const Text('Chiqish'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Bekor qilish'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showSuccessDialog({
    required Person person,
    required String action,
    required double score,
    required DateTime time,
    required Uint8List photo,
  }) {
    final isEntry = action == 'entry';
    final color = isEntry ? AppColors.green : AppColors.red;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Icon(
                    isEntry ? Icons.login_rounded : Icons.logout_rounded,
                    color: color,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isEntry ? 'KIRISH QAYD ETILDI' : 'CHIQISH QAYD ETILDI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                person.fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${person.employeeCode} · ${(score * 100).toStringAsFixed(1)}% · '
                '${formatTime(time)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.subtext, fontSize: 12),
              ),
              if (widget.onlyPersonId != null) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cloud_upload_outlined,
                      color: AppColors.subtext,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        "MySQL bazasiga avtomatik yuboriladi",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.subtext,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (photo.isNotEmpty) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    photo,
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Yana'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Yopish'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.subtext,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canScan = _session.isReady && !_busy;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0605),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.text,
                      disabledForegroundColor: AppColors.muted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Skanerlash',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.onlyPersonId == null
                              ? 'Yuzni kameraga to\'g\'ri tuting'
                              : 'Faqat o\'z yuzingiz bilan',
                          style: const TextStyle(
                            color: AppColors.subtext,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Pill(
                    text: 'OFLAYN',
                    icon: Icons.wifi_off_rounded,
                    color: AppColors.green,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreviewBox(session: _session, borderRadius: 28),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 236,
                          height: 318,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(
                              Radius.elliptical(130, 178),
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.38),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.center_focus_strong_rounded,
                                color: Colors.white70,
                                size: 16,
                              ),
                              SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  "Yuzni ramka ichiga joylashtiring",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_busy)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.68),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _status,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_shot > 0) ...[
                                    const SizedBox(height: 14),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        for (var i = 0; i < _shotCount; i++)
                                          Container(
                                            width: 26,
                                            height: 4,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: i < _shot
                                                  ? AppColors.primary
                                                  : Colors.white24,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  const Text(
                                    "Iltimos, qimirlamang",
                                    style: TextStyle(
                                      color: AppColors.subtext,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "3 ta rasm avtomatik olinadi va eng yaxshisi tanlanadi",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.subtext, fontSize: 11),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: IconButton(
                          onPressed: canScan && _session.canSwitchCamera
                              ? _session.switchCamera
                              : null,
                          icon: const Icon(Icons.cameraswitch_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.text,
                            disabledForegroundColor: AppColors.muted,
                            minimumSize: const Size(48, 48),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _ShutterButton(
                            enabled: canScan,
                            onTap: _startScan,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: Icon(
                          _session.lens == CameraLensDirection.front
                              ? Icons.person_outline_rounded
                              : Icons.landscape_outlined,
                          color: AppColors.muted,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _session.lens == CameraLensDirection.front
                        ? 'Old kamera'
                        : 'Orqa kamera',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Skanerlashni boshlash',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: enabled ? AppColors.primary : AppColors.muted,
              width: 3,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? AppColors.primary : AppColors.surfaceHigh,
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                size: 30,
                color: enabled ? const Color(0xFF2A0F05) : AppColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
