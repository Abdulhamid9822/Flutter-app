import 'package:flutter/material.dart';

import '../../api.dart';
import '../screens/bind_screen.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/recognition_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'geofence_dialog.dart';

/// Push orqali kelgan "yuz rasmini yangilash" so'rovini ko'rsatadi.
/// Xodim "Qabul qilish"ni bossa, kod tekshiriladi va rasm olish oynasi
/// ochiladi.
Future<void> showFaceIdEnrollmentRequestDialog(
  BuildContext context, {
  required String code,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.photo_camera_front_rounded, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('Yuz rasmini yangilash so‘rovi')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Admin sizga yuz rasmini yangilashga ruxsat berdi.',
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
            const SizedBox(height: 12),
            Text(
              'Qabul qilsangiz, kod ishlatiladi va yuz rasmi olish oynasi '
              'ochiladi. Kod 15 daqiqa amal qiladi.',
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
            child: const Text('Bekor qilish'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.check_rounded, size: 19),
            label: const Text('Qabul qilish'),
          ),
        ],
      );
    },
  );

  if (accepted != true || !context.mounted) return;

  try {
    await SettingsService.instance.init();
    await SettingsService.instance.refreshInstitutionFromServer();

    final geofence = await LocationService.instance.checkInstitution();
    if (!context.mounted) return;
    if (!geofence.isInside) {
      await showGeofenceDialog(context, geofence);
      return;
    }

    await Api.instance.faceIdEnrollmentValidate(code);
    if (!context.mounted) return;

    final user = Api.instance.user;
    final employeeId = user?.employeeId;
    if (user == null || employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Hisobingiz xodim kartasiga bog'lanmagan."),
        ),
      );
      return;
    }

    final person = await DatabaseService.instance.ensureExternalPerson(
      externalId: employeeId,
      fullName: user.name,
      accountName: user.account,
    );
    await RecognitionService.instance.invalidateIndex();
    if (!context.mounted) return;

    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: faceIdTheme,
          child: FaceBindScreen(person: person),
        ),
      ),
    );
    if (added == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Yuz rasmingiz saqlandi.')),
        );
    }
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
