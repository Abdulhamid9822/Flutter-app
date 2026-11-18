import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'main.dart';
import 'period.dart';
import 'theme.dart';
import 'widgets.dart';

(String, Color) statusFor(String? st, int late) {
  switch (st) {
    case 'present':
      return late > 0 ? ('Kechikdi', AppColors.statusLate) : ('Keldi', AppColors.statusPresent);
    case 'absent':
      return ('Kelmadi', AppColors.statusAbsent);
    case 'half_day':
      return ('Yarim kun', AppColors.statusLate);
    case 'overtime':
      return ('Qo\'shimcha', AppColors.brandPrimary);
    case 'vacation':
      return ('Ta\'til', AppColors.brandCyan);
    case 'dayoff':
      return ('Dam olish', AppColors.brandCyan);
    case 'sick':
      return ('Kasal', AppColors.statusEarly);
    case null:
      return ('Belgilanmagan', AppColors.darkMuted);
    default:
      return (st, AppColors.darkMuted);
  }
}

String timeOf(dynamic v) => (v == null || v.toString().length < 5) ? '--:--' : v.toString().substring(0, 5);

// ---------------- DASHBOARD ----------------
class DashboardView extends StatefulWidget {
  final bool employeeMode;
  const DashboardView({super.key, required this.employeeMode});
  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late DateTimeRange _range;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    // Admin uchun dashboard bugungi kun bilan ochiladi.
    _range = widget.employeeMode ? monthRange() : todayRange();
    _load();
  }

  void _load() {
    final from = dayKey(_range.start), to = dayKey(_range.end);
    if (widget.employeeMode) {
      _future = Api.instance.attendance(monthKey(_range.start), from: from, to: to).then(_fromAttendance);
    } else {
      _future = Api.instance.dashboard(from, to);
    }
  }

  // Xodim uchun o'z davomatidan dashboard ma'lumotini yig'adi
  Map<String, dynamic> _fromAttendance(Map<String, dynamic> d) {
    final rows = (d['days'] as List).cast<Map<String, dynamic>>();
    final sum = {'came': 0, 'late': 0, 'absent': 0};
    final days = <Map<String, dynamic>>[];
    for (final r in rows.reversed) {
      final late = int.tryParse('${r['kechikish_daqiqa'] ?? 0}') ?? 0;
      final st = r['davomat_holati'];
      final came = st == 'present' || st == 'overtime' || st == 'half_day' ? 1 : 0;
      final lateF = late > 0 ? 1 : 0;
      final abs = st == 'absent' ? 1 : 0;
      sum['came'] = sum['came']! + came;
      sum['late'] = sum['late']! + lateF;
      sum['absent'] = sum['absent']! + abs;
      days.add({'date': r['sana'], 'came': came, 'late': lateF, 'absent': abs});
    }
    return {'summary': sum, 'days': days, 'total_employees': 1};
  }

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return Column(children: [
      PeriodBar(
          range: _range,
          onChanged: (r) => setState(() {
                _range = r;
                _load();
              })),
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary));
            }
            if (snap.hasError) {
              handleAuthError(context, snap.error);
              return ErrorBox('${snap.error}', onRetry: () => setState(_load));
            }
            final s = snap.data!['summary'] as Map<String, dynamic>;
            final days = (snap.data!['days'] as List).cast<Map<String, dynamic>>();
            return RefreshIndicator(
              onRefresh: () async => setState(_load),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                MetricGrid(
                  children: [
                    if (!widget.employeeMode)
                      MetricCard(
                          label: 'Jami xodimlar',
                          value: '${snap.data!['total_employees']}',
                          icon: Icons.people,
                          color: AppColors.brandPrimary),
                    MetricCard(
                        label: 'Keldi',
                        value: '${s['came']}',
                        icon: Icons.check_circle,
                        color: AppColors.statusPresent),
                    MetricCard(
                        label: 'Kechikdi',
                        value: '${s['late']}',
                        icon: Icons.schedule,
                        color: AppColors.statusLate),
                    MetricCard(
                        label: 'Kelmadi',
                        value: '${s['absent']}',
                        icon: Icons.cancel,
                        color: AppColors.statusAbsent),
                  ],
                ),
                const SectionLabel('Davomat diagrammasi'),
                AttendanceChart(days: days),
                if (!widget.employeeMode) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const DailyReportScreen())),
                    icon: const Icon(Icons.table_chart),
                    label: const Text('Kunlik hisobot jadvali'),
                  ),
                ],
                SizedBox(height: d ? 8 : 0),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

