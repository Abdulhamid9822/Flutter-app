import 'package:flutter/material.dart';

import '../../api.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class FaceIdSettingsScreen extends StatefulWidget {
  const FaceIdSettingsScreen({super.key});

  @override
  State<FaceIdSettingsScreen> createState() => _FaceIdSettingsScreenState();
}

class _FaceIdSettingsScreenState extends State<FaceIdSettingsScreen> {
  final _settings = SettingsService.instance;
  final _db = DatabaseService.instance;

  late double _match;
  late double _duplicate;
  late int _cooldown;
  late String _lens;

  final _locationNameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController();
  GeofenceResult? _geofence;
  bool _locating = false;
  bool _savingLocation = false;
  bool _checkingLocation = false;
  bool _loadingServerLocation = true;

  HomeStats? _stats;
  bool _loadingStats = true;

  bool get _locationBusy => _locating || _savingLocation || _checkingLocation;

  @override
  void initState() {
    super.initState();
    _match = _settings.matchThreshold;
    _duplicate = _settings.duplicateThreshold;
    _cooldown = _settings.cooldownMinutes;
    _lens = _settings.cameraLens;
    _fillLocationFields();
    _loadStats();
    _loadServerLocation();
  }

  Future<void> _loadServerLocation() async {
    await _settings.refreshInstitutionFromServer();
    if (!mounted) return;
    setState(() {
      _fillLocationFields();
      _loadingServerLocation = false;
    });
  }

  void _fillLocationFields() {
    _locationNameController.text = _settings.institutionName;
    _latitudeController.text = _settings.institutionLat == null
        ? ''
        : _settings.institutionLat!.toStringAsFixed(6);
    _longitudeController.text = _settings.institutionLng == null
        ? ''
        : _settings.institutionLng!.toStringAsFixed(6);
    _radiusController.text = _settings.institutionRadiusMeters
        .round()
        .toString();
  }

