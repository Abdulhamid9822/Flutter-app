import 'dart:io';

import 'package:flutter/material.dart';

import '../models/person.dart';
import '../services/database_service.dart';
import '../services/photo_store.dart';
import '../services/recognition_service.dart';
import '../theme.dart';
import '../widgets/enrollment_permission_dialog.dart';
import '../widgets/ui.dart';
import 'bind_screen.dart';

/// Attendance tizimidan olingan xodimning lokal FaceID rasmlari.
class FaceIdEmployeeScreen extends StatefulWidget {
  const FaceIdEmployeeScreen({super.key, required this.personId});

  final int personId;

  @override
  State<FaceIdEmployeeScreen> createState() => _FaceIdEmployeeScreenState();
}

class _FaceIdEmployeeScreenState extends State<FaceIdEmployeeScreen> {
  final _db = DatabaseService.instance;

  Person? _person;
  List<String> _images = const [];
  bool _loading = true;
  bool _deleting = false;
  bool _granting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final person = await _db.getPerson(widget.personId);
      final images = await _db.getPersonImagePaths(widget.personId);
      if (!mounted) return;
      setState(() {
        _person = person;
        _images = images;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _bindPhotos() async {
    final person = _person;
    if (person == null) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: faceIdTheme,
          child: FaceBindScreen(person: person),
        ),
      ),
    );
    if (added == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Yuz rasmlari bog\'landi.')));
    }
  }

  Future<void> _grantPermission() async {
    final person = _person;
    final employeeId = person?.externalId;
    if (person == null || employeeId == null || _granting) return;

    setState(() => _granting = true);
    try {
      await showEnrollmentPermissionDialog(
        context,
        employeeId: employeeId,
        employeeName: person.fullName,
      );
    } finally {
      if (mounted) setState(() => _granting = false);
    }
  }

  Future<void> _deleteLocal() async {
    final person = _person;
    if (person == null || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Yuz ma'lumotlarini o'chirish"),
        content: Text(
          '"${person.fullName}" xodimining ${person.faceCount} ta yuz rasmi '
          "o'chiriladi.\n\n"
          "Xodim ro'yxatda qoladi — unga keyin qayta rasm bog'lash mumkin. "
          'Davom etilsinmi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: const Color(0xFF2A0B10),
            ),
            child: const Text("O'chirish"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final paths = await _db.deletePersonFaces(person.id);
      for (final path in paths) {
        await PhotoStore.deleteQuietly(path);
      }
      await RecognitionService.instance.invalidateIndex();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Yuz ma'lumotlari o'chirildi.")),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("O'chirib bo'lmadi: $error")));
    }
  }

  void _previewImage(String path) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xodim yuzlari'),
        actions: [
          IconButton(
            tooltip: 'Lokal FaceID ma\'lumotlarini o\'chirish',
            onPressed: _loading || _deleting ? null : _deleteLocal,
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.red,
                  ),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _person == null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Xatolik',
        message: _error ?? 'Xodim topilmadi.',
        action: FilledButton(
          onPressed: _load,
          child: const Text('Qayta urinish'),
        ),
      );
    }

    final person = _person!;
    final ready = person.faceCount >= 2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 37,
                backgroundColor: AppColors.primary.withValues(alpha: 0.16),
                backgroundImage: _images.isEmpty
                    ? null
                    : FileImage(File(_images.first)),
                child: _images.isEmpty
                    ? Text(
                        person.fullName.isEmpty
                            ? '?'
                            : person.fullName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.fullName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    if ((person.position ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        person.position!,
                        style: const TextStyle(
                          color: AppColors.subtext,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      'Attendance ID: ${person.externalId ?? '—'}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Pill(
                          text: ready ? 'TAYYOR' : 'RASM KERAK',
                          icon: ready
                              ? Icons.verified_rounded
                              : Icons.warning_amber_rounded,
                          color: ready ? AppColors.green : AppColors.yellow,
                        ),
                        const SizedBox(width: 8),
                        Pill(
                          text: '${person.faceCount} rasm',
                          icon: Icons.face_retouching_natural,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _deleting ? null : _bindPhotos,
            icon: const Icon(Icons.add_a_photo_outlined, size: 20),
            label: Text(
              person.faceCount == 0
                  ? 'Yuz rasmlarini bog\'lash'
                  : 'Yana rasm qo\'shish',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (_granting || person.externalId == null)
                ? null
                : _grantPermission,
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
        ),
        const SizedBox(height: 22),
        SectionTitle('YUZ RASMLARI (${_images.length})'),
        if (_images.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.yellowBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.yellow.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              "Bu xodimga hali yuz rasmi bog'lanmagan. Kamida 2 ta rasm "
              "qo'shing — shundan keyin u FaceID skanerlashda qatnashadi.",
              style: TextStyle(
                color: AppColors.yellow,
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
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _previewImage(path),
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppColors.surfaceHigh,
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.muted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 20),
        const Text(
          "Eslatma: bu yerda faqat shu qurilmadagi yuz ma'lumotlari "
          "o'chadi. Attendance tizimidagi xodim va davomat yozuvlari "
          "o'zgarmaydi.",
          style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
        ),
      ],
    );
  }
}
