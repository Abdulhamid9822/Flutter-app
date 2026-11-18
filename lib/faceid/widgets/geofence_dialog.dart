import 'package:flutter/material.dart';

import '../../api.dart';
import '../screens/settings_screen.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';

/// Muassasa hududidan tashqarida skanerlash yoki ro'yxatga olishga
/// urinilganda ko'rsatiladigan dialog.
Future<void> showGeofenceDialog(
  BuildContext context,
  GeofenceResult result,
) async {
  final status = result.status;
  final isOutside = status == GeofenceStatus.outside;
  final needsSystemSettings =
      status == GeofenceStatus.serviceDisabled ||
      status == GeofenceStatus.permissionDeniedForever;

  final color = isOutside ? AppColors.red : AppColors.yellow;
  final icon = isOutside
      ? Icons.wrong_location_outlined
      : status == GeofenceStatus.permissionDeniedForever
      ? Icons.lock_outline_rounded
      : Icons.location_disabled_rounded;

  final settings = SettingsService.instance;
  final configured = settings.hasInstitutionLocation;
  final isEmployee = Api.instance.user?.isEmployee ?? false;

  final detail = StringBuffer(result.message);
  if (result.distanceMeters != null) {
    detail.write(
      "\n\nMasofa: ${formatDistance(result.distanceMeters!)} · "
      "Ruxsat etilgan radius: ${settings.institutionRadiusMeters.round()} m",
    );
  }

  if (!context.mounted) return;
  final action = await showDialog<String>(
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
              isOutside ? 'Hududdan tashqarida' : 'Joylashuv kerak',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              detail.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.subtext,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            if (needsSystemSettings)
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop('system'),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Tizim sozlamalari'),
              )
            else if (!isEmployee && !configured)
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop('settings'),
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Muassasa joylashuvini sozlash'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Yopish'),
            ),
          ],
        ),
      ),
    ),
  );

  if (!context.mounted) return;
  if (action == 'settings') {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            Theme(data: faceIdTheme, child: const FaceIdSettingsScreen()),
      ),
    );
  } else if (action == 'system') {
    await LocationService.instance.openSettingsFor(status);
  }
}
