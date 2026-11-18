import 'package:flutter/material.dart';

import '../../api.dart';
import 'enrollment_permission_dialog.dart';

/// Xodim yuborgan rasm olish so'rovini admin tasdiqlaydi yoki rad etadi.
Future<void> showFaceIdEnrollmentAdminRequestDialog(
  BuildContext context, {
  required int requestId,
  required String employeeName,
}) async {
  final approve = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.photo_camera_front_rounded, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('Rasm olish so‘rovi')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              employeeName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text(
              'Xodim yuz rasmini yangilash uchun ruxsat so‘rayapti. '
              'Tasdiqlasangiz, unga bir martalik kod yuboriladi.',
            ),
            const SizedBox(height: 10),
            Text(
              'Kod 15 daqiqa amal qiladi va faqat bir marta ishlatiladi.',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            child: const Text('Rad etish'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.check_rounded, size: 19),
            label: const Text('Ruxsat berish'),
          ),
        ],
      );
    },
  );

  if (approve == null || !context.mounted) return;

  try {
    final data = await Api.instance.faceIdEnrollmentRequestDecide(
      requestId,
      approve ? 'approved' : 'rejected',
    );
    if (!context.mounted) return;
    if (!approve) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('So‘rov rad etildi.')));
      return;
    }
    final employee = (data['employee'] as Map?)?.cast<String, dynamic>();
    await showEnrollmentCodeDialog(
      context,
      code: data['code']?.toString() ?? '',
      employeeName: (employee?['name'] ?? employeeName).toString(),
      photos: (data['photos_allowed'] as num?)?.toInt() ?? 2,
      pushSent: (data['push_sent'] as num?)?.toInt() ?? 0,
    );
  } on ApiException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Xatolik: $error')));
  }
}