// ---------------- DAILY REPORT ----------------
class DailyReportScreen extends StatelessWidget {
  const DailyReportScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('KUNLIK HISOBOT',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
        body: const DailyReportView(),
      );
}

class DailyReportView extends StatefulWidget {
  const DailyReportView({super.key});
  @override
  State<DailyReportView> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportView> {
  DateTime _date = DateTime.now();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = Api.instance.daily(dayKey(_date));

  // Xodim qatorini bosib turilsa: dam olish kuni berish yoki bekor qilish
  Future<void> _dayOff(Map<String, dynamic> r) async {
    final isOff = r['status'] == 'dayoff';
    final note = TextEditingController();
    final days = TextEditingController(text: '1');
    var from = _date;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(isOff ? 'Dam olishni bekor qilish' : 'Dam olish kuni berish'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${r['name']}'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(DateFormat('dd.MM.yyyy').format(from)),
              onPressed: isOff
                  ? null
                  : () async {
                      final p = await showDatePicker(
                          context: ctx,
                          initialDate: from,
                          firstDate: DateTime.now().subtract(const Duration(days: 60)),
                          lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (p != null) setD(() => from = p);
                    },
            ),
            if (!isOff) ...[
              const SizedBox(height: 12),
              TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Necha kun'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLength: 300,
                decoration:
                    InputDecoration(labelText: tr('Izoh (ixtiyoriy)'), border: const OutlineInputBorder()),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isOff ? 'Bekor qilish' : 'Yuborish')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      if (isOff) {
        await Api.instance.removeDayOff(r['id'] as int, dayKey(_date));
      } else {
        await Api.instance.setDayOff(
            r['id'] as int, dayKey(from), int.tryParse(days.text.trim()) ?? 1, note.text.trim());
      }
      if (mounted) setState(_load);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) return handleAuthError(context, e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final r = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(now.year - 2),
        lastDate: now);
    if (r != null) {
      setState(() {
        _date = r;
        _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    final isToday = dayKey(_date) == dayKey(DateTime.now());
    return Container(
        decoration: appScreenBackground(d),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            decoration: cardDecoration(d),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(
                  onPressed: () => setState(() {
                        _date = _date.subtract(const Duration(days: 1));
                        _load();
                      }),
                  icon: const Icon(Icons.chevron_left)),
              TextButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(DateFormat('dd.MM.yyyy').format(_date),
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(
                  onPressed: isToday
                      ? null
                      : () => setState(() {
                            _date = _date.add(const Duration(days: 1));
                            _load();
                          }),
                  icon: const Icon(Icons.chevron_right)),
            ]),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary));
                }
                if (snap.hasError) {
                  handleAuthError(context, snap.error);
                  return ErrorBox('${snap.error}', onRetry: () => setState(_load));
                }
                final rows = (snap.data!['rows'] as List).cast<Map<String, dynamic>>();
                int came = 0, late = 0, absent = 0, none = 0, off = 0;
                for (final r in rows) {
                  final l = (r['late'] as num).toInt();
                  final st = r['status'];
                  if (st == null) {
                    none++;
                  } else if (st == 'dayoff') {
                    off++;
                  } else if (st == 'absent') {
                    absent++;
                  } else {
                    came++;
                    if (l > 0) late++;
                  }
                }
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Wrap(spacing: 8, runSpacing: 6, children: [
                      StatusPill('Keldi: $came', AppColors.statusPresent),
                      StatusPill('Kechikdi: $late', AppColors.statusLate),
                      StatusPill('Kelmadi: $absent', AppColors.statusAbsent),
                      StatusPill('Dam olish: $off', AppColors.brandCyan),
                      StatusPill('Belgilanmagan: $none', AppColors.darkMuted),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => setState(_load),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          final st = statusFor(r['status'] as String?, (r['late'] as num).toInt());
                          final inT = timeOf(r['check_in']);
                          final outT = timeOf(r['check_out']);
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => showEmployeeSheet(
                                context, r['id'] as int, r['name'] ?? '', r['position'] ?? ''),
                            onLongPress: () => _dayOff(r),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: cardDecoration(d),
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(r['name'] ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontWeight: FontWeight.w600, color: appText(d))),
                                    const SizedBox(height: 2),
                                    Text('Kirdi: $inT  •  Chiqdi: $outT',
                                        style: TextStyle(fontSize: 12, color: appSubtext(d))),
                                  ]),
                                ),
                                const SizedBox(width: 8),
                                StatusPill(st.$1, st.$2),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ]),
      );
  }
}

