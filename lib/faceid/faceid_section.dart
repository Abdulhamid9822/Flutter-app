import 'dart:io';

import 'package:flutter/material.dart';

import '../api.dart';
import '../period.dart';
import '../theme.dart';
import '../widgets.dart';
import 'faceid_self_section.dart';
import 'models/person.dart';
import 'screens/camera_screen.dart';
import 'screens/employee_detail_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/settings_screen.dart';
import 'services/database_service.dart';
import 'services/faceid_sync_service.dart';
import 'services/photo_store.dart';
import 'services/recognition_service.dart';
import 'services/settings_service.dart';
import 'theme.dart' as fid;
import 'widgets/enrollment_permission_dialog.dart';

/// Attendance ilovasi ichidagi FaceID bo'limi.
///
/// Xodimlar attendance API'dan filial bo'yicha olinadi va lokal SQLite'ga
/// keshlanadi. Keyin faqat yuz rasmlari bog'lanadi — ism/kod qo'lda
/// kiritilmaydi. Barcha skanerlash va bog'lash oflayn ishlaydi, faqat
/// xodimlar ro'yxatini yangilash uchun internet kerak bo'ladi.
class FaceIdSection extends StatefulWidget {
  const FaceIdSection({super.key});

  @override
  State<FaceIdSection> createState() => _FaceIdSectionState();
}

class _FaceIdSectionState extends State<FaceIdSection> {
  final _db = DatabaseService.instance;

  bool _initializing = true;
  String? _initError;

  bool _syncing = false;
  String? _syncError;
  bool _backendHasSpot = true;
  Set<int>? _syncedIds;

  List<Person> _persons = const [];
  List<Map<String, dynamic>> _enrollmentRequests = const [];
  Map<int, String> _covers = const {};
  List<Map<String, dynamic>> _branches = const [];
  int _spot = 0;
  String _query = '';

  int _todayEntries = 0;
  int _todayExits = 0;
  int _pendingSync = 0;
  bool _sendingQueue = false;

