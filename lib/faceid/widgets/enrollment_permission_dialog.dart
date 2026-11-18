import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api.dart';

/// Admin xodimga bir martalik rasm olish ruxsatini beradi va kodni
/// ko'rsatadi.
Future<void> showEnrollmentPermissionDialog(
  BuildContext context, {
  required int employeeId,
  required String employeeName,
}) async {
  try {
    final data = await Api.instance.faceIdEnrollmentGrant(
      employeeId: employeeId,
    );
    if (!context.mounted) return;
    await showEnrollmentCodeDialog(
      context,
      code: data['code']?.toString() ?? '',
      employeeName: employeeName,
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

/// Yaratilgan kodni ko'rsatadi. Admin so'rovni tasdiqlaganda ham shu
/// dialog ishlatiladi.
Future<void> showEnrollmentCodeDialog(
  BuildContext context, {
  required String code,
  required String employeeName,
  required int photos,
  required int pushSent,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text('Rasm olishga ruxsat')),
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
            const SizedBox(height: 12),
            Text(
              pushSent > 0
                  ? "Kod xodimga push notification orqali yuborildi. U "
                        'bildirishnomani ochib, “Qabul qilish”ni bosadi. '
                        'Agar kerak bo‘lsa, kodni qo‘lda ham bering.'
                  : "Push yuborilmadi (xodim qurilmasi ro‘yxatdan "
                        "o‘tmagan bo‘lishi mumkin). Kodni xodimga qo‘lda "
                        'bering.',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Kod 15 daqiqa amal qiladi va bir marta ishlatiladi. '
              'Ruxsat $photos tagacha rasm uchun.',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Kod nusxalandi.')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Nusxalash'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Yopish'),
          ),
        ],
      );
    },
  );
}
