import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/person.dart';
import '../services/camera_session.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/photo_store.dart';
import '../services/recognition_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/geofence_dialog.dart';
import '../widgets/ui.dart';

/// Mavjud (Attendance tizimidan olingan) xodimga yuz rasmlarini bog‘laydi.
class FaceBindScreen extends StatefulWidget {
  const FaceBindScreen({super.key, required this.person});

  final Person person;

  @override
  State<FaceBindScreen> createState() => _FaceBindScreenState();
}

class _Sample {
  const _Sample({required this.image, required this.embedding});

  final Uint8List image;
  final Float32List embedding;
}

class _FaceBindScreenState extends State<FaceBindScreen> {
  static const int _maxSamples = 5;
  static const int _minSamples = 2;

  final _db = DatabaseService.instance;
  final _settings = SettingsService.instance;
  final _imagePicker = ImagePicker();
  final List<_Sample> _samples = <_Sample>[];

  late final CameraSession _session;
  bool _busy = false;
  bool _saving = false;
  String _status = '';

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

  Future<void> _captureSample() async {
    if (_busy || _saving) return;
    if (_samples.length >= _maxSamples) {
      _snack("Ko'pi bilan $_maxSamples ta rasm qo'shish mumkin.");
      return;
    }
    if (!_session.isReady) {
      _snack('Kamera hali tayyor emas. Bir oz kuting.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Rasm olinmoqda...';
    });
    String? path;
    try {
      await HapticFeedback.mediumImpact();
      path = await _session.takePhoto();
      await _addFromPath(path);
    } catch (error) {
      await _info(
        icon: Icons.error_outline_rounded,
        color: AppColors.red,
        title: 'Xatolik',
        message: "Rasmni qayta ishlab bo'lmadi:\n$error",
      );
    } finally {
      await PhotoStore.deleteQuietly(path);
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy || _saving) return;
    if (_samples.length >= _maxSamples) {
      _snack("Ko'pi bilan $_maxSamples ta rasm qo'shish mumkin.");
      return;
    }

    List<XFile> files;
    try {
      files = await _imagePicker.pickMultiImage(
        imageQuality: 90,
        maxWidth: 1600,
      );
    } catch (error) {
      _snack("Galereyani ochib bo'lmadi: $error");
      return;
    }
    if (files.isEmpty || !mounted) return;

    setState(() {
      _busy = true;
      _status = 'Rasmlar tayyorlanmoqda...';
    });

    var added = 0;
    var skipped = 0;
    try {
      for (var i = 0; i < files.length; i++) {
        if (_samples.length >= _maxSamples) {
          skipped += files.length - i;
          break;
        }
        if (!mounted) return;
        setState(() => _status = 'Tahlil: ${i + 1}/${files.length}');
        try {
          final ok = await _addFromPath(files[i].path, quietFaceErrors: true);
          if (ok) {
            added++;
          } else {
            skipped++;
          }
        } catch (_) {
          skipped++;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }

    if (!mounted) return;
    if (added == 0) {
      _snack("Rasm qo'shilmadi. Har bir rasmda bitta aniq yuz bo'lishi kerak.");
    } else {
      _snack(
        '$added ta rasm qo\'shildi'
        '${skipped > 0 ? ', $skipped ta o\'tkazib yuborildi' : ''}.',
      );
    }
  }

  Future<bool> _addFromPath(String path, {bool quietFaceErrors = false}) async {
    final analysis = await RecognitionService.instance.analyzePhoto(path);
    if (analysis.faceCount == 0) {
      if (!quietFaceErrors) {
        await _info(
          icon: Icons.face_retouching_off_rounded,
          color: AppColors.yellow,
          title: 'Yuz aniqlanmadi',
          message:
              "Bu rasmda yuz topilmadi. Yaxshi yorug'likda, kameraga "
              "to'g'ri qarab qayta suratga oling.",
        );
      }
      return false;
    }
    if (analysis.faceCount > 1) {
      if (!quietFaceErrors) {
        await _info(
          icon: Icons.groups_2_outlined,
          color: AppColors.yellow,
          title: 'Bir nechta yuz',
          message:
              'Rasmda bir nechta yuz bor. Har bir rasmda faqat bitta '
              'odam bo\'lishi kerak.',
        );
      }
      return false;
    }

    final embedding = analysis.embedding;
    final image = analysis.alignedJpeg;
    if (embedding == null || image == null) {
      if (!quietFaceErrors) {
        await _info(
          icon: Icons.error_outline_rounded,
          color: AppColors.red,
          title: 'Tahlil xatosi',
          message:
              "Yuzni tayyorlab bo'lmadi. Boshqa rasm bilan urinib ko'ring.",
        );
      }
      return false;
    }

    final duplicate = await RecognitionService.instance.bestOtherMatch(
      embedding,
      excludePersonId: widget.person.id,
    );
    if (duplicate != null && duplicate.score >= _settings.duplicateThreshold) {
      final other = await _db.getPerson(duplicate.personId);
      await _blockDuplicate(
        other?.fullName ?? 'boshqa xodim',
        duplicate.score,
      );
      return false;
    }

    if (!mounted) return false;
    setState(() {
      _samples.add(_Sample(image: image, embedding: embedding));
    });
    await HapticFeedback.selectionClick();
    return true;
  }

  Future<void> _blockDuplicate(String otherName, double score) async {
    await _info(
      icon: Icons.block_rounded,
      color: AppColors.red,
      title: "Bu yuz boshqa xodimga tegishli",
      message:
          "Bu yuz \"$otherName\" xodimiga "
          "${(score * 100).toStringAsFixed(0)}% o'xshaydi.\n\n"
          "Bir yuz bitta accountda faqat bitta xodimga bog'lanadi. "
          "Bu rasm qo'shilmadi. "
          "Agar xato deb hisoblasangiz, administratorga murojaat qiling.",
    );
  }

  Future<void> _save() async {
    if (_saving || _busy) return;
    if (_samples.length < _minSamples) {
      _snack(
        "Kamida $_minSamples ta rasm qo'shing. Hozir: ${_samples.length}.",
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _status = 'Joylashuv tekshirilmoqda...';
    });

    if (!SettingsService.instance.hasInstitutionLocation) {
      await SettingsService.instance.refreshInstitutionFromServer();
    }
    final geofence = await LocationService.instance.checkInstitution();
    if (!mounted) return;
    if (!geofence.isInside) {
      setState(() {
        _saving = false;
        _status = '';
      });
      await showGeofenceDialog(context, geofence);
      return;
    }

    setState(() => _status = 'Saqlanmoqda...');

    try {
      for (final sample in _samples) {
        final imagePath = await PhotoStore.saveKnownFace(
          widget.person.id,
          sample.image,
        );
        await _db.addEmbedding(
          widget.person.id,
          sample.embedding,
          imagePath: imagePath,
        );
      }
      await RecognitionService.instance.invalidateIndex();

      if (!mounted) return;
      await HapticFeedback.heavyImpact();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      await _info(
        icon: Icons.error_outline_rounded,
        color: AppColors.red,
        title: 'Saqlash xatosi',
        message: "Yuz rasmlarini saqlab bo'lmadi:\n$error",
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _info({
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yuz rasmlarini bog\'lash'),
        actions: [
          if (_samples.isNotEmpty)
            IconButton(
              tooltip: 'Rasmlarni tozalash',
              onPressed: _busy || _saving
                  ? null
                  : () => setState(() => _samples.clear()),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.16),
                    child: Text(
                      person.fullName.isEmpty
                          ? '?'
                          : person.fullName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.fullName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        if ((person.position ?? '').isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            person.position!,
                            style: const TextStyle(
                              color: AppColors.subtext,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${person.externalId ?? person.employeeCode} · '
                          '${person.faceCount} ta mavjud rasm',
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppColors.yellow,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Yaxshi yorug'likda, kameraga to'g'ri qarab turing. "
                      "2–5 ta rasm qo'shing: oldidan, biroz chapdan va o'ngdan.",
                      style: TextStyle(
                        color: AppColors.subtext,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreviewBox(session: _session, borderRadius: 24),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 176,
                          height: 236,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(
                              Radius.elliptical(96, 130),
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_busy)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.68),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 34,
                                height: 34,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _status,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || _saving ? null : _captureSample,
                    icon: const Icon(Icons.camera_alt_rounded, size: 20),
                    label: const Text('Rasm olish'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 58,
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _busy || _saving ? null : _pickFromGallery,
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Icon(Icons.photo_library_outlined, size: 21),
                  ),
                ),
                if (_session.canSwitchCamera) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 48,
                    height: 54,
                    child: IconButton(
                      tooltip: 'Kamerani almashtirish',
                      onPressed: _busy || _saving
                          ? null
                          : _session.switchCamera,
                      icon: const Icon(Icons.cameraswitch_rounded),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            SectionTitle(
              'YANGI RASMLAR (${_samples.length}/$_maxSamples)',
              trailing: _samples.isEmpty
                  ? null
                  : const Text(
                      'Kamida 2 ta',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
            ),
            if (_samples.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  "Hozircha yangi rasm qo'shilmagan. Kamera yoki galereyadan "
                  'yuz rasmlarini qo\'shing.',
                  style: TextStyle(color: AppColors.subtext, fontSize: 12),
                ),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (var i = 0; i < _samples.length; i++)
                    _SampleThumb(
                      image: _samples[i].image,
                      onRemove: _saving
                          ? null
                          : () => setState(() => _samples.removeAt(i)),
                    ),
                ],
              ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _busy ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded, size: 20),
                label: Text(_saving ? 'Saqlanmoqda...' : 'Rasmlarni bog\'lash'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 13,
                  color: AppColors.muted,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    "Yuz ma'lumotlari faqat shu qurilmada saqlanadi",
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SampleThumb extends StatelessWidget {
  const _SampleThumb({required this.image, this.onRemove});

  final Uint8List image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.memory(
            image,
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 84,
              height: 84,
              color: AppColors.surfaceHigh,
              child: const Icon(
                Icons.image_not_supported_outlined,
                color: AppColors.muted,
              ),
            ),
          ),
        ),
        Positioned(
          top: -7,
          right: -7,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