  @override
  void dispose() {
    _locationNameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _db.getHomeStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loadingStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStats = false);
    }
  }

  ({double latitude, double longitude, double radius}) _readLocationForm() {
    final latitude = double.tryParse(
      _latitudeController.text.trim().replaceAll(',', '.'),
    );
    if (latitude == null) {
      throw const FormatException(
        'Kenglikni to\'g\'ri kiriting (masalan: 41.311081).',
      );
    }
    if (latitude < -90 || latitude > 90) {
      throw const FormatException('Kenglik -90 va 90 orasida bo\'lishi kerak.');
    }

    final longitude = double.tryParse(
      _longitudeController.text.trim().replaceAll(',', '.'),
    );
    if (longitude == null) {
      throw const FormatException(
        'Uzunlikni to\'g\'ri kiriting (masalan: 69.240562).',
      );
    }
    if (longitude < -180 || longitude > 180) {
      throw const FormatException(
        'Uzunlik -180 va 180 orasida bo\'lishi kerak.',
      );
    }

    final radius = double.tryParse(
      _radiusController.text.trim().replaceAll(',', '.'),
    );
    if (radius == null) {
      throw const FormatException('Radiusni metrda kiriting.');
    }
    if (radius < 20 || radius > 1000) {
      throw const FormatException(
        'Radius 20 va 1000 metr orasida bo\'lishi kerak.',
      );
    }

    return (latitude: latitude, longitude: longitude, radius: radius);
  }

  Future<bool> _saveLocation({bool announce = true}) async {
    if (_locationBusy) return false;

    final ({double latitude, double longitude, double radius}) form;
    try {
      form = _readLocationForm();
    } on FormatException catch (error) {
      _snack(error.message);
      return false;
    }

    setState(() => _savingLocation = true);
    try {
      final name = _locationNameController.text.trim();
      // Avval serverga yoziladi. Server yozuvi muvaffaqiyatsiz bo'lsa
      // lokal qiymat o'zgartirilmaydi — keyingi ochilishda eski server
      // qiymati bilan almashib ketmasligi uchun.
      try {
        await Api.instance.faceIdSettingsSet(
          name: name,
          latitude: form.latitude,
          longitude: form.longitude,
          radius: form.radius,
        );
      } on ApiException catch (error) {
        _snack("Serverga saqlanmadi: ${error.message}");
        return false;
      }
      await _settings.setInstitutionName(name);
      await _settings.setInstitutionLocation(form.latitude, form.longitude);
      await _settings.setInstitutionRadiusMeters(form.radius);
      if (!mounted) return false;
      setState(() {
        _geofence = null;
        _loadingServerLocation = false;
        _locationNameController.text = _settings.institutionName;
        _radiusController.text = _settings.institutionRadiusMeters
            .round()
            .toString();
      });
      if (announce) {
        _snack('Muassasa joylashuvi barcha qurilmalar uchun saqlandi.');
      }
      return true;
    } finally {
      if (mounted) setState(() => _savingLocation = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_locationBusy) return;
    setState(() => _locating = true);
    try {
      final position = await LocationService.instance.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });
      _snack(
        'Joriy joylashuv olindi (aniqlik: ±${position.accuracy.round()} m). '
        'Saqlash tugmasini bosing.',
      );
    } on LocationFailure catch (error) {
      if (!mounted) return;
      final needsSystemSettings =
          error.status == GeofenceStatus.serviceDisabled ||
          error.status == GeofenceStatus.permissionDeniedForever;
      _snack(
        error.message,
        action: needsSystemSettings
            ? SnackBarAction(
                label: 'Sozlamalar',
                onPressed: () =>
                    LocationService.instance.openSettingsFor(error.status),
              )
            : null,
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _checkLocation() async {
    if (_locationBusy) return;
    final saved = await _saveLocation(announce: false);
    if (!saved || !mounted) return;

    setState(() => _checkingLocation = true);
    final result = await LocationService.instance.checkInstitution();
    if (!mounted) return;
    setState(() {
      _geofence = result;
      _checkingLocation = false;
    });
  }

  Future<void> _clearLocation() async {
    if (_locationBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Joylashuvni o'chirish"),
        content: const Text(
          "Muassasa koordinatalari o'chiriladi va skanerlash hamda "
          "ro'yxatga olish vaqtincha bloklanadi. Davom etilsinmi?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text("O'chirish"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Api.instance.faceIdSettingsClear();
    } on ApiException catch (error) {
      if (mounted) {
        _snack("Serverdan o'chirib bo'lmadi: ${error.message}");
      }
      return;
    }
    await _settings.clearInstitutionLocation();
    if (!mounted) return;
    setState(() {
      _latitudeController.clear();
      _longitudeController.clear();
      _geofence = null;
      _loadingServerLocation = false;
    });
    _snack("Muassasa joylashuvi barcha qurilmalardan o'chirildi.");
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    IconData? icon,
    String? suffixText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 18),
      suffixText: suffixText,
      filled: true,
      fillColor: AppColors.surfaceHigh,
      labelStyle: const TextStyle(color: AppColors.subtext, fontSize: 12),
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }

  Widget _buildLocationCard() {
    final configured = _settings.hasInstitutionLocation;
    return _SettingsCard(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Muassasa joylashuvi',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Pill(
              text: configured ? 'Sozlangan' : 'Sozlanmagan',
              color: configured ? AppColors.green : AppColors.yellow,
              icon: configured
                  ? Icons.gps_fixed_rounded
                  : Icons.gps_off_rounded,
            ),
          ],
        ),
        if (_loadingServerLocation) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 8),
        const Text(
          "Bu joylashuv serverga saqlanadi va accountdagi barcha "
          "qurilmalarga qo'llanadi. Skanerlash oflayn rejimda ham oxirgi "
          "kesh bo'yicha ishlaydi.",
          style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _locationNameController,
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration(
            label: 'Muassasa nomi',
            hint: 'Masalan: Markaziy filial',
            icon: Icons.business_rounded,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _latitudeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: _fieldDecoration(
                  label: 'Kenglik (lat)',
                  hint: '41.311081',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _longitudeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: _fieldDecoration(
                  label: 'Uzunlik (lng)',
                  hint: '69.240562',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _radiusController,
          keyboardType: TextInputType.number,
          decoration: _fieldDecoration(
            label: 'Radius',
            hint: '20 – 1000',
            suffixText: 'metr',
          ),
        ),
        if (configured) ...[
          const SizedBox(height: 8),
          Text(
            'Saqlangan: ${_settings.institutionLat!.toStringAsFixed(6)}, '
            '${_settings.institutionLng!.toStringAsFixed(6)} · '
            '${_settings.institutionRadiusMeters.round()} m',
            style: const TextStyle(
              color: AppColors.subtext,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _locationBusy ? null : _useCurrentLocation,
            icon: _locating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded, size: 18),
            label: Text(
              _locating
                  ? 'Joylashuv aniqlanmoqda...'
                  : 'Joriy joylashuvni olish',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _locationBusy ? null : () => _saveLocation(),
                icon: _savingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF2A0F05),
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Saqlash'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locationBusy || !configured ? null : _checkLocation,
                icon: _checkingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.gps_fixed_rounded, size: 18),
                label: const Text('Tekshirish'),
              ),
            ),
          ],
        ),
        if (configured)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _locationBusy ? null : _clearLocation,
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text("Joylashuvni o'chirish"),
            ),
          ),
        if (_geofence != null) ...[
          const SizedBox(height: 8),
          _buildGeofenceResult(_geofence!),
        ],
      ],
    );
  }

  Widget _buildGeofenceResult(GeofenceResult result) {
    final inside = result.status == GeofenceStatus.inside;
    final outside = result.status == GeofenceStatus.outside;
    final color = inside
        ? AppColors.green
        : outside
        ? AppColors.red
        : AppColors.yellow;
    final icon = inside
        ? Icons.check_circle_outline_rounded
        : outside
        ? Icons.wrong_location_outlined
        : Icons.info_outline_rounded;
    final title = switch (result.status) {
      GeofenceStatus.inside => 'Muassasa hududdasiz',
      GeofenceStatus.outside => 'Hududdan tashqarida',
      GeofenceStatus.notConfigured => 'Joylashuv sozlanmagan',
      GeofenceStatus.serviceDisabled => "GPS o'chirilgan",
      GeofenceStatus.permissionDenied ||
      GeofenceStatus.permissionDeniedForever => "Joylashuv ruxsati yo'q",
      GeofenceStatus.error => 'Joylashuv xatosi',
    };

    final details = <String>[result.message];
    if (result.distanceMeters != null) {
      details.add('Masofa: ${formatDistance(result.distanceMeters!)}');
    }
    if (result.accuracyMeters != null) {
      details.add('Aniqlik: ±${result.accuracyMeters!.round()} m');
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  details.join('\n'),
                  style: const TextStyle(
                    color: AppColors.subtext,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sozlamalar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            const SectionTitle('ANIQLIK'),
            _SettingsCard(
              children: [
                _ThresholdSlider(
                  label: 'Tanish chegarasi',
                  hint:
                      "Yuz shu foizdan yuqori moslikda taniladi. Pastroq — "
                      "ko'proq tanidi, lekin xato ehtimoli oshadi.",
                  value: _match,
                  min: 0.40,
                  max: 0.80,
                  divisions: 40,
                  onChanged: (value) => setState(() => _match = value),
                  onSettled: (value) => _settings.setMatchThreshold(value),
                ),
                const Divider(height: 30),
                _ThresholdSlider(
                  label: "O'xshashlik ogohlantirishi",
                  hint:
                      "Ro'yxatdan o'tkazishda boshqa xodimga shu foizdan "
                      "yuqori o'xshasa, ogohlantirish chiqadi.",
                  value: _duplicate,
                  min: 0.40,
                  max: 0.90,
                  divisions: 50,
                  onChanged: (value) => setState(() => _duplicate = value),
                  onSettled: (value) => _settings.setDuplicateThreshold(value),
                ),
                const Divider(height: 30),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Qayta skanerlash kutish vaqti',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Pill(text: '$_cooldown daqiqa', icon: Icons.timer_outlined),
                  ],
                ),
                Slider(
                  value: _cooldown.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: '$_cooldown daqiqa',
                  onChanged: (value) =>
                      setState(() => _cooldown = value.round()),
                  onChangeEnd: (value) =>
                      _settings.setCooldownMinutes(value.round()),
                ),
                const Text(
                  "Bir xodim qayta skanerlanganda shu vaqt ichida yangi "
                  "yozuv yaratilmaydi.",
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionTitle('KAMERA'),
            _SettingsCard(
              children: [
                const Text(
                  'Standart kamera',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'front',
                        label: Text('Old'),
                        icon: Icon(Icons.person_outline_rounded, size: 18),
                      ),
                      ButtonSegment(
                        value: 'back',
                        label: Text('Orqa'),
                        icon: Icon(Icons.landscape_outlined, size: 18),
                      ),
                    ],
                    selected: {_lens},
                    onSelectionChanged: (selection) async {
                      final value = selection.first;
                      setState(() => _lens = value);
                      await _settings.setCameraLens(value);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "O'zgarish keyingi safar kamera ochilganda qo'llanadi.",
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionTitle('MUASSASA JOYLASHUVI'),
            _buildLocationCard(),
            const SizedBox(height: 22),
            const SectionTitle('QURILMADAGI MA\'LUMOTLAR'),
            _SettingsCard(
              children: [
                _InfoRow(
                  icon: Icons.groups_2_outlined,
                  label: 'Xodimlar',
                  value: _loadingStats ? '...' : '${_stats?.persons ?? 0} ta',
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.face_retouching_natural,
                  label: 'Yuz rasmlari',
                  value: _loadingStats ? '...' : '${_stats?.faces ?? 0} ta',
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.receipt_long_outlined,
                  label: 'Jurnal yozuvlari',
                  value: _loadingStats ? '...' : '${_stats?.totalLogs ?? 0} ta',
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.storage_rounded,
                        color: AppColors.subtext,
                        size: 17,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          "Barcha ma'lumotlar shu qurilmaning SQLite bazasida "
                          "saqlanadi. MySQL sinxron keyin qo'shiladi.",
                          style: TextStyle(
                            color: AppColors.subtext,
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionTitle('TIZIM'),
            _SettingsCard(
              children: const [
                _InfoRow(
                  icon: Icons.wifi_off_rounded,
                  label: 'Ish rejimi',
                  value: "To'liq oflayn",
                ),
                SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.memory_rounded,
                  label: 'Model',
                  value: 'MobileFaceNet · 192',
                ),
                SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.straighten_rounded,
                  label: 'Kirish o\'lchami',
                  value: '112 × 112',
                ),
                SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.info_outline_rounded,
                  label: 'Versiya',
                  value: '1.0.0',
                ),
              ],
            ),
            const SizedBox(height: 26),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 13, color: AppColors.muted),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    "O'zgarishlar darhol saqlanadi",
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onSettled,
  });

  final String label;
  final String hint;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onSettled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Pill(text: '${(value * 100).round()}%'),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: '${(value * 100).round()}%',
          onChanged: onChanged,
          onChangeEnd: onSettled,
        ),
        Text(
          hint,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.subtext),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.subtext, fontSize: 12),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