// ---------------- EMPLOYEE SHEET ----------------
void showEmployeeSheet(BuildContext context, int id, String name, String position) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: appCardBackground(isDarkOf(context)),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      minChildSize: .4,
      maxChildSize: .95,
      builder: (ctx, scroll) => _EmployeeSheet(id: id, name: name, position: position, scroll: scroll),
    ),
  );
}

class _EmployeeSheet extends StatefulWidget {
  final int id;
  final String name;
  final String position;
  final ScrollController scroll;
  const _EmployeeSheet(
      {required this.id, required this.name, required this.position, required this.scroll});
  @override
  State<_EmployeeSheet> createState() => _EmployeeSheetState();
}

class _EmployeeSheetState extends State<_EmployeeSheet> {
  late final Future<List<Map<String, dynamic>>> _future = Future.wait([
    Api.instance.salary(monthKey(DateTime.now()), employeeId: widget.id),
    Api.instance.attendance(monthKey(DateTime.now()), employeeId: widget.id),
  ]);

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return ListView(controller: widget.scroll, padding: const EdgeInsets.all(20), children: [
      Center(
        child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: appMuted(d), borderRadius: BorderRadius.circular(2))),
      ),
      const SizedBox(height: 16),
      Row(children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.brandPrimary.withValues(alpha: .2),
          child: Text(widget.name.isEmpty ? '?' : widget.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                  color: AppColors.brandPrimary, fontWeight: FontWeight.w800, fontSize: 20)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.name,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: appText(d))),
            if (widget.position.isNotEmpty)
              Text(widget.position, style: TextStyle(color: appSubtext(d))),
          ]),
        ),
      ]),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: AppColors.brandPrimary)));
          }
          if (snap.hasError) return ErrorBox('${snap.error}');
          final s = snap.data![0]['salary'] as Map<String, dynamic>;
          final days = (snap.data![1]['days'] as List).cast<Map<String, dynamic>>();
          int came = 0, late = 0, absent = 0;
          for (final r in days) {
            final st = r['davomat_holati'];
            if (st == 'absent') {
              absent++;
            } else {
              came++;
              if ((int.tryParse('${r['kechikish_daqiqa'] ?? 0}') ?? 0) > 0) late++;
            }
          }
          final balance = s['balance'] as num?;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionLabel('Shu oy oyligi'),
            MetricGrid(
              children: [
                MetricCard(
                    label: 'Hisoblangan',
                    value: s['earned'] == null ? '—' : som(s['earned']),
                    icon: Icons.calculate,
                    color: AppColors.brandPrimary),
                MetricCard(
                    label: 'To\'langan',
                    value: s['paid'] == null ? '—' : som(s['paid']),
                    icon: Icons.check_circle,
                    color: AppColors.statusPresent),
                MetricCard(
                    label: balance == null
                        ? 'To\'lanishi kerak'
                        : balance > 0
                            ? 'To\'lanishi kerak'
                            : balance < 0 ? 'Ortiqcha to\'langan' : 'Hisob-kitob teng',
                    value: balance == null ? '—' : som(balance.abs()),
                    icon: Icons.account_balance_wallet,
                    color: balance != null && balance < 0 ? AppColors.statusAbsent : AppColors.statusLate),
              ],
            ),
            const SectionLabel('Shu oy davomati'),
            Wrap(spacing: 8, runSpacing: 6, children: [
              StatusPill('Keldi: $came', AppColors.statusPresent),
              StatusPill('Kechikdi: $late', AppColors.statusLate),
              StatusPill('Kelmadi: $absent', AppColors.statusAbsent),
            ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EmployeeDetailScreen(id: widget.id, name: widget.name)));
              },
              icon: const Icon(Icons.history),
              label: const Text('To\'liq oylik va tarix'),
            ),
          ]);
        },
      ),
    ]);
  }
}