  bool get _isSuper => Api.instance.user?.role == 'super';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _initializing = true;
      _initError = null;
    });
    try {
      await SettingsService.instance.init();
      await SettingsService.instance.refreshInstitutionFromServer();
      await _db.database;
      await RecognitionService.instance.init();
      await PhotoStore.cleanupTemp();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _initError = error.toString();
      });
      return;
    }

    await _loadLocal();
    await _loadEnrollmentRequests();
    if (_isSuper) await _loadBranches();
    if (!mounted) return;
    setState(() => _initializing = false);
    await _syncFromApi();
  }

  Future<void> _loadBranches() async {
    try {
      final data = await Api.instance.branches();
      final list = (data['branches'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() => _branches = list);
    } catch (_) {
      // Filiallar ro'yxati olinmasa ham asosiy ish davom etadi.
    }
  }

  Future<void> _loadLocal() async {
    final persons = await _db.getPersons();
    final covers = await _db.getCoverImages();
    final entries = await _db.countToday('entry');
    final exits = await _db.countToday('exit');
    final user = Api.instance.user;
    final account = (user?.account ?? '').trim();
    final pending = await _db.countPendingSync(
      externalId: user?.role == 'employee' ? user?.employeeId : null,
      accountName: account.isEmpty ? null : account,
    );
    if (!mounted) return;
    setState(() {
      _persons = persons;
      _covers = covers;
      _todayEntries = entries;
      _todayExits = exits;
      _pendingSync = pending;
    });
  }

  Future<void> _loadEnrollmentRequests() async {
    try {
      final data = await Api.instance.faceIdEnrollmentRequests();
      final list = (data['requests'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() => _enrollmentRequests = list);
    } catch (_) {
      // So'rovlar ro'yxatini olmasa ham xodimlar ro'yxati ishlaydi.
    }
  }

  Future<void> _decideEnrollmentRequest(
    Map<String, dynamic> request,
    bool approve,
  ) async {
    final id = (request['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      final data = await Api.instance.faceIdEnrollmentRequestDecide(
        id,
        approve ? 'approved' : 'rejected',
      );
      if (!mounted) return;
      await _loadEnrollmentRequests();
      if (!mounted) return;
      if (approve) {
        final employee = (data['employee'] as Map?)?.cast<String, dynamic>();
        await showEnrollmentCodeDialog(
          context,
          code: data['code']?.toString() ?? '',
          employeeName: (employee?['name'] ?? request['name'] ?? '').toString(),
          photos: (data['photos_allowed'] as num?)?.toInt() ?? 2,
          pushSent: (data['push_sent'] as num?)?.toInt() ?? 0,
        );
      } else {
        _snack('So‘rov rad etildi.');
      }
    } on ApiException catch (error) {
      _snack(error.message);
    } catch (error) {
      _snack('Xatolik: $error');
    }
  }

  Future<void> _syncFromApi() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      // Eski o'rnatishlarda account ma'lumoti hali yuklanmagan bo'lishi
      // mumkin. Xodimlarni accountga bog'lashdan oldin aniqlashtiramiz.
      if ((Api.instance.user?.account ?? '').isEmpty &&
          Api.instance.token != null) {
        await Api.instance.refreshLang();
      }
      final data = await Api.instance.daily(
        dayKey(DateTime.now()),
        spotId: _isSuper && _spot > 0 ? _spot : null,
      );
      final rows = (data['rows'] as List? ?? const [])
          .cast<Map<String, dynamic>>();

      for (final row in rows) {
        final id = row['id'];
        if (id is! int) continue;
        await _db.upsertExternalPerson(
          externalId: id,
          fullName: (row['name'] ?? '').toString(),
          position: row['position']?.toString(),
          spotId: row['spot_id'] as int?,
          accountName: Api.instance.user?.account,
        );
      }

      await RecognitionService.instance.invalidateIndex();

      if (!mounted) return;
      _backendHasSpot = rows.any((row) => row.containsKey('spot_id'));
      _syncedIds = rows.map((row) => row['id']).whereType<int>().toSet();
      await _loadLocal();
      await _loadEnrollmentRequests();
      if (!mounted) return;
      setState(() => _syncError = null);
      // Oldingi skanlar internet yo'qligida navbatda qolgan bo'lishi mumkin.
      try {
        final result = await FaceIdSyncService.instance.syncPending();
        if (mounted) setState(() => _pendingSync = result.pending);
      } catch (_) {
        // Davomat navbatini yuborish xatosi ro'yxatni yangilashni
        // bekor qilmaydi.
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _syncError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _syncError = error.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<Person> get _filtered {
    var list = _persons;

    final synced = _syncedIds;
    if (synced != null) {
      list = list
          .where(
            (person) =>
                person.externalId != null && synced.contains(person.externalId),
          )
          .toList();
    }

    if (_isSuper && _spot > 0 && _backendHasSpot) {
      list = list.where((person) => person.spotId == _spot).toList();
    }

    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return list;
    return list.where((person) {
      final name = person.fullName.toLowerCase();
      final position = (person.position ?? '').toLowerCase();
      final code = person.employeeCode.toLowerCase();
      return name.contains(query) ||
          position.contains(query) ||
          code.contains(query);
    }).toList();
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Theme(data: fid.faceIdTheme, child: screen),
      ),
    );
    if (!mounted) return;
    await _loadLocal();
  }

  Future<void> _openEmployee(Person person) async {
    await _openScreen(FaceIdEmployeeScreen(personId: person.id));
    if (!mounted) return;
    // Xodim lokal bazada qoladi, shuning uchun faqat lokal holat yangilanadi.
  }

  Future<void> _openSelfAttendance() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Mening davomatim')),
          body: const FaceIdSelfSection(),
        ),
      ),
    );
    if (!mounted) return;
    await _loadLocal();
  }

  Future<void> _grantPermission(Person person) async {
    final employeeId = person.externalId;
    if (employeeId == null) return;
    await showEnrollmentPermissionDialog(
      context,
      employeeId: employeeId,
      employeeName: person.fullName,
    );
  }

  Future<void> _openScanner() async {
    final ready = _filtered.where((person) => person.faceCount >= 2).length;
    if (ready == 0) {
      _snack(
        "Avval kamida bitta xodimga 2 ta yuz rasmini bog'lang. "
        "Shundan keyin skanerlash ishlaydi.",
      );
      return;
    }
    await _openScreen(const FaceIdCameraScreen());
    if (mounted) await _loadLocal();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _syncAttendanceQueue() async {
    if (_sendingQueue) return;
    setState(() => _sendingQueue = true);
    try {
      final result = await FaceIdSyncService.instance.syncPending();
      if (!mounted) return;
      setState(() => _pendingSync = result.pending);
      if (result.pending == 0 && result.sent > 0) {
        _snack("Davomat yozuvlari MySQL bazasiga yuborildi.");
      } else if (result.pending > 0) {
        _snack(
          result.error ?? "Yuborilmagan yozuvlar qoldi: ${result.pending}",
        );
      }
    } finally {
      if (mounted) setState(() => _sendingQueue = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const _InitializingView();
    }
    if (_initError != null) {
      return ErrorBox(
        "FaceID modulini ishga tushirib bo'lmadi:\n$_initError",
        onRetry: _initialize,
      );
    }

    final d = isDarkOf(context);
    final filtered = _filtered;
    final ready = filtered.where((person) => person.faceCount >= 2).length;
    final photos = filtered.fold<int>(
      0,
      (sum, person) => sum + person.faceCount,
    );

    return RefreshIndicator(
      onRefresh: _syncFromApi,
      color: AppColors.brandPrimary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(d),
                  if (_syncing) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  if (_syncError != null) ...[
                    const SizedBox(height: 12),
                    _buildOfflineBanner(d),
                  ],
                  const SizedBox(height: 14),
                  MetricGrid(
                    children: [
                      MetricCard(
                        label: "Xodimlar",
                        value: '${filtered.length}',
                        icon: Icons.groups_2_outlined,
                        color: AppColors.brandPrimary,
                      ),
                      MetricCard(
                        label: 'Tayyor',
                        value: '$ready',
                        icon: Icons.verified_user_outlined,
                        color: AppColors.statusPresent,
                      ),
                      MetricCard(
                        label: 'Yuz rasmlari',
                        value: '$photos',
                        icon: Icons.face_retouching_natural,
                        color: AppColors.brandCyan,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildActions(),
                  if (_pendingSync > 0) ...[
                    const SizedBox(height: 12),
                    _buildPendingSyncBanner(d),
                  ],
                  if (_enrollmentRequests.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildEnrollmentRequests(d),
                  ],
                  const SizedBox(height: 6),
                  SectionLabel('Xodimlar'),
                  if (_isSuper) ...[
                    _buildBranchPicker(d),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: "Ism, lavozim yoki ID bo'yicha qidirish",
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmpty(filtered),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final person = filtered[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == filtered.length - 1 ? 0 : 10,
                    ),
                    child: _EmployeeTile(
                      person: person,
                      coverPath: _covers[person.id],
                      showBranch: _isSuper && _spot == 0,
                      onTap: () => _openEmployee(person),
                      onGrant: () => _grantPermission(person),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool d) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.brandPrimary, AppColors.brandCyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.face_retouching_natural,
            color: Colors.white,
            size: 25,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FaceID',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: appText(d),
                ),
              ),
              Text(
                'Kirish / chiqish nazorati',
                style: TextStyle(fontSize: 12, color: appSubtext(d)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Jurnal',
          onPressed: () => _openScreen(const FaceIdLogsScreen()),
          icon: const Icon(Icons.receipt_long_outlined),
        ),
        IconButton(
          tooltip: 'Sozlamalar',
          onPressed: () => _openScreen(const FaceIdSettingsScreen()),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget _buildOfflineBanner(bool d) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.statusLate.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.statusLate.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.statusLate,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Serverga ulanib bo'lmadi. Keshlangan xodimlar bilan oflayn "
              "ishlayapsiz.",
              style: TextStyle(color: appSubtext(d), fontSize: 11, height: 1.4),
            ),
          ),
          IconButton(
            tooltip: 'Qayta yangilash',
            onPressed: _syncing ? null : _syncFromApi,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSyncBanner(bool d) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.statusLate.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.statusLate.withValues(alpha: .30)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_upload_outlined,
            color: AppColors.statusLate,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "MySQLga yuborilmagan davomat: $_pendingSync ta",
              style: TextStyle(color: appSubtext(d), fontSize: 11, height: 1.4),
            ),
          ),
          TextButton(
            onPressed: _sendingQueue ? null : _syncAttendanceQueue,
            child: Text(_sendingQueue ? 'Yuborilmoqda...' : 'Yuborish'),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final entries = _todayEntries;
    final exits = _todayExits;
    return Column(
      children: [
        if (Api.instance.user?.employeeId != null) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openSelfAttendance,
              icon: const Icon(Icons.person_pin_circle_outlined, size: 20),
              label: const Text('Mening FaceID davomatim'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: _syncing && _persons.isEmpty ? null : _openScanner,
                icon: const Icon(Icons.camera_front_rounded, size: 21),
                label: const Text('Skanerlash'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: () => _openScreen(const FaceIdLogsScreen()),
                icon: const Icon(Icons.history_rounded, size: 20),
                label: const Text('Jurnal'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.login_rounded,
              size: 14,
              color: AppColors.statusPresent,
            ),
            const SizedBox(width: 5),
            Text(
              "Bugun kirdi: $entries",
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.statusPresent,
              ),
            ),
            const SizedBox(width: 16),
            const Icon(
              Icons.logout_rounded,
              size: 14,
              color: AppColors.statusEarly,
            ),
            const SizedBox(width: 5),
            Text(
              "chiqdi: $exits",
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.statusEarly,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEnrollmentRequests(bool d) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.photo_camera_front_rounded,
                color: AppColors.statusLate,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Rasm olish so‘rovlari',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              StatusPill(
                '${_enrollmentRequests.length}',
                AppColors.statusLate,
              ),
            ],
          ),
          for (var i = 0; i < _enrollmentRequests.length; i++) ...[
            if (i > 0) Divider(height: 18, color: appCardBorder(d)),
            Builder(
              builder: (_) {
                final r = _enrollmentRequests[i];
                final name = (r['name'] ?? '').toString();
                final position = (r['position'] ?? '').toString();
                final rawTime = (r['requested_at'] ?? '').toString();
                final time = rawTime.length >= 16
                    ? rawTime.substring(0, 16)
                    : rawTime;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: appText(d),
                      ),
                    ),
                    if (position.isNotEmpty)
                      Text(
                        position,
                        style: TextStyle(
                          fontSize: 11,
                          color: appSubtext(d),
                        ),
                      ),
                    Text(
                      time,
                      style: TextStyle(fontSize: 10, color: appMuted(d)),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => _decideEnrollmentRequest(r, false),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.statusAbsent,
                          ),
                          child: const Text('Rad etish'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: () => _decideEnrollmentRequest(r, true),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('Ruxsat'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBranchPicker(bool d) {
    final items = <DropdownMenuItem<int>>[
      const DropdownMenuItem(value: 0, child: Text('Barcha filiallar')),
      for (final branch in _branches)
        if ((branch['spot_id'] as int? ?? 0) != 0)
          DropdownMenuItem(
            value: branch['spot_id'] as int,
            child: Text(
              'Filial ${branch['spot_id']} · ${branch['employees']} xodim',
            ),
          ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: appCardBackground(d),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: appCardBorder(d)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: _spot,
          dropdownColor: appCardBackground(d),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: items,
          onChanged: _syncing
              ? null
              : (value) {
                  final next = value ?? 0;
                  if (next == _spot) return;
                  setState(() {
                    _spot = next;
                    _syncedIds = null;
                  });
                  _syncFromApi();
                },
        ),
      ),
    );
  }

  Widget _buildEmpty(List<Person> filtered) {
    final d = isDarkOf(context);
    if (_syncing && _persons.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              "Xodimlar yuklanmoqda...",
              style: TextStyle(color: appSubtext(d), fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (_persons.isEmpty && _syncError != null) {
      return ErrorBox(
        "Xodimlar ro'yxatini yuklab bo'lmadi.\n$_syncError",
        onRetry: _syncFromApi,
      );
    }
    if (_query.trim().isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            "Qidiruv bo'yicha xodim topilmadi.",
            textAlign: TextAlign.center,
            style: TextStyle(color: appSubtext(d), fontSize: 13),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_2_outlined, size: 48, color: appMuted(d)),
            const SizedBox(height: 14),
            Text(
              _isSuper && _spot > 0
                  ? "Bu filialda faol xodim yo'q."
                  : "Hozircha xodimlar yuklanmagan. Internetga ulanib, "
                        "ro'yxatni yangilang.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: appSubtext(d),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _syncing ? null : _syncFromApi,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Yangilash'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitializingView extends StatelessWidget {
  const _InitializingView();

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 16),
          Text(
            'FaceID tayyorlanmoqda...',
            style: TextStyle(color: appSubtext(d), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Yuz modeli yuklanmoqda',
            style: TextStyle(color: appMuted(d), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile({
    required this.person,
    required this.onTap,
    this.onGrant,
    this.coverPath,
    this.showBranch = false,
  });

  final Person person;
  final String? coverPath;
  final bool showBranch;
  final VoidCallback onTap;
  final VoidCallback? onGrant;

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    final position = (person.position ?? '').trim();
    final subtitle = <String>[
      if (position.isNotEmpty) position,
      if (showBranch)
        person.spotId == null ? "Filial yo'q" : 'Filial ${person.spotId}',
    ].join(' · ');

    final (badge, badgeColor) = switch (person.faceCount) {
      0 => ("RASM YO'Q", AppColors.statusAbsent),
      1 => ('RASM KERAK', AppColors.statusLate),
      _ => ('TAYYOR', AppColors.statusPresent),
    };

    return Container(
      decoration: cardDecoration(d),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _Avatar(person: person, imagePath: coverPath, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: appText(d),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle.isEmpty ? "Lavozim ko'rsatilmagan" : subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: appSubtext(d)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          StatusPill(badge, badgeColor),
                          const SizedBox(width: 7),
                          Text(
                            '${person.faceCount} rasm',
                            style: TextStyle(fontSize: 11, color: appMuted(d)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Rasm olishga ruxsat',
                  onPressed: onGrant,
                  icon: const Icon(Icons.vpn_key_outlined, size: 20),
                ),
                Icon(Icons.chevron_right_rounded, color: appMuted(d), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.person, required this.size, this.imagePath});

  final Person person;
  final double size;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final name = person.fullName.trim();
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brandPrimary, AppColors.brandCyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * .38,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );

    final path = imagePath;
    if (path == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .32),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
